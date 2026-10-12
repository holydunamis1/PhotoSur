import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../models/editable_image_state.dart';
import '../services/mask_pipeline.dart';
import '../services/mask_refine.dart';
import '../services/segmentation_service.dart';
import '../utils/background_presets.dart';
import '../utils/subject_layout.dart';

/// Arguments for [postprocessInIsolate] (kept sendable: only typed data).
class PostprocessArgs {
  const PostprocessArgs(this.probs, this.width, this.height, this.guideGray);
  final Float32List probs;
  final int width;
  final int height;
  final Uint8List? guideGray;
}

Uint8List postprocessInIsolate(PostprocessArgs args) {
  final mask = postprocessMask(args.probs, args.width, args.height);
  final guide = args.guideGray;
  if (guide == null) return mask;
  try {
    return refineMask(mask, guide, args.width, args.height);
  } catch (_) {
    return mask; // refinement is an extra: never let it break a cut-out
  }
}

class ImageEditProvider extends ValueNotifier<EditableImageState> {
  ImageEditProvider() : super(const EditableImageState());

  // Incremented on every loadImage so a late segmentation result for a
  // previous image can never overwrite the current one.
  int _loadToken = 0;

  // True once the current image has been exported; used to decide whether
  // to remind the user about an unfinished edit.
  bool _exported = false;

  /// An image is open in the editor and has not been exported yet.
  bool get hasUnfinishedEdit => value.originalPath != null && !_exported;

  void markExported() {
    _exported = true;
  }

  void loadImage(String path, Size imageSize) {
    _loadToken++;
    _exported = false;
    value = EditableImageState(
      originalPath: path,
      imageSize: imageSize,
    );
  }

  /// Runs the model on [modelInput] (kModelInputSize x kModelInputSize x 3
  /// floats from preprocessRgb) and stores a full-size mask of
  /// [width] x [height] — the size of the image the editor is showing.
  Future<void> autoSegment(
    Float32List modelInput,
    int width,
    int height, {
    Uint8List? guideGray,
  }) async {
    final token = _loadToken;
    value = value.copyWith(isProcessing: true, autoSegmentationFailed: false);
    try {
      final probs = await SegmentationService.instance.infer(modelInput);
      final mask = await compute(
        postprocessInIsolate,
        PostprocessArgs(probs, width, height, guideGray),
      );
      if (token != _loadToken) return;
      value = value.copyWith(
        baseMaskBytes: mask,
        maskBytes: mask,
        brushHistory: const [],
        historyIndex: -1,
        isProcessing: false,
        autoSegmentationFailed: false,
      );
    } catch (_) {
      if (token != _loadToken) return;
      value = value.copyWith(
        isProcessing: false,
        autoSegmentationFailed: true,
      );
    }
  }

  void setBrushSize(double sizePx) {
    value = value.copyWith(currentBrushSizePx: sizePx);
  }

  void setBrushMode({required bool isRestore}) {
    value = value.copyWith(currentBrushIsRestore: isRestore);
  }

  void setBrushOpacity(double opacity) {
    value = value.copyWith(currentBrushOpacity: opacity);
  }

  /// Fresh copy of the untouched base mask (or fully-opaque if there is none
  /// yet, e.g. when auto-segmentation failed and the user paints manually).
  Uint8List _baseMaskCopy(int length) {
    final base = value.baseMaskBytes;
    if (base != null && base.length == length) {
      return Uint8List.fromList(base);
    }
    return Uint8List(length)..fillRange(0, length, 255);
  }

  /// Paints one stroke. [points] are in IMAGE pixel coordinates.
  /// [sizeInImagePx] is the brush diameter in image pixels; when omitted the
  /// brush-size slider value is used as-is (image pixels).
  void applyBrushStroke(List<Offset> points, {double? sizeInImagePx}) {
    final size = value.imageSize;
    if (size == null || points.isEmpty) return;
    final width = size.width.round();
    final height = size.height.round();

    final stroke = BrushStrokeEvent(
      points: points,
      brushSizePx: sizeInImagePx ?? value.currentBrushSizePx,
      isRestore: value.currentBrushIsRestore,
      opacity: value.currentBrushOpacity,
    );
    final kept = value.brushHistory.sublist(0, value.historyIndex + 1);
    final newHistory = [...kept, stroke];

    // The current mask already reflects history[0..historyIndex], so the
    // new stroke can be painted on top of a copy — no full replay needed.
    final current = value.maskBytes;
    final mask = (current != null && current.length == width * height)
        ? Uint8List.fromList(current)
        : _baseMaskCopy(width * height);
    _paintStroke(mask, width, height, stroke);

    value = value.copyWith(
      brushHistory: newHistory,
      historyIndex: newHistory.length - 1,
      maskBytes: mask,
    );
  }

  void undo() {
    if (value.historyIndex < 0) return;
    _replayTo(value.historyIndex - 1);
  }

  void redo() {
    if (value.historyIndex + 1 >= value.brushHistory.length) return;
    _replayTo(value.historyIndex + 1);
  }

  bool get canUndo => value.historyIndex >= 0;
  bool get canRedo => value.historyIndex + 1 < value.brushHistory.length;

  /// Back to the untouched AI mask (or fully-opaque if none).
  void resetMask() {
    value = value.copyWith(brushHistory: const [], historyIndex: -1);
    _replayTo(-1);
  }

