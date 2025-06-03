import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A service that stores and retrieves user settings.
///
/// By default, this class does not persist user settings. If you'd like to
/// persist the user settings locally, use the shared_preferences package. If
/// you'd like to store settings on a web server, use the http package.
class SettingsService {
  final prefs = SharedPreferencesAsync();

  /// Loads the User's preferred ThemeMode from local or remote storage.
  Future<ThemeMode> themeMode() async {
    final stored = await prefs.getString(SettingsKeys.themeMode.name) ??
        ThemeMode.system.name;
    return ThemeMode.values.firstWhere((e) => e.name == stored);
  }

  /// Persists the user's preferred ThemeMode to local or remote storage.
  Future<void> updateThemeMode(ThemeMode theme) async {
    await prefs.setString(SettingsKeys.themeMode.name, theme.name);
  }

  Future<bool> bypassShotController() async {
    return await prefs.getBool(SettingsKeys.bypassShotController.name) ?? false;
  }

  Future<void> updateBypassShotController(bool bypass) async {
    await prefs.setBool(SettingsKeys.bypassShotController.name, bypass);
  }

  Future<String> logLevel() async {
    return await prefs.getString(SettingsKeys.logLevel.name) ?? "INFO";
  }

  Future<void> updateLogLevel(String newLogLevel) async {
    await prefs.setString(SettingsKeys.logLevel.name, newLogLevel);
  }
}

enum SettingsKeys { themeMode, bypassShotController, logLevel }
