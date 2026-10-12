import 'package:flutter/material.dart';

// ============================================================
// DESIGN TOKENS — Section 7
// Accent reskinned to Emerald green (#10B981 / #34D399 dark).
// ============================================================

class AppColors {
  AppColors._();

  // Light
  static const Color accentLight = Color(0xFF10B981);
  static const Color accentDimLight = Color(0xFF059669);
  static const Color bgPrimaryLight = Color(0xFFFFFFFF);
  static const Color bgSecondaryLight = Color(0xFFF5F5F7);
  static const Color bgTertiaryLight = Color(0xFFE8E8ED);
  static const Color textPrimaryLight = Color(0xFF1C1C1E);
  static const Color textSecondaryLight = Color(0xFF6E6E73);
  static const Color textTertiaryLight = Color(0xFFA1A1AA);
  static const Color borderSubtleLight = Color(0xFFE5E5EA);
  static const Color borderFocusLight = Color(0xFF10B981);
  static const Color errorLight = Color(0xFFDC2626);
  static const Color successLight = Color(0xFF10B981);
  static const Color warningLight = Color(0xFFF59E0B);

  // Dark
  static const Color accentDark = Color(0xFF34D399);
  static const Color accentDimDark = Color(0xFF10B981);
  static const Color bgPrimaryDark = Color(0xFF0F0F11);
  static const Color bgSecondaryDark = Color(0xFF1A1A1E);
  static const Color bgTertiaryDark = Color(0xFF232329);
  static const Color textPrimaryDark = Color(0xFFF0F0F5);
  static const Color textSecondaryDark = Color(0xFF8A8A95);
  static const Color textTertiaryDark = Color(0xFF52525B);
  static const Color borderSubtleDark = Color(0xFF2A2A30);
  static const Color borderFocusDark = Color(0xFF34D399);
  static const Color errorDark = Color(0xFFEF4444);
  static const Color successDark = Color(0xFF34D399);
  static const Color warningDark = Color(0xFFFBBF24);
}

// ============================================================
// AD UNIT ID CONSTANTS — RAW STRINGS ONLY (Section 9)
// Runtime selection logic (kReleaseMode + Platform.isIOS branching)
// lives in lib/platform/ad_service.dart per A3 — NOT here.
// This file must never import dart:io.
//
// Test IDs are Google's official public test ad unit IDs, verified
// against developers.google.com/admob docs (re-confirmed accurate
// as of this build). Platform-specific — do not cross-use.
// ============================================================

// Test IDs — Android
const String kTestBannerAdUnitIdAndroid =
    'ca-app-pub-3940256099942544/6300978111';
const String kTestInterstitialAdUnitIdAndroid =
    'ca-app-pub-3940256099942544/1033173712';

// Test IDs — iOS
const String kTestBannerAdUnitIdIos =
    'ca-app-pub-3940256099942544/2934735716';
const String kTestInterstitialAdUnitIdIos =
    'ca-app-pub-3940256099942544/4411468910';

// "Production" IDs — currently Google's official test IDs (verified against
// Google's AdMob documentation) so no placeholder strings exist anywhere.
// Replace with the real AdMob unit IDs before publishing to the stores.
const String kProdBannerAdUnitIdAndroid = kTestBannerAdUnitIdAndroid;
const String kProdBannerAdUnitIdIos = kTestBannerAdUnitIdIos;
const String kProdInterstitialAdUnitIdAndroid =
    kTestInterstitialAdUnitIdAndroid;
const String kProdInterstitialAdUnitIdIos = kTestInterstitialAdUnitIdIos;

const int kInterstitialMinIntervalSeconds = 120;

// ============================================================
// FEATURE FLAGS
// Section 1: no daily-habit loop -> no notifications subsystem.
// Section 1: no cross-device sync -> zero backend.
// Path A (Section 16) stays off until explicitly enabled post-launch.
// ============================================================

const bool kNotificationsEnabled = true; // unfinished-edit reminders
const bool kCloudSyncEnabled = false;
const bool kMlKitPathAEnabled = false; // Android-only enhancement, Section 16

// ============================================================
// BRUSH / EDIT LIMITS (Section 2, Features 2, 3, 4, 11, 14)
// ============================================================

const double kBrushSizeMinPx = 1.0;
const double kBrushSizeMaxPx = 50.0;
const double kEdgeFeatherMinPx = 0.0;
const double kEdgeFeatherMaxPx = 20.0;
const double kBackgroundBlurMinPx = 0.0;
const double kBackgroundBlurMaxPx = 25.0;
const double kZoomMin = 1.0;
const double kZoomMax = 8.0;

// Export resize presets (Feature 14)
const Size kResizePreset1x1 = Size(1080, 1080);
const Size kResizePreset4x5 = Size(1080, 1350);
const Size kResizePreset9x16 = Size(1080, 1920);

// --- Segmentation pipeline (U2-Netp, see assets/models/MODEL_NOTICE.md) ---
const String kSegmentationModelAsset = 'assets/models/segmentation.tflite';
const int kModelInputSize = 320; // model tensors: [1,320,320,3] -> [1,320,320,1]
// Longest edge of the image the editor works on. Larger photos are scaled
// down once at load so mask building, brush replay and export stay fast and
// within memory on mid-range phones.
const int kMaxWorkingEdgePx = 2048;

// --- Unfinished-edit reminder (local notification) ---
// How long after leaving an unexported edit the reminder appears.
const Duration kUnfinishedEditReminderDelay = Duration(hours: 3);
const String kReminderChannelId = 'unfinished_edit';


/// Shows the failing step and error type under the export-failed message so a
/// phone-only tester can report what went wrong. Switch to false before
/// store release.
const bool kShowExportDiagnostics = true;

/// Most photos one batch run accepts (keeps memory and run time sane).
const int kMaxBatchPhotos = 30;
