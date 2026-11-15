import 'package:flutter/foundation.dart';

/// The five consent operations, so the sequencing below can be tested
/// without the ads plugin. The real implementation is in ad_service.dart.
class ConsentGateway {
  const ConsentGateway({
    required this.requestInfoUpdate,
    required this.showFormIfRequired,
    required this.canRequestAds,
    required this.privacyOptionsRequired,
    required this.showPrivacyOptions,
  });

  /// Throws when Google's consent service cannot be reached.
  final Future<void> Function() requestInfoUpdate;

  /// Shows Google's consent form only if one is needed. Throws on an error.
  final Future<void> Function() showFormIfRequired;
  final Future<bool> Function() canRequestAds;
  final Future<bool> Function() privacyOptionsRequired;
  final Future<void> Function() showPrivacyOptions;
}

class ConsentResult {
  const ConsentResult({
    required this.adsAllowed,
    required this.infoUpdateFailed,
    required this.privacyOptionsRequired,
    this.canRequestAdsError,
  });

  /// Whether ads may be requested now.
  final bool adsAllowed;

  /// The consent info could not be updated (offline, service error).
  final bool infoUpdateFailed;

  /// Show the Settings "Privacy choices" row.
  final bool privacyOptionsRequired;

  /// Set when canRequestAds() itself threw. It is reported, not hidden.
  final Object? canRequestAdsError;
}

/// Ads are blocked only when Google says they may not be requested. If the
/// answer is unknown (the check failed), ads are still requested.
bool decideAdsAllowed(bool? canRequestAds) => canRequestAds != false;

class ConsentFlow {
  ConsentFlow(this._gateway);

  final ConsentGateway _gateway;

  /// Runs the whole sequence. Never throws.
  Future<ConsentResult> gather() async {
    var updateFailed = false;
    try {
      await _gateway.requestInfoUpdate();
    } catch (e) {
      updateFailed = true;
      debugPrint('Consent info update failed: $e');
    }

    if (!updateFailed) {
      try {
        await _gateway.showFormIfRequired();
      } catch (e) {
        debugPrint('Consent form failed: $e');
      }
    }

    bool? can;
    Object? canError;
    try {
      can = await _gateway.canRequestAds();
    } catch (e) {
      canError = e;
      debugPrint('canRequestAds failed: $e');
    }

    var optionsRequired = false;
    try {
      optionsRequired = await _gateway.privacyOptionsRequired();
    } catch (e) {
      debugPrint('Privacy options status failed: $e');
    }

    return ConsentResult(
      adsAllowed: decideAdsAllowed(can),
      infoUpdateFailed: updateFailed,
      privacyOptionsRequired: optionsRequired,
      canRequestAdsError: canError,
    );
  }

  /// Opens Google's privacy options form (Settings row). Returns the fresh
  /// "may ads be requested" answer afterwards.
  Future<bool> showPrivacyOptions() async {
    try {
      await _gateway.showPrivacyOptions();
    } catch (e) {
      debugPrint('Privacy options form failed: $e');
    }
    try {
      return decideAdsAllowed(await _gateway.canRequestAds());
    } catch (e) {
      debugPrint('canRequestAds failed: $e');
      return true;
    }
  }
}
