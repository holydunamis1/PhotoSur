import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photosur/core/models/editable_image_state.dart';
import 'package:photosur/core/models/export_job.dart';
import 'package:photosur/core/services/export_service.dart';

/// Builds a small synthetic source image programmatically — no binary
/// test fixture files committed to the repo, keeps this test
/// self-contained and CI-friendly. 4x4 red square, opaque.
Uint8List _buildTestSourceImage() {
  final image = img.Image(width: 4, height: 4);
  image.clear(img.ColorRgb8(220, 40, 40));
  return Uint8List.fromList(img.encodePng(image));
}

/// Uniform mask buffer — [value] for every pixel of a 4x4 image (16
/// elements), matching _buildTestSourceImage's dimensions.
Uint8List _uniformMask(int value) {
  return Uint8List(16)..fillRange(0, 16, value);
}

void main() {
  group('ExportService — PNG', () {
    test('preserves transparency: mask alpha passes through directly', () async {
      final service = ExportService.forTesting(
        (pngBytes, quality) async => throw UnsupportedError('not used in this test'),
      );

      final result = await service.compositeAndExport(
        originalBytes: _buildTestSourceImage(),
        maskBytes: _uniformMask(128), // half-alpha
        backgroundType: BackgroundType.transparent,
        format: ExportFormat.png,
        quality: 100,
        resizeMode: ResizeMode.original,
      );

      final decoded = img.decodePng(result);
      expect(decoded, isNotNull);
      final pixel = decoded!.getPixel(0, 0);
      // Transparent background type: alpha is the mask value directly,
      // not blended (see export_service.dart's _applyMaskAndBackground).
      expect(pixel.a.toInt(), 128);
    });

    test('fully transparent mask (0) yields alpha 0 across the image', () async {
      final service = ExportService.forTesting(
        (pngBytes, quality) async => throw UnsupportedError('not used in this test'),
      );

      final result = await service.compositeAndExport(
        originalBytes: _buildTestSourceImage(),
        maskBytes: _uniformMask(0),
        backgroundType: BackgroundType.transparent,
        format: ExportFormat.png,
        quality: 100,
        resizeMode: ResizeMode.original,
      );

      final decoded = img.decodePng(result)!;
      for (var y = 0; y < decoded.height; y++) {
        for (var x = 0; x < decoded.width; x++) {
          expect(decoded.getPixel(x, y).a.toInt(), 0);
        }
      }
    });
  });

  group('ExportService — JPG', () {
    test('applies white background when source background was transparent', () async {
      final service = ExportService.forTesting(
        (pngBytes, quality) async => throw UnsupportedError('not used in this test'),
      );

      final result = await service.compositeAndExport(
        originalBytes: _buildTestSourceImage(),
        maskBytes: _uniformMask(0), // fully "background" everywhere
        backgroundType: BackgroundType.transparent,
        format: ExportFormat.jpg,
        quality: 95,
        resizeMode: ResizeMode.original,
      );

      final decoded = img.decodeJpg(result);
      expect(decoded, isNotNull);
      final pixel = decoded!.getPixel(0, 0);
      // JPEG has no alpha channel; alpha=0 areas flatten onto white per
      // _flattenOntoWhite. Allow a small tolerance for JPEG's lossy
      // compression rather than asserting exact 255.
      expect(pixel.r.toInt(), greaterThan(248));
      expect(pixel.g.toInt(), greaterThan(248));
      expect(pixel.b.toInt(), greaterThan(248));
    });
  });

  group('ExportService — WEBP', () {
    test('passes the requested quality through to the encoder', () async {
      int? capturedQuality;
      final service = ExportService.forTesting((pngBytes, quality) async {
        capturedQuality = quality;
        return Uint8List.fromList([1, 2, 3]); // fake non-empty WEBP bytes
      });

      final result = await service.compositeAndExport(
        originalBytes: _buildTestSourceImage(),
        maskBytes: _uniformMask(255),
        backgroundType: BackgroundType.white,
        format: ExportFormat.webp,
        quality: 42,
        resizeMode: ResizeMode.original,
      );

      expect(capturedQuality, 42);
      expect(result, [1, 2, 3]);
    });

    test('falls back to JPG when the encoder throws UnsupportedError', () async {
      final service = ExportService.forTesting(
        (pngBytes, quality) async => throw UnsupportedError('platform encoder unavailable'),
      );

      final result = await service.compositeAndExport(
        originalBytes: _buildTestSourceImage(),
        maskBytes: _uniformMask(255),
        backgroundType: BackgroundType.white,
        format: ExportFormat.webp,
        quality: 80,
        resizeMode: ResizeMode.original,
      );

      // Fallback output should be a valid JPG, not WEBP bytes.
      final decoded = img.decodeJpg(result);
      expect(decoded, isNotNull);
    });
  });

  group('ExportService — resize', () {
    test('original mode preserves source dimensions', () async {
      final service = ExportService.forTesting(
        (pngBytes, quality) async => throw UnsupportedError('not used in this test'),
      );

      final result = await service.compositeAndExport(
        originalBytes: _buildTestSourceImage(),
        maskBytes: _uniformMask(255),
        backgroundType: BackgroundType.white,
        format: ExportFormat.png,
        quality: 100,
        resizeMode: ResizeMode.original,
      );

      final decoded = img.decodePng(result)!;
      expect(decoded.width, 4);
      expect(decoded.height, 4);
    });

    test('square1x1 preset resizes to 1080x1080', () async {
      final service = ExportService.forTesting(
        (pngBytes, quality) async => throw UnsupportedError('not used in this test'),
      );

      final result = await service.compositeAndExport(
        originalBytes: _buildTestSourceImage(),
        maskBytes: _uniformMask(255),
        backgroundType: BackgroundType.white,
        format: ExportFormat.png,
        quality: 100,
        resizeMode: ResizeMode.square1x1,
      );

      final decoded = img.decodePng(result)!;
      expect(decoded.width, 1080);
      expect(decoded.height, 1080);
    });

    test('custom mode applies the requested width/height', () async {
      final service = ExportService.forTesting(
        (pngBytes, quality) async => throw UnsupportedError('not used in this test'),
      );

      final result = await service.compositeAndExport(
        originalBytes: _buildTestSourceImage(),
        maskBytes: _uniformMask(255),
        backgroundType: BackgroundType.white,
        format: ExportFormat.png,
        quality: 100,
        resizeMode: ResizeMode.custom,
        customWidth: 200,
        customHeight: 150,
      );

      final decoded = img.decodePng(result)!;
      expect(decoded.width, 200);
      expect(decoded.height, 150);
    });

    test('custom mode without width/height throws ExportException', () async {
      final service = ExportService.forTesting(
        (pngBytes, quality) async => throw UnsupportedError('not used in this test'),
      );

      expect(
        () => service.compositeAndExport(
          originalBytes: _buildTestSourceImage(),
          maskBytes: _uniformMask(255),
          backgroundType: BackgroundType.white,
          format: ExportFormat.png,
          quality: 100,
          resizeMode: ResizeMode.custom,
        ),
        throwsA(isA<ExportException>()),
      );
    });
  });
}
