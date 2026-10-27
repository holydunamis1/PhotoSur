import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photosur/generated/l10n/app_localizations.dart';
import 'package:photosur/widgets/preference_sheets.dart';

/// What Flutter picks for a phone's system language when the app setting is
/// "System default" (a first install). Uses the same resolution Flutter runs
/// at start-up, with the app's real supported locales.
String _pick(Locale system) => resolveAppLocale(
        [system], AppLocalizations.supportedLocales)
    .toLanguageTag();

Locale _l(String tag) {
  final p = tag.split('-');
  String? script;
  String? country;
  for (final x in p.skip(1)) {
    if (x.length == 4) script = x;
    if (x.length == 2 || x.length == 3 && int.tryParse(x) != null) country = x;
  }
  return Locale.fromSubtags(
      languageCode: p.first, scriptCode: script, countryCode: country);
}

void main() {
  // system language tag -> the app language it should start in
  const expected = <String, String>{
    'en-US': 'en', 'en-GB': 'en', 'en-IN': 'en',
    'es-ES': 'es', 'es-MX': 'es', 'es-419': 'es',
    'pt-BR': 'pt', 'pt-PT': 'pt',
    'fr-FR': 'fr', 'fr-CA': 'fr', 'de-DE': 'de', 'de-AT': 'de',
    'it-IT': 'it', 'nl-NL': 'nl', 'nl-BE': 'nl', 'sv-SE': 'sv',
    'da-DK': 'da', 'fi-FI': 'fi', 'nb-NO': 'nb', 'pl-PL': 'pl',
    'cs-CZ': 'cs', 'sk-SK': 'sk', 'hu-HU': 'hu', 'ro-RO': 'ro',
    'bg-BG': 'bg', 'el-GR': 'el', 'uk-UA': 'uk', 'ru-RU': 'ru',
    'tr-TR': 'tr', 'ca-ES': 'ca',
    'ar-SA': 'ar', 'ar-EG': 'ar', 'he-IL': 'he', 'fa-IR': 'fa', 'ur-PK': 'ur',
    'hi-IN': 'hi', 'bn-BD': 'bn', 'bn-IN': 'bn', 'mr-IN': 'mr', 'gu-IN': 'gu',
    'ta-IN': 'ta', 'te-IN': 'te', 'ml-IN': 'ml',
    'id-ID': 'id', 'ms-MY': 'ms', 'fil-PH': 'fil', 'vi-VN': 'vi', 'th-TH': 'th',
    // Old codes some phones still report.
    'iw-IL': 'he', 'in-ID': 'id', 'tl-PH': 'fil', 'no-NO': 'nb', 'nn-NO': 'nb',
    'ja-JP': 'ja', 'ko-KR': 'ko', 'sw-KE': 'sw', 'sw-TZ': 'sw',
    // Chinese: simplified for mainland and Singapore, traditional for
    // Taiwan, Hong Kong and Macau, with or without an explicit script.
    'zh-CN': 'zh', 'zh-SG': 'zh', 'zh-Hans-CN': 'zh',
    'zh-TW': 'zh_Hant', 'zh-HK': 'zh_Hant', 'zh-MO': 'zh_Hant',
    'zh-Hant-TW': 'zh_Hant', 'zh-Hant-HK': 'zh_Hant',
    // Languages the app does not ship: English, never an arbitrary language.
    'af-ZA': 'en', 'zu-ZA': 'en', 'is-IS': 'en', 'et-EE': 'en', 'lv-LV': 'en',
    'lt-LT': 'en', 'sl-SI': 'en', 'hr-HR': 'en', 'sr-RS': 'en', 'ka-GE': 'en',
    'hy-AM': 'en', 'am-ET': 'en', 'ne-NP': 'en', 'si-LK': 'en', 'km-KH': 'en',
  };

  test('first install follows the phone language (system default)', () {
    final wrong = <String>[];
    expected.forEach((tag, want) {
      final got = _pick(_l(tag));
      final gotCode = got.replaceAll('-', '_');
      final wantTag = want.replaceAll('_', '-');
      final ok = want == 'zh_Hant'
          ? got.contains('Hant')
          : (got.split('-').first == want && !got.contains('Hant'));
      if (!ok) wrong.add('$tag -> $gotCode (wanted $wantTag)');
    });
    expect(wrong, isEmpty,
        reason: 'Wrong start language for: ${wrong.join('; ')}');
  });

  test('the first phone language the app ships wins', () {
    final supported = AppLocalizations.supportedLocales;
    expect(resolveAppLocale([_l('hr-HR'), _l('de-DE')], supported).languageCode,
        'de');
    expect(resolveAppLocale([_l('af-ZA'), _l('en-US')], supported).languageCode,
        'en');
    expect(resolveAppLocale([_l('zu-ZA'), _l('zh-TW')], supported).toLanguageTag(),
        contains('Hant'));
    expect(resolveAppLocale(null, supported).languageCode, 'en');
    expect(resolveAppLocale(const [], supported).languageCode, 'en');
  });

  test('manual choice overrides the system language', () {
    for (final entry in {
      'de': 'de', 'ar': 'ar', 'zh': 'zh', 'zh_Hant': 'zh', 'ja': 'ja',
    }.entries) {
      final locale = localeForSetting(entry.key);
      expect(locale, isNotNull, reason: entry.key);
      expect(locale!.languageCode, entry.value, reason: entry.key);
    }
    // A manual Traditional Chinese choice keeps its script.
    expect(localeForSetting('zh_Hant')!.scriptCode, 'Hant');
    expect(localeForSetting(kLanguageSystem), isNull);
    expect(localeForSetting('not-a-language'), isNull);
  });
}
