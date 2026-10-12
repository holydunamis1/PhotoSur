import 'dart:math' as math;
import 'dart:typed_data';

/// Pure-Dart clean-up of a segmentation mask (no plugins, no dart:io, no
/// dart:ui). Runs after the model's coarse 320x320 output has been enlarged
/// to the photo's size:
///
///  1. [removeSpecks]  - drops tiny disconnected blobs and plugs pin-holes.
///  2. [guidedRefine]  - snaps soft edges to real edges in the photo
///     (guided filter, computed on a reduced grid so it stays cheap).
///
/// [refineMask] runs both. It never throws on a size mismatch: it returns
/// the mask unchanged, so a refinement problem can never break cut-outs.

/// Longest side of the grid used for blob analysis.
const int kBlobGridMax = 512;

/// Blobs smaller than this fraction of the largest blob are removed.
const double kMinBlobFraction = 0.04;

/// Enclosed background holes up to this fraction of the subject are filled.
/// Deliberately small: a gap between an arm and a torso is real background.
const double kMaxHoleFraction = 0.01;

/// Longest side of the grid used by the guided filter.
const int kGuideGridMax = 768;

/// Guided-filter window radius, in grid pixels, as a fraction of the grid's
/// longest side, and its edge-stopping epsilon (guide range 0..1).
const double kGuideRadiusFraction = 0.011;
const double kGuideEpsilon = 0.0004;

/// Final contrast band applied to the refined alpha.
const double kRefineCurveLow = 0.10;
const double kRefineCurveHigh = 0.90;

Uint8List refineMask(Uint8List mask, Uint8List guideGray, int w, int h) {
  if (w <= 0 || h <= 0 || mask.length != w * h || guideGray.length != w * h) {
    return mask;
  }
  final cleaned = removeSpecks(mask, w, h);
  return guidedRefine(cleaned, guideGray, w, h);
}

// ---------------------------------------------------------------------------
// 1. Specks and pin-holes
// ---------------------------------------------------------------------------

