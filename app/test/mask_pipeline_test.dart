import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photosur/core/services/mask_pipeline.dart';

// Expected values below were produced by an independent float64 Python
// reference implementation of the same algorithm, not by running this code.
void main() {
  group('preprocessRgb', () {
    test('downscale 4x3 -> 2x2 matches reference', () {
      final rgb = Uint8List.fromList([
        175, 196, 25, 246, 67, 211, 151, 103, 92, 185, 142, 23, //
        72, 89, 110, 42, 218, 136, 167, 230, 68, 176, 127, 135, //
        172, 0, 75, 55, 250, 6, 19, 188, 44, 191, 69, 56,
      ]);
      const expected = [
        2.079433049, 1.617558149, 1.338125218, 2.248908297, 1.660460174, //
        0.068283948, 0.357241718, 1.499577580, -0.062314216, 1.130371659,
        1.769365314, -0.067242449,
      ];
      final out = preprocessRgb(rgb, 4, 3, size: 2);
      expect(out.length, 12);
      for (var i = 0; i < expected.length; i++) {
        expect(out[i], closeTo(expected[i], 1e-4), reason: 'index $i');
      }
    });

    test('upscale 2x2 -> 3x3 matches reference', () {
      final rgb = Uint8List.fromList([
        10, 200, 30, 250, 40, 60, //
        90, 90, 90, 0, 255, 128,
      ]);
      const expected = [
        -1.946656392, 1.465686275, -1.281568627, 0.108314068, 0.065126050,
        -1.020130719, 2.163284528, -1.335434174, -0.758692810, -1.261666239,
        0.502801120, -0.758692810, -0.619487970, 0.524684874, -0.462396514,
        0.022690299, 0.546568627, -0.166100218, -0.576676085, -0.460084034,
        -0.235816993, -1.347290008, 0.984243697, 0.095337691, -2.117903930,
        2.428571429, 0.426492375,
      ];
      final out = preprocessRgb(rgb, 2, 2, size: 3);
      expect(out.length, 27);
      for (var i = 0; i < expected.length; i++) {
        expect(out[i], closeTo(expected[i], 1e-4), reason: 'index $i');
      }
    });

    test('rejects a buffer whose length does not match the dimensions', () {
      expect(
        () => preprocessRgb(Uint8List(10), 4, 3, size: 2),
        throwsArgumentError,
      );
    });

    test('default output size is the model input size', () {
      final out = preprocessRgb(Uint8List(2 * 2 * 3), 2, 2);
      expect(out.length, 320 * 320 * 3);
    });
  });

  group('postprocessMask', () {
    test('normalise + upscale + curve matches reference', () {
      final probs = Float32List.fromList([
        0.02, 0.05, 0.1, 0.04, //
        0.08, 0.6, 0.95, 0.12, //
        0.07, 0.85, 0.9, 0.1, //
        0.01, 0.06, 0.09, 0.03,
      ]);
      const expected = [
        0, 0, 16, 12, 0, //
        0, 156, 255, 230, 0, //
        0, 2, 24, 8, 0,
      ];
      final mask = postprocessMask(probs, 5, 3, modelSize: 4);
      expect(mask.length, 15);
      expect(mask.toList(), expected);
    });

    test('no confident subject leaves the mask fully opaque', () {
      final probs = Float32List(16)..fillRange(0, 16, 0.01);
      final mask = postprocessMask(probs, 6, 4, modelSize: 4);
      expect(mask.length, 24);
      expect(mask.every((v) => v == 255), isTrue);
    });

    test('mask is exactly outW x outH regardless of model size', () {
      final probs = Float32List(320 * 320);
      for (var i = 0; i < probs.length; i++) {
        probs[i] = (i % 320) < 160 ? 0.9 : 0.05;
      }
      final mask = postprocessMask(probs, 1234, 777);
      expect(mask.length, 1234 * 777);
      // Left side foreground, right side background.
      expect(mask[400 * 1234 + 100], 255);
      expect(mask[400 * 1234 + 1100], 0);
    });

    test('rejects probs of the wrong size', () {
      expect(
        () => postprocessMask(Float32List(10), 5, 5, modelSize: 4),
        throwsArgumentError,
      );
    });
  });
}
