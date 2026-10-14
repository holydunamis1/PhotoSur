import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photosur/core/providers/image_edit_provider.dart';
import 'package:photosur/generated/l10n/app_localizations.dart';
import 'package:photosur/widgets/editor_canvas.dart';
import 'package:provider/provider.dart';

void main() {
  setUpAll(() {
    // The real app switches this off in PhotoSurApp.build; tests that
    // host the provider directly must do the same.
    Provider.debugCheckInvalidValueType = null;
  });

  group('fitImageRect — the photo keeps its true proportions', () {
    test('square photo in a tall panel is letterboxed, never stretched', () {
      final fit = fitImageRect(const Size(1000, 1000), const Size(720, 970));
      expect(fit.width, 720);
      expect(fit.height, 720); // still square
      expect(fit.top, closeTo((970 - 720) / 2, 1e-9));
      expect(fit.left, 0);
    });

    test('same photo in a shorter panel keeps the same proportions', () {
      final tall = fitImageRect(const Size(1000, 1000), const Size(720, 970));
      final short = fitImageRect(const Size(1000, 1000), const Size(720, 730));
      expect(tall.width / tall.height, closeTo(1.0, 1e-9));
      expect(short.width / short.height, closeTo(1.0, 1e-9));
    });

    test('wide and portrait photos fit inside the viewport', () {
      for (final image in const [Size(2000, 1000), Size(1000, 2000)]) {
        const viewport = Size(400, 600);
        final fit = fitImageRect(image, viewport);
        expect(fit.width / fit.height, closeTo(image.width / image.height, 1e-9));
        expect(fit.left, greaterThanOrEqualTo(0));
        expect(fit.top, greaterThanOrEqualTo(0));
        expect(fit.right, lessThanOrEqualTo(viewport.width + 1e-9));
        expect(fit.bottom, lessThanOrEqualTo(viewport.height + 1e-9));
      }
    });
  });

  testWidgets('touching the canvas paints at the matching spot in the photo',
      (tester) async {
    // A 100x50 photo shown in a 200x300 canvas: scale 2, letterboxed to
    // the rect (0, 100)-(200, 200).
    late final String path;
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('canvas_test');
      path = '${dir.path}/photo.png';
      final photo = img.Image(width: 100, height: 50);
      await File(path).writeAsBytes(img.encodePng(photo));
    });

    final provider = ImageEditProvider();
    provider.loadImage(path, const Size(100, 50));
    final base = Uint8List(100 * 50)..fillRange(0, 100 * 50, 255);
    provider.value = provider.value.copyWith(
      baseMaskBytes: base,
      maskBytes: Uint8List.fromList(base),
    );
    provider.setBrushSize(20); // 20 on-screen px => 10 image px at scale 2

    final app =
      Provider<ImageEditProvider>.value(
        value: provider,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 200,
                height: 300,
                child: EditorCanvas(brushEnabled: true),
              ),
            ),
          ),
        ),
      );
    await tester.runAsync(() async {
      await tester.pumpWidget(app);
      // Let the photo decode (real async work).
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();
    await tester.pump();

    // Touch the middle of the canvas = the middle of the photo.
    final gesture = await tester.startGesture(const Offset(100, 150));
    await gesture.moveBy(const Offset(4, 0));
    await gesture.up();
    await tester.pump();

    final mask = provider.value.maskBytes!;
    expect(mask.length, 100 * 50);
    // Photo centre (50, 25) was erased...
    expect(mask[25 * 100 + 50], 0);
    // ...and the corners, far from the touch, were not.
    expect(mask[0], 255);
    expect(mask[100 * 50 - 1], 255);
    expect(provider.value.brushHistory.length, 1);
  });

  testWidgets('with the brush off, one finger does not paint', (tester) async {
    late final String path;
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('canvas_test2');
      path = '${dir.path}/photo.png';
      await File(path).writeAsBytes(img.encodePng(img.Image(width: 100, height: 50)));
    });
    final provider = ImageEditProvider();
    provider.loadImage(path, const Size(100, 50));
    final base = Uint8List(100 * 50)..fillRange(0, 100 * 50, 255);
    provider.value = provider.value.copyWith(
      baseMaskBytes: base,
      maskBytes: Uint8List.fromList(base),
    );

    final app =
      Provider<ImageEditProvider>.value(
        value: provider,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: 200, height: 300, child: EditorCanvas()),
            ),
          ),
        ),
      );
    await tester.runAsync(() async {
      await tester.pumpWidget(app);
      // Let the photo decode (real async work).
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();
    await tester.pump();

    final gesture = await tester.startGesture(const Offset(100, 150));
    await gesture.moveBy(const Offset(30, 0));
    await gesture.up();
    await tester.pump();

    expect(provider.value.brushHistory, isEmpty);
    expect(provider.value.maskBytes![25 * 100 + 50], 255);
  });
}