Uint8List removeSpecks(Uint8List mask, int w, int h) {
  if (mask.length != w * h || w <= 0 || h <= 0) return mask;

  final f = math.max(1, (math.max(w, h) / kBlobGridMax).ceil());
  final gw = (w + f - 1) ~/ f;
  final gh = (h + f - 1) ~/ f;

  // Foreground grid: a cell is foreground when its average alpha >= 128.
  final fg = Uint8List(gw * gh);
  for (var gy = 0; gy < gh; gy++) {
    final y0 = gy * f;
    final y1 = math.min(h, y0 + f);
    for (var gx = 0; gx < gw; gx++) {
      final x0 = gx * f;
      final x1 = math.min(w, x0 + f);
      var sum = 0;
      for (var y = y0; y < y1; y++) {
        final row = y * w;
        for (var x = x0; x < x1; x++) {
          sum += mask[row + x];
        }
      }
      final count = (y1 - y0) * (x1 - x0);
      fg[gy * gw + gx] = (sum / count) >= 128 ? 1 : 0;
    }
  }

  final labels = Int32List(gw * gh); // 0 = background / unlabeled
  final areas = <int>[0]; // index = label
  final queue = Int32List(gw * gh);
  var nextLabel = 1;
  for (var i = 0; i < fg.length; i++) {
    if (fg[i] == 0 || labels[i] != 0) continue;
    final label = nextLabel++;
    var head = 0;
    var tail = 0;
    queue[tail++] = i;
    labels[i] = label;
    var area = 0;
    while (head < tail) {
      final c = queue[head++];
      area++;
      final cx = c % gw;
      final cy = c ~/ gw;
      if (cx > 0 && fg[c - 1] == 1 && labels[c - 1] == 0) {
        labels[c - 1] = label;
        queue[tail++] = c - 1;
      }
      if (cx < gw - 1 && fg[c + 1] == 1 && labels[c + 1] == 0) {
        labels[c + 1] = label;
        queue[tail++] = c + 1;
      }
      if (cy > 0 && fg[c - gw] == 1 && labels[c - gw] == 0) {
        labels[c - gw] = label;
        queue[tail++] = c - gw;
      }
      if (cy < gh - 1 && fg[c + gw] == 1 && labels[c + gw] == 0) {
        labels[c + gw] = label;
        queue[tail++] = c + gw;
      }
    }
    areas.add(area);
  }
  if (nextLabel == 1) return mask; // nothing found

  var largest = 0;
  var totalFg = 0;
  for (var l = 1; l < areas.length; l++) {
    largest = math.max(largest, areas[l]);
    totalFg += areas[l];
  }
  final keep = List<bool>.generate(
    areas.length,
    (l) => l != 0 && areas[l] >= largest * kMinBlobFraction,
  );

  // Enclosed background holes: background cells not connected to the grid
  // border. Flood the background from the border, the rest are holes.
  final outside = Uint8List(gw * gh);
  var head = 0;
  var tail = 0;
  void seed(int c) {
    if (fg[c] == 0 && outside[c] == 0) {
      outside[c] = 1;
      queue[tail++] = c;
    }
  }

  for (var x = 0; x < gw; x++) {
    seed(x);
    seed((gh - 1) * gw + x);
  }
  for (var y = 0; y < gh; y++) {
    seed(y * gw);
    seed(y * gw + gw - 1);
  }
  while (head < tail) {
    final c = queue[head++];
    final cx = c % gw;
    final cy = c ~/ gw;
    if (cx > 0) seed(c - 1);
    if (cx < gw - 1) seed(c + 1);
    if (cy > 0) seed(c - gw);
    if (cy < gh - 1) seed(c + gw);
  }

  // Group the enclosed cells into holes and keep only the small ones.
  final holeLabel = Int32List(gw * gh);
  final holeAreas = <int>[0];
  for (var i = 0; i < fg.length; i++) {
    if (fg[i] == 1 || outside[i] == 1 || holeLabel[i] != 0) continue;
    final label = holeAreas.length;
    head = 0;
    tail = 0;
    queue[tail++] = i;
    holeLabel[i] = label;
    var area = 0;
    while (head < tail) {
      final c = queue[head++];
      area++;
      final cx = c % gw;
      final cy = c ~/ gw;
      void visit(int n) {
        if (fg[n] == 0 && outside[n] == 0 && holeLabel[n] == 0) {
          holeLabel[n] = label;
          queue[tail++] = n;
        }
      }

      if (cx > 0) visit(c - 1);
      if (cx < gw - 1) visit(c + 1);
      if (cy > 0) visit(c - gw);
      if (cy < gh - 1) visit(c + gw);
    }
    holeAreas.add(area);
  }
  final maxHole = math.max(1.0, totalFg * kMaxHoleFraction);

  final out = Uint8List.fromList(mask);
  var changed = false;
  for (var gy = 0; gy < gh; gy++) {
    final y0 = gy * f;
    final y1 = math.min(h, y0 + f);
    for (var gx = 0; gx < gw; gx++) {
      final cell = gy * gw + gx;
      final label = labels[cell];
      final hole = holeLabel[cell];
      int? value;
      if (label != 0 && !keep[label]) {
        value = 0; // stray blob
      } else if (hole != 0 && holeAreas[hole] <= maxHole) {
        value = 255; // pin-hole inside the subject
      }
      if (value == null) continue;
      changed = true;
      final x0 = gx * f;
      final x1 = math.min(w, x0 + f);
      for (var y = y0; y < y1; y++) {
        final row = y * w;
        for (var x = x0; x < x1; x++) {
          out[row + x] = value == 0 ? 0 : math.max(out[row + x], 255);
        }
      }
    }
  }
  return changed ? out : mask;
}

// ---------------------------------------------------------------------------
// 2. Guided filter
// ---------------------------------------------------------------------------

/// Mean over a (2r+1) square window, edge-normalised, via an integral image.
Float32List _boxMean(Float32List src, int w, int h, int r) {
  final stride = w + 1;
  final integral = Float64List((w + 1) * (h + 1));
  for (var y = 0; y < h; y++) {
    var rowSum = 0.0;
    for (var x = 0; x < w; x++) {
      rowSum += src[y * w + x];
      integral[(y + 1) * stride + (x + 1)] = integral[y * stride + (x + 1)] + rowSum;
    }
  }
  final out = Float32List(w * h);
  for (var y = 0; y < h; y++) {
    final y0 = math.max(0, y - r);
    final y1 = math.min(h, y + r + 1);
    for (var x = 0; x < w; x++) {
      final x0 = math.max(0, x - r);
      final x1 = math.min(w, x + r + 1);
      final sum = integral[y1 * stride + x1] -
          integral[y0 * stride + x1] -
          integral[y1 * stride + x0] +
          integral[y0 * stride + x0];
      out[y * w + x] = sum / ((y1 - y0) * (x1 - x0));
    }
  }
  return out;
}

