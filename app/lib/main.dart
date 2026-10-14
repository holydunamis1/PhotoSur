import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'app.dart';
import 'core/providers/ad_provider.dart';
import 'core/providers/image_edit_provider.dart';
import 'core/providers/settings_provider.dart';
import 'core/providers/subscription_provider.dart';
import 'core/providers/theme_provider.dart';
import 'core/services/storage_service.dart';
import 'core/utils/error_handler.dart';
import 'platform/ad_service.dart';
import 'core/utils/constants.dart';
import 'platform/model_download_service.dart';
import 'platform/notification_service.dart';

void _boot(String step) => debugPrint('BOOT $step');

/// Runs [task] but never lets it block or crash startup: failures and
/// timeouts are logged and startup continues with defaults.
Future<void> _guard(
  String name,
  Future<void> Function() task,
  Duration timeout,
) async {
  try {
    await task().timeout(timeout);
    _boot('$name ok');
  } catch (e) {
    _boot('$name FAILED or TIMED OUT: $e');
  }
}

/// Everything that is not needed to draw the first screen. Runs after
/// runApp so a slow or stuck SDK (ads especially) can never leave the user
/// staring at the splash screen.
Future<void> _startBackgroundServices(SettingsProvider settingsProvider) async {
  if (kNotificationsEnabled) {
    await _guard(
      'notifications init',
      NotificationService.instance.init,
      const Duration(seconds: 15),
    );
  }

  // ATT request — safety net for RETURNING users whose onboarding completed
  // in a prior session but the app was killed before ATT could show. The
  // first-run case is handled in onboarding_screen.dart's _finish().
  if (settingsProvider.value.hasCompletedOnboarding &&
      !settingsProvider.value.hasSeenAttPrompt) {
    await _guard('att', () async {
      await AdService.instance.requestTrackingAuthorization();
      await settingsProvider.markAttPromptSeen();
    }, const Duration(seconds: 60));
  }

  // Ads last: after ATT (iOS), and slowest, so it blocks nothing.
  await _guard(
    'ads init',
    AdService.instance.initialize,
    const Duration(seconds: 45),
  );
}

Future<void> main() async {
  _boot('main start');
  WidgetsFlutterBinding.ensureInitialized();
  _boot('binding ready');

  AppErrorHandler.init();

  // Apache-2.0 attribution for the bundled segmentation model (U2-Netp),
  // shown on the in-app licenses page (Settings > Open-source licenses).
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/licenses/inter_ofl.txt');
    yield LicenseEntryWithLineBreaks(['Inter typeface'], text);
  });
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/licenses/u2net_apache2.txt');
    yield LicenseEntryWithLineBreaks(
      ['U2-Net (u2netp) segmentation model'],
      'U2-Net: Going Deeper with Nested U-Structure for Salient Object '
      'Detection. Xuebin Qin, Zichen Zhang, Chenyang Huang, Masood Dehghan, '
      'Osmar R. Zaiane and Martin Jagersand. Pattern Recognition, 2020.\n'
      'https://github.com/xuebinqin/U-2-Net\n\n'
      'Changes: the pretrained u2netp weights were converted to TensorFlow '
      'Lite format and the model was trimmed to its single fused output. '
      'The optional HD model (full U2-Net weights, downloaded on request) '
      'was converted and trimmed the same way.\n\n'
      '$text',
    );
  });

  // sqflite init (File 47) — eagerly open/create the database so any
  // first-use failure surfaces here, wrapped in try/catch, rather than
  // silently on first export/history read.
  await _guard('storage', StorageService.instance.initialize,
      const Duration(seconds: 8));

  // Pick up an HD cut-out model downloaded in an earlier session (if any).
  await _guard('hd model', ModelDownloadService.instance.init,
      const Duration(seconds: 4));

  // Providers are created here (not inside app.dart) so their async load
  // steps can complete before the first frame — avoids a flash of the
  // wrong theme or a moment where settings appear unset.
  final themeProvider = ThemeProvider();
  final settingsProvider = SettingsProvider();
  await _guard('theme load', themeProvider.load, const Duration(seconds: 5));
  await _guard(
      'settings load', settingsProvider.load, const Duration(seconds: 5));

  // IAP init — subscriptionProvider seeds its initial value from
  // settingsProvider's cached isAdFree (Gap 6 resolution) before the live
  // purchaseStream/restorePurchases calls resolve.
  final subscriptionProvider = SubscriptionProvider(settingsProvider);
  subscriptionProvider.initialize();

  final adProvider = AdProvider(subscriptionProvider);
  final imageEditProvider = ImageEditProvider();

  _boot('calling runApp');
  runApp(
    KatharEraseApp(
      themeProvider: themeProvider,
      settingsProvider: settingsProvider,
      subscriptionProvider: subscriptionProvider,
      adProvider: adProvider,
      imageEditProvider: imageEditProvider,
    ),
  );
  // Background services start only AFTER the first frame is on screen, so
  // nothing they do can ever delay the UI appearing.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _boot('first frame drawn');
    unawaited(_startBackgroundServices(settingsProvider));
  });
}
