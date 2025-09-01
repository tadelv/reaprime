import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/settings/gateway_mode.dart';

import 'settings_service.dart';

/// A class that many Widgets can interact with to read user settings, update
/// user settings, or listen to user settings changes.
///
/// Controllers glue Data Services to Flutter Widgets. The SettingsController
/// uses the SettingsService to store and retrieve user settings.
class SettingsController with ChangeNotifier {
  SettingsController(this._settingsService);

  // Make SettingsService a private variable so it is not used directly.
  final SettingsService _settingsService;

  // Make ThemeMode a private variable so it is not updated directly without
  // also persisting the changes with the SettingsService.
  late ThemeMode _themeMode;

  late GatewayMode _gatewayMode;

  late String _logLevel;

  late bool _simulatedDevices;

  // Allow Widgets to read the user's preferred ThemeMode.
  ThemeMode get themeMode => _themeMode;
  GatewayMode get gatewayMode => _gatewayMode;
  String get logLevel => _logLevel;
  bool get simulatedDevices => _simulatedDevices;

  /// Load the user's settings from the SettingsService. It may load from a
  /// local database or the internet. The controller only knows it can load the
  /// settings from the service.
  Future<void> loadSettings() async {
    _themeMode = await _settingsService.themeMode();
    _gatewayMode = await _settingsService.gatewayMode();
    _logLevel = await _settingsService.logLevel();
    _simulatedDevices = await _settingsService.simulateDevices();

    // Important! Inform listeners a change has occurred.
    notifyListeners();
  }

  /// Update and persist the ThemeMode based on the user's selection.
  Future<void> updateThemeMode(ThemeMode? newThemeMode) async {
    if (newThemeMode == null) return;

    // Do not perform any work if new and old ThemeMode are identical
    if (newThemeMode == _themeMode) return;

    // Otherwise, store the new ThemeMode in memory
    _themeMode = newThemeMode;

    // Important! Inform listeners a change has occurred.
    notifyListeners();

    // Persist the changes to a local database or the internet using the
    // SettingService.
    await _settingsService.updateThemeMode(newThemeMode);
  }

  Future<void> updateGatewayMode(GatewayMode mode) async {
    if (mode == _gatewayMode) {
      return;
    }

    _gatewayMode = mode;

    notifyListeners();

    await _settingsService.updateGatewayMode(mode);
  }

  Future<void> updateLogLevel(String? newLogLevel) async {
    if (newLogLevel == null) {
      return;
    }
    if (newLogLevel == _logLevel) {
      return;
    }
    final loggerLevel =
        Level.LEVELS.firstWhereOrNull((e) => e.name == newLogLevel);
    if (loggerLevel == null) {
      return;
    }
    Logger.root.level = loggerLevel;

    _logLevel = newLogLevel;

    notifyListeners();

    await _settingsService.updateLogLevel(newLogLevel);
  }

  Future<void> setSimulatedDevices(bool value) async {
    if (value == _simulatedDevices) {
      return;
    }
    _simulatedDevices = value;
    await _settingsService.setSimulatedDevices(value);
    notifyListeners();
  }
}
