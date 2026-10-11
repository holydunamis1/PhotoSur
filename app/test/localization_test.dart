import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:katharerase/app.dart';
import 'package:katharerase/core/providers/ad_provider.dart';
import 'package:katharerase/core/providers/image_edit_provider.dart';
import 'package:katharerase/core/providers/settings_provider.dart';
import 'package:katharerase/core/providers/subscription_provider.dart';
import 'package:katharerase/core/providers/theme_provider.dart';
import 'package:katharerase/generated/l10n/app_localizations.dart';
import 'package:katharerase/screens/home_screen.dart';
import 'package:katharerase/screens/onboarding_screen.dart';
import 'package:katharerase/widgets/preference_sheets.dart';

const _languages = [
  'es', 'pt', 'fr', 'de', 'hi', 'id', 'ar', 'tr', //
  'he', 'ja', 'ko', 'zh', 'ru', 'it', 'pl', 'vi', 'th', //
  'zh_Hant', 'nl', 'uk', 'sv', 'bn', 'ur', 'fa', 'fil', 'ms', //
  'ta', 'te', 'mr', 'gu', 'sw', 'ro', //
  'ml', 'el', 'cs', 'hu', 'da',
];

/// Languages written right-to-left.
const _rtl = {'ar', 'he', 'ur', 'fa'};

Map<String, dynamic> _arb(String code) =>
    jsonDecode(File('lib/l10n/app_$code.arb').readAsStringSync())
        as Map<String, dynamic>;

Set<String> _keys(Map<String, dynamic> arb) =>
    arb.keys.where((k) => !k.startsWith('@')).toSet();

Set<String> _placeholders(String text) =>
    RegExp(r'\{(\w+)\}').allMatches(text).map((m) => m.group(1)!).toSet();

KatharEraseApp _app(SettingsProvider settings) {
  final subscription = SubscriptionProvider(settings);
  return KatharEraseApp(
    themeProvider: ThemeProvider(),
    settingsProvider: settings,
    subscriptionProvider: subscription,
    adProvider: AdProvider(subscription),
    imageEditProvider: ImageEditProvider(),
  );
}

void main() {
  final en = _arb('en');
  final enKeys = _keys(en);

  group('ARB files', () {
    for (final code in _languages) {
      test('$code has exactly the English keys', () {
        final arb = _arb(code);
        expect(arb['@@locale'], code);
        expect(_keys(arb), enKeys);
      });

      test('$code keeps every placeholder and has no empty value', () {
        final arb = _arb(code);
        for (final key in enKeys) {
          final value = arb[key] as String;
          expect(value.trim(), isNotEmpty, reason: '$code/$key empty');
          expect(
            _placeholders(value),
            _placeholders(en[key] as String),
            reason: '$code/$key placeholders differ',
          );
        }
      });

      test('$code is actually translated (not a copy of English)', () {
        final arb = _arb(code);
        final same = enKeys.where((k) => arb[k] == en[k]).length;
        // Brand name, format names, ratios and a few cognates may match.
        expect(same, lessThan(30), reason: '$code looks untranslated');
      });
    }

    // Short labels live in chips, tabs and buttons where a long word
    // overflows; sentences wrap, so only labels are length-checked.
    const labelKeys = [
      'brushErase', 'brushRestore', 'exportResizeCustom',
      'exportResizeOriginal', 'backgroundTransparent', 'editorToolCutout',
      'editorToolBrush', 'editorToolBackground', 'cropAspectFree',
      'toolbarExport', 'toolbarReset', 'onboardingNext',
      'onboardingGetStarted', 'homeCameraButton', 'homeGalleryButton',
      'cropContinue', 'exportShare',
    ];
    for (final code in _languages) {
      test('$code short UI labels are at most 16 characters', () {
        final arb = _arb(code);
        for (final key in labelKeys) {
          expect((arb[key] as String).length, lessThanOrEqualTo(16),
              reason: '$code/$key');
        }
      });
    }
  });

  group('language list', () {
    test('every supported locale has a native name', () {
      for (final locale in AppLocalizations.supportedLocales) {
        expect(kLanguageNativeNames.containsKey(languageCodeOf(locale)), isTrue,
            reason: languageCodeOf(locale));
      }
      expect(AppLocalizations.supportedLocales.length, _languages.length + 1);
    });
  });

  group('app boots in every language', () {
    for (final code in ['en', ..._languages]) {
      testWidgets('$code: onboarding and home build without errors',
          (tester) async {
        final settings = SettingsProvider();
        settings.value = settings.value.copyWith(language: code);
        await tester.pumpWidget(_app(settings));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        expect(find.byType(OnboardingScreen), findsOneWidget);

        final context = tester.element(find.byType(OnboardingScreen));
        expect(
          Directionality.of(context),
          _rtl.contains(code) ? TextDirection.rtl : TextDirection.ltr,
        );
        expect(languageCodeOf(Localizations.localeOf(context)), code);
      });

      testWidgets('$code: home screen has no layout overflow', (tester) async {
        final settings = SettingsProvider();
        settings.value = settings.value
            .copyWith(language: code, hasCompletedOnboarding: true);
        await tester.pumpWidget(_app(settings));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        expect(find.byType(HomeScreen), findsOneWidget);
        await tester.pump(const Duration(seconds: 31));
        expect(tester.takeException(), isNull);
      });
    }
  });
}
