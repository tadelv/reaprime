import 'package:flutter/material.dart';
import 'package:reaprime/src/settings/charging_mode.dart';
import 'package:reaprime/src/settings/gateway_mode.dart';
import 'package:reaprime/src/settings/scale_power_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Abstract interface for storing and retrieving user settings.
///
/// Concrete implementations can use SharedPreferences, in-memory storage,
/// or any other persistence mechanism.
abstract class SettingsService {
  Future<ThemeMode> themeMode();
  Future<void> updateThemeMode(ThemeMode theme);
  Future<GatewayMode> gatewayMode();
  Future<void> updateGatewayMode(GatewayMode mode);
  Future<String> logLevel();
  Future<void> updateLogLevel(String newLogLevel);
  Future<bool> recordShotPreheat();
  Future<void> setRecordShotPreheat(bool value);
  Future<bool> simulateDevices();
  Future<void> setSimulatedDevices(bool value);
  Future<double> weightFlowMultiplier();
  Future<void> setWeightFlowMultiplier(double value);
  Future<double> volumeFlowMultiplier();
  Future<void> setVolumeFlowMultiplier(double value);
  Future<ScalePowerMode> scalePowerMode();
  Future<void> setScalePowerMode(ScalePowerMode mode);
  Future<String?> preferredMachineId();
  Future<void> setPreferredMachineId(String? machineId);
  Future<String?> preferredScaleId();
  Future<void> setPreferredScaleId(String? scaleId);
  Future<SkinExitButtonPosition> skinExitButtonPosition();
  Future<void> setSkinExitButtonPosition(SkinExitButtonPosition position);
  Future<String> defaultSkinId();
  Future<void> setDefaultSkinId(String skinId);
  Future<bool> automaticUpdateCheck();
  Future<void> setAutomaticUpdateCheck(bool value);
  Future<DateTime?> lastUpdateCheckTime();
  Future<void> setLastUpdateCheckTime(DateTime time);
  Future<bool> telemetryConsent();
  Future<void> setTelemetryConsent(bool value);
  Future<bool> telemetryPromptShown();
  Future<void> setTelemetryPromptShown(bool value);
  Future<bool> telemetryConsentDialogShown();
  Future<void> setTelemetryConsentDialogShown(bool value);
  Future<String?> skippedVersion();
  Future<void> setSkippedVersion(String? version);
  Future<ChargingMode> chargingMode();
  Future<void> setChargingMode(ChargingMode mode);
  Future<bool> nightModeEnabled();
  Future<void> setNightModeEnabled(bool value);
  Future<int> nightModeSleepTime();
  Future<void> setNightModeSleepTime(int minutes);
  Future<int> nightModeMorningTime();
  Future<void> setNightModeMorningTime(int minutes);
}

/// SharedPreferences-backed implementation of [SettingsService].
class SharedPreferencesSettingsService extends SettingsService {
  final prefs = SharedPreferencesAsync();

  @override
  Future<ThemeMode> themeMode() async {
    final stored =
        await prefs.getString(SettingsKeys.themeMode.name) ??
        ThemeMode.system.name;
    return ThemeMode.values.firstWhere((e) => e.name == stored);
  }

  @override
  Future<void> updateThemeMode(ThemeMode theme) async {
    await prefs.setString(SettingsKeys.themeMode.name, theme.name);
  }

  @override
  Future<GatewayMode> gatewayMode() async {
    return GatewayModeFromString.fromString(
          await prefs.getString(SettingsKeys.gatewayMode.name) ??
              GatewayMode.disabled.name,
        ) ??
        GatewayMode.disabled;
  }

  @override
  Future<void> updateGatewayMode(GatewayMode mode) async {
    await prefs.setString(SettingsKeys.gatewayMode.name, mode.name);
  }

  @override
  Future<String> logLevel() async {
    return await prefs.getString(SettingsKeys.logLevel.name) ?? "INFO";
  }

  @override
  Future<void> updateLogLevel(String newLogLevel) async {
    await prefs.setString(SettingsKeys.logLevel.name, newLogLevel);
  }

  @override
  Future<bool> recordShotPreheat() async {
    return await prefs.getBool(SettingsKeys.recordShotPreheat.name) ?? false;
  }

  @override
  Future<void> setRecordShotPreheat(bool value) async {
    return await prefs.setBool(SettingsKeys.recordShotPreheat.name, value);
  }

  @override
  Future<bool> simulateDevices() async {
    return await prefs.getBool(SettingsKeys.simulateDevices.name) ?? false;
  }

  @override
  Future<void> setSimulatedDevices(bool value) async {
    await prefs.setBool(SettingsKeys.simulateDevices.name, value);
  }

  @override
  Future<double> weightFlowMultiplier() async {
    return await prefs.getDouble(SettingsKeys.weightFlowMultiplier.name) ?? 1.0;
  }

  @override
  Future<void> setWeightFlowMultiplier(double value) async {
    await prefs.setDouble(SettingsKeys.weightFlowMultiplier.name, value);
  }

  @override
  Future<double> volumeFlowMultiplier() async {
    return await prefs.getDouble(SettingsKeys.volumeFlowMultiplier.name) ?? 0.3;
  }

  @override
  Future<void> setVolumeFlowMultiplier(double value) async {
    await prefs.setDouble(SettingsKeys.volumeFlowMultiplier.name, value);
  }

  @override
  Future<ScalePowerMode> scalePowerMode() async {
    return ScalePowerModeFromString.fromString(
          await prefs.getString(SettingsKeys.scalePowerMode.name) ??
              ScalePowerMode.disabled.name,
        ) ??
        ScalePowerMode.disabled;
  }

  @override
  Future<void> setScalePowerMode(ScalePowerMode mode) async {
    await prefs.setString(SettingsKeys.scalePowerMode.name, mode.name);
  }

