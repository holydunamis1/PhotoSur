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
  'fi': 'Suomi',
  'nb': 'Norsk bokmål',
  'sk': 'Slovenčina',
  'bg': 'Български',
  'ca': 'Català',
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

/// English names, used only so people can search in English ("Hindi")
/// as well as in the language's own script.
const Map<String, String> kLanguageEnglishNames = {
  'en': 'English', 'es': 'Spanish', 'pt': 'Portuguese', 'fr': 'French',
  'de': 'German', 'hi': 'Hindi', 'id': 'Indonesian', 'ar': 'Arabic',
  'tr': 'Turkish', 'he': 'Hebrew', 'ja': 'Japanese', 'ko': 'Korean',
  'zh': 'Chinese Simplified', 'ru': 'Russian', 'it': 'Italian',
  'pl': 'Polish', 'vi': 'Vietnamese', 'th': 'Thai',
  'zh_Hant': 'Chinese Traditional', 'nl': 'Dutch', 'uk': 'Ukrainian',
  'sv': 'Swedish', 'bn': 'Bengali', 'ur': 'Urdu', 'fa': 'Persian',
  'fil': 'Filipino', 'ms': 'Malay', 'ta': 'Tamil', 'te': 'Telugu',
  'mr': 'Marathi', 'gu': 'Gujarati', 'sw': 'Swahili', 'ro': 'Romanian',
  'ml': 'Malayalam', 'el': 'Greek', 'cs': 'Czech', 'hu': 'Hungarian',
  'da': 'Danish', 'fi': 'Finnish', 'nb': 'Norwegian', 'sk': 'Slovak',
  'bg': 'Bulgarian', 'ca': 'Catalan',
};

/// Language codes in picker order: sorted by the English name so the list
/// is predictable, with "System default" always first.
List<String> sortedLanguageCodes() {
  final codes = <String>[
    for (final locale in AppLocalizations.supportedLocales)
      languageCodeOf(locale),
  ];
  String key(String c) => (kLanguageEnglishNames[c] ?? c).toLowerCase();
  codes.sort((a, b) => key(a).compareTo(key(b)));
  return [kLanguageSystem, ...codes];
}

/// Codes whose label, English name or code contains [query] (case-blind).
/// An empty query keeps everything.
List<String> filterLanguageCodes(
  List<String> codes,
  String query,
  String Function(String code) labelOf,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return codes;
  return [
    for (final c in codes)
      if (c == kLanguageSystem
          ? labelOf(c).toLowerCase().contains(q)
          : labelOf(c).toLowerCase().contains(q) ||
              (kLanguageEnglishNames[c] ?? '').toLowerCase().contains(q) ||
              c.toLowerCase().contains(q))
        c,
  ];
}

Future<void> showLanguageSheet(BuildContext context) {
  final settings = Provider.of<SettingsProvider>(context, listen: false);
  final codes = sortedLanguageCodes();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => _LanguageSheet(settings: settings, codes: codes),
  );
}

class _LanguageSheet extends StatefulWidget {
  const _LanguageSheet({required this.settings, required this.codes});

  final SettingsProvider settings;
  final List<String> codes;

  @override
  State<_LanguageSheet> createState() => _LanguageSheetState();
}

class _LanguageSheetState extends State<_LanguageSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final shown = filterLanguageCodes(
      widget.codes,
      _query,
      (c) => languageLabel(l10n, c),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ValueListenableBuilder<UserSettings>(
        valueListenable: widget.settings,
        builder: (context, current, _) {
          return Column(
            children: [
              ListTile(
                title: Text(
                  l10n.languageSheetTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: MaterialLocalizations.of(context).searchFieldLabel,
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.only(
                      bottom: MediaQuery.viewPaddingOf(context).bottom),
                  itemCount: shown.length,
                  itemBuilder: (context, i) {
                    final code = shown[i];
                    return ListTile(
                      title: Text(languageLabel(l10n, code)),
                      trailing: current.language == code
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () async {
                        await widget.settings.setLanguage(code);
                        if (context.mounted) Navigator.of(context).pop();
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
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
