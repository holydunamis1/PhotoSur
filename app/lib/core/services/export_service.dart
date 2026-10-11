import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

import '../models/editable_image_state.dart';
import '../models/export_job.dart';
import '../utils/background_presets.dart';
import '../utils/constants.dart';
import '../utils/subject_layout.dart';

class ExportException implements Exception {
  const ExportException(this.message, [this.cause]);
  final String message;
  final Object? cause;

  @override
  String toString() => 'ExportException: $message'
      '${cause != null ? ' (cause: $cause)' : ''}';
}

/// Composites image + mask + background into final output and applies
/// resize (Feature 14) during compositing. All pixel work goes through
/// package:image; WEBP output is a secondary re-encode step through
/// flutter_image_compress, since package:image cannot encode WEBP at all
/// (confirmed live — it's decode-only for that format). See pubspec.yaml
/// comment on flutter_image_compress for why this dependency exists.
class ExportService {
  ExportService._({
    Future<Uint8List> Function(Uint8List pngBytes, int quality)? webpEncoder,
  }) : _webpEncoder = webpEncoder ?? _defaultWebpEncoder;

  static final ExportService instance = ExportService._();

  /// Test-only constructor — injects a fake WEBP encoder so unit tests
  /// can exercise compositeAndExport's WEBP path (including the quality
  /// parameter and the JPG fallback branch) without a real platform
  /// channel, which throws MissingPluginException in a standard
  /// `flutter test` unit test. See test/export_service_test.dart.
  @visibleForTesting
  ExportService.forTesting(
    Future<Uint8List> Function(Uint8List pngBytes, int quality) webpEncoder,
  ) : _webpEncoder = webpEncoder;

  static Future<Uint8List> _defaultWebpEncoder(
    Uint8List pngBytes,
    int quality,
  ) {
    return FlutterImageCompress.compressWithList(
      pngBytes,
      format: CompressFormat.webp,
      quality: quality,
    );
  }

  final Future<Uint8List> Function(Uint8List pngBytes, int quality) _webpEncoder;

  /// Main entry point: takes the original image bytes, the mask produced
  /// by segmentation / brush edits, and the current editor state, and
  /// produces final export bytes in the requested format.
  ///
  /// The heavy pixel work (decode, composite, blur, resize, PNG/JPG encode)
  /// runs in a background isolate so the UI never freezes. WEBP encoding
  /// needs a platform plugin, which is only available on the main isolate,
  /// so for WEBP the isolate returns PNG bytes and the final encode happens
  /// here.
  Future<Uint8List> compositeAndExport({
    required Uint8List originalBytes,
    required Uint8List maskBytes,
    required BackgroundType backgroundType,
    Color? bgColor,
    double blurRadius = 0.0,
    double edgeFeather = 0.0,
    required ExportFormat format,
    required int quality,
    required ResizeMode resizeMode,
    int? customWidth,
    int? customHeight,
    int gradientIndex = 0,
    Uint8List? bgImageBytes,
    double shadowOpacity = 0.0,
    double subjectScale = 1.0,
    Offset subjectOffset = Offset.zero,
    double? canvasAspect,
  }) async {
    try {
      final args = _ExportArgs(
        originalBytes: originalBytes,
        maskBytes: maskBytes,
        backgroundType: backgroundType,
        bgColorArgb: bgColor?.toARGB32(),
        blurRadius: blurRadius,
        edgeFeather: edgeFeather,
        format: format,
        quality: quality,
        resizeMode: resizeMode,
        customWidth: customWidth,
        customHeight: customHeight,
        gradientIndex: gradientIndex,
        bgImageBytes: bgImageBytes,
        shadowOpacity: shadowOpacity,
        subjectScale: subjectScale,
        subjectOffsetX: subjectOffset.dx,
        subjectOffsetY: subjectOffset.dy,
        canvasAspect: canvasAspect,
      );
      final bytes = await compute(_exportInIsolate, args);
      if (format == ExportFormat.webp) {
        return _encodeWebpWithFallback(bytes, quality: quality);
      }
      return bytes;
    } on ExportException {
      rethrow;
    } catch (e) {
      throw ExportException('Export failed.', e);
    }
  }

