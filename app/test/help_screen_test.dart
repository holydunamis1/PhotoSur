import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photosur/app.dart';
import 'package:photosur/core/providers/ad_provider.dart';
import 'package:photosur/core/providers/image_edit_provider.dart';
import 'package:photosur/core/providers/settings_provider.dart';
import 'package:photosur/core/providers/subscription_provider.dart';
import 'package:photosur/core/providers/theme_provider.dart';
import 'package:photosur/core/theme/app_theme.dart';
import 'package:photosur/generated/l10n/app_localizations.dart';
import 'package:photosur/screens/help_screen.dart';
import 'package:photosur/screens/home_screen.dart';
import 'package:photosur/screens/settings_screen.dart';
import 'package:provider/provider.dart';

Widget _host(String code, {double textScale = 1.0}) {
  Provider.debugCheckInvalidValueType = null;
  final subscription = SubscriptionProvider(SettingsProvider());
  return MaterialApp(
    theme: buildAppTheme(Brightness.light),
    locale: Locale(code.split('_').first, code.contains('_') ? 'Hant' : null),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
      ),
      child: child!,
    ),
    home: Provider<SubscriptionProvider>.value(
      value: subscription,
      child: const HelpScreen(),
    ),
  );
}

PhotoSurApp _app(SettingsProvider settings) {
  final subscription = SubscriptionProvider(settings);
  return PhotoSurApp(
    themeProvider: ThemeProvider(),
    settingsProvider: settings,
    subscriptionProvider: subscription,
    adProvider: AdProvider(subscription),
    imageEditProvider: ImageEditProvider(),
  );
}

void main() {
  const tallPhone = Size(1080, 90000);

  for (final code in ['en', 'de', 'ru', 'ar', 'ja', 'th', 'fil', 'zh_Hant']) {
    testWidgets('$code: every topic opens at 1.3x text without overflow',
        (tester) async {
      tester.view.physicalSize = tallPhone;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(code, textScale: 1.3));
      await tester.pump();
      expect(tester.takeException(), isNull);

      final context = tester.element(find.byType(HelpScreen));
      final topics = helpTopics(AppLocalizations.of(context));
      expect(topics.length, 13);
      expect(find.byType(ExpansionTile), findsNWidgets(topics.length));
      for (final topic in topics) {
        expect(find.text(topic.title), findsOneWidget, reason: topic.title);
      }

      for (var i = 0; i < topics.length; i++) {
        await tester.tap(find.byType(ExpansionTile).at(i));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$code topic $i');
      }
      // Every paragraph of every topic is now on screen.
      for (final topic in topics) {
        for (final paragraph in topic.paragraphs) {
          expect(find.text(paragraph), findsOneWidget,
              reason: '$code: ${topic.title}');
        }
      }

      await tester.pump(const Duration(seconds: 31));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the Home header help button opens the help screen',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3; // a 360 x 640 phone
    addTearDown(tester.view.reset);

    final settings = SettingsProvider();
    settings.value = settings.value
        .copyWith(language: 'en', hasCompletedOnboarding: true);
    await tester.pumpWidget(_app(settings));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(find.byType(HomeScreen), findsOneWidget);

    await tester.tap(find.byIcon(Icons.help_outline_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(HelpScreen), findsOneWidget);
    expect(find.text('Help & how to use'), findsOneWidget);

    await tester.pump(const Duration(seconds: 31));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home header has no overflow on a narrow phone in long languages',
      (tester) async {
    tester.view.physicalSize = const Size(960, 1920);
    tester.view.devicePixelRatio = 3; // 320 x 640
    addTearDown(tester.view.reset);

    for (final code in ['de', 'ru', 'ar']) {
      final settings = SettingsProvider();
      settings.value = settings.value
          .copyWith(language: code, hasCompletedOnboarding: true);
      await tester.pumpWidget(_app(settings));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull, reason: code);
      expect(find.byType(HomeScreen), findsOneWidget);
      await tester.pump(const Duration(seconds: 31));
    }
  });

  testWidgets('Settings has a Help row that opens the help screen',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final settings = SettingsProvider();
    settings.value = settings.value
        .copyWith(language: 'en', hasCompletedOnboarding: true);
    await tester.pumpWidget(_app(settings));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.byIcon(Icons.settings_outlined).first);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);

    await tester.tap(find.byIcon(Icons.menu_book_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(HelpScreen), findsOneWidget);

    await tester.pump(const Duration(seconds: 31));
    expect(tester.takeException(), isNull);
  });
}
