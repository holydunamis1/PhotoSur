import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/providers/ad_provider.dart';
import 'core/providers/image_edit_provider.dart';
import 'core/providers/settings_provider.dart';
import 'core/models/user_settings.dart';
import 'core/theme/app_theme.dart';
import 'core/providers/subscription_provider.dart';
import 'core/providers/theme_provider.dart';
import 'generated/l10n/app_localizations.dart';
import 'router.dart';
import 'widgets/preference_sheets.dart';

/// MaterialApp, GoRouter, theme injection, Provider.value
/// tree.
///
/// Provider.value note: all five providers here are plain classes (four
/// extend ValueNotifier, AdProvider holds ValueNotifiers directly) — not
/// ChangeNotifier — so this uses plain `Provider<T>.value` for DI lookup
/// only, never ChangeNotifierProvider. Reactivity for theme comes from
/// the `ValueListenableBuilder<ThemeMode>` wrapping MaterialApp.router
/// below, not from package:provider's own change-notification mechanism,
/// consistent with the "ValueNotifier + ListenableBuilder, provider is
/// DI-only" architecture rule.
class PhotoSurApp extends StatelessWidget {
  const PhotoSurApp({
    super.key,
    required this.themeProvider,
    required this.settingsProvider,
    required this.subscriptionProvider,
    required this.adProvider,
    required this.imageEditProvider,
  });

  final ThemeProvider themeProvider;
  final SettingsProvider settingsProvider;
  final SubscriptionProvider subscriptionProvider;
  final AdProvider adProvider;
  final ImageEditProvider imageEditProvider;

  @override
  Widget build(BuildContext context) {
    // package:provider asserts, in DEBUG builds only, that Provider.value is
    // never given a Listenable (ValueNotifier). This app deliberately uses
    // ValueNotifier + ListenableBuilder with Provider purely for dependency
    // injection (see the class comment), so that check must be off —
    // otherwise every debug build throws on its very first build and freezes
    // on the splash screen. Set here (not only in main) so ANY way of
    // mounting the app is covered; test/app_boot_test.dart guards it.
    Provider.debugCheckInvalidValueType = null;

    final router = buildRouter(settingsProvider);

    return MultiProvider(
      providers: [
        Provider<ThemeProvider>.value(value: themeProvider),
        Provider<SettingsProvider>.value(value: settingsProvider),
        Provider<SubscriptionProvider>.value(value: subscriptionProvider),
        Provider<AdProvider>.value(value: adProvider),
        Provider<ImageEditProvider>.value(value: imageEditProvider),
      ],
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: themeProvider,
        builder: (context, themeMode, _) {
          // No forced Directionality: MaterialApp resolves text direction
          // from the active locale, so Arabic lays out right-to-left.
          return ValueListenableBuilder<UserSettings>(
            valueListenable: settingsProvider,
            builder: (context, settings, _) {
              return MaterialApp.router(
                  title: 'PhotoSur',
                  debugShowCheckedModeBanner: false,
                  themeMode: themeMode,
                  theme: buildAppTheme(Brightness.light),
                  darkTheme: buildAppTheme(Brightness.dark),
                  routerConfig: router,
                  // null = follow the device language; otherwise the
                  // user's manual choice from the language sheet.
                  locale: localeForSetting(settings.language),
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
              );
            },
          );
        },
      ),
    );
  }
}