  /// The isolate-side work. Returns PNG bytes for png and webp, JPG bytes
  /// for jpg.
  Uint8List _compositeToBytes(_ExportArgs a) {
    final original = img.decodeImage(a.originalBytes);
    if (original == null) {
      throw const ExportException('Could not decode source image.');
    }

    final canvasSize = _canvasSize(a, original.width, original.height);
    final plainLayout = canvasSize.$1 == original.width &&
        canvasSize.$2 == original.height &&
        a.subjectScale == 1.0 &&
        a.subjectOffsetX == 0.0 &&
        a.subjectOffsetY == 0.0 &&
        a.shadowOpacity <= 0 &&
        a.backgroundType != BackgroundType.gradient &&
        a.backgroundType != BackgroundType.image;

    final composited = plainLayout
        ? _applyMaskAndBackground(
            original: original,
            maskBytes: a.maskBytes,
            backgroundType: a.backgroundType,
            bgColor: a.bgColorArgb == null ? null : Color(a.bgColorArgb!),
            blurRadius: a.blurRadius,
            edgeFeather: a.edgeFeather,
          )
        : _composeOnCanvas(a, original, canvasSize.$1, canvasSize.$2);

    switch (a.format) {
      case ExportFormat.png:
      case ExportFormat.webp:
        return Uint8List.fromList(img.encodePng(composited));
      case ExportFormat.jpg:
        // JPEG has no alpha channel — flatten onto white first if the
        // background choice was "transparent" (Feature 4 + Feature 5
        // interaction the build plan doesn't explicitly resolve; white
        // flatten is the least-surprising default rather than black).
        final flattened = a.backgroundType == BackgroundType.transparent
            ? _flattenOntoWhite(composited)
            : composited;
        return Uint8List.fromList(
          img.encodeJpg(flattened, quality: a.quality),
        );
    }
  }


  /// Output canvas size. A resize preset / custom size defines the canvas
  /// shape; "original" keeps the photo's longer side and applies the
  /// editor's chosen aspect (or the photo's own shape).
  (int, int) _canvasSize(_ExportArgs a, int iw, int ih) {
    switch (a.resizeMode) {
      case ResizeMode.original:
        final aspect = a.canvasAspect;
        if (aspect == null) return (iw, ih);
        final longer = iw > ih ? iw : ih;
        return aspect >= 1
            ? (longer, (longer / aspect).round().clamp(1, 1 << 14))
            : ((longer * aspect).round().clamp(1, 1 << 14), longer);
      case ResizeMode.square1x1:
        return (kResizePreset1x1.width.round(), kResizePreset1x1.height.round());
      case ResizeMode.portrait4x5:
        return (kResizePreset4x5.width.round(), kResizePreset4x5.height.round());
      case ResizeMode.portrait9x16:
        return (kResizePreset9x16.width.round(), kResizePreset9x16.height.round());
      case ResizeMode.custom:
        if (a.customWidth == null || a.customHeight == null) {
          throw const ExportException(
            'Custom resize selected but width/height not provided.',
          );
        }
        return (a.customWidth!, a.customHeight!);
    }
  }

  /// General path: background fills the canvas, the cut-out subject is
  /// fitted (never stretched), scaled and moved, with an optional shadow.
  img.Image _composeOnCanvas(_ExportArgs a, img.Image original, int cw, int ch) {
    final subject = _applyMaskAndBackground(
      original: original,
      maskBytes: a.maskBytes,
      backgroundType: BackgroundType.transparent,
      blurRadius: 0,
      edgeFeather: a.edgeFeather,
    );
    final place = placeSubject(
      imageWidth: original.width.toDouble(),
      imageHeight: original.height.toDouble(),
      canvasWidth: cw.toDouble(),
      canvasHeight: ch.toDouble(),
      scale: a.subjectScale,
      offsetX: a.subjectOffsetX,
      offsetY: a.subjectOffsetY,
    );
    final pw = place.width.round().clamp(1, 1 << 14);
    final ph = place.height.round().clamp(1, 1 << 14);
    final layer = (pw == original.width && ph == original.height)
        ? subject
        : img.copyResize(
            subject,
            width: pw,
            height: ph,
            interpolation: img.Interpolation.linear,
          );
    final left = place.left.round();
    final top = place.top.round();

    final canvas = _buildBackground(a, original, cw, ch);
    if (a.shadowOpacity > 0) {
      _paintShadow(canvas, layer, left, top, a.shadowOpacity);
    }
    _drawOver(canvas, layer, left, top);
    return canvas;
  }

