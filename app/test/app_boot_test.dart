import 'package:flutter_test/flutter_test.dart';
import 'package:photosur/app.dart';
import 'package:photosur/core/providers/ad_provider.dart';
import 'package:photosur/core/providers/image_edit_provider.dart';
import 'package:photosur/core/providers/settings_provider.dart';
import 'package:photosur/core/providers/subscription_provider.dart';
import 'package:photosur/core/providers/theme_provider.dart';
import 'package:photosur/screens/home_screen.dart';
import 'package:photosur/screens/onboarding_screen.dart';

/// Boots the REAL app widget tree (real router, real providers, real
/// localization) the way main() does, in debug mode where framework
/// assertions are active. A throw on the first build — like the
/// "Tried to use Provider with a subtype of Listenable" crash that left
/// debug builds frozen on the splash screen — fails this test, with no
/// APK or device needed.
PhotoSurApp _buildApp(SettingsProvider settings) {
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
  testWidgets('fresh install: first screen (onboarding) builds without errors',
      (tester) async {
    await tester.pumpWidget(_buildApp(SettingsProvider()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(find.byType(OnboardingScreen), findsOneWidget);
  });

  testWidgets('returning user: home screen builds without errors',
      (tester) async {
    final settings = SettingsProvider();
    settings.value = settings.value.copyWith(hasCompletedOnboarding: true);

    await tester.pumpWidget(_buildApp(settings));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(find.byType(HomeScreen), findsOneWidget);

    // Let the banner-ad load timeouts (up to 20 s) fire on the fake clock:
    // checks nothing throws when they do, and leaves no timers pending.
    await tester.pump(const Duration(seconds: 31));
    expect(tester.takeException(), isNull);
  });
}