  /// Rebuilds maskBytes from the base mask plus history[0..index].
  void _replayTo(int index) {
    final size = value.imageSize;
    if (size == null) return;
    final width = size.width.round();
    final height = size.height.round();
    final mask = _baseMaskCopy(width * height);
    for (var i = 0; i <= index && i < value.brushHistory.length; i++) {
      _paintStroke(mask, width, height, value.brushHistory[i]);
    }
    value = value.copyWith(historyIndex: index, maskBytes: mask);
  }

  /// Paints a stroke onto [mask]. Consecutive points are connected (a fast
  /// swipe leaves a continuous line, not dots), and the stroke's opacity is
  /// applied ONCE per pixel however many times the path overlaps itself.
  static void _paintStroke(
    Uint8List mask,
    int width,
    int height,
    BrushStrokeEvent stroke,
  ) {
    if (stroke.points.isEmpty) return;
    final radius = math.max(1, math.min(400, (stroke.brushSizePx / 2).round()));
    final delta = math.max(0, math.min(255, (255 * stroke.opacity).round()));

    // Densify the path so stamps are never more than radius/2 apart.
    final step = math.max(1.0, radius / 2);
    final path = <Offset>[];
    for (var i = 0; i < stroke.points.length; i++) {
      final p = stroke.points[i];
      if (i > 0) {
        final prev = stroke.points[i - 1];
        final pieces = ((p - prev).distance / step).floor();
        for (var k = 1; k <= pieces; k++) {
          path.add(Offset.lerp(prev, p, k / (pieces + 1))!);
        }
      }
      path.add(p);
    }

    // Bounding box of everything the stroke can touch.
    var minX = width, minY = height, maxX = -1, maxY = -1;
    for (final p in path) {
      minX = math.min(minX, p.dx.round() - radius);
      minY = math.min(minY, p.dy.round() - radius);
      maxX = math.max(maxX, p.dx.round() + radius);
      maxY = math.max(maxY, p.dy.round() + radius);
    }
    minX = math.max(0, minX);
    minY = math.max(0, minY);
    maxX = math.min(width - 1, maxX);
    maxY = math.min(height - 1, maxY);
    if (maxX < minX || maxY < minY) return;

    final boxW = maxX - minX + 1;
    final coverage = Uint8List(boxW * (maxY - minY + 1));
    final r2 = radius * radius;
    for (final p in path) {
      final cx = p.dx.round();
      final cy = p.dy.round();
      for (var dy = -radius; dy <= radius; dy++) {
        final y = cy + dy;
        if (y < minY || y > maxY) continue;
        for (var dx = -radius; dx <= radius; dx++) {
          if (dx * dx + dy * dy > r2) continue;
          final x = cx + dx;
          if (x < minX || x > maxX) continue;
          coverage[(y - minY) * boxW + (x - minX)] = 1;
        }
      }
    }

    for (var y = minY; y <= maxY; y++) {
      for (var x = minX; x <= maxX; x++) {
        if (coverage[(y - minY) * boxW + (x - minX)] == 0) continue;
        final idx = y * width + x;
        final next = stroke.isRestore ? mask[idx] + delta : mask[idx] - delta;
        mask[idx] = math.max(0, math.min(255, next));
      }
    }
  }

  void setBackgroundType(BackgroundType type) {
    value = value.copyWith(backgroundType: type);
  }

  void setBgColor(Color color) {
    value = value.copyWith(backgroundType: BackgroundType.solidColor, bgColor: color);
  }

  void setBlurRadius(double radiusPx) {
    value = value.copyWith(
      backgroundType: BackgroundType.gaussianBlur,
      blurRadius: radiusPx,
    );
  }

  void setGradient(int index) {
    value = value.copyWith(
      backgroundType: BackgroundType.gradient,
      gradientIndex: index,
    );
  }

  void setBackgroundImage(Uint8List bytes) {
    value = value.copyWith(
      backgroundType: BackgroundType.image,
      bgImageBytes: bytes,
    );
  }

  void setShadow(double opacity) {
    value = value.copyWith(shadowOpacity: opacity.clamp(0.0, kShadowMaxOpacity));
  }

  void setSubjectScale(double scale) {
    value = value.copyWith(subjectScale: scale.clamp(0.2, 3.0));
  }

  void setSubjectOffset(Offset offset) {
    value = value.copyWith(subjectOffset: offset);
  }

  void setCanvasAspect(double? aspect) {
    value = value.copyWith(canvasAspect: aspect);
  }

  /// Reset move/scale to the photo as framed.
  void resetSubjectLayout() {
    value = value.copyWith(subjectScale: 1.0, subjectOffset: Offset.zero);
  }

  /// Centre the cut-out subject on the canvas and size it to fill it.
  void autoCenterSubject() {
    final mask = value.maskBytes;
    final size = value.imageSize;
    if (mask == null || size == null) return;
    final bounds = subjectBounds(mask, size.width.round(), size.height.round());
    if (bounds == null) return;
    final (cw, ch) =
        canvasDimensions(size.width, size.height, value.canvasAspect);
    final layout = autoCenterLayout(
      bounds: bounds,
      imageWidth: size.width,
      imageHeight: size.height,
      canvasWidth: cw,
      canvasHeight: ch,
    );
    value = value.copyWith(
      subjectScale: layout.scale,
      subjectOffset: Offset(layout.offsetX, layout.offsetY),
    );
  }

  void setEdgeFeather(double featherPx) {
    value = value.copyWith(edgeFeather: featherPx);
  }

  void setZoom(double zoom) {
    value = value.copyWith(zoom: zoom);
  }

  void setPanOffset(Offset offset) {
    value = value.copyWith(panOffset: offset);
  }

  void toggleBeforeAfter() {
    value = value.copyWith(showBeforeAfter: !value.showBeforeAfter);
  }
}