  img.Image _buildBackground(_ExportArgs a, img.Image original, int cw, int ch) {
    final canvas = img.Image(width: cw, height: ch, numChannels: 4);
    switch (a.backgroundType) {
      case BackgroundType.transparent:
        return canvas; // all zero = fully transparent
      case BackgroundType.white:
        return canvas..clear(img.ColorRgba8(255, 255, 255, 255));
      case BackgroundType.black:
        return canvas..clear(img.ColorRgba8(0, 0, 0, 255));
      case BackgroundType.solidColor:
        final c = a.bgColorArgb == null ? const Color(0xFFFFFFFF) : Color(a.bgColorArgb!);
        return canvas
          ..clear(img.ColorRgba8(
            (c.r * 255).round(),
            (c.g * 255).round(),
            (c.b * 255).round(),
            255,
          ));
      case BackgroundType.gradient:
        final stops = kGradientPresets[a.gradientIndex.clamp(0, kGradientPresets.length - 1)];
        final top = Color(stops[0]);
        final bottom = Color(stops[1]);
        for (var y = 0; y < ch; y++) {
          final t = ch <= 1 ? 0.0 : y / (ch - 1);
          final r = ((top.r + (bottom.r - top.r) * t) * 255).round();
          final g = ((top.g + (bottom.g - top.g) * t) * 255).round();
          final b = ((top.b + (bottom.b - top.b) * t) * 255).round();
          for (var x = 0; x < cw; x++) {
            canvas.setPixelRgba(x, y, r, g, b, 255);
          }
        }
        return canvas;
      case BackgroundType.gaussianBlur:
        final blurred = img.gaussianBlur(
          img.Image.from(original),
          radius: a.blurRadius.round().clamp(
                kBackgroundBlurMinPx.round(),
                kBackgroundBlurMaxPx.round(),
              ),
        );
        return _coverFill(canvas, blurred);
      case BackgroundType.image:
        final bytes = a.bgImageBytes;
        final decoded = bytes == null ? null : img.decodeImage(bytes);
        if (decoded == null) {
          return canvas..clear(img.ColorRgba8(255, 255, 255, 255));
        }
        return _coverFill(canvas, decoded);
    }
  }

  /// Fill [canvas] with [source] scaled to cover it (centre-cropped).
  img.Image _coverFill(img.Image canvas, img.Image source) {
    final scale = math.max(
      canvas.width / source.width,
      canvas.height / source.height,
    );
    final w = (source.width * scale).ceil().clamp(canvas.width, 1 << 14);
    final h = (source.height * scale).ceil().clamp(canvas.height, 1 << 14);
    final resized = img.copyResize(
      source,
      width: w,
      height: h,
      interpolation: img.Interpolation.linear,
    );
    final x0 = (w - canvas.width) ~/ 2;
    final y0 = (h - canvas.height) ~/ 2;
    for (var y = 0; y < canvas.height; y++) {
      for (var x = 0; x < canvas.width; x++) {
        final p = resized.getPixel(x + x0, y + y0);
        canvas.setPixelRgba(x, y, p.r.toInt(), p.g.toInt(), p.b.toInt(), 255);
      }
    }
    return canvas;
  }

  /// Soft black shadow from the subject's own alpha, dropped slightly.
  void _paintShadow(
    img.Image canvas,
    img.Image layer,
    int left,
    int top,
    double opacity,
  ) {
    final longSide = math.max(canvas.width, canvas.height);
    final radius = math.max(1, (longSide * kShadowBlurFraction).round());
    final drop = (longSide * kShadowDropFraction).round();
    final pad = radius * 2;
    final sw = layer.width + pad * 2;
    final sh = layer.height + pad * 2;
    final alpha = img.Image(width: sw, height: sh, numChannels: 1);
    for (var y = 0; y < layer.height; y++) {
      for (var x = 0; x < layer.width; x++) {
        alpha.setPixelR(x + pad, y + pad, layer.getPixel(x, y).a.toInt());
      }
    }
    final blurred = img.gaussianBlur(alpha, radius: radius);
    for (var y = 0; y < sh; y++) {
      final cy = top - pad + y + drop;
      if (cy < 0 || cy >= canvas.height) continue;
      for (var x = 0; x < sw; x++) {
        final cx = left - pad + x;
        if (cx < 0 || cx >= canvas.width) continue;
        final a = blurred.getPixel(x, y).r.toInt() / 255.0 * opacity;
        if (a <= 0) continue;
        _blendPixel(canvas, cx, cy, 0, 0, 0, a);
      }
    }
  }

