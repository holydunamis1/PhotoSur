import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';

import '../core/providers/subscription_provider.dart';
import '../platform/ad_service.dart';

/// Standard banner (AdSize.banner) is 320x50 dp. The slot reserves exactly
/// that, plus a small gap above it so the ad never touches the controls
/// right above it.
const double kAdBannerHeight = 50.0;
const double kAdBannerWidth = 320.0;
const double kAdBannerGap = 8.0;
const double kAdBannerSlotHeight = kAdBannerHeight + kAdBannerGap;

/// Fixed-height banner. While the ad loads the slot already holds its final
/// height (blank), so nothing on screen jumps when the ad arrives. It
/// collapses to 0dp on failure and when ad-free — never a broken
/// placeholder.
///
/// Every slot owns its OWN BannerAd (created on mount, disposed on
/// unmount). A single shared ad cannot be shown in two places at once, and
/// one screen closing used to destroy the ad another screen was showing.
///
/// SubscriptionProvider is located via Provider.of(context, listen: false)
/// — DI only, per the architecture rule; reactivity comes from the
/// ValueListenableBuilder below.
class AdBannerSlot extends StatefulWidget {
  const AdBannerSlot({super.key, required this.personalized});

  final bool personalized;

  @override
  State<AdBannerSlot> createState() => _AdBannerSlotState();
}

class _AdBannerSlotState extends State<AdBannerSlot> {
  late final SubscriptionProvider _subscriptionProvider;
  BannerAd? _banner;
  bool _loaded = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _subscriptionProvider =
        Provider.of<SubscriptionProvider>(context, listen: false);
    _load();
  }

  Future<void> _load() async {
    if (_subscriptionProvider.value) return; // ad-free, nothing to load
    final banner = await AdService.instance.loadBannerAd(
      personalized: widget.personalized,
      onLoaded: (_) {
        if (mounted) setState(() => _loaded = true);
      },
      onFailed: (_, __) {
        if (mounted) {
          setState(() {
            _loaded = false;
            _failed = true;
            _banner = null;
          });
        }
      },
    );
    if (!mounted) {
      banner?.dispose();
      return;
    }
    if (banner != null) {
      setState(() => _banner = banner);
    } else {
      setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _banner?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _subscriptionProvider,
      builder: (context, isAdFree, _) {
        final banner = _banner;
        if (isAdFree || _failed) return const SizedBox.shrink();
        // A screen covered by another full page (Home under the Editor) has
        // its tickers switched off by the Navigator. Hold the slot's space
        // but do not draw the ad, so only one banner is live on screen.
        final covered = !TickerMode.of(context);
        return SizedBox(
          height: kAdBannerSlotHeight,
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.only(top: kAdBannerGap),
            child: (banner == null || !_loaded || covered)
                ? null // loading or covered: space is held, nothing drawn
                : Center(
                    child: SizedBox(
                      width: kAdBannerWidth,
                      height: kAdBannerHeight,
                      child: AdWidget(ad: banner),
                    ),
                  ),
          ),
        );
      },
    );
  }
}
