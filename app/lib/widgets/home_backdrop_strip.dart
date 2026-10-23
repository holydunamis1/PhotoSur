import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models/user_settings.dart';
import '../core/providers/settings_provider.dart';
import '../core/theme/app_tokens.dart';

/// The four onboarding pictures, reused as the background of the Home "Recent Exports" section (no
/// extra image files), each with the vertical focus that shows its subject
/// in a 4:3 picture cropped to the section.
const List<({String asset, double focusY})> kHomeStripPictures = [
  (asset: 'assets/images/onboarding_auto.webp', focusY: -0.5),
  (asset: 'assets/images/onboarding_manual.webp', focusY: -0.3),
  (asset: 'assets/images/onboarding_studio.webp', focusY: 0.1),
  (asset: 'assets/images/onboarding_batch.webp', focusY: 0.0),
];

/// How long each picture stays (including the cross-fade), and the fade.
const Duration kHomeStripCycle = Duration(seconds: 9);
const Duration kHomeStripFade = Duration(milliseconds: 1200);

/// Strip of slowly cross-fading pictures behind the Home header. Used as the
/// AppBar's flexibleSpace, so it sits behind the status bar and the icons.
///
/// Off when Settings > "Animated home background" is off (plain header).
/// With the phone's "reduce animations" setting on, it shows the first
/// picture and never moves. It stops while the app is in the background and
/// whenever another screen covers Home.
///
/// Power: frames are drawn only during the 1.2 s fades. Between fades a
/// single Timer waits and nothing is redrawn.
class HomeBackdropStrip extends StatelessWidget {
  const HomeBackdropStrip({super.key});

  @override
  Widget build(BuildContext context) {
    SettingsProvider? settings;
    try {
      settings = Provider.of<SettingsProvider>(context, listen: false);
    } catch (_) {
      settings = null; // no settings in scope: plain background
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
  late final AnimationController _fade;
  Timer? _hold;
  int _index = 0;
  bool _reduceMotion = false;
  bool _active = true; // app resumed
  bool _precached = false;

  int get _next => (_index + 1) % kHomeStripPictures.length;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fade = AnimationController(vsync: this, duration: kHomeStripFade)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _index = _next);
          _fade.value = 0;
          _startHold();
        }
      });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _sync();
    if (!_precached) {
      _precached = true;
      // Decode the second picture ahead of the first fade. Failure is
      // harmless: the image widget shows nothing for a missing file.
      precacheImage(AssetImage(kHomeStripPictures[_next].asset), context)
          .catchError((_) {});
    }
  }

  void _startHold() {
    _hold?.cancel();
    _hold = Timer(kHomeStripCycle - kHomeStripFade, () {
      _hold = null;
      if (mounted && !_reduceMotion && _active) _fade.forward(from: 0);
    });
  }

  /// Run or pause according to reduce-motion and the app state.
  void _sync() {
    if (_reduceMotion || !_active) {
      _hold?.cancel();
      _hold = null;
      _fade.stop();
    } else if (_fade.value > 0) {
      _fade.forward(); // resume a fade that was interrupted
    } else if (_hold == null) {
      _startHold();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hold?.cancel();
    _fade.dispose();
    super.dispose();
  }

  Widget _picture(int i) {
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
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _fade,
              builder: (context, _) {
                final eased = Curves.easeInOut.transform(_fade.value);
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    _picture(_index),
                    if (eased > 0)
                      Opacity(opacity: eased, child: _picture(_next)),
                  ],
                );
              },
            ),
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
