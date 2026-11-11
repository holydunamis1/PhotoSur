import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photosur/core/providers/image_edit_provider.dart';
import 'package:photosur/core/providers/settings_provider.dart';
import 'package:photosur/core/providers/subscription_provider.dart';
import 'package:photosur/core/theme/app_theme.dart';
import 'package:photosur/generated/l10n/app_localizations.dart';
import 'package:photosur/screens/export_bottom_sheet.dart';
import 'package:photosur/screens/help_screen.dart';
import 'package:photosur/screens/onboarding_screen.dart';
import 'package:photosur/screens/paywall_screen.dart';
import 'package:photosur/screens/settings_screen.dart';
import 'package:photosur/screens/unsupported_device_screen.dart';
import 'package:photosur/widgets/editor_tool_dock.dart';
import 'package:provider/provider.dart';

/// Every shipped language x two text scales x the main screens at 320 dp.
/// Uses Flutter's test font, so it catches wording that is far too long, not
/// sub-pixel differences from the real fonts.
Widget _host(Locale locale, double scale, Widget home) {
  Provider.debugCheckInvalidValueType = null;
  final settings = SettingsProvider();
  return MultiProvider(
    providers: [
      Provider<ImageEditProvider>.value(value: ImageEditProvider()),
      Provider<SubscriptionProvider>.value(value: SubscriptionProvider(settings)),
    ],
    child: MaterialApp(
      theme: buildAppTheme(Brightness.light),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: home,
    ),
  );
}

void main() {
  final surfaces = <String, Widget Function()>{
    'onboarding': () => const OnboardingScreen(replay: true),
    'settings': () => const SettingsScreen(),
    'help': () => const HelpScreen(),
    'paywall': () => const PaywallScreen(),
    'unsupported-noCamera': () =>
        const UnsupportedDeviceScreen(reason: UnsupportedReason.noCamera),
    'unsupported-lowMemory': () =>
        const UnsupportedDeviceScreen(reason: UnsupportedReason.lowMemory),
    'dock': () => Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: EditorToolDock(selected: EditorTool.cutout, onSelected: (_) {}),
          ),
        ),
    'export-sheet': () => const Scaffold(
          body: Align(alignment: Alignment.bottomCenter, child: ExportBottomSheet()),
        ),
  };

  for (final locale in AppLocalizations.supportedLocales) {
    for (final scale in [1.0, 1.3]) {
      for (final entry in surfaces.entries) {
        testWidgets('$locale x$scale ${entry.key}: no overflow', (tester) async {
          tester.view.devicePixelRatio = 1.0;
          tester.view.physicalSize = const Size(320, 640);
          addTearDown(tester.view.reset);
          final errors = <String>[];
          final prev = FlutterError.onError;
          FlutterError.onError = (d) {
            final m = d.exceptionAsString().split('\n').first;
            errors.add(m.length > 110 ? m.substring(0, 110) : m);
          };
          addTearDown(() => FlutterError.onError = prev);
          await tester.pumpWidget(_host(locale, scale, entry.value()));
          await tester.pump(const Duration(milliseconds: 100));
          FlutterError.onError = prev;
          expect(errors, isEmpty, reason: '${entry.key}: ${errors.take(2).join(' // ')}');
        });
      }
    }
  }
}
