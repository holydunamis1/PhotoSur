import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../generated/l10n/app_localizations.dart';
import '../widgets/ad_banner_slot.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/primary_button.dart';

/// Extreme fallback: device has <1GB RAM or no camera. Honest message +
/// manual import instructions.
///
/// *** RAM CHECK — NOT IMPLEMENTED, flagged honestly rather than faked ***
/// Checked live during Phase 9: Flutter's own GitHub tracker
/// (flutter/flutter#68181) confirms the mainstream, verified-publisher
/// `device_info_plus` plugin does NOT expose actual device RAM size —
/// it's an open, unimplemented feature request. The packages that do
/// claim to expose RAM (`ram_info`, `system_info_plus`, `memory_info`)
/// are all small, low-adoption packages with no verified publisher — a
/// different trust tier than every other dependency added during this
/// build (permission_handler/baseflow.com, url_launcher/flutter.dev,
/// crop_your_image/tsuyoshichujo.com, flutter_image_compress/
/// fluttercandies.com). Adding an unverified-publisher plugin just to
/// satisfy this one checkbox was rejected on the same reasoning as the
/// IAP backend decision earlier in this build: low benefit for a real
/// dependency-risk cost. If RAM detection is wanted later, evaluate a
/// specific package on its own merits then — this screen's [reason]
/// enum already has a slot ready for it (RAM check would set
/// UnsupportedReason.lowMemory once a trustworthy source for that value
/// exists).
///
/// What IS implemented: camera-absence detection, using the already-
/// present `camera` package's availableCameras() — no new dependency,
/// no trust-tier compromise.
enum UnsupportedReason { noCamera, lowMemory }

class UnsupportedDeviceScreen extends StatelessWidget {
  const UnsupportedDeviceScreen({super.key, required this.reason});

  final UnsupportedReason reason;

  /// Checks whether this screen's noCamera condition applies. Call this
  /// from wherever camera access is first attempted (camera_screen.dart)
  /// — this screen itself doesn't probe hardware, it only presents the
  /// already-determined reason, keeping detection logic in one place.
  static Future<bool> deviceHasNoCamera() async {
    try {
      final cameras = await availableCameras();
      return cameras.isEmpty;
    } catch (e) {
      // If the camera plugin itself throws during enumeration, treat
      // that the same as "no camera" for this screen's purposes — the
      // user's actual experience (can't use the camera) is identical.
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final message = switch (reason) {
      UnsupportedReason.noCamera => l10n.unsupportedNoCameraMessage,
      UnsupportedReason.lowMemory => l10n.unsupportedLowMemoryMessage,
    };

    return AppScaffold(
      appBar: AppBar(title: Text(l10n.unsupportedTitle)),
      body: Column(
        children: [
          Expanded(
            child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.phonelink_erase_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.unsupportedManualImportHint,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 24),
            PrimaryButton(
              label: l10n.unsupportedUseGalleryButton,
              onPressed: () => context.go('/'), // home_screen's Gallery button covers this path
            ),
          ],
        ),
            ),
          ),
          const AdBannerSlot(personalized: false),
        ],
      ),
    );
  }
}
