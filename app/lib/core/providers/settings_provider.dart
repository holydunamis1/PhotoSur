import 'package:flutter/material.dart';

import '../models/user_settings.dart';
import '../services/storage_service.dart';

/// `ValueNotifier<UserSettings>`. Loads/persists settings, tracks
/// onboarding completion.
///
/// themeMode and isAdFree fields on UserSettings are mirrors, not sources
/// of truth — see Gap 6 resolution (theme_provider.dart doc comment).
/// This provider writes those two fields when told to by
/// syncThemeMode/syncAdFreeStatus, but never originates a theme or
/// subscription change itself. language and hasCompletedOnboarding /
/// hasSeenAttPrompt ARE authoritative here — nothing else in the app
/// owns those.
class SettingsProvider extends ValueNotifier<UserSettings> {
  SettingsProvider() : super(const UserSettings());

  bool _loaded = false;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    final loaded = await StorageService.instance.loadSettings();
    value = loaded;
    _loaded = true;
  }

  Future<void> _persist() async {
    try {
      await StorageService.instance.saveSettings(value);
    } catch (e) {
      // Persist failure shouldn't crash the UI — in-memory value still
      // reflects the user's choice for this session.
    }
  }

  /// Called by theme_provider (or the widget that owns both, e.g.
  /// settings_screen.dart in Phase 5) after a theme change, so
  /// UserSettings.themeMode stays a faithful mirror without this
  /// provider originating the change itself.
  Future<void> syncThemeMode(ThemeMode mode) async {
    value = value.copyWith(themeMode: mode);
    await _persist();
  }

  /// Called by subscription_provider after an entitlement change, for
  /// the same mirroring reason as syncThemeMode.
  Future<void> syncAdFreeStatus(bool isAdFree) async {
    value = value.copyWith(isAdFree: isAdFree);
    await _persist();
  }

  Future<void> completeOnboarding() async {
    value = value.copyWith(hasCompletedOnboarding: true);
    await _persist();
  }

  Future<void> setHdRemovedByUser(bool removed) async {
    if (value.hdRemovedByUser == removed) return;
    value = value.copyWith(hdRemovedByUser: removed);
    await _persist();
  }

  Future<void> markAttPromptSeen() async {
    value = value.copyWith(hasSeenAttPrompt: true);
    await _persist();
  }

  Future<void> setRemindersEnabled(bool enabled) async {
    value = value.copyWith(remindersEnabled: enabled);
    await _persist();
  }

  Future<void> setLanguage(String languageCode) async {
    value = value.copyWith(language: languageCode);
    await _persist();
  }

  Future<void> setAnimatedHomeBackground(bool enabled) async {
    value = value.copyWith(animatedHomeBackground: enabled);
    await _persist();
  }
}
