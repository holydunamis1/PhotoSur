import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/providers/settings_provider.dart';
import '../core/theme/app_tokens.dart';
import '../generated/l10n/app_localizations.dart';
import '../platform/ad_service.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/primary_button.dart';

/// 3 pages that teach the product, with no mention of ads or payment:
/// automatic removal, brush clean-up, studio backgrounds. "Get Started"
/// button. Illustrations live in assets/images/onboarding_*.png.
///
/// Title/body strings come from AppLocalizations at build time, so the page
/// list is built from a method taking BuildContext.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.replay = false});

  /// Opened from Settings: just shows the pages again and returns, without
  /// touching onboarding state or asking for any permission.
  final bool replay;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _page = 0;

  static const _assets = [
    'assets/images/onboarding_auto.png',
    'assets/images/onboarding_manual.png',
    'assets/images/onboarding_studio.png',
  ];

  List<_OnboardingPageData> _pages(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return [
      _OnboardingPageData(
        asset: _assets[0],
        title: l10n.onboardingPage1Title,
        body: l10n.onboardingPage1Body,
      ),
      _OnboardingPageData(
        asset: _assets[1],
        title: l10n.onboardingPage2Title,
        body: l10n.onboardingPage2Body,
      ),
      _OnboardingPageData(
        asset: _assets[2],
        title: l10n.onboardingPage3Title,
        body: l10n.onboardingPage3Body,
      ),
    ];
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finish(BuildContext context) async {
    if (widget.replay) {
      if (context.mounted) context.pop();
      return;
    }
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    await settings.completeOnboarding();

    // ATT request (post-onboarding), Section 1a compliance table. This
    // is the immediate first-run trigger — main.dart's startup sequence
    // separately covers the returning-user case (onboarding completed in
    // a prior session but the app was killed before ATT could show).
    // AppTrackingTransparency's request call is safe to invoke more than
    // once — it only shows UI when status is notDetermined, otherwise it
    // just returns the existing status — so there's no double-prompt risk
    // between these two trigger points.
    if (!settings.value.hasSeenAttPrompt) {
      await AdService.instance.requestTrackingAuthorization();
      await settings.markAttPromptSeen();
    }

    if (context.mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final accent = context.palette.accent;
    final pages = _pages(context);

    return AppScaffold(
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: pages.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) => _OnboardingPage(data: pages[i]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(pages.length, (i) {
                    final active = i == _page;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: active ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: active ? accent : accent.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 28),
                PrimaryButton(
                  label: _page == pages.length - 1
                      ? l10n.onboardingGetStarted
                      : l10n.onboardingNext,
                  onPressed: () {
                    if (_page == pages.length - 1) {
                      _finish(context);
                    } else {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingPageData {
  const _OnboardingPageData({
    required this.asset,
    required this.title,
    required this.body,
  });
  final String asset;
  final String title;
  final String body;
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({required this.data});
  final _OnboardingPageData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.palette;
    // One-shot entrance (finite, so tests can settle): the text and picture
    // rise and fade in when the page is first built.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 16 * (1 - t)), child: child),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
        child: Column(
          children: [
            Expanded(
              flex: 5,
              child: Center(
                child: Image.asset(
                  data.asset,
                  fit: BoxFit.contain,
                  excludeFromSemantics: true,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    Icons.image_outlined,
                    size: 96,
                    color: p.text3,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpace.l),
            Text(
              data.title,
              style: theme.textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpace.m),
            Text(
              data.body,
              style: theme.textTheme.bodyLarge?.copyWith(color: p.text2),
              textAlign: TextAlign.center,
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}