Float32List _downsample(Uint8List src, int w, int h, int f, int gw, int gh) {
  final out = Float32List(gw * gh);
  for (var gy = 0; gy < gh; gy++) {
    final y0 = gy * f;
    final y1 = math.min(h, y0 + f);
    for (var gx = 0; gx < gw; gx++) {
      final x0 = gx * f;
      final x1 = math.min(w, x0 + f);
      var sum = 0;
      for (var y = y0; y < y1; y++) {
        final row = y * w;
        for (var x = x0; x < x1; x++) {
          sum += src[row + x];
        }
      }
      out[gy * gw + gx] = sum / ((y1 - y0) * (x1 - x0) * 255.0);
    }
  }
  return out;
}

/// Bilinear sample of a coarse grid at full-resolution pixel (x, y) with
/// the half-pixel-centre convention, edge-clamped.
double _sampleGrid(Float32List grid, int gw, int gh, double fx, double fy) {
  final x = math.max(0.0, math.min(fx, gw - 1.0));
  final y = math.max(0.0, math.min(fy, gh - 1.0));
  final x0 = x.floor();
  final y0 = y.floor();
  final x1 = math.min(x0 + 1, gw - 1);
  final y1 = math.min(y0 + 1, gh - 1);
  final tx = x - x0;
  final ty = y - y0;
  final top = grid[y0 * gw + x0] * (1 - tx) + grid[y0 * gw + x1] * tx;
  final bottom = grid[y1 * gw + x0] * (1 - tx) + grid[y1 * gw + x1] * tx;
  return top * (1 - ty) + bottom * ty;
}

double _smooth(double x, double a, double b) {
  final t = math.max(0.0, math.min((x - a) / (b - a), 1.0));
  return t * t * (3 - 2 * t);
}

Uint8List guidedRefine(Uint8List mask, Uint8List guideGray, int w, int h) {
  if (mask.length != w * h || guideGray.length != w * h) return mask;

  final f = math.max(1, (math.max(w, h) / kGuideGridMax).ceil());
  final gw = (w + f - 1) ~/ f;
  final gh = (h + f - 1) ~/ f;
  final r = math.max(2, (math.max(gw, gh) * kGuideRadiusFraction).round());

  final guide = _downsample(guideGray, w, h, f, gw, gh); // I
  final alpha = _downsample(mask, w, h, f, gw, gh); // p

  final n = gw * gh;
  final ii = Float32List(n);
  final ip = Float32List(n);
  for (var i = 0; i < n; i++) {
    ii[i] = guide[i] * guide[i];
    ip[i] = guide[i] * alpha[i];
  }
  final meanI = _boxMean(guide, gw, gh, r);
  final meanP = _boxMean(alpha, gw, gh, r);
  final corrI = _boxMean(ii, gw, gh, r);
  final corrIp = _boxMean(ip, gw, gh, r);

  final a = Float32List(n);
  final b = Float32List(n);
  for (var i = 0; i < n; i++) {
    final varI = corrI[i] - meanI[i] * meanI[i];
    final covIp = corrIp[i] - meanI[i] * meanP[i];
    final ai = covIp / (varI + kGuideEpsilon);
    a[i] = ai;
    b[i] = meanP[i] - ai * meanI[i];
  }
  final meanA = _boxMean(a, gw, gh, r);
  final meanB = _boxMean(b, gw, gh, r);

  final out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    final fy = (y + 0.5) / f - 0.5;
    for (var x = 0; x < w; x++) {
      final fx = (x + 0.5) / f - 0.5;
      final av = _sampleGrid(meanA, gw, gh, fx, fy);
      final bv = _sampleGrid(meanB, gw, gh, fx, fy);
      final q = av * (guideGray[y * w + x] / 255.0) + bv;
      final v = _smooth(math.max(0.0, math.min(q, 1.0)), kRefineCurveLow, kRefineCurveHigh);
      out[y * w + x] = (v * 255 + 0.5).floor();
    }
  }
  return out;
}
