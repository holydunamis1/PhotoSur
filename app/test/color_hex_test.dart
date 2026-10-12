import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:katharerase/core/utils/color_hex.dart';

void main() {
  test('parses long, short, prefixed and mixed-case forms', () {
    expect(parseHexColor('#10B981'), const Color(0xFF10B981));
    expect(parseHexColor('10b981'), const Color(0xFF10B981));
    expect(parseHexColor(' #fa0 '), const Color(0xFFFFAA00));
  });

  test('rejects bad input', () {
    for (final bad in ['', '#', '12345', '1234567', 'GGGGGG', '#12 456']) {
      expect(parseHexColor(bad), isNull, reason: bad);
    }
  });

  test('round trip', () {
    expect(colorToHex(const Color(0xFF0B9A6E)), '#0B9A6E');
    expect(colorToHex(const Color(0xFF000000)), '#000000');
    expect(parseHexColor(colorToHex(const Color(0xFF123456))),
        const Color(0xFF123456));
  });
}