  /// Standard "over" composite of [src] onto [dst] at (x0, y0), clipped.
  void _drawOver(img.Image dst, img.Image src, int x0, int y0) {
    for (var sy = 0; sy < src.height; sy++) {
      final dy = y0 + sy;
      if (dy < 0 || dy >= dst.height) continue;
      for (var sx = 0; sx < src.width; sx++) {
        final dx = x0 + sx;
        if (dx < 0 || dx >= dst.width) continue;
        final p = src.getPixel(sx, sy);
        final a = p.a.toInt() / 255.0;
        if (a <= 0) continue;
        _blendPixel(dst, dx, dy, p.r.toInt(), p.g.toInt(), p.b.toInt(), a);
      }
    }
  }

  void _blendPixel(img.Image dst, int x, int y, int r, int g, int b, double a) {
    final d = dst.getPixel(x, y);
    final da = d.a.toInt() / 255.0;
    final outA = a + da * (1 - a);
    if (outA <= 0) return;
    final or = ((r * a + d.r.toInt() * da * (1 - a)) / outA).round();
    final og = ((g * a + d.g.toInt() * da * (1 - a)) / outA).round();
    final ob = ((b * a + d.b.toInt() * da * (1 - a)) / outA).round();
    dst.setPixelRgba(x, y, or, og, ob, (outA * 255).round());
  }

  img.Image _applyMaskAndBackground({
    required img.Image original,
    required Uint8List maskBytes,
    required BackgroundType backgroundType,
    Color? bgColor,
    required double blurRadius,
    required double edgeFeather,
  }) {
    final result = img.Image(
      width: original.width,
      height: original.height,
      numChannels: 4, // RGBA — needed for transparent/blur backgrounds
    );

    // Edge feather (Feature 11): soften the mask itself before compositing,
    // not the final image, so it only affects the subject/background
    // boundary rather than blurring the whole frame.
    final effectiveMask = edgeFeather > 0
        ? _featherMask(maskBytes, original.width, original.height, edgeFeather)
        : maskBytes;

    img.Image? backgroundLayer;
    switch (backgroundType) {
      case BackgroundType.white:
        backgroundLayer = img.Image(width: original.width, height: original.height)
          ..clear(img.ColorRgb8(255, 255, 255));
        break;
      case BackgroundType.black:
        backgroundLayer = img.Image(width: original.width, height: original.height)
          ..clear(img.ColorRgb8(0, 0, 0));
        break;
      case BackgroundType.solidColor:
        final c = bgColor ?? const Color(0xFFFFFFFF);
        backgroundLayer = img.Image(width: original.width, height: original.height)
          ..clear(img.ColorRgb8(
            (c.r * 255).round(),
            (c.g * 255).round(),
            (c.b * 255).round(),
          ));
        break;
      case BackgroundType.gaussianBlur:
        backgroundLayer = img.gaussianBlur(
          img.Image.from(original),
          radius: blurRadius.round().clamp(
                kBackgroundBlurMinPx.round(),
                kBackgroundBlurMaxPx.round(),
              ),
        );
        break;
      case BackgroundType.transparent:
      case BackgroundType.gradient:
      case BackgroundType.image:
        // gradient/image take the general canvas path; never reach here.
        backgroundLayer = null; // leave alpha=0 where mask says background
        break;
    }

    for (var y = 0; y < original.height; y++) {
      for (var x = 0; x < original.width; x++) {
        final maskIdx = y * original.width + x;
        final alpha = maskIdx < effectiveMask.length ? effectiveMask[maskIdx] : 0;
        final srcPixel = original.getPixel(x, y);

        if (backgroundLayer != null) {
          final bgPixel = backgroundLayer.getPixel(x, y);
          final blended = _blend(srcPixel, bgPixel, alpha / 255.0);
          result.setPixelRgba(x, y, blended.r, blended.g, blended.b, 255);
        } else {
          result.setPixelRgba(
            x,
            y,
            srcPixel.r.toInt(),
            srcPixel.g.toInt(),
            srcPixel.b.toInt(),
            alpha,
          );
        }
      }
    }
    return result;
  }

  ({int r, int g, int b}) _blend(img.Pixel fg, img.Pixel bg, double alpha) {
    return (
      r: (fg.r * alpha + bg.r * (1 - alpha)).round(),
      g: (fg.g * alpha + bg.g * (1 - alpha)).round(),
      b: (fg.b * alpha + bg.b * (1 - alpha)).round(),
    );
  }

