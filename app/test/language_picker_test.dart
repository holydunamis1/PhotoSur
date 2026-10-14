import 'package:flutter_test/flutter_test.dart';
import 'package:photosur/generated/l10n/app_localizations.dart';
import 'package:photosur/widgets/preference_sheets.dart';

void main() {
  test('every shipped language has native and English names', () {
    for (final locale in AppLocalizations.supportedLocales) {
      final code = languageCodeOf(locale);
      expect(kLanguageNativeNames.containsKey(code), isTrue, reason: code);
      expect(kLanguageEnglishNames.containsKey(code), isTrue, reason: code);
    }
  });

  test('picker order: system first, rest sorted by English name', () {
    final codes = sortedLanguageCodes();
    expect(codes.first, kLanguageSystem);
    final names = [
      for (final c in codes.skip(1)) kLanguageEnglishNames[c]!.toLowerCase(),
    ];
    expect(names, [...names]..sort());
    expect(codes.length, AppLocalizations.supportedLocales.length + 1);
  });

  test('search matches native name, English name and code', () {
    final codes = sortedLanguageCodes();
    String label(String c) =>
        c == kLanguageSystem ? 'System default' : kLanguageNativeNames[c]!;
    expect(filterLanguageCodes(codes, 'hindi', label), ['hi']);
    expect(filterLanguageCodes(codes, 'हिन्दी', label), ['hi']);
    expect(filterLanguageCodes(codes, 'zh_hant', label), ['zh_Hant']);
    expect(filterLanguageCodes(codes, '  ', label), codes);
    expect(filterLanguageCodes(codes, 'qqqq', label), isEmpty);
  });
}
