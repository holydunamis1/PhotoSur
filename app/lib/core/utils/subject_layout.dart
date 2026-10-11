import 'dart:math' as math;
import 'dart:typed_data';

/// Where the photo (subject layer) lands on the output canvas.
///
/// The photo is first fitted ("contain") inside the canvas, then multiplied
/// by [scale], then shifted by [offsetX]/[offsetY] expressed as fractions of
/// the canvas width/height. The editor preview and the exporter both call
/// this one function, so what you see is what you export.
class SubjectPlacement {
  const SubjectPlacement({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;
}

SubjectPlacement placeSubject({
  required double imageWidth,
  required double imageHeight,
  required double canvasWidth,
  required double canvasHeight,
  double scale = 1.0,
  double offsetX = 0.0,
  double offsetY = 0.0,
}) {
  final fit = math.min(canvasWidth / imageWidth, canvasHeight / imageHeight);
  final w = imageWidth * fit * scale;
  final h = imageHeight * fit * scale;
  return SubjectPlacement(
    left: (canvasWidth - w) / 2 + offsetX * canvasWidth,
    top: (canvasHeight - h) / 2 + offsetY * canvasHeight,
    width: w,
    height: h,
  );
}

/// Pixel bounds of everything the mask keeps, or null if the mask is empty.
({int left, int top, int right, int bottom})? subjectBounds(
  Uint8List mask,
  int width,
  int height, {
  int threshold = 128,
}) {
  var minX = width, minY = height, maxX = -1, maxY = -1;
  final n = math.min(mask.length, width * height);
  for (var i = 0; i < n; i++) {
    if (mask[i] >= threshold) {
      final x = i % width;
      final y = i ~/ width;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }
  if (maxX < 0) return null;
  return (left: minX, top: minY, right: maxX + 1, bottom: maxY + 1);
}

/// Scale and offset that centre the subject on the canvas and make it fill
/// up to `1 - 2 * margin` of the canvas in its tighter direction.
({double scale, double offsetX, double offsetY}) autoCenterLayout({
  required ({int left, int top, int right, int bottom}) bounds,
  required double imageWidth,
  required double imageHeight,
  required double canvasWidth,
  required double canvasHeight,
  double margin = 0.08,
  double minScale = 0.2,
  double maxScale = 3.0,
}) {
  final fit = math.min(canvasWidth / imageWidth, canvasHeight / imageHeight);
  final bw = (bounds.right - bounds.left) * fit;
  final bh = (bounds.bottom - bounds.top) * fit;
  final usable = 1 - 2 * margin;
  final wanted = math.min(canvasWidth * usable / bw, canvasHeight * usable / bh);
  final scale = wanted.clamp(minScale, maxScale).toDouble();
  final cx = (bounds.left + bounds.right) / 2;
  final cy = (bounds.top + bounds.bottom) / 2;
  final offPxX = -(cx - imageWidth / 2) * fit * scale;
  final offPxY = -(cy - imageHeight / 2) * fit * scale;
  return (
    scale: scale,
    offsetX: offPxX / canvasWidth,
    offsetY: offPxY / canvasHeight,
  );
}
