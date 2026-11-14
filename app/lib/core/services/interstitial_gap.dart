import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/constants.dart';

/// SharedPreferences key holding the epoch-milliseconds of the last
/// interstitial that was actually shown.
const String kLastInterstitialShownAtKey = 'last_interstitial_shown_at_ms';

/// The "at least [kInterstitialMinIntervalSeconds] between interstitials"
/// rule. The last-shown time is saved on the phone, so closing and
/// reopening the app does not make the next export eligible again.
///
/// Storage problems never block anything: if the saved value cannot be read
/// the rule behaves as if no ad had been shown yet, and if it cannot be
/// written the in-memory value still applies for this app run.
class InterstitialGap {
  InterstitialGap({
    DateTime Function()? now,
    int minSeconds = kInterstitialMinIntervalSeconds,
  })  : _now = now ?? DateTime.now,
        _minSeconds = minSeconds;

  final DateTime Function() _now;
  final int _minSeconds;

  DateTime? _last;
  Future<void>? _loading;

  Future<void> _load() => _loading ??= _readSaved();

  Future<void> _readSaved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(kLastInterstitialShownAtKey);
      // Never overwrite a value set by markShown() while this was loading.
      if (ms != null && _last == null) {
        _last = DateTime.fromMillisecondsSinceEpoch(ms);
      }
    } catch (e) {
      // Wrong type or an unreadable store: treat as "nothing saved".
      debugPrint('Interstitial gap: could not read saved time: $e');
    }
  }

  /// True when enough time has passed since the last interstitial (or none
  /// was ever shown).
  Future<bool> isOpen() async {
    await _load();
    final last = _last;
    if (last == null) return true;
    final elapsed = _now().difference(last).inSeconds;
    // A saved time in the future means the phone's clock was set back.
    // Waiting for it to catch up could block ads for days, so allow one.
    if (elapsed < 0) return true;
    return elapsed >= _minSeconds;
  }

  /// Call when an interstitial has actually been shown.
  Future<void> markShown() async {
    final shownAt = _now();
    _last = shownAt;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        kLastInterstitialShownAtKey,
        shownAt.millisecondsSinceEpoch,
      );
    } catch (e) {
      debugPrint('Interstitial gap: could not save shown time: $e');
    }
  }
}
