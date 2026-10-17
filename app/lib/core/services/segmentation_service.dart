import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../utils/constants.dart';

class SegmentationException implements Exception {
  const SegmentationException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => 'SegmentationException: $message'
      '${cause != null ? ' (cause: $cause)' : ''}';
}

/// Runs the model: takes the preprocessed input tensor (320x320x3 floats)
/// and returns the raw output tensor (320x320 floats).
typedef SegmentationRunner = Future<Float32List> Function(Float32List input);

/// On-device salient-object segmentation (U2-Netp, class-agnostic).
///
/// Inference runs in a background isolate (with a main-thread retry if that
/// fails) so a slow phone doesn't freeze the UI. Pre/post-processing lives in mask_pipeline.dart.
class SegmentationService {
  SegmentationService._() : _runner = null;

  static final SegmentationService instance = SegmentationService._();

  /// Test-only constructor — injects a fake runner so the error-handling
  /// contract can be tested without a native TFLite library.
  @visibleForTesting
  SegmentationService.forTesting(SegmentationRunner runner) : _runner = runner;

  final SegmentationRunner? _runner;
  String? _lastError;

  /// Path of the downloaded HD model, or null when it is not installed.
  /// Set by the model download service; when set, inference uses it and
  /// quietly falls back to the bundled model if it can't be run.
  String? hdModelPath;

  String? get lastError => _lastError;

  /// Native address of the HD interpreter kept open for a whole batch, or
  /// null when no batch session is open (every run then loads the model on
  /// its own, as the editor does).
  int? _batchAddress;

  /// Opens the HD model once for a batch so every photo reuses it instead of
  /// loading 88 MB again. Never throws: without HD, or if it can't be opened,
  /// photos simply run the normal way.
  Future<void> beginBatch() async {
    if (_runner != null || _batchAddress != null) return;
    final path = hdModelPath;
    if (path == null) return;
    try {
      if (!File(path).existsSync()) return;
      _batchAddress = await Isolate.run(() => _openFileInterpreter(path));
    } catch (_) {
      _batchAddress = null;
    }
  }

  /// Closes the interpreter opened by [beginBatch]. Safe to call anytime.
  Future<void> endBatch() async {
    final address = _batchAddress;
    _batchAddress = null;
    if (address == null) return;
    try {
      await Isolate.run(() => Interpreter.fromAddress(address).close());
    } catch (_) {
      // Nothing more to release.
    }
  }

  /// Returns the raw model output (kModelInputSize x kModelInputSize floats).
  /// Any failure is wrapped in [SegmentationException] so callers can fall
  /// back to the manual brush.
  Future<Float32List> infer(Float32List input) async {
    const expectedIn = kModelInputSize * kModelInputSize * 3;
    const expectedOut = kModelInputSize * kModelInputSize;
    if (input.length != expectedIn) {
      final err = 'Input has ${input.length} values, expected $expectedIn.';
      _lastError = err;
      throw SegmentationException(err);
    }
    try {
      final output = await (_runner?.call(input) ?? _defaultRunner(input, hdModelPath, _batchAddress));
      if (output.length != expectedOut) {
        throw StateError(
          'Model returned ${output.length} values, expected $expectedOut.',
        );
      }
      _lastError = null;
      return output;
    } catch (e, stack) {
      _lastError = 'INFERENCE FAILURE: $e\n$stack';
      throw SegmentationException(
        'Background removal failed. Falling back to manual brush.',
        e,
      );
    }
  }

  static Future<Float32List> _defaultRunner(
    Float32List input,
    String? hdPath,
    int? sessionAddress,
  ) async {
    if (sessionAddress != null) {
      try {
        return await Isolate.run(() => _runInterpreter(
              Interpreter.fromAddress(sessionAddress, allocated: true),
              input,
              close: false,
            ));
      } catch (_) {
        // Shared model unusable: fall through to loading it per photo.
      }
    }
    if (hdPath != null) {
      try {
        if (File(hdPath).existsSync()) {
          return await Isolate.run(() => _inferFileInIsolate(hdPath, input));
        }
      } catch (_) {
        // HD model unusable on this phone: use the bundled one below.
      }
    }
    final data = await rootBundle.load(kSegmentationModelAsset);
    final modelBytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    try {
      return await Isolate.run(() => _inferInIsolate(modelBytes, input));
    } catch (_) {
      // Safety net: if native inference can't run off the main thread on
      // this device, retry once on the main thread (slower, but works)
      // instead of giving up on automatic removal.
      return _inferInIsolate(modelBytes, input);
    }
  }
}

bool _sameShape(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Float32List _inferInIsolate(Uint8List modelBytes, Float32List input) {
  final options = InterpreterOptions()..threads = 4;
  return _runInterpreter(
    Interpreter.fromBuffer(modelBytes, options: options),
    input,
  );
}

/// Same as [_inferInIsolate] but maps the model straight from a file, so the
/// 88 MB HD model is never copied into Dart memory.
Float32List _inferFileInIsolate(String path, Float32List input) {
  final options = InterpreterOptions()..threads = 4;
  return _runInterpreter(
    Interpreter.fromFile(File(path), options: options),
    input,
  );
}

/// Opens the HD model from its file and returns the interpreter's native
/// address, so later runs (in other isolates) can reuse it.
int _openFileInterpreter(String path) {
  final options = InterpreterOptions()..threads = 4;
  return Interpreter.fromFile(File(path), options: options).address;
}

Float32List _runInterpreter(
  Interpreter interpreter,
  Float32List input, {
  bool close = true,
}) {
  try {
    final inputShape = interpreter.getInputTensor(0).shape;
    final outputShape = interpreter.getOutputTensor(0).shape;
    const expectedIn = [1, kModelInputSize, kModelInputSize, 3];
    const expectedOut = [1, kModelInputSize, kModelInputSize, 1];
    if (!_sameShape(inputShape, expectedIn) ||
        !_sameShape(outputShape, expectedOut)) {
      throw StateError(
        'Unexpected model tensor shapes: input $inputShape, '
        'output $outputShape.',
      );
    }

    final outputLength = outputShape.reduce((a, b) => a * b);
    final reshapedInput = input.reshape<dynamic>(inputShape);
    final reshapedOutput =
        List<double>.filled(outputLength, 0.0).reshape<dynamic>(outputShape);

    interpreter.run(reshapedInput, reshapedOutput);

    final result = Float32List(outputLength);
    var index = 0;
    void flatten(dynamic element) {
      if (element is List) {
        for (final sub in element) {
          flatten(sub);
        }
      } else if (element is num && index < outputLength) {
        result[index] = element.toDouble();
        index++;
      }
    }

    flatten(reshapedOutput);
    return result;
  } finally {
    if (close) interpreter.close();
  }
}
