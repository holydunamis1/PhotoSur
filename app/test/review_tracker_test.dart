import 'package:flutter_test/flutter_test.dart';
import 'package:photosur/core/services/review_tracker.dart';
import 'package:photosur/core/utils/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> exportsOn(DateTime day, int n, ReviewTracker Function() t) async {
    for (var i = 0; i < n; i++) {
      await t().recordExport();
    }
  }

  test('approved thresholds: 10 exports over at least 3 days', () {
    expect(kReviewMinExports, 10);
    expect(kReviewMinDays, 3);
  });

  test('not due with nothing recorded', () async {
    expect(await ReviewTracker().isDue(), isFalse);
  });

  test('10 exports on one day is not enough', () async {
    final day = DateTime(2026, 11, 14, 10);
    await exportsOn(day, 12, () => ReviewTracker(now: () => day));
    expect(await ReviewTracker().isDue(), isFalse);
  });

  test('3 days but only 9 exports is not enough', () async {
    for (final d in [14, 15, 16]) {
      final day = DateTime(2026, 11, d, 10);
      await exportsOn(day, 3, () => ReviewTracker(now: () => day));
    }
    expect(await ReviewTracker().isDue(), isFalse);
  });

  test('10th export on the 3rd day makes it due', () async {
    for (final d in [14, 15]) {
      final day = DateTime(2026, 11, d, 10);
      await exportsOn(day, 4, () => ReviewTracker(now: () => day));
    }
    final day3 = DateTime(2026, 11, 16, 10);
    final t = ReviewTracker(now: () => day3);
    await exportsOn(day3, 1, () => t);
    expect(await t.isDue(), isFalse); // 9 so far
    await t.recordExport();
    expect(await t.isDue(), isTrue); // 10 on 3 days
  });

  test('once marked prompted it is never due again', () async {
    for (final d in [14, 15, 16]) {
      final day = DateTime(2026, 11, d, 10);
      await exportsOn(day, 5, () => ReviewTracker(now: () => day));
    }
    final t = ReviewTracker();
    expect(await t.isDue(), isTrue);
    await t.markPrompted();
    expect(await t.isDue(), isFalse);
    await t.recordExport();
    expect(await t.isDue(), isFalse);
  });

  test('state survives a restart (new instance)', () async {
    for (final d in [14, 15, 16]) {
      final day = DateTime(2026, 11, d, 10);
      await exportsOn(day, 4, () => ReviewTracker(now: () => day));
    }
    expect(await ReviewTracker().isDue(), isTrue);
  });

  test('day list stays short however many days pass', () async {
    for (var d = 1; d <= 20; d++) {
      final day = DateTime(2026, 10, d, 10);
      await ReviewTracker(now: () => day).recordExport();
    }
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(kReviewDaysKey)!.length,
        lessThanOrEqualTo(kReviewMinDays + 2));
  });

  test('wrong-type saved values do not crash and mean not due', () async {
    SharedPreferences.setMockInitialValues({kReviewCountKey: 'x'});
    expect(await ReviewTracker().isDue(), isFalse);
  });
}
