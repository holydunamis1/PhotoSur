import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/constants.dart';

const String kReviewCountKey = 'review_export_count';
const String kReviewDaysKey = 'review_export_days';
const String kReviewPromptedKey = 'review_prompted';

/// Remembers, on the phone, how many exports happened and on which days, and
/// decides when the one-time review prompt is allowed.
class ReviewTracker {
  ReviewTracker({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  static String _dayKey(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-'
      '${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';

  /// Counts one successful export event. Failures are logged, never thrown.
  Future<void> recordExport() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final count = (prefs.getInt(kReviewCountKey) ?? 0) + 1;
      final days = (prefs.getStringList(kReviewDaysKey) ?? <String>[]).toList();
      final today = _dayKey(_now());
      if (!days.contains(today)) {
        days.add(today);
        // Only the number of distinct days matters, and only up to the
        // threshold: keep the list short.
        if (days.length > kReviewMinDays + 2) {
          days.removeRange(0, days.length - (kReviewMinDays + 2));
        }
      }
      await prefs.setInt(kReviewCountKey, count);
      await prefs.setStringList(kReviewDaysKey, days);
    } catch (e) {
      debugPrint('Review tracker write failed: $e');
    }
  }

  /// True when enough exports on enough days have happened and the prompt
  /// has not been requested before.
  Future<bool> isDue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(kReviewPromptedKey) ?? false) return false;
      final count = prefs.getInt(kReviewCountKey) ?? 0;
      final days = prefs.getStringList(kReviewDaysKey)?.toSet().length ?? 0;
      return count >= kReviewMinExports && days >= kReviewMinDays;
    } catch (e) {
      debugPrint('Review tracker read failed: $e');
      return false;
    }
  }

  Future<void> markPrompted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kReviewPromptedKey, true);
    } catch (e) {
      debugPrint('Review tracker write failed: $e');
    }
  }
}
