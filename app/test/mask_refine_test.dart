import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:katharerase/core/services/mask_refine.dart';

Uint8List _blank(int w, int h, [int v = 0]) =>
    Uint8List(w * h)..fillRange(0, w * h, v);

void _rect(Uint8List m, int w, int x0, int y0, int x1, int y1, int v) {
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      m[y * w + x] = v;
    }
  }
}

void main() {
  const w = 200;
  const h = 200;

  group('removeSpecks', () {
    test('drops a tiny stray blob but keeps the subject', () {
      final m = _blank(w, h);
      _rect(m, w, 40, 40, 160, 160, 255); // subject
      _rect(m, w, 5, 5, 9, 9, 255); // speck
      final out = removeSpecks(m, w, h);
      expect(out[7 * w + 7], 0);
      expect(out[100 * w + 100], 255);
    });

    test('keeps a second object that is big enough', () {
      final m = _blank(w, h);
      _rect(m, w, 10, 10, 100, 100, 255);
      _rect(m, w, 120, 120, 190, 190, 255); // ~60% of the first
      final out = removeSpecks(m, w, h);
      expect(out[150 * w + 150], 255);
    });

    test('fills a pin-hole but keeps a large gap', () {
      final m = _blank(w, h);
      _rect(m, w, 20, 20, 180, 180, 255);
      _rect(m, w, 50, 50, 53, 53, 0); // pin-hole
      _rect(m, w, 100, 60, 140, 140, 0); // big enclosed gap
      final out = removeSpecks(m, w, h);
      expect(out[51 * w + 51], 255);
      expect(out[100 * w + 120], 0);
    });

    test('returns an empty or full mask untouched', () {
      expect(removeSpecks(_blank(w, h), w, h), everyElement(0));
      expect(removeSpecks(_blank(w, h, 255), w, h), everyElement(255));
    });
  });

  group('guidedRefine', () {
    test('makes a soft edge narrower and keeps it on the photo edge', () {
      // Photo: dark left half, bright right half, sharp edge at x = 100.
      final guide = Uint8List(w * h);
      final soft = Uint8List(w * h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          guide[y * w + x] = x < 100 ? 50 : 200;
          // Subject is the dark side; its mask has a wide soft ramp.
          final t = ((x - 90) / 20.0).clamp(0.0, 1.0);
          soft[y * w + x] = ((1 - t) * 255).round();
        }
      }
      int width(Uint8List m) {
        var hi = -1;
        var lo = -1;
        for (var x = 0; x < w; x++) {
          final v = m[100 * w + x];
          if (hi < 0 && v < 230) hi = x;
          if (lo < 0 && v < 25) lo = x;
        }
        return lo - hi;
      }

      final out = guidedRefine(soft, guide, w, h);
      expect(width(out), lessThan(width(soft)));
      // Fully inside the subject stays opaque, fully outside stays clear.
      expect(out[100 * w + 20], greaterThan(240));
      expect(out[100 * w + 180], lessThan(15));
    });

    test('leaves uniform masks uniform', () {
      final guide = _blank(w, h, 128);
      expect(guidedRefine(_blank(w, h, 255), guide, w, h), everyElement(255));
      expect(guidedRefine(_blank(w, h), guide, w, h), everyElement(0));
    });
  });

  group('refineMask', () {
    test('returns the input when sizes do not match', () {
      final m = _blank(w, h, 255);
      expect(identical(refineMask(m, _blank(10, 10), w, h), m), isTrue);
    });

    test('handles a large photo-sized mask', () {
      const bw = 1600;
      const bh = 1200;
      final m = _blank(bw, bh);
      _rect(m, bw, 400, 300, 1200, 900, 255);
      final guide = _blank(bw, bh, 120);
      final out = refineMask(m, guide, bw, bh);
      expect(out.length, bw * bh);
      expect(out[600 * bw + 800], 255);
      expect(out[10 * bw + 10], 0);
    });
  });
}
