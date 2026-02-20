import 'package:flutter/material.dart';
import 'package:reaprime/src/settings/gateway_mode.dart';
import 'package:reaprime/src/settings/scale_power_mode.dart';
import 'package:reaprime/src/settings/settings_service.dart';

/// In-memory SettingsService for widget tests.
/// Returns sensible defaults without touching SharedPreferences.
class MockSettingsService extends SettingsService {
  ThemeMode _themeMode = ThemeMode.system;
  GatewayMode _gatewayMode = GatewayMode.disabled;
  String _logLevel = 'INFO';
  bool _recordShotPreheat = false;
  bool _simulateDevices = false;
  double _weightFlowMultiplier = 1.0;
  double _volumeFlowMultiplier = 0.3;
  ScalePowerMode _scalePowerMode = ScalePowerMode.disabled;
  String? _preferredMachineId;
  String? _preferredScaleId;
  SkinExitButtonPosition _skinExitButtonPosition = SkinExitButtonPosition.topLeft;
  String _defaultSkinId = 'streamline_project-main';
  bool _automaticUpdateCheck = true;
  DateTime? _lastUpdateCheckTime;
  bool _telemetryConsent = false;
  bool _telemetryPromptShown = true; // skip prompt in tests
  bool _telemetryConsentDialogShown = true; // skip dialog in tests
  String? _skippedVersion;

  @override
  Future<ThemeMode> themeMode() async => _themeMode;
  @override
  Future<void> updateThemeMode(ThemeMode theme) async => _themeMode = theme;
  @override
  Future<GatewayMode> gatewayMode() async => _gatewayMode;
  @override
  Future<void> updateGatewayMode(GatewayMode mode) async => _gatewayMode = mode;
  @override
  Future<String> logLevel() async => _logLevel;
  @override
  Future<void> updateLogLevel(String newLogLevel) async => _logLevel = newLogLevel;
  @override
  Future<bool> recordShotPreheat() async => _recordShotPreheat;
  @override
  Future<void> setRecordShotPreheat(bool value) async => _recordShotPreheat = value;
  @override
  Future<bool> simulateDevices() async => _simulateDevices;
  @override
  Future<void> setSimulatedDevices(bool value) async => _simulateDevices = value;
  @override
  Future<double> weightFlowMultiplier() async => _weightFlowMultiplier;
  @override
  Future<void> setWeightFlowMultiplier(double value) async => _weightFlowMultiplier = value;
  @override
  Future<double> volumeFlowMultiplier() async => _volumeFlowMultiplier;
  @override
  Future<void> setVolumeFlowMultiplier(double value) async => _volumeFlowMultiplier = value;
  @override
  Future<ScalePowerMode> scalePowerMode() async => _scalePowerMode;
  @override
  Future<void> setScalePowerMode(ScalePowerMode mode) async => _scalePowerMode = mode;
  @override
  Future<String?> preferredMachineId() async => _preferredMachineId;
  @override
  Future<void> setPreferredMachineId(String? machineId) async => _preferredMachineId = machineId;
  @override
  Future<String?> preferredScaleId() async => _preferredScaleId;
  @override
  Future<void> setPreferredScaleId(String? scaleId) async => _preferredScaleId = scaleId;
  @override
  Future<SkinExitButtonPosition> skinExitButtonPosition() async => _skinExitButtonPosition;
  @override
  Future<void> setSkinExitButtonPosition(SkinExitButtonPosition position) async =>
      _skinExitButtonPosition = position;
  @override
  Future<String> defaultSkinId() async => _defaultSkinId;
  @override
  Future<void> setDefaultSkinId(String skinId) async => _defaultSkinId = skinId;
  @override
  Future<bool> automaticUpdateCheck() async => _automaticUpdateCheck;
  @override
  Future<void> setAutomaticUpdateCheck(bool value) async => _automaticUpdateCheck = value;
  @override
  Future<DateTime?> lastUpdateCheckTime() async => _lastUpdateCheckTime;
  @override
  Future<void> setLastUpdateCheckTime(DateTime time) async => _lastUpdateCheckTime = time;
  @override
  Future<bool> telemetryConsent() async => _telemetryConsent;
  @override
  Future<void> setTelemetryConsent(bool value) async => _telemetryConsent = value;
  @override
  Future<bool> telemetryPromptShown() async => _telemetryPromptShown;
  @override
  Future<void> setTelemetryPromptShown(bool value) async => _telemetryPromptShown = value;
  @override
  Future<bool> telemetryConsentDialogShown() async => _telemetryConsentDialogShown;
  @override
  Future<void> setTelemetryConsentDialogShown(bool value) async =>
      _telemetryConsentDialogShown = value;
  @override
  Future<String?> skippedVersion() async => _skippedVersion;
  @override
  Future<void> setSkippedVersion(String? version) async => _skippedVersion = version;
}
