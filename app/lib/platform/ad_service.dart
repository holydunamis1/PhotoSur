import 'dart:async';
import 'dart:io' show Platform;

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart' show debugPrint, kReleaseMode;
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../core/services/interstitial_gap.dart';
import '../core/utils/constants.dart';

/// AdMob init, ATT request, banner/interstitial load-show, capping logic.
class AdService {
  AdService._();
  static final AdService instance = AdService._();

  /// Minimum time between interstitials. The last-shown time is saved on the
  /// phone, so it survives the app being closed.
  final InterstitialGap _gap = InterstitialGap();

  /// Falls back to test IDs if production IDs still contain bracket
  /// placeholders (Section 1a pending items) — kept from the k3 rewrite,
  /// a genuine improvement: prevents AdMob SDK crashing on an invalid
  /// (still-a-placeholder) ad unit ID string in a release build before
  /// real AdMob dashboard IDs exist.
  String get bannerAdUnitId {
    final isIos = Platform.isIOS;
    final prodId = isIos ? kProdBannerAdUnitIdIos : kProdBannerAdUnitIdAndroid;
    final testId = isIos ? kTestBannerAdUnitIdIos : kTestBannerAdUnitIdAndroid;
    return (kReleaseMode && !prodId.contains('[')) ? prodId : testId;
  }

  String get interstitialAdUnitId {
    final isIos = Platform.isIOS;
    final prodId =
        isIos ? kProdInterstitialAdUnitIdIos : kProdInterstitialAdUnitIdAndroid;
    final testId =
        isIos ? kTestInterstitialAdUnitIdIos : kTestInterstitialAdUnitIdAndroid;
    return (kReleaseMode && !prodId.contains('[')) ? prodId : testId;
  }

  Future<void>? _initFuture;

  /// Idempotent: every caller shares one initialization. This is started in
  /// the background after the first frame (see main.dart) because the SDK
  /// can take many seconds — or never call back — on some networks/devices.
  Future<void> initialize() => _initFuture ??= _initialize();

  Future<void> _initialize() async {
    try {
      await MobileAds.instance.initialize();
    } catch (e) {
      debugPrint('AdMob initialization failed: $e');
    }
  }

  /// Lets ad loads wait for SDK initialization, but never forever.
  Future<void> _waitUntilInitialized() async {
    try {
      await initialize().timeout(const Duration(seconds: 20));
    } catch (_) {
      // Proceed anyway; the load itself has its own timeout.
    }
  }

  Future<bool> requestTrackingAuthorization() async {
    if (!Platform.isIOS) return true;
    try {
      final status = await AppTrackingTransparency.requestTrackingAuthorization();
      return status == TrackingStatus.authorized;
    } catch (e) {
      debugPrint('ATT request failed: $e');
      return false;
    }
  }

  AdRequest _buildAdRequest({required bool personalized}) {
    return AdRequest(nonPersonalizedAds: !personalized);
  }

  Future<BannerAd?> loadBannerAd({
    required bool personalized,
    required void Function(Ad ad) onLoaded,
    required void Function(Ad ad, LoadAdError error) onFailed,
  }) async {
    await _waitUntilInitialized();
    final banner = BannerAd(
      adUnitId: bannerAdUnitId,
      size: AdSize.banner,
      request: _buildAdRequest(personalized: personalized),
      listener: BannerAdListener(
        onAdLoaded: onLoaded,
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          onFailed(ad, error);
        },
      ),
    );
    try {
      // Timeout added — same reasoning as maybeLoadAndShowInterstitial
      // below: a banner ad slot must be able to give up and collapse
      // rather than leave the widget waiting forever if AdMob's SDK
      // never calls back.
      await banner.load().timeout(const Duration(seconds: 10));
      return banner;
    } catch (e) {
      debugPrint('Banner ad load failed or timed out: $e');
      onFailed(
        banner,
        LoadAdError(0, 'internal', 'load threw or timed out: $e', null),
      );
      return null;
    }
  }

  /// FIX: added a hard timeout on the completer. Previously, if AdMob's
  /// SDK never invoked either onAdLoaded or onAdFailedToLoad (genuinely
  /// possible — flaky network, blocked ad domain, certain sandboxed test
  /// environments), completer.future would never resolve, and since
  /// export_bottom_sheet.dart awaits this call before dismissing itself,
  /// the ENTIRE EXPORT FLOW would hang indefinitely — the image having
  /// already saved successfully, but the UI never confirming or
  /// dismissing. This matches a real-world report of "export not
  /// working." An ad failing to load should never be able to block a
  /// core app flow — this restores that guarantee.
  Future<bool> maybeLoadAndShowInterstitial({
    required bool personalized,
  }) async {
    if (!await _gap.isOpen()) return false;

    await _waitUntilInitialized();
    final completer = Completer<bool>();
    try {
      await InterstitialAd.load(
        adUnitId: interstitialAdUnitId,
        request: _buildAdRequest(personalized: personalized),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            ad.fullScreenContentCallback = FullScreenContentCallback(
              onAdDismissedFullScreenContent: (dismissedAd) {
                dismissedAd.dispose();
              },
              onAdFailedToShowFullScreenContent: (failedAd, error) {
                failedAd.dispose();
              },
            );
            ad.show();
            unawaited(_gap.markShown());
            if (!completer.isCompleted) completer.complete(true);
          },
          onAdFailedToLoad: (error) {
            debugPrint('Interstitial load failed: $error');
            if (!completer.isCompleted) completer.complete(false);
          },
        ),
      );
    } catch (e) {
      debugPrint('Interstitial load threw: $e');
      if (!completer.isCompleted) completer.complete(false);
    }

    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        debugPrint('Interstitial load timed out — proceeding without an ad.');
        return false;
      },
    );
  }
}