  @override
  Future<String?> preferredMachineId() async {
    return await prefs.getString(SettingsKeys.preferredMachineId.name);
  }

  @override
  Future<void> setPreferredMachineId(String? machineId) async {
    if (machineId == null) {
      await prefs.remove(SettingsKeys.preferredMachineId.name);
    } else {
      await prefs.setString(SettingsKeys.preferredMachineId.name, machineId);
    }
  }

  @override
  Future<String?> preferredScaleId() async {
    return await prefs.getString(SettingsKeys.preferredScaleId.name);
  }

  @override
  Future<void> setPreferredScaleId(String? scaleId) async {
    if (scaleId == null) {
      await prefs.remove(SettingsKeys.preferredScaleId.name);
    } else {
      await prefs.setString(SettingsKeys.preferredScaleId.name, scaleId);
    }
  }

  @override
  Future<SkinExitButtonPosition> skinExitButtonPosition() async {
    return SkinExitButtonPositionFromString.fromString(
          await prefs.getString(SettingsKeys.skinExitButtonPosition.name) ??
              SkinExitButtonPosition.topLeft.name,
        ) ??
        SkinExitButtonPosition.topLeft;
  }

  @override
  Future<void> setSkinExitButtonPosition(SkinExitButtonPosition position) async {
    await prefs.setString(SettingsKeys.skinExitButtonPosition.name, position.name);
  }

  @override
  Future<String> defaultSkinId() async {
    return await prefs.getString(SettingsKeys.defaultSkinId.name) ?? 'streamline_project-main';
  }

  @override
  Future<void> setDefaultSkinId(String skinId) async {
    await prefs.setString(SettingsKeys.defaultSkinId.name, skinId);
  }

  @override
  Future<bool> automaticUpdateCheck() async {
    return await prefs.getBool(SettingsKeys.automaticUpdateCheck.name) ?? true;
  }

  @override
  Future<void> setAutomaticUpdateCheck(bool value) async {
    await prefs.setBool(SettingsKeys.automaticUpdateCheck.name, value);
  }

  @override
  Future<DateTime?> lastUpdateCheckTime() async {
    final timestamp = await prefs.getInt(SettingsKeys.lastUpdateCheckTime.name);
    return timestamp != null ? DateTime.fromMillisecondsSinceEpoch(timestamp) : null;
  }

  @override
  Future<void> setLastUpdateCheckTime(DateTime time) async {
    await prefs.setInt(SettingsKeys.lastUpdateCheckTime.name, time.millisecondsSinceEpoch);
  }

  @override
  Future<bool> telemetryConsent() async {
    return await prefs.getBool(SettingsKeys.telemetryConsent.name) ?? false;
  }

  @override
  Future<void> setTelemetryConsent(bool value) async {
    await prefs.setBool(SettingsKeys.telemetryConsent.name, value);
  }

  @override
  Future<bool> telemetryPromptShown() async {
    return await prefs.getBool(SettingsKeys.telemetryPromptShown.name) ?? false;
  }

  @override
  Future<void> setTelemetryPromptShown(bool value) async {
    await prefs.setBool(SettingsKeys.telemetryPromptShown.name, value);
  }

  @override
  Future<bool> telemetryConsentDialogShown() async {
    return await prefs.getBool(SettingsKeys.telemetryConsentDialogShown.name) ?? false;
  }

  @override
  Future<void> setTelemetryConsentDialogShown(bool value) async {
    await prefs.setBool(SettingsKeys.telemetryConsentDialogShown.name, value);
  }

  @override
  Future<String?> skippedVersion() async {
    return await prefs.getString(SettingsKeys.skippedVersion.name);
  }

  @override
  Future<void> setSkippedVersion(String? version) async {
    if (version == null) {
      await prefs.remove(SettingsKeys.skippedVersion.name);
    } else {
      await prefs.setString(SettingsKeys.skippedVersion.name, version);
    }
  }

  @override
  Future<ChargingMode> chargingMode() async {
    return ChargingModeFromString.fromString(
          await prefs.getString(SettingsKeys.chargingMode.name) ??
              ChargingMode.balanced.name,
        ) ??
        ChargingMode.balanced;
  }

  @override
  Future<void> setChargingMode(ChargingMode mode) async {
    await prefs.setString(SettingsKeys.chargingMode.name, mode.name);
  }

  @override
  Future<bool> nightModeEnabled() async {
    return await prefs.getBool(SettingsKeys.nightModeEnabled.name) ?? false;
  }

  @override
  Future<void> setNightModeEnabled(bool value) async {
    await prefs.setBool(SettingsKeys.nightModeEnabled.name, value);
  }

  @override
  Future<int> nightModeSleepTime() async {
    return await prefs.getInt(SettingsKeys.nightModeSleepTime.name) ?? 1320;
  }

  @override
  Future<void> setNightModeSleepTime(int minutes) async {
    await prefs.setInt(SettingsKeys.nightModeSleepTime.name, minutes);
  }

  @override
  Future<int> nightModeMorningTime() async {
    return await prefs.getInt(SettingsKeys.nightModeMorningTime.name) ?? 420;
  }

  @override
  Future<void> setNightModeMorningTime(int minutes) async {
    await prefs.setInt(SettingsKeys.nightModeMorningTime.name, minutes);
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
  preferredScaleId,
  skinExitButtonPosition,
  defaultSkinId,
  automaticUpdateCheck,
  lastUpdateCheckTime,
  telemetryConsent,
  telemetryPromptShown,
  telemetryConsentDialogShown,
  skippedVersion,
  chargingMode,
  nightModeEnabled,
  nightModeSleepTime,
  nightModeMorningTime,
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
