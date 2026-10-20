import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photosur/core/providers/settings_provider.dart';
import 'package:photosur/widgets/home_backdrop_strip.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _host(SettingsProvider settings, {bool reduceMotion = false}) {
  return Provider<SettingsProvider>.value(
    value: settings,
    child: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 400,
          height: 80,
          child: Stack(children: [Positioned.fill(child: HomeBackdropStrip())]),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    Provider.debugCheckInvalidValueType = null;
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows the first picture when on, nothing when off',
      (tester) async {
    final settings = SettingsProvider();
    await tester.pumpWidget(_host(settings));
    expect(find.byKey(const ValueKey('home-strip-image-0')), findsOneWidget);

    await settings.setAnimatedHomeBackground(false);
    await tester.pump();
    expect(find.byKey(const ValueKey('home-strip-image-0')), findsNothing);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('moves to the next picture after one cycle', (tester) async {
    final settings = SettingsProvider();
    await tester.pumpWidget(_host(settings));
    await tester.pump(kHomeStripCycle + const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('home-strip-image-1')), findsOneWidget);

    // Remove the widget so the controller is disposed (no pending ticker).
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduce-animations keeps the first picture still',
      (tester) async {
    final settings = SettingsProvider();
    await tester.pumpWidget(_host(settings, reduceMotion: true));
    await tester.pump(kHomeStripCycle * 2);
    expect(find.byKey(const ValueKey('home-strip-image-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-strip-image-1')), findsNothing);
  });

  test('the switch survives a restart', () async {
    final first = SettingsProvider();
    await first.load();
    expect(first.value.animatedHomeBackground, isTrue);
    await first.setAnimatedHomeBackground(false);

    final second = SettingsProvider();
    await second.load();
    expect(second.value.animatedHomeBackground, isFalse);
  });
}
