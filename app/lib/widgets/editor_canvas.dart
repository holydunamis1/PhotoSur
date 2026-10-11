import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models/editable_image_state.dart';
import '../core/providers/image_edit_provider.dart';
import '../core/utils/background_presets.dart';
import '../core/utils/constants.dart';
import '../core/utils/subject_layout.dart';
import '../generated/l10n/app_localizations.dart';

/// Where a photo of [image] size sits inside [viewport]: scaled uniformly
/// (never stretched) and centered, so the picture keeps its true
/// proportions whatever space the tool panel leaves for the canvas.
Rect fitImageRect(Size image, Size viewport) {
  if (image.width <= 0 || image.height <= 0) return Offset.zero & viewport;
  final scale = math.min(
    viewport.width / image.width,
    viewport.height / image.height,
  );
  final w = image.width * scale;
  final h = image.height * scale;
  return Rect.fromLTWH(
    (viewport.width - w) / 2,
    (viewport.height - h) / 2,
    w,
    h,
  );
}

/// A brush stroke in progress: points in IMAGE pixels (for painting), and
/// the finger position in canvas units (for the brush-size circle).
class _LiveStroke {
  const _LiveStroke(this.imagePoints, this.cursor);

  final List<Offset> imagePoints;
  final Offset? cursor;

  static const _LiveStroke none = _LiveStroke(<Offset>[], null);
}

class EditorCanvas extends StatefulWidget {
  /// [brushEnabled]: one finger paints (Manual tool); two fingers still
  /// pinch-zoom. When false, one finger pans the zoomed photo instead.
  const EditorCanvas({
    super.key,
    this.brushEnabled = false,
    this.moveEnabled = false,
  });

  final bool brushEnabled;

  /// Layout tool: one finger drags the subject, two fingers pinch-scale it.
  final bool moveEnabled;

  @override
  State<EditorCanvas> createState() => _EditorCanvasState();
}

class _EditorCanvasState extends State<EditorCanvas> {
  late final ImageEditProvider _provider;
  final TransformationController _transformController = TransformationController();
  final ValueNotifier<_LiveStroke> _live = ValueNotifier(_LiveStroke.none);

  ui.Image? _originalImage;
  ui.Image? _maskImage;
  String? _decodedForPath;
  // The mask buffer _maskImage was built from, and a counter that lets a
  // slow build be discarded if a newer mask arrived meanwhile. Rebuilding
  // the full-size mask image is expensive, so it only happens when the
  // mask itself changed (not on zoom, pan or slider changes).
  Uint8List? _maskSource;
  int _maskGeneration = 0;

  // Brush gesture state (raw pointers, so brush and pinch never fight over
  // the gesture arena).
  int _pointers = 0;
  bool _strokeActive = false;
  List<Offset> _strokeImagePoints = [];
  bool _hintDismissed = false;

  // Layout of the photo inside the viewport, refreshed on every build.
  Rect _fit = Rect.zero;
  Rect _canvasRect = Rect.zero;
  double _fitScale = 1.0;

  // Custom background photo, decoded once per picked file.
  ui.Image? _bgImage;
  Uint8List? _bgImageSource;

  // Layout-tool gestures.
  final Map<int, Offset> _movePointers = {};
  double _pinchStartDistance = 0;
  double _pinchStartScale = 1;

  @override
  void initState() {
    super.initState();
    _provider = Provider.of<ImageEditProvider>(context, listen: false);
    _provider.addListener(_onStateChanged);
    _onStateChanged();
  }

  @override
  void dispose() {
    _provider.removeListener(_onStateChanged);
    _transformController.dispose();
    _live.dispose();
    _originalImage?.dispose();
    _maskImage?.dispose();
    _bgImage?.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    final state = _provider.value;
    if (state.originalPath != null && state.originalPath != _decodedForPath) {
      _decodeOriginalImage(state.originalPath!);
    }
    if (!identical(state.bgImageBytes, _bgImageSource)) {
      _bgImageSource = state.bgImageBytes;
      _decodeBackgroundImage(state.bgImageBytes);
    }
    if (!identical(state.maskBytes, _maskSource)) {
      _maskSource = state.maskBytes;
      if (state.maskBytes != null) {
        _updateMaskImage(state.maskBytes!);
      } else if (_maskImage != null) {
        _maskGeneration++;
        setState(() {
          _maskImage?.dispose();
          _maskImage = null;
        });
      }
    }
  }

