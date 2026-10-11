import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models/user_settings.dart';
import '../core/providers/settings_provider.dart';
import '../core/providers/theme_provider.dart';
import '../generated/l10n/app_localizations.dart';

/// Stored value meaning "follow the device language".
const String kLanguageSystem = 'system';

/// Native names of the languages the app ships. Add an entry here whenever
/// a new lib/l10n/app_<code>.arb is added.
const Map<String, String> kLanguageNativeNames = {
  'en': 'English',
  'es': 'Español',
  'pt': 'Português (Brasil)',
  'fr': 'Français',
  'de': 'Deutsch',
  'hi': 'हिन्दी',
  'id': 'Bahasa Indonesia',
  'ar': 'العربية',
  'tr': 'Türkçe',
  'he': 'עברית',
  'ja': '日本語',
  'ko': '한국어',
  'zh': '简体中文',
  'ru': 'Русский',
  'it': 'Italiano',
  'pl': 'Polski',
  'vi': 'Tiếng Việt',
  'th': 'ไทย',
  'zh_Hant': '繁體中文',
  'nl': 'Nederlands',
  'uk': 'Українська',
  'sv': 'Svenska',
  'bn': 'বাংলা',
  'ur': 'اردو',
  'fa': 'فارسی',
  'fil': 'Filipino',
  'ms': 'Bahasa Melayu',
  'ta': 'தமிழ்',
  'te': 'తెలుగు',
  'mr': 'मराठी',
  'gu': 'ગુજરાતી',
  'sw': 'Kiswahili',
  'ro': 'Română',
  'ml': 'മലയാളം',
  'el': 'Ελληνικά',
  'cs': 'Čeština',
  'hu': 'Magyar',
  'da': 'Dansk',
};

/// The stored/setting code for a locale: the language code, plus the
/// script when one distinguishes variants (e.g. `zh` vs `zh_Hant`).
String languageCodeOf(Locale locale) {
  final script = locale.scriptCode;
  return script == null || script.isEmpty
      ? locale.languageCode
      : '${locale.languageCode}_$script';
}

String languageLabel(AppLocalizations l10n, String code) {
  if (code == kLanguageSystem) return l10n.languageSystemDefault;
  return kLanguageNativeNames[code] ?? code;
}

/// The Locale to force on MaterialApp, or null to follow the device.
Locale? localeForSetting(String code) {
  if (code == kLanguageSystem) return null;
  for (final locale in AppLocalizations.supportedLocales) {
    if (languageCodeOf(locale) == code) return locale;
  }
  return null;
}

String themeLabel(AppLocalizations l10n, ThemeMode mode) {
  switch (mode) {
    case ThemeMode.system:
      return l10n.themeOptionSystem;
    case ThemeMode.light:
      return l10n.themeOptionLight;
    case ThemeMode.dark:
      return l10n.themeOptionDark;
  }
}

Future<void> showLanguageSheet(BuildContext context) {
  final settings = Provider.of<SettingsProvider>(context, listen: false);
  final codes = <String>[
    kLanguageSystem,
    for (final locale in AppLocalizations.supportedLocales)
      languageCodeOf(locale),
  ];
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      final l10n = AppLocalizations.of(sheetContext);
      return SafeArea(
        child: ValueListenableBuilder<UserSettings>(
          valueListenable: settings,
          builder: (context, current, _) {
            // 27 languages do not fit on a phone: the list scrolls.
            return ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  title: Text(
                    l10n.languageSheetTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                for (final code in codes)
                  ListTile(
                    title: Text(languageLabel(l10n, code)),
                    trailing: current.language == code
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () async {
                      await settings.setLanguage(code);
                      if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                    },
                  ),
              ],
            );
          },
        ),
      );
    },
  );
}

Future<void> showThemeSheet(BuildContext context) {
  final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
  final settings = Provider.of<SettingsProvider>(context, listen: false);
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      final l10n = AppLocalizations.of(sheetContext);
      return SafeArea(
        child: ValueListenableBuilder<ThemeMode>(
          valueListenable: themeProvider,
          builder: (context, current, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(
                    l10n.themeSheetTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                for (final mode in ThemeMode.values)
                  ListTile(
                    title: Text(themeLabel(l10n, mode)),
                    trailing:
                        current == mode ? const Icon(Icons.check) : null,
                    onTap: () async {
                      await themeProvider.setThemeMode(mode);
                      await settings.syncThemeMode(mode);
                      if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                    },
                  ),
              ],
            );
          },
        ),
      );
    },
  );
}
