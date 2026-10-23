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
      data: MediaQueryData(
        size: const Size(400, 800), disableAnimations: reduceMotion),
      child: const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 400,
          height: 80,
          child: HomeBackdropStrip(child: Center(child: Text('content'))),
        ),
      ),
    ),
  );
}

Future<void> _oneCycle(WidgetTester tester) async {
  await tester.pump(kHomeStripCycle - kHomeStripFade); // hold ends
  await tester.pump(); // fade starts
  for (var i = 0; i < 14; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
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
    expect(find.text('content'), findsOneWidget); // content is never lost
  });

  testWidgets('idle between fades: no frames scheduled', (tester) async {
    final settings = SettingsProvider();
    await tester.pumpWidget(_host(settings));
    await tester.pump(const Duration(seconds: 2));
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('moves to the next picture after one cycle', (tester) async {
    final settings = SettingsProvider();
    await tester.pumpWidget(_host(settings));
    await _oneCycle(tester);
    expect(find.byKey(const ValueKey('home-strip-image-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-strip-image-0')), findsNothing);

    // Remove the widget so the timer and controller are disposed.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduce-animations keeps the first picture still',
      (tester) async {
    final settings = SettingsProvider();
    await tester.pumpWidget(_host(settings, reduceMotion: true));
    await tester.pump(kHomeStripCycle * 2);
    await tester.pump(kHomeStripCycle * 2);
    expect(find.byKey(const ValueKey('home-strip-image-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-strip-image-1')), findsNothing);
  });

  testWidgets('the section fills the space below short content',
      (tester) async {
    final settings = SettingsProvider();
    await tester.pumpWidget(
      Provider<SettingsProvider>.value(
        value: settings,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(400, 800)),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: HomeBackdropStrip(
                    child: Container(
                      key: const ValueKey('section-content'),
                      child: const Center(child: Text('content')),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // 800 tall viewport, 100 used above: the content area is 700 tall, and
    // the 4:3 picture (300 wide x 400... 400 wide = 300 tall) sits at its top.
    expect(tester.getSize(find.byKey(const ValueKey('section-content'))).height,
        700);
    final picture = tester.getRect(find.byKey(const ValueKey('home-strip-image-0')));
    expect(picture.top, 100);
    expect(picture.width, 400);
    expect(picture.height, 300);
    await tester.pumpWidget(const SizedBox());
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
