import 'package:go_router/go_router.dart';

import 'core/providers/settings_provider.dart';
import 'screens/batch_screen.dart';
import 'screens/camera_screen.dart';
import 'screens/crop_rotate_screen.dart';
import 'screens/editor_screen.dart';
import 'screens/export_viewer_screen.dart';
import 'screens/exports_screen.dart';
import 'screens/help_screen.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/paywall_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/unsupported_device_screen.dart';

/// GoRouter routes: / (home), /camera, /crop, /editor, /settings,
/// /paywall — per Section 5, File 49.
///
/// Gap 11 addition: /onboarding is NOT in Section 49's literal route
/// list, but onboarding_screen.dart (File 39) is a real screen that must
/// be reachable, and Section 3's flow diagram requires it as the
/// mandatory first-launch gate before Home Screen. Adding this route is a
/// mechanical necessity — the app cannot show onboarding at all without
/// it — not a design deviation being made silently.
///
/// [redirect] + [refreshListenable]: gates '/' behind onboarding
/// completion. refreshListenable: settingsProvider means this redirect
/// re-evaluates automatically the moment hasCompletedOnboarding flips
/// true (settingsProvider is a ValueNotifier, i.e. a Listenable) —
/// standard go_router pattern for auth/onboarding gates, no polling.
GoRouter buildRouter(SettingsProvider settingsProvider) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: settingsProvider,
    redirect: (context, state) {
      final onboarded = settingsProvider.value.hasCompletedOnboarding;
      final goingToOnboarding = state.matchedLocation == '/onboarding';

      if (!onboarded && !goingToOnboarding) return '/onboarding';
      if (onboarded && goingToOnboarding) return '/';
      return null; // no redirect needed
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/intro',
        builder: (context, state) => const OnboardingScreen(replay: true),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/help',
        builder: (context, state) => const HelpScreen(),
      ),
      GoRoute(
        path: '/camera',
        builder: (context, state) => const CameraScreen(),
      ),
      GoRoute(
        path: '/crop',
        builder: (context, state) {
          final imagePath = state.extra as String?;
          if (imagePath == null) {
            // Defensive fallback — this route should never be reached
            // without an image path, but a raw crash here would be worse
            // than bouncing back to home per the graceful-degradation rule.
            return const HomeScreen();
          }
          return CropRotateScreen(imagePath: imagePath);
        },
      ),
      GoRoute(
        path: '/editor',
        builder: (context, state) {
          final imagePath = state.extra as String?;
          if (imagePath == null) return const HomeScreen();
          return EditorScreen(imagePath: imagePath);
        },
      ),
      GoRoute(
        path: '/exports',
        builder: (context, state) => const ExportsScreen(),
      ),
      GoRoute(
        path: '/export-viewer',
        builder: (context, state) {
          final args = state.extra as ExportViewerArgs?;
          if (args == null || args.jobs.isEmpty) return const ExportsScreen();
          return ExportViewerScreen(args: args);
        },
      ),
      GoRoute(
        path: '/batch',
        builder: (context, state) {
          final paths = state.extra as List<String>?;
          if (paths == null || paths.isEmpty) return const HomeScreen();
          return BatchScreen(imagePaths: paths);
        },
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/unsupported-device',
        // Gap-style addition, same reasoning as /onboarding above: not
        // in Section 49's literal route list, but unsupported_device_
        // screen.dart (File 72) needs a real navigation target.
        builder: (context, state) {
          final reason = state.extra as UnsupportedReason? ?? UnsupportedReason.noCamera;
          return UnsupportedDeviceScreen(reason: reason);
        },
      ),
      GoRoute(
        path: '/paywall',
        builder: (context, state) => const PaywallScreen(),
      ),
    ],
  );
}
