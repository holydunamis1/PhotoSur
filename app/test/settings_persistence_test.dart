import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photosur/app.dart';
import 'package:photosur/core/providers/ad_provider.dart';
import 'package:photosur/core/providers/image_edit_provider.dart';
import 'package:photosur/core/providers/settings_provider.dart';
import 'package:photosur/core/providers/subscription_provider.dart';
import 'package:photosur/core/providers/theme_provider.dart';
import 'package:photosur/screens/home_screen.dart';
import 'package:photosur/screens/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "Restart" = a brand-new SettingsProvider reading what the previous one
/// saved, with the same on-disk store in between.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('finishing onboarding is still finished after a restart', () async {
    final first = SettingsProvider();
    await first.load();
    expect(first.value.hasCompletedOnboarding, isFalse);
    await first.completeOnboarding();

    final prefs = await SharedPreferences.getInstance();
    final saved =
        jsonDecode(prefs.getString('user_settings')!) as Map<String, dynamic>;
    expect(saved['has_completed_onboarding'], isTrue);

    final second = SettingsProvider();
    await second.load();
    expect(second.value.hasCompletedOnboarding, isTrue);
  });

  test('later changes (ATT, language, theme, ad-free) keep it finished',
      () async {
    final first = SettingsProvider();
    await first.load();
    await first.completeOnboarding();
    await first.markAttPromptSeen();
    await first.setLanguage('id');
    await first.syncThemeMode(ThemeMode.dark);
    await first.syncAdFreeStatus(false);
    await first.setRemindersEnabled(false);

    final second = SettingsProvider();
    await second.load();
    expect(second.value.hasCompletedOnboarding, isTrue);
    expect(second.value.language, 'id');
    expect(second.value.themeMode, ThemeMode.dark);
  });

  test('the one-time automatic HD download is remembered after a restart',
      () async {
    final first = SettingsProvider();
    await first.load();
    expect(first.value.hdAutoDownloadTried, isFalse);
    await first.markHdAutoDownloadTried();

    final second = SettingsProvider();
    await second.load();
    expect(second.value.hdAutoDownloadTried, isTrue);
  });

  testWidgets('after a restart the app opens Home, not onboarding',
      (tester) async {
    final first = SettingsProvider();
    await first.load();
    await first.completeOnboarding();

    final restarted = SettingsProvider();
    await restarted.load();
    final subscription = SubscriptionProvider(restarted);
    await tester.pumpWidget(PhotoSurApp(
      themeProvider: ThemeProvider(),
      settingsProvider: restarted,
      subscriptionProvider: subscription,
      adProvider: AdProvider(subscription),
      imageEditProvider: ImageEditProvider(),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    await tester.pump(const Duration(seconds: 31));
  });
}
