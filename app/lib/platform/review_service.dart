import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';

import '../core/services/review_tracker.dart';

/// Counts exports and, once, asks the store to show its review sheet.
/// Never throws. Google/Apple decide whether the sheet actually appears.
class ReviewService {
  ReviewService._();
  static final ReviewService instance = ReviewService._();

  final ReviewTracker _tracker = ReviewTracker();

  /// [adShown]: an interstitial was shown in this same flow, so skip the
  /// prompt this time (a later export may show it). [allowPrompt] is false
  /// for batch runs: they count as one export but never prompt.
  Future<void> recordExport({
    bool adShown = false,
    bool allowPrompt = true,
  }) async {
    try {
      await _tracker.recordExport();
      if (adShown || !allowPrompt) return;
      if (!await _tracker.isDue()) return;

      // Let the export screen finish closing before the sheet appears.
      await Future<void>.delayed(const Duration(seconds: 2));

      final review = InAppReview.instance;
      if (!await review.isAvailable()) return;
      await _tracker.markPrompted();
      await review.requestReview();
    } catch (e) {
      debugPrint('Review prompt failed: $e');
    }
  }
}
