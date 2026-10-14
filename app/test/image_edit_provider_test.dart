import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:photosur/core/providers/image_edit_provider.dart';

const int _w = 12;
const int _h = 10;

Uint8List _base() => Uint8List(_w * _h)..fillRange(0, _w * _h, 200);

ImageEditProvider _providerWithBase() {
  final provider = ImageEditProvider();
  provider.loadImage('/tmp/x.jpg', const Size(12, 10));
  final base = _base();
  provider.value = provider.value.copyWith(
    baseMaskBytes: base,
    maskBytes: Uint8List.fromList(base),
  );
  return provider;
}

void main() {
  test('a full-size mask is never discarded by brush operations', () {
    final provider = _providerWithBase();
    provider.setBrushSize(4);
    provider.applyBrushStroke(const [Offset(6, 5)]);

    final mask = provider.value.maskBytes!;
    expect(mask.length, _w * _h);
    // Untouched pixels keep the AI value (200), not a reset to 255.
    expect(mask[0], 200);
    // Painted centre pixel is fully erased (opacity 1.0).
    expect(mask[5 * _w + 6], 0);
  });

  test('undo returns exactly to the base mask, redo reapplies', () {
    final provider = _providerWithBase();
    provider.setBrushSize(4);
    provider.applyBrushStroke(const [Offset(6, 5)]);
    final afterStroke = Uint8List.fromList(provider.value.maskBytes!);

    provider.undo();
    expect(provider.value.maskBytes, _base());

    provider.redo();
    expect(provider.value.maskBytes, afterStroke);
  });

  test('undo is not applied on top of itself with several strokes', () {
    final provider = _providerWithBase();
    provider.setBrushSize(4);
    provider.applyBrushStroke(const [Offset(3, 3)]);
    final afterFirst = Uint8List.fromList(provider.value.maskBytes!);
    provider.applyBrushStroke(const [Offset(9, 7)]);

    provider.undo();
    expect(provider.value.maskBytes, afterFirst);
    provider.undo();
    expect(provider.value.maskBytes, _base());
    expect(provider.canUndo, isFalse);
    expect(provider.canRedo, isTrue);
  });

  test('a new stroke after undo discards the redo branch', () {
    final provider = _providerWithBase();
    provider.setBrushSize(4);
    provider.applyBrushStroke(const [Offset(3, 3)]);
    provider.applyBrushStroke(const [Offset(9, 7)]);
    provider.undo();
    provider.applyBrushStroke(const [Offset(6, 5)]);

    expect(provider.value.brushHistory.length, 2);
    expect(provider.canRedo, isFalse);
  });

  test('restore brush paints opacity back toward 255', () {
    final provider = _providerWithBase();
    provider.setBrushSize(4);
    provider.applyBrushStroke(const [Offset(6, 5)]);
    provider.setBrushMode(isRestore: true);
    provider.applyBrushStroke(const [Offset(6, 5)]);

    expect(provider.value.maskBytes![5 * _w + 6], 255);
  });

  test('resetMask goes back to the AI mask, not to fully opaque', () {
    final provider = _providerWithBase();
    provider.setBrushSize(4);
    provider.applyBrushStroke(const [Offset(6, 5)]);

    provider.resetMask();

    expect(provider.value.maskBytes, _base());
    expect(provider.value.brushHistory, isEmpty);
    expect(provider.value.historyIndex, -1);
  });

  test('manual painting without an AI mask starts from fully opaque', () {
    final provider = ImageEditProvider();
    provider.loadImage('/tmp/x.jpg', const Size(12, 10));
    provider.setBrushSize(4);
    provider.applyBrushStroke(const [Offset(6, 5)]);

    final mask = provider.value.maskBytes!;
    expect(mask.length, _w * _h);
    expect(mask[0], 255);
    expect(mask[5 * _w + 6], 0);
  });

  test('a fast swipe paints a continuous line, not isolated dots', () {
    final provider = _providerWithBase();
    provider.setBrushSize(2); // radius 1
    provider.applyBrushStroke(const [Offset(0, 5), Offset(11, 5)]);

    final mask = provider.value.maskBytes!;
    for (var x = 0; x < _w; x++) {
      expect(mask[5 * _w + x], 0, reason: 'gap at x=$x');
    }
  });

  test('opacity is applied once per pixel even when the path overlaps', () {
    final provider = _providerWithBase();
    provider.setBrushSize(4);
    provider.setBrushOpacity(0.5);
    provider.applyBrushStroke(
      const [Offset(6, 5), Offset(6, 5), Offset(7, 5), Offset(6, 5)],
    );

    // 200 - round(255 * 0.5) = 72, once — not compounded per stamp.
    expect(provider.value.maskBytes![5 * _w + 6], 72);
  });

  test('sizeInImagePx overrides the slider value', () {
    final provider = _providerWithBase();
    provider.setBrushSize(50); // would cover the whole 12x10 image
    provider.applyBrushStroke(const [Offset(6, 5)], sizeInImagePx: 2);

    final mask = provider.value.maskBytes!;
    expect(mask[5 * _w + 6], 0);
    expect(mask[0], 200);
    expect(mask[9 * _w + 11], 200);
  });
}
