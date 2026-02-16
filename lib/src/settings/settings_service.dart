import 'package:flutter/material.dart';
import 'package:reaprime/src/settings/gateway_mode.dart';
import 'package:reaprime/src/settings/scale_power_mode.dart';
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
    final stored =
        await prefs.getString(SettingsKeys.themeMode.name) ??
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
              GatewayMode.disabled.name,
        ) ??
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

  Future<double> weightFlowMultiplier() async {
    return await prefs.getDouble(SettingsKeys.weightFlowMultiplier.name) ?? 1.0;
  }

  Future<void> setWeightFlowMultiplier(double value) async {
    await prefs.setDouble(SettingsKeys.weightFlowMultiplier.name, value);
  }

  Future<double> volumeFlowMultiplier() async {
    return await prefs.getDouble(SettingsKeys.volumeFlowMultiplier.name) ?? 0.3;
  }

  Future<void> setVolumeFlowMultiplier(double value) async {
    await prefs.setDouble(SettingsKeys.volumeFlowMultiplier.name, value);
  }

  Future<ScalePowerMode> scalePowerMode() async {
    return ScalePowerModeFromString.fromString(
          await prefs.getString(SettingsKeys.scalePowerMode.name) ??
              ScalePowerMode.disabled.name,
        ) ??
        ScalePowerMode.disabled;
  }

  Future<void> setScalePowerMode(ScalePowerMode mode) async {
    await prefs.setString(SettingsKeys.scalePowerMode.name, mode.name);
  }

  Future<String?> preferredMachineId() async {
    return await prefs.getString(SettingsKeys.preferredMachineId.name);
  }

  Future<void> setPreferredMachineId(String? machineId) async {
    if (machineId == null) {
      await prefs.remove(SettingsKeys.preferredMachineId.name);
    } else {
      await prefs.setString(SettingsKeys.preferredMachineId.name, machineId);
    }
  }

  Future<SkinExitButtonPosition> skinExitButtonPosition() async {
    return SkinExitButtonPositionFromString.fromString(
          await prefs.getString(SettingsKeys.skinExitButtonPosition.name) ??
              SkinExitButtonPosition.topLeft.name,
        ) ??
        SkinExitButtonPosition.topLeft;
  }

  Future<void> setSkinExitButtonPosition(SkinExitButtonPosition position) async {
    await prefs.setString(SettingsKeys.skinExitButtonPosition.name, position.name);
  }

  Future<String> defaultSkinId() async {
    return await prefs.getString(SettingsKeys.defaultSkinId.name) ?? 'streamline_project-main';
  }

  Future<void> setDefaultSkinId(String skinId) async {
    await prefs.setString(SettingsKeys.defaultSkinId.name, skinId);
  }

  Future<bool> automaticUpdateCheck() async {
    return await prefs.getBool(SettingsKeys.automaticUpdateCheck.name) ?? true;
  }

  Future<void> setAutomaticUpdateCheck(bool value) async {
    await prefs.setBool(SettingsKeys.automaticUpdateCheck.name, value);
  }

  Future<DateTime?> lastUpdateCheckTime() async {
    final timestamp = await prefs.getInt(SettingsKeys.lastUpdateCheckTime.name);
    return timestamp != null ? DateTime.fromMillisecondsSinceEpoch(timestamp) : null;
  }

  Future<void> setLastUpdateCheckTime(DateTime time) async {
    await prefs.setInt(SettingsKeys.lastUpdateCheckTime.name, time.millisecondsSinceEpoch);
  }

  Future<bool> telemetryConsent() async {
    return await prefs.getBool(SettingsKeys.telemetryConsent.name) ?? false;
  }

  Future<void> setTelemetryConsent(bool value) async {
    await prefs.setBool(SettingsKeys.telemetryConsent.name, value);
  }

  Future<bool> telemetryPromptShown() async {
    return await prefs.getBool(SettingsKeys.telemetryPromptShown.name) ?? false;
  }

  Future<void> setTelemetryPromptShown(bool value) async {
    await prefs.setBool(SettingsKeys.telemetryPromptShown.name, value);
  }

  Future<bool> telemetryConsentDialogShown() async {
    return await prefs.getBool(SettingsKeys.telemetryConsentDialogShown.name) ?? false;
  }

  Future<void> setTelemetryConsentDialogShown(bool value) async {
    await prefs.setBool(SettingsKeys.telemetryConsentDialogShown.name, value);
  }
}

enum SettingsKeys {
  themeMode,
  gatewayMode,
  logLevel,
  recordShotPreheat,
  simulateDevices,
  weightFlowMultiplier,
  volumeFlowMultiplier,
  scalePowerMode,
  preferredMachineId,
  skinExitButtonPosition,
  defaultSkinId,
  automaticUpdateCheck,
  lastUpdateCheckTime,
  telemetryConsent,
  telemetryPromptShown,
  telemetryConsentDialogShown,
}

/// Position options for the skin view exit button
enum SkinExitButtonPosition {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

extension SkinExitButtonPositionFromString on SkinExitButtonPosition {
  static SkinExitButtonPosition? fromString(String value) {
    return SkinExitButtonPosition.values.firstWhere(
      (e) => e.name == value,
      orElse: () => SkinExitButtonPosition.topLeft,
    );
  }
}
