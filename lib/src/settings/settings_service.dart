import 'package:flutter/material.dart';
import 'package:reaprime/src/settings/gateway_mode.dart';
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

  Future<GatewayMode> gatewayMode() async {
    return GatewayModeFromString.fromString(
            await prefs.getString(SettingsKeys.gatewayMode.name) ??
                GatewayMode.disabled.name) ??
        GatewayMode.disabled;
  }

  Future<void> updateGatewayMode(GatewayMode mode) async {
    await prefs.setString(SettingsKeys.gatewayMode.name, mode.name);
  }

  Future<String> logLevel() async {
    return await prefs.getString(SettingsKeys.logLevel.name) ?? "INFO";
  }

  Future<void> updateLogLevel(String newLogLevel) async {
    await prefs.setString(SettingsKeys.logLevel.name, newLogLevel);
  }

  Future<bool> recordShotPreheat() async {
    return await prefs.getBool(SettingsKeys.recordShotPreheat.name) ?? false;
  }

  Future<void> setRecordShotPreheat(bool value) async {
    return await prefs.setBool(SettingsKeys.recordShotPreheat.name, value);
  }

  Future<bool> simulateDevices() async {
    return await prefs.getBool(SettingsKeys.simulateDevices.name) ?? false;
  }

  Future<void> setSimulatedDevices(bool value) async {
    await prefs.setBool(SettingsKeys.simulateDevices.name, value);
  }
}

enum SettingsKeys {
  themeMode,
  gatewayMode,
  logLevel,
  recordShotPreheat,
  simulateDevices
}
