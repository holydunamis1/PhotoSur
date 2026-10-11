import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:katharerase/core/models/editable_image_state.dart';
import 'package:katharerase/core/models/export_job.dart';
import 'package:katharerase/core/services/export_service.dart';
import 'package:katharerase/core/utils/subject_layout.dart';

ExportService _service() => ExportService.forTesting(
      (png, q) async => throw UnsupportedError('unused'),
    );

/// 20x10 image, left half red, right half blue, fully kept by the mask.
Uint8List _twoTone() {
  final image = img.Image(width: 20, height: 10);
  for (var y = 0; y < 10; y++) {
    for (var x = 0; x < 20; x++) {
      image.setPixelRgb(x, y, x < 10 ? 255 : 0, 0, x < 10 ? 0 : 255);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  group('placeSubject', () {
    test('fits inside the canvas without stretching (aspect preserved)', () {
      final p = placeSubject(
        imageWidth: 200,
        imageHeight: 100,
        canvasWidth: 100,
        canvasHeight: 100,
      );
      expect(p.width, 100);
      expect(p.height, 50);
      expect(p.left, 0);
      expect(p.top, 25);
    });

    test('scale and offset move the subject', () {
      final p = placeSubject(
        imageWidth: 100,
        imageHeight: 100,
        canvasWidth: 100,
        canvasHeight: 100,
        scale: 0.5,
        offsetX: 0.1,
        offsetY: -0.1,
      );
      expect(p.width, 50);
      expect(p.left, closeTo(25 + 10, 1e-9));
      expect(p.top, closeTo(25 - 10, 1e-9));
    });
  });

  group('subjectBounds / autoCenterLayout', () {
    test('finds the box around kept pixels', () {
      final mask = Uint8List(10 * 10);
      for (var y = 2; y < 5; y++) {
        for (var x = 6; x < 9; x++) {
          mask[y * 10 + x] = 255;
        }
      }
      expect(subjectBounds(mask, 10, 10),
          (left: 6, top: 2, right: 9, bottom: 5));
    });

    test('empty mask has no bounds', () {
      expect(subjectBounds(Uint8List(100), 10, 10), isNull);
    });

    test('auto-center puts the subject box in the middle of the canvas', () {
      const bounds = (left: 6, top: 2, right: 9, bottom: 5);
      final l = autoCenterLayout(
        bounds: bounds,
        imageWidth: 10,
        imageHeight: 10,
        canvasWidth: 100,
        canvasHeight: 100,
      );
      final p = placeSubject(
        imageWidth: 10,
        imageHeight: 10,
        canvasWidth: 100,
        canvasHeight: 100,
        scale: l.scale,
        offsetX: l.offsetX,
        offsetY: l.offsetY,
      );
      final k = p.width / 10;
      final cx = p.left + 7.5 * k;
      final cy = p.top + 3.5 * k;
      expect(cx, closeTo(50, 1e-6));
      expect(cy, closeTo(50, 1e-6));
      // 3px box fills 84% of the canvas (margin 8% each side).
      expect(3 * k, closeTo(84, 1e-6));
    });
  });

  group('export: fit instead of stretch, layout, shadow, backgrounds', () {
    test('square preset letterboxes a wide photo (no distortion)', () async {
      final result = await _service().compositeAndExport(
        originalBytes: _twoTone(),
        maskBytes: Uint8List(200)..fillRange(0, 200, 255),
        backgroundType: BackgroundType.white,
        format: ExportFormat.png,
        quality: 100,
        resizeMode: ResizeMode.square1x1,
      );
      final out = img.decodePng(result)!;
      expect(out.width, 1080);
      expect(out.height, 1080);
      // Top-left corner is background (white), the middle row is photo.
      final corner = out.getPixel(2, 2);
      expect([corner.r, corner.g, corner.b], [255, 255, 255]);
      final left = out.getPixel(100, 540);
      expect(left.r.toInt(), greaterThan(200));
      expect(left.b.toInt(), lessThan(60));
      final right = out.getPixel(980, 540);
      expect(right.b.toInt(), greaterThan(200));
    });

    test('gradient background fills the canvas top to bottom', () async {
      final result = await _service().compositeAndExport(
        originalBytes: _twoTone(),
        maskBytes: Uint8List(200), // nothing kept: pure background
        backgroundType: BackgroundType.gradient,
        gradientIndex: 5, // night: dark grey -> black
        format: ExportFormat.png,
        quality: 100,
        resizeMode: ResizeMode.square1x1,
      );
      final out = img.decodePng(result)!;
      final top = out.getPixel(500, 0);
      final bottom = out.getPixel(500, 1079);
      expect(top.r.toInt(), greaterThan(bottom.r.toInt() + 20));
      expect(bottom.r.toInt(), lessThan(8));
    });

    test('custom image background is cover-filled', () async {
      final bg = img.Image(width: 8, height: 8)
        ..clear(img.ColorRgb8(0, 200, 0));
      final result = await _service().compositeAndExport(
        originalBytes: _twoTone(),
        maskBytes: Uint8List(200),
        backgroundType: BackgroundType.image,
        bgImageBytes: Uint8List.fromList(img.encodePng(bg)),
        format: ExportFormat.png,
        quality: 100,
        resizeMode: ResizeMode.portrait4x5,
      );
      final out = img.decodePng(result)!;
      expect(out.width, 1080);
      expect(out.height, 1350);
      final p = out.getPixel(540, 675);
      expect(p.g.toInt(), greaterThan(180));
      expect(p.r.toInt(), lessThan(20));
    });

    test('shrunk subject leaves a transparent margin; shadow darkens below it',
        () async {
      Future<img.Image> run(double shadow) async {
        final result = await _service().compositeAndExport(
          originalBytes: _twoTone(),
          maskBytes: Uint8List(200)..fillRange(0, 200, 255),
          backgroundType: BackgroundType.white,
          shadowOpacity: shadow,
          subjectScale: 0.5,
          format: ExportFormat.png,
          quality: 100,
          resizeMode: ResizeMode.square1x1,
        );
        return img.decodePng(result)!;
      }

      final plain = await run(0);
      final shadowed = await run(0.6);
      // Subject is 540 wide x 270 tall, centred: bottom edge at y=675.
      final below = plain.getPixel(540, 690);
      expect(below.r.toInt(), 255);
      final shaded = shadowed.getPixel(540, 690);
      expect(shaded.r.toInt(), lessThan(250));
    });

    test('transparent background keeps alpha outside the moved subject',
        () async {
      final result = await _service().compositeAndExport(
        originalBytes: _twoTone(),
        maskBytes: Uint8List(200)..fillRange(0, 200, 255),
        backgroundType: BackgroundType.transparent,
        subjectScale: 0.5,
        subjectOffset: const Offset(0.2, 0),
        format: ExportFormat.png,
        quality: 100,
        resizeMode: ResizeMode.square1x1,
      );
      final out = img.decodePng(result)!;
      expect(out.getPixel(10, 10).a.toInt(), 0);
      // Subject centre sits right of canvas centre by 0.2*1080.
      expect(out.getPixel(540 + 216, 540).a.toInt(), 255);
    });
  });
}
