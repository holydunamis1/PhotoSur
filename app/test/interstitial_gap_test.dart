import 'package:flutter_test/flutter_test.dart';
import 'package:photosur/core/services/interstitial_gap.dart';
import 'package:photosur/core/utils/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A clock the test can move.
class _Clock {
  _Clock(this.value);
  DateTime value;
  DateTime call() => value;
  void advance(Duration d) => value = value.add(d);
}

void main() {
  final start = DateTime(2026, 11, 14, 12);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the approved gap is 7 minutes', () {
    expect(kInterstitialMinIntervalSeconds, 420);
  });

  test('nothing shown yet: open', () async {
    final gap = InterstitialGap(now: _Clock(start).call);
    expect(await gap.isOpen(), isTrue);
  });

  test('closed right after one is shown, open again exactly at 7 minutes',
      () async {
    final clock = _Clock(start);
    final gap = InterstitialGap(now: clock.call);
    await gap.markShown();

    expect(await gap.isOpen(), isFalse);

    clock.advance(const Duration(seconds: 419));
    expect(await gap.isOpen(), isFalse);

    clock.advance(const Duration(seconds: 1)); // 420 s
    expect(await gap.isOpen(), isTrue);
  });

  test('the old 120 s gap no longer re-opens it', () async {
    final clock = _Clock(start);
    final gap = InterstitialGap(now: clock.call);
    await gap.markShown();
    clock.advance(const Duration(minutes: 3));
    expect(await gap.isOpen(), isFalse);
  });

  test('restart: a new instance still sees the saved time', () async {
    final clock = _Clock(start);
    await InterstitialGap(now: clock.call).markShown();

    // "Restart" = brand-new object, same on-disk store.
    clock.advance(const Duration(minutes: 2));
    final afterRestart = InterstitialGap(now: clock.call);
    expect(await afterRestart.isOpen(), isFalse);

    clock.advance(const Duration(minutes: 5)); // 7 minutes since the ad
    expect(await InterstitialGap(now: clock.call).isOpen(), isTrue);
  });

  test('the saved value is epoch milliseconds under the documented key',
      () async {
    final gap = InterstitialGap(now: _Clock(start).call);
    await gap.markShown();
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getInt(kLastInterstitialShownAtKey),
      start.millisecondsSinceEpoch,
    );
  });

  test('clock set back (saved time in the future): open, not blocked for days',
      () async {
    SharedPreferences.setMockInitialValues({
      kLastInterstitialShownAtKey:
          start.add(const Duration(days: 3)).millisecondsSinceEpoch,
    });
    final gap = InterstitialGap(now: _Clock(start).call);
    expect(await gap.isOpen(), isTrue);
  });

  test('unreadable saved value (wrong type): treated as nothing saved',
      () async {
    SharedPreferences.setMockInitialValues({
      kLastInterstitialShownAtKey: 'not a number',
    });
    final gap = InterstitialGap(now: _Clock(start).call);
    expect(await gap.isOpen(), isTrue);
  });

  test('markShown right away wins over a slow first read', () async {
    SharedPreferences.setMockInitialValues({
      kLastInterstitialShownAtKey:
          start.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
    });
    final clock = _Clock(start);
    final gap = InterstitialGap(now: clock.call);
    // markShown() is called before isOpen() ever loaded the saved value.
    await gap.markShown();
    expect(await gap.isOpen(), isFalse);
  });
}
