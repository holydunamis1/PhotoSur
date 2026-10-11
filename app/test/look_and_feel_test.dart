import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:katharerase/core/providers/image_edit_provider.dart';
import 'package:katharerase/core/providers/settings_provider.dart';
import 'package:katharerase/core/providers/subscription_provider.dart';
import 'package:katharerase/core/theme/app_theme.dart';
import 'package:katharerase/generated/l10n/app_localizations.dart';
import 'package:katharerase/screens/paywall_screen.dart';
import 'package:katharerase/widgets/editor_top_bar.dart';
import 'package:provider/provider.dart';

Widget _app(Widget home, {required String locale, double textScale = 1.0}) {
  return MultiProvider(
    providers: [
      Provider<ImageEditProvider>.value(value: ImageEditProvider()),
      Provider<SubscriptionProvider>.value(
        value: SubscriptionProvider(SettingsProvider()),
      ),
    ],
    child: MaterialApp(
      theme: buildAppTheme(Brightness.light),
      locale: Locale(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: home,
    ),
  );
}

void main() {
  setUpAll(() {
    Provider.debugCheckInvalidValueType = null;
  });

  group('editor top bar on a narrow phone', () {
    for (final locale in ['en', 'de', 'ru', 'ar', 'fil', 'vi']) {
      testWidgets('$locale: 320 dp wide, large text, no overflow',
          (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(320, 640);
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          _app(
            Scaffold(
              body: SafeArea(
                child: EditorTopBar(onBack: () {}, onExport: () {}),
              ),
            ),
            locale: locale,
            textScale: 1.3,
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('paywall', () {
    for (final locale in ['en', 'de', 'ru', 'ar']) {
      testWidgets('$locale: 320 dp wide, large text, no overflow',
          (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(320, 640);
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          _app(const PaywallScreen(), locale: locale, textScale: 1.3),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        expect(find.byType(PaywallScreen), findsOneWidget);
      });
    }
  });

  test('onboarding copy never talks about ads, payment or subscriptions', () {
    final arb = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
        as Map<String, dynamic>;
    final banned = RegExp(
      r'\b(ads?|advert\w*|purchase|buy|subscri\w*|pay\w*|paid|price|premium|pro|free|\$)\b',
      caseSensitive: false,
    );
    for (final key in arb.keys.where((k) => k.startsWith('onboarding'))) {
      final text = arb[key];
      if (text is! String) continue;
      expect(banned.hasMatch(text), isFalse, reason: '$key: "$text"');
    }
  });

  test('every onboarding illustration exists', () {
    for (final f in ['auto', 'manual', 'studio']) {
      expect(File('assets/images/onboarding_$f.png').existsSync(), isTrue);
    }
    expect(File('assets/images/onboarding_ads.png').existsSync(), isFalse);
  });
}
