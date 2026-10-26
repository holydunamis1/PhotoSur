import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'user_settings.freezed.dart';
part 'user_settings.g.dart';

/// Persisted via SharedPreferences (storage_service.dart Phase 2,
/// settings_provider.dart Phase 3). Drives theme_provider and the
/// onboarding gate in main.dart/router.dart.
///
/// Section 1: single language at v1 ("English only at v1", File 50), so
/// `language` is 'system' (follow the device language, the default) or a
/// language code chosen manually; only 'en' ships so far.
///
/// freezed ^3.2.5 syntax: `abstract class`, not plain `class` (breaking
/// change from freezed 2.x — see pubspec.yaml comment on the freezed pin).
@freezed
abstract class UserSettings with _$UserSettings {
  const factory UserSettings({
    @Default(ThemeMode.system) ThemeMode themeMode,
    @Default('system') String language,
    @Default(false) bool isAdFree,
    @Default(false) bool hasCompletedOnboarding,
    @Default(false) bool hasSeenAttPrompt,
    // Unfinished-edit reminder notifications (on by default; the OS still
    // asks for notification permission separately).
    @Default(true) bool remindersEnabled,
    // Slowly cross-fading pictures behind the Home header (Settings switch).
    @Default(true) bool animatedHomeBackground,
    // The HD model downloads by itself whenever a photo opens and it isn't
    // installed yet (once per app launch, resuming a partial file). Set when
    // the user removes it in Settings, so it never comes back uninvited.
    @Default(false) bool hdRemovedByUser,
  }) = _UserSettings;

  factory UserSettings.fromJson(Map<String, dynamic> json) =>
      _$UserSettingsFromJson(json);
}
