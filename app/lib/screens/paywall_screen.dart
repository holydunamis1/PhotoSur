import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/providers/subscription_provider.dart';
import '../core/theme/app_tokens.dart';
import '../generated/l10n/app_localizations.dart';
import '../platform/iap_service.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/primary_button.dart';
import '../widgets/toast_notification.dart';

/// Non-blocking. "Go Ad-Free." Hero, store price, Free vs Ad-Free comparison,
/// purchase and Restore buttons. Every feature stays free either way.
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  bool _isPurchasing = false;

  /// Localized price string from the store (e.g. "$14.99"), once loaded.
  /// Never hardcoded, so it is always correct for the user's country.
  String? _price;

  @override
  void initState() {
    super.initState();
    _loadPrice();
  }

  Future<void> _loadPrice() async {
    try {
      final response = await IapService.instance.queryAdFreeProduct();
      if (!mounted || response.productDetails.isEmpty) return;
      setState(() => _price = response.productDetails.first.price);
    } catch (_) {
      // Price stays generic ("One-time purchase"); purchase still works.
    }
  }

  Future<void> _purchase(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _isPurchasing = true);
    try {
      final response = await IapService.instance.queryAdFreeProduct();
      if (response.productDetails.isEmpty) {
        if (context.mounted) {
          ToastNotification.show(
            context,
            message: l10n.paywallProductUnavailable,
            type: ToastType.error,
          );
        }
        return;
      }
      await IapService.instance.buyAdFree(response.productDetails.first);
    } catch (e) {
      if (context.mounted) {
        ToastNotification.show(context, message: l10n.paywallPurchaseFailed, type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _isPurchasing = false);
    }
  }

  Future<void> _restore(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    try {
      await IapService.instance.restorePurchases();
      if (context.mounted) {
        ToastNotification.show(
          context,
          message: l10n.settingsRestoreRequested,
          type: ToastType.info,
        );
      }
    } catch (e) {
      if (context.mounted) {
        ToastNotification.show(context, message: l10n.settingsRestoreFailed, type: ToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = context.palette;
    final subscriptionProvider =
        Provider.of<SubscriptionProvider>(context, listen: false);

    return AppScaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: ValueListenableBuilder<bool>(
        valueListenable: subscriptionProvider,
        builder: (context, isAdFree, _) {
          if (isAdFree) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _Hero(icon: Icons.verified_rounded),
                    const SizedBox(height: AppSpace.xl),
                    Text(
                      l10n.paywallAlreadyAdFree,
                      style: theme.textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: _Hero(icon: Icons.block_rounded)),
                      const SizedBox(height: AppSpace.xl),
                      Text(
                        l10n.paywallTitle,
                        style: theme.textTheme.headlineMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpace.s),
                      if (_price != null) ...[
                        Text(
                          _price!,
                          style: theme.textTheme.displaySmall
                              ?.copyWith(color: palette.accentText),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpace.xs),
                      ],
                      Text(
                        l10n.paywallPlanAdFreePrice,
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(color: palette.text2),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpace.xxl),
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _PlanCard(
                                title: l10n.paywallPlanFreeTitle,
                                price: l10n.paywallPlanFreePrice,
                                bullets: [
                                  (Icons.check_circle_rounded, l10n.paywallFeatureAllFeatures),
                                  (Icons.campaign_outlined, l10n.paywallFeatureAdSupported),
                                ],
                                highlighted: false,
                              ),
                            ),
                            const SizedBox(width: AppSpace.m),
                            Expanded(
                              child: _PlanCard(
                                title: l10n.paywallPlanAdFreeTitle,
                                price: _price ?? l10n.paywallPlanAdFreePrice,
                                bullets: [
                                  (Icons.check_circle_rounded, l10n.paywallFeatureAllFeatures),
                                  (Icons.check_circle_rounded, l10n.paywallFeatureZeroAds),
                                ],
                                highlighted: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PrimaryButton(
                      label: _price == null
                          ? l10n.paywallPurchaseButton
                          : l10n.paywallPurchaseButtonPrice(_price!),
                      isLoading: _isPurchasing,
                      onPressed: () => _purchase(context),
                    ),
                    const SizedBox(height: AppSpace.xs),
                    TextButton(
                      onPressed: () => _restore(context),
                      child: Text(l10n.paywallRestorePurchases),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(color: p.accentTint, shape: BoxShape.circle),
      child: Icon(icon, size: 44, color: p.accentText),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.title,
    required this.price,
    required this.bullets,
    required this.highlighted,
  });

  final String title;
  final String price;
  final List<(IconData, String)> bullets;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(AppSpace.l),
      decoration: BoxDecoration(
        color: highlighted ? p.accentTint : p.surface,
        border: Border.all(
          color: highlighted ? p.accent : p.separator,
          width: highlighted ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(AppRadius.l),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: highlighted ? p.accentText : p.text,
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(price, style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpace.m),
          for (final (icon, label) in bullets)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.s),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 18, color: highlighted ? p.accentText : p.text3),
                  const SizedBox(width: AppSpace.s),
                  Expanded(child: Text(label, style: theme.textTheme.bodySmall)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
