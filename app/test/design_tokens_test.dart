import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photosur/core/theme/app_theme.dart';
import 'package:photosur/core/theme/app_tokens.dart';

double _channel(double v) =>
    v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

/// WCAG 2.x contrast ratio.
double contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  for (final entry in {
    'light': AppPalette.light,
    'dark': AppPalette.dark,
  }.entries) {
    final p = entry.value;
    final name = entry.key;

    group('$name palette meets WCAG AA (4.5:1) for text', () {
      final pairs = <String, (Color, Color)>{
        'text on background': (p.text, p.background),
        'text on surface': (p.text, p.surface),
        'text on muted': (p.text, p.muted),
        'secondary text on background': (p.text2, p.background),
        'secondary text on surface': (p.text2, p.surface),
        'secondary text on muted': (p.text2, p.muted),
        'tertiary text on background': (p.text3, p.background),
        'tertiary text on surface': (p.text3, p.surface),
        'button label on accent': (p.onAccent, p.accent),
        'accent text on surface': (p.accentText, p.surface),
        'accent text on background': (p.accentText, p.background),
        'accent text on selected tint': (p.accentText, p.accentTint),
        'error text on surface': (p.danger, p.surface),
      };
      pairs.forEach((label, colors) {
        test(label, () {
          expect(
            contrast(colors.$1, colors.$2),
            greaterThanOrEqualTo(4.5),
            reason: '$name: $label',
          );
        });
      });
    });
  }

  group('theme', () {
    test('light and dark themes use their own palette', () {
      final light = buildAppTheme(Brightness.light);
      final dark = buildAppTheme(Brightness.dark);

      expect(light.colorScheme.primary, AppPalette.light.accent);
      expect(dark.colorScheme.primary, AppPalette.dark.accent);
      expect(light.scaffoldBackgroundColor, AppPalette.light.background);
      expect(dark.scaffoldBackgroundColor, AppPalette.dark.background);
      expect(light.extension<AppTokens>()!.palette, AppPalette.light);
      expect(dark.extension<AppTokens>()!.palette, AppPalette.dark);
    });

    test('dark text is light and light text is dark (no light-theme text in dark mode)',
        () {
      final dark = buildAppTheme(Brightness.dark);
      final light = buildAppTheme(Brightness.light);
      expect(dark.textTheme.bodyLarge!.color, AppPalette.dark.text);
      expect(light.textTheme.bodyLarge!.color, AppPalette.light.text);
    });

    test('one typeface everywhere', () {
      final t = buildAppTheme(Brightness.light);
      expect(t.textTheme.titleLarge!.fontFamily, kFontFamily);
      expect(t.textTheme.bodyMedium!.fontFamily, kFontFamily);
      expect(t.textTheme.labelSmall!.fontFamily, kFontFamily);
    });

    test('chips have no cramped checkmark; sheets show a drag handle', () {
      final t = buildAppTheme(Brightness.light);
      expect(t.chipTheme.showCheckmark, isFalse);
      expect(t.bottomSheetTheme.showDragHandle, isTrue);
    });

    test('iOS-style page transitions on Android', () {
      final t = buildAppTheme(Brightness.light);
      expect(
        t.pageTransitionsTheme.builders[TargetPlatform.android],
        isA<CupertinoPageTransitionsBuilder>(),
      );
    });

    test('filled buttons are at least 48 px tall', () {
      final t = buildAppTheme(Brightness.light);
      final min = t.filledButtonTheme.style!.minimumSize!.resolve({});
      expect(min!.height, greaterThanOrEqualTo(48));
    });
  });
}