  Uint8List _featherMask(
    Uint8List mask,
    int width,
    int height,
    double radiusPx,
  ) {
    // Represent mask as a single-channel image so package:image's own
    // gaussianBlur can do the softening — avoids hand-rolling a separable
    // blur kernel for a byte buffer.
    final maskImage = img.Image(width: width, height: height, numChannels: 1);
    for (var i = 0; i < mask.length && i < width * height; i++) {
      maskImage.setPixelR(i % width, i ~/ width, mask[i]);
    }
    final blurred = img.gaussianBlur(
      maskImage,
      radius: radiusPx.round().clamp(
            kEdgeFeatherMinPx.round(),
            kEdgeFeatherMaxPx.round(),
          ),
    );
    final out = Uint8List(width * height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        out[y * width + x] = blurred.getPixel(x, y).r.toInt();
      }
    }
    return out;
  }

  img.Image _flattenOntoWhite(img.Image withAlpha) {
    final flat = img.Image(width: withAlpha.width, height: withAlpha.height);
    for (var y = 0; y < withAlpha.height; y++) {
      for (var x = 0; x < withAlpha.width; x++) {
        final p = withAlpha.getPixel(x, y);
        final a = p.a / 255.0;
        flat.setPixelRgb(
          x,
          y,
          (p.r * a + 255 * (1 - a)).round(),
          (p.g * a + 255 * (1 - a)).round(),
          (p.b * a + 255 * (1 - a)).round(),
        );
      }
    }
    return flat;
  }

  /// WEBP has no encoder in package:image (confirmed decode-only). Route
  /// through the injectable _webpEncoder (flutter_image_compress by
  /// default) instead, encoding the already-composited PNG bytes. Falls
  /// back to JPG on UnsupportedError per flutter_image_compress's own
  /// documented pattern — WEBP requires a working platform encoder, not
  /// guaranteed on every device.
  Future<Uint8List> _encodeWebpWithFallback(
    Uint8List pngBytes, {
    required int quality,
  }) async {
    try {
      final webpBytes = await _webpEncoder(pngBytes, quality);
      if (webpBytes.isEmpty) {
        throw const ExportException(
          'WEBP encode returned empty result, falling back to JPG.',
        );
      }
      return webpBytes;
    } on UnsupportedError catch (_) {
      // Documented fallback pattern from flutter_image_compress's own
      // README — this device/platform combination can't produce WEBP.
      final decoded = img.decodePng(pngBytes);
      if (decoded == null) {
        throw const ExportException('WEBP export failed.');
      }
      return Uint8List.fromList(img.encodeJpg(decoded, quality: quality));
    } catch (e) {
      throw ExportException('WEBP export failed.', e);
    }
  }
}

/// Everything the isolate needs, as plain sendable data (Color travels as
/// an ARGB int).
class _ExportArgs {
  const _ExportArgs({
    required this.originalBytes,
    required this.maskBytes,
    required this.backgroundType,
    required this.bgColorArgb,
    required this.blurRadius,
    required this.edgeFeather,
    required this.format,
    required this.quality,
    required this.resizeMode,
    required this.customWidth,
    required this.customHeight,
    this.gradientIndex = 0,
    this.bgImageBytes,
    this.shadowOpacity = 0.0,
    this.subjectScale = 1.0,
    this.subjectOffsetX = 0.0,
    this.subjectOffsetY = 0.0,
    this.canvasAspect,
  });

  final Uint8List originalBytes;
  final Uint8List maskBytes;
  final BackgroundType backgroundType;
  final int? bgColorArgb;
  final double blurRadius;
  final double edgeFeather;
  final ExportFormat format;
  final int quality;
  final ResizeMode resizeMode;
  final int? customWidth;
  final int? customHeight;
  final int gradientIndex;
  final Uint8List? bgImageBytes;
  final double shadowOpacity;
  final double subjectScale;
  final double subjectOffsetX;
  final double subjectOffsetY;
  final double? canvasAspect;
}

Future<Uint8List> _unavailableWebpEncoder(Uint8List pngBytes, int quality) {
  throw UnsupportedError('WEBP encoding is not available in the isolate.');
}

Uint8List _exportInIsolate(_ExportArgs args) {
  return ExportService.forTesting(_unavailableWebpEncoder)
      ._compositeToBytes(args);
}
