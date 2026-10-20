import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models/user_settings.dart';
import '../core/providers/settings_provider.dart';
import '../core/theme/app_tokens.dart';

/// The four onboarding pictures, reused as the Home header backdrop (no
/// extra image files), each with the vertical focus that shows its subject
/// in a wide, short strip.
const List<({String asset, double focusY})> kHomeStripPictures = [
  (asset: 'assets/images/onboarding_auto.webp', focusY: -0.5),
  (asset: 'assets/images/onboarding_manual.webp', focusY: -0.3),
  (asset: 'assets/images/onboarding_studio.webp', focusY: 0.1),
  (asset: 'assets/images/onboarding_batch.webp', focusY: 0.0),
];

/// How long each picture stays, and how much of that is the cross-fade.
const Duration kHomeStripCycle = Duration(seconds: 9);
const double kHomeStripFadeFraction = 0.13; // about 1.2 s of the 9 s

/// Strip of slowly cross-fading pictures behind the Home header. Used as the
/// AppBar's flexibleSpace, so it sits behind the status bar and the icons.
///
/// Off when Settings > "Animated home background" is off (plain header).
/// With the phone's "reduce animations" setting on, it shows the first
/// picture and never moves. It stops while the app is in the background and
/// whenever another screen covers Home (a muted ticker does not run).
///
/// Driven by one AnimationController (no Timer), so it never leaves a
/// pending timer behind.
class HomeBackdropStrip extends StatelessWidget {
  const HomeBackdropStrip({super.key});

  @override
  Widget build(BuildContext context) {
    SettingsProvider? settings;
    try {
      settings = Provider.of<SettingsProvider>(context, listen: false);
    } catch (_) {
      settings = null; // no settings in scope: plain header
    }
    if (settings == null) return const SizedBox.shrink();
    return ValueListenableBuilder<UserSettings>(
      valueListenable: settings,
      builder: (context, current, _) => current.animatedHomeBackground
          ? const _Strip()
          : const SizedBox.shrink(),
    );
  }
}

class _Strip extends StatefulWidget {
  const _Strip();

  @override
  State<_Strip> createState() => _StripState();
}

class _StripState extends State<_Strip>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  int _index = 0;
  bool _reduceMotion = false;
  bool _precached = false;

  int get _next => (_index + 1) % kHomeStripPictures.length;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = AnimationController(vsync: this, duration: kHomeStripCycle)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _index = _next);
          _controller.forward(from: 0);
        }
      });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.forward();
    }
    if (!_precached) {
      _precached = true;
      // Decode the second picture ahead of the first fade. Failure is
      // harmless: the image widget shows nothing for a missing file.
      precacheImage(AssetImage(kHomeStripPictures[_next].asset), context)
          .catchError((_) {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_reduceMotion && !_controller.isAnimating) _controller.forward();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  Widget _picture(int i, BuildContext context) {
    final p = kHomeStripPictures[i];
    final width = MediaQuery.sizeOf(context).width *
        MediaQuery.devicePixelRatioOf(context);
    return Image.asset(
      p.asset,
      key: ValueKey('home-strip-image-$i'),
      fit: BoxFit.cover,
      alignment: Alignment(0, p.focusY),
      cacheWidth: width >= 1 ? width.round() : null,
      gaplessPlayback: true,
      excludeFromSemantics: true,
      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ExcludeSemantics(
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final fadeStart = 1 - kHomeStripFadeFraction;
              final t = ((_controller.value - fadeStart) /
                      kHomeStripFadeFraction)
                  .clamp(0.0, 1.0);
              final eased = Curves.easeInOut.transform(t);
              return Stack(
                fit: StackFit.expand,
                children: [
                  _picture(_index, context),
                  if (eased > 0)
                    Opacity(opacity: eased, child: _picture(_next, context)),
                ],
              );
            },
          ),
          // A tint keeps the header icons readable on light and dark, and the
          // lower edge fades into the screen colour so there is no seam.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  palette.background.withValues(alpha: 0.70),
                  palette.background.withValues(alpha: 0.70),
                  palette.background,
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