  Future<void> _decodeBackgroundImage(Uint8List? bytes) async {
    if (bytes == null) {
      setState(() {
        _bgImage?.dispose();
        _bgImage = null;
      });
      return;
    }
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (!mounted || !identical(bytes, _bgImageSource)) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _bgImage?.dispose();
        _bgImage = frame.image;
      });
    } catch (e) {
      debugPrint('Failed to decode background image: $e');
    }
  }

  Future<void> _decodeOriginalImage(String path) async {
    _decodedForPath = path;
    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (!mounted) return;
      _transformController.value = Matrix4.identity();
      setState(() => _originalImage = frame.image);
    } catch (e) {
      debugPrint('Failed to decode original image: $e');
    }
  }

  Future<void> _updateMaskImage(Uint8List maskBytes) async {
    final generation = ++_maskGeneration;
    try {
      final width = _provider.value.imageSize?.width.round() ?? 0;
      final height = _provider.value.imageSize?.height.round() ?? 0;
      if (width <= 0 || height <= 0) return;
      if (maskBytes.length != width * height) {
        debugPrint(
          'Mask buffer size mismatch: expected ${width * height}, got ${maskBytes.length}',
        );
        return;
      }

      final rgba = Uint8List(width * height * 4);
      for (var i = 0; i < width * height; i++) {
        rgba[i * 4] = 255; // R
        rgba[i * 4 + 1] = 255; // G
        rgba[i * 4 + 2] = 255; // B
        rgba[i * 4 + 3] = maskBytes[i]; // A — the actual mask value
      }

      final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
      final descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: width,
        height: height,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      final codec = await descriptor.instantiateCodec();
      final frame = await codec.getNextFrame();
      buffer.dispose();
      if (!mounted || generation != _maskGeneration) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _maskImage?.dispose();
        _maskImage = frame.image;
      });
    } catch (e) {
      debugPrint('Failed to create mask image: $e');
    }
  }

  Offset _toImage(Offset canvasPoint) => Offset(
        (canvasPoint.dx - _fit.left) / _fitScale,
        (canvasPoint.dy - _fit.top) / _fitScale,
      );

  double get _zoom => _transformController.value.getMaxScaleOnAxis();

  /// Brush diameter in image pixels. The slider is in on-screen pixels, so
  /// a stroke covers the same visible size whatever the photo's resolution,
  /// and zooming in gives finer control.
  double _brushImagePx(EditableImageState state) =>
      state.currentBrushSizePx / (_fitScale * _zoom);

  bool get _brushActive =>
      widget.brushEnabled && !_provider.value.showBeforeAfter;

  void _onPointerDown(PointerDownEvent e) {
    _pointers++;
    if (widget.moveEnabled) {
      _moveDown(e);
      return;
    }
    if (!_brushActive) return;
    if (_pointers == 1) {
      _strokeActive = true;
      _strokeImagePoints = [_toImage(e.localPosition)];
      _live.value = _LiveStroke(_strokeImagePoints, e.localPosition);
      if (!_hintDismissed) setState(() => _hintDismissed = true);
    } else {
      // A second finger means pinch-zoom: drop the stroke in progress.
      _cancelStroke();
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (widget.moveEnabled) {
      _moveMove(e);
      return;
    }
    if (!_strokeActive || _pointers != 1) return;
    _strokeImagePoints.add(_toImage(e.localPosition));
    _live.value = _LiveStroke(_strokeImagePoints, e.localPosition);
  }

  void _onPointerUp(PointerUpEvent e) {
    final wasSingle = _pointers == 1;
    _pointers = math.max(0, _pointers - 1);
    if (widget.moveEnabled) {
      _movePointers.remove(e.pointer);
      _restartPinch();
      return;
    }
    if (_strokeActive && wasSingle) {
      _commitStroke();
    } else {
      _cancelStroke();
    }
  }

  void _onPointerCancel(PointerCancelEvent e) {
    _pointers = math.max(0, _pointers - 1);
    if (widget.moveEnabled) {
      _movePointers.remove(e.pointer);
      _restartPinch();
      return;
    }
    _cancelStroke();
  }

  // --- Layout tool: drag to move the subject, pinch to scale it. ---

  void _moveDown(PointerDownEvent e) {
    _movePointers[e.pointer] = e.localPosition;
    _restartPinch();
  }

  void _restartPinch() {
    if (_movePointers.length == 2) {
      final pts = _movePointers.values.toList();
      _pinchStartDistance = (pts[0] - pts[1]).distance;
      _pinchStartScale = _provider.value.subjectScale;
    }
  }

  void _moveMove(PointerMoveEvent e) {
    if (!_movePointers.containsKey(e.pointer)) return;
    _movePointers[e.pointer] = e.localPosition;
    if (_movePointers.length == 1) {
      final w = _canvasRect.width;
      final h = _canvasRect.height;
      if (w <= 0 || h <= 0) return;
      final cur = _provider.value.subjectOffset;
      _provider.setSubjectOffset(
        Offset(cur.dx + e.delta.dx / w, cur.dy + e.delta.dy / h),
      );
    } else if (_movePointers.length == 2 && _pinchStartDistance > 0) {
      final pts = _movePointers.values.toList();
      final d = (pts[0] - pts[1]).distance;
      _provider.setSubjectScale(_pinchStartScale * d / _pinchStartDistance);
    }
  }

  void _cancelStroke() {
    _strokeActive = false;
    _strokeImagePoints = [];
    _live.value = _LiveStroke.none;
  }

  void _commitStroke() {
    final points = _strokeImagePoints;
    _strokeActive = false;
    _strokeImagePoints = [];
    _live.value = _LiveStroke.none;
    if (points.isEmpty) return;
    _provider.applyBrushStroke(
      points,
      sizeInImagePx: _brushImagePx(_provider.value),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<EditableImageState>(
      valueListenable: _provider,
      builder: (context, state, _) {
        if (_originalImage == null || state.imageSize == null) {
          return const Center(child: CircularProgressIndicator());
        }

        final imageSize = state.imageSize!;

        return LayoutBuilder(
          builder: (context, constraints) {
            final viewport = constraints.biggest;
            final (canvasW, canvasH) = canvasDimensions(
              imageSize.width,
              imageSize.height,
              state.canvasAspect,
            );
            _canvasRect = fitImageRect(Size(canvasW, canvasH), viewport);
            final place = placeSubject(
              imageWidth: imageSize.width,
              imageHeight: imageSize.height,
              canvasWidth: _canvasRect.width,
              canvasHeight: _canvasRect.height,
              scale: state.subjectScale,
              offsetX: state.subjectOffset.dx,
              offsetY: state.subjectOffset.dy,
            );
            _fit = Rect.fromLTWH(
              _canvasRect.left + place.left,
              _canvasRect.top + place.top,
              place.width,
              place.height,
            );
            _fitScale = imageSize.width > 0 ? _fit.width / imageSize.width : 1.0;

            return Stack(
              fit: StackFit.expand,
              children: [
                InteractiveViewer(
                  transformationController: _transformController,
                  minScale: kZoomMin,
                  maxScale: kZoomMax,
                  panEnabled: !widget.brushEnabled && !widget.moveEnabled,
                  scaleEnabled: !widget.moveEnabled,
                  child: SizedBox(
                    width: viewport.width,
                    height: viewport.height,
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: _onPointerDown,
                      onPointerMove: _onPointerMove,
                      onPointerUp: _onPointerUp,
                      onPointerCancel: _onPointerCancel,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CustomPaint(
                            painter: _EditorPainter(
                              original: _originalImage!,
                              maskImage: _maskImage,
                              showBeforeAfter: state.showBeforeAfter,
                              backgroundType: state.backgroundType,
                              bgColor: state.bgColor,
                              blurRadius: state.blurRadius,
                              edgeFeather: state.edgeFeather,
                              fit: _fit,
                              canvasRect: _canvasRect,
                              fitScale: _fitScale,
                              gradientIndex: state.gradientIndex,
                              bgImage: _bgImage,
                              shadowOpacity: state.shadowOpacity,
                            ),
                          ),
                          if (widget.brushEnabled)
                            CustomPaint(
                              painter: _BrushOverlayPainter(
                                live: _live,
                                transform: _transformController,
                                fit: _fit,
                                fitScale: _fitScale,
                                brushScreenPx: state.currentBrushSizePx,
                                isRestore: state.currentBrushIsRestore,
                                opacity: state.currentBrushOpacity,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (widget.brushEnabled && !_hintDismissed)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 12,
                    child: IgnorePointer(
                      child: Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            child: Text(
                              AppLocalizations.of(context).editorBrushHint,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Live feedback while painting: the stroke so far, and a circle showing
/// the brush's real on-screen size under the finger.
class _BrushOverlayPainter extends CustomPainter {
  _BrushOverlayPainter({
    required this.live,
    required this.transform,
    required this.fit,
    required this.fitScale,
    required this.brushScreenPx,
    required this.isRestore,
    required this.opacity,
  }) : super(repaint: Listenable.merge([live, transform]));

  final ValueNotifier<_LiveStroke> live;
  final TransformationController transform;
  final Rect fit;
  final double fitScale;
  final double brushScreenPx;
  final bool isRestore;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = live.value;
    final cursor = stroke.cursor;
    if (cursor == null) return;

    final zoom = transform.value.getMaxScaleOnAxis();
    final brushCanvas = brushScreenPx / zoom;
    final color = isRestore ? const Color(0xFF34C759) : const Color(0xFFFF3B30);

    if (stroke.imagePoints.isNotEmpty) {
      canvas.saveLayer(
        Offset.zero & size,
        Paint()..color = Colors.white.withValues(alpha: 0.25 + 0.4 * opacity),
      );
      final line = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = brushCanvas
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final first = _toCanvas(stroke.imagePoints.first);
      final path = Path()..moveTo(first.dx, first.dy);
      for (final p in stroke.imagePoints.skip(1)) {
        final c = _toCanvas(p);
        path.lineTo(c.dx, c.dy);
      }
      if (stroke.imagePoints.length == 1) {
        canvas.drawCircle(first, brushCanvas / 2, Paint()..color = color);
      } else {
        canvas.drawPath(path, line);
      }
      canvas.restore();
    }

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / zoom;
    canvas.drawCircle(cursor, brushCanvas / 2, ring..color = Colors.black54);
    canvas.drawCircle(
      cursor,
      brushCanvas / 2 - 1.5 / zoom,
      ring..color = Colors.white,
    );
  }

  Offset _toCanvas(Offset imagePoint) => Offset(
        imagePoint.dx * fitScale + fit.left,
        imagePoint.dy * fitScale + fit.top,
      );

  @override
  bool shouldRepaint(covariant _BrushOverlayPainter old) =>
      old.fit != fit ||
      old.fitScale != fitScale ||
      old.brushScreenPx != brushScreenPx ||
      old.isRestore != isRestore ||
      old.opacity != opacity;
}

class _EditorPainter extends CustomPainter {
  _EditorPainter({
    required this.original,
    this.maskImage,
    required this.showBeforeAfter,
    required this.backgroundType,
    required this.bgColor,
    required this.blurRadius,
    required this.edgeFeather,
    required this.fit,
    required this.canvasRect,
    required this.fitScale,
    required this.gradientIndex,
    this.bgImage,
    required this.shadowOpacity,
  });

  final ui.Image original;
  final ui.Image? maskImage;
  final bool showBeforeAfter;
  final BackgroundType backgroundType;
  final Color? bgColor;
  final double blurRadius;
  final double edgeFeather;

  /// Where the photo (the subject layer) is drawn; may extend past the canvas.
  final Rect fit;

  /// The output canvas. Backgrounds fill it; everything is clipped to it.
  final Rect canvasRect;
  final double fitScale;
  final int gradientIndex;
  final ui.Image? bgImage;
  final double shadowOpacity;

  Rect get _src =>
      Rect.fromLTWH(0, 0, original.width.toDouble(), original.height.toDouble());

  @override
  void paint(Canvas canvas, Size size) {
    final rect = fit;
    canvas.save();
    canvas.clipRect(canvasRect);

    if (showBeforeAfter) {
      // "Before": the untouched original at its natural framing.
      canvas.drawImageRect(original, _src, rect, Paint());
      canvas.restore();
      return;
    }

    switch (backgroundType) {
      case BackgroundType.white:
        canvas.drawRect(canvasRect, Paint()..color = Colors.white);
        break;
      case BackgroundType.black:
        canvas.drawRect(canvasRect, Paint()..color = Colors.black);
        break;
      case BackgroundType.solidColor:
        canvas.drawRect(canvasRect, Paint()..color = bgColor ?? Colors.white);
        break;
      case BackgroundType.gaussianBlur:
        _drawBlurredBackground(canvas);
        break;
      case BackgroundType.gradient:
        final stops = kGradientPresets[gradientIndex.clamp(0, kGradientPresets.length - 1)];
        canvas.drawRect(
          canvasRect,
          Paint()
            ..shader = ui.Gradient.linear(
              canvasRect.topCenter,
              canvasRect.bottomCenter,
              [Color(stops[0]), Color(stops[1])],
            ),
        );
        break;
      case BackgroundType.image:
        if (bgImage != null) {
          _drawCover(canvas, bgImage!, canvasRect);
        } else {
          canvas.drawRect(canvasRect, Paint()..color = Colors.white);
        }
        break;
      case BackgroundType.transparent:
        _drawTransparencyCheckerboard(canvas, canvasRect);
        break;
    }

    if (maskImage != null) {
      if (shadowOpacity > 0) _drawShadow(canvas, rect);
      _drawSubject(canvas, rect);
    } else {
      canvas.drawImageRect(original, _src, rect, Paint());
    }
    canvas.restore();
  }

  /// The cut-out subject: photo masked by the (optionally feathered) mask.
  void _drawSubject(Canvas canvas, Rect rect, {Paint? layerPaint}) {
    canvas.saveLayer(rect.inflate(1), layerPaint ?? Paint());
    canvas.drawImageRect(original, _src, rect, Paint());
    final maskPaint = Paint()..blendMode = BlendMode.dstIn;
    // Feather is specified in image pixels; scale it to what's on screen.
    final sigma = edgeFeather * fitScale;
    if (sigma > 0) {
      maskPaint.imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);
    }
    canvas.drawImageRect(
      maskImage!,
      Rect.fromLTWH(0, 0, maskImage!.width.toDouble(), maskImage!.height.toDouble()),
      rect,
      maskPaint,
    );
    canvas.restore();
  }

  /// Soft black silhouette under the subject, dropped slightly.
  void _drawShadow(Canvas canvas, Rect rect) {
    final longSide = math.max(canvasRect.width, canvasRect.height);
    final sigma = longSide * kShadowBlurFraction / 2;
    final drop = longSide * kShadowDropFraction;
    final layerPaint = Paint()
      ..colorFilter = ColorFilter.mode(
        Colors.black.withValues(alpha: shadowOpacity),
        BlendMode.srcIn,
      )
      ..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);
    _drawSubject(
      canvas,
      rect.shift(Offset(0, drop)).inflate(sigma * 4),
      layerPaint: layerPaint,
    );
  }

  /// Draw [image] scaled to cover [target], centre-cropped.
  void _drawCover(Canvas canvas, ui.Image image, Rect target) {
    final iw = image.width.toDouble();
    final ih = image.height.toDouble();
    final scale = math.max(target.width / iw, target.height / ih);
    final srcW = target.width / scale;
    final srcH = target.height / scale;
    final src = Rect.fromLTWH((iw - srcW) / 2, (ih - srcH) / 2, srcW, srcH);
    canvas.drawImageRect(image, src, target, Paint());
  }

  void _drawBlurredBackground(Canvas canvas) {
    final sigma = blurRadius * fitScale;
    canvas.saveLayer(
      canvasRect,
      Paint()
        ..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
    );
    _drawCover(canvas, original, canvasRect);
    canvas.restore();
  }

  void _drawTransparencyCheckerboard(Canvas canvas, Rect rect) {
    const tile = 12.0;
    final light = Paint()..color = const Color(0xFFE0E0E0);
    final dark = Paint()..color = const Color(0xFFBDBDBD);
    canvas.drawRect(rect, light);
    for (var y = rect.top; y < rect.bottom; y += tile) {
      for (var x = rect.left; x < rect.right; x += tile) {
        final isDark = (((x - rect.left) ~/ tile) + ((y - rect.top) ~/ tile)) % 2 == 0;
        if (isDark) {
          canvas.drawRect(Rect.fromLTWH(x, y, tile, tile), dark);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _EditorPainter oldDelegate) {
    return oldDelegate.original != original ||
        oldDelegate.maskImage != maskImage ||
        oldDelegate.showBeforeAfter != showBeforeAfter ||
        oldDelegate.backgroundType != backgroundType ||
        oldDelegate.bgColor != bgColor ||
        oldDelegate.blurRadius != blurRadius ||
        oldDelegate.edgeFeather != edgeFeather ||
        oldDelegate.fit != fit ||
        oldDelegate.canvasRect != canvasRect ||
        oldDelegate.fitScale != fitScale ||
        oldDelegate.gradientIndex != gradientIndex ||
        oldDelegate.bgImage != bgImage ||
        oldDelegate.shadowOpacity != shadowOpacity;
  }
}
