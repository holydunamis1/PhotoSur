import 'package:flutter/foundation.dart';

import '../../platform/ad_service.dart';
import '../models/ad_load_state.dart';
import 'subscription_provider.dart';

const String kPlacementPostExportInterstitial = 'post_export_interstitial';

/// Load state for the post-export interstitial. (Banners are owned by each
/// AdBannerSlot individually — see ad_banner_slot.dart.)
class AdProvider {
  AdProvider(this._subscriptionProvider);

  final SubscriptionProvider _subscriptionProvider;

  final ValueNotifier<AdLoadState> postExportInterstitial = ValueNotifier(
    const AdLoadState(placementId: kPlacementPostExportInterstitial),
  );

  /// export_bottom_sheet.dart calls this after a successful export.
  /// AdService itself enforces the minimum gap between interstitials
  /// (kInterstitialMinIntervalSeconds, saved on the phone), so this method
  /// doesn't need to duplicate that check — it just reflects whatever
  /// AdService actually did into AdLoadState for the UI.
  Future<void> maybeShowPostExportInterstitial({
    required bool personalized,
  }) async {
    if (_subscriptionProvider.value) return; // ad-free

    postExportInterstitial.value = postExportInterstitial.value.copyWith(
      state: AdLoadStatus.loading,
    );
    final shown = await AdService.instance.maybeLoadAndShowInterstitial(
      personalized: personalized,
    );
    postExportInterstitial.value = postExportInterstitial.value.copyWith(
      state: shown ? AdLoadStatus.loaded : AdLoadStatus.failed,
    );
  }

  void dispose() {
    postExportInterstitial.dispose();
  }
}
