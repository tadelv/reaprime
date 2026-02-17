import 'package:flutter/foundation.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/de1_rawmessage.dart';
import 'package:reaprime/src/models/data/utils.dart';

abstract class De1Interface extends Machine {
  Stream<bool> get ready;

  Stream<De1RawMessage> get rawOutStream;
  void sendRawMessage(De1RawMessage message);

  Stream<De1ShotSettings> get shotSettings;
  Future<void> updateShotSettings(De1ShotSettings newSettings);

  Stream<De1WaterLevels> get waterLevels;
  Future<void> setRefillLevel(int newRefillLevel);

  Future<void> setProfile(Profile profile);
  // TODO: also heater timeouts and others? (check mmr for options)

  //// Timeouts and Thresholds
  Future<void> setFanThreshhold(int temp);
  Future<int> getFanThreshhold();
  Future<int> getTankTempThreshold();
  Future<void> setTankTempThreshold(int temp);
  //
  //// Flow Control
  Future<void> setSteamFlow(double newFlow);
  Future<double> getSteamFlow();
  Future<void> setHotWaterFlow(double newFlow);
  Future<double> getHotWaterFlow();

// Flush/Rinse control
  Future<void> setFlushFlow(double newFlow);
  Future<double> getFlushFlow();
  Future<void> setFlushTimeout(double newTimeout);
  Future<double> getFlushTimeout();
  Future<double> getFlushTemperature();
  Future<void> setFlushTemperature(double newTemp);

  // Calibration
  Future<double> getFlowEstimation();
  Future<void> setFlowEstimation(double multiplier);

  //// USB and Charger Settings
  Future<bool> getUsbChargerMode();
  Future<void> setUsbChargerMode(bool t);
  
  //// Steam Purge
  Future<void> setSteamPurgeMode(int mode);
  Future<int> getSteamPurgeMode();
  
  //// Device Info
  //Future<int> getFirmwareBuild();
  //Future<int> getSerialNumber();
  //Future<int> getGhcInfo();
  //Future<int> getGhcMode();

  // Heater prefs
  Future<double> getHeaterPhase1Flow();
  Future<void> setHeaterPhase1Flow(double val);
  Future<double> getHeaterPhase2Flow();
  Future<void> setHeaterPhase2Flow(double val);
  Future<double> getHeaterPhase2Timeout();
  Future<void> setHeaterPhase2Timeout(double val);
  Future<double> getHeaterIdleTemp();
  Future<void> setHeaterIdleTemp(double val);

  // Firmware upgrade
  // TODO: should it be something different than Uint8List?
  Future<void> updateFirmware(Uint8List fwImage,
      {required void Function(double progress) onProgress});

  /// Cancel an in-progress firmware upload. Sets the machine to sleeping.
  /// No-op if no upload is in progress.
  Future<void> cancelFirmwareUpload() async {}
}

// This doesn't change anything
enum De1SteamSettingsValues {
  none(0),
  fastStart(0x80),
  slowStart(0x00),
  highPower(0x40),
  lowPower(0x00);

  final int hex;
  const De1SteamSettingsValues(this.hex);
}

final class De1ShotSettings {
  final int steamSetting;
  final int targetSteamTemp;
  final int targetSteamDuration;
  final int targetHotWaterTemp;
  final int targetHotWaterVolume;
  final int targetHotWaterDuration;
  final int targetShotVolume;
  final double groupTemp;

  De1ShotSettings({
    required this.steamSetting,
    required this.targetSteamTemp,
    required this.targetSteamDuration,
    required this.targetHotWaterTemp,
    required this.targetHotWaterVolume,
    required this.targetHotWaterDuration,
    required this.targetShotVolume,
    required this.groupTemp,
  });

  Map<String, dynamic> toJson() {
    return {
      'steamSetting': steamSetting,
      'targetSteamTemp': targetSteamTemp,
      'targetSteamDuration': targetSteamDuration,
      'targetHotWaterTemp': targetHotWaterTemp,
      'targetHotWaterVolume': targetHotWaterVolume,
      'targetHotWaterDuration': targetHotWaterDuration,
      'targetShotVolume': targetShotVolume,
      'groupTemp': groupTemp,
    };
  }

  factory De1ShotSettings.fromJson(Map<String, dynamic> json) {
    return De1ShotSettings(
      steamSetting: parseInt(json['steamSetting']),
      targetSteamTemp: parseInt(json['targetSteamTemp']),
      targetSteamDuration: parseInt(json['targetSteamDuration']),
      targetHotWaterTemp: parseInt(json['targetHotWaterTemp']),
      targetHotWaterVolume: parseInt(json['targetHotWaterVolume']),
      targetHotWaterDuration: parseInt(json['targetHotWaterDuration']),
      targetShotVolume: parseInt(json['targetShotVolume']),
      groupTemp: parseDouble(json['groupTemp']),
    );
  }

  De1ShotSettings copyWith({
    int? steamSetting,
    int? targetSteamTemp,
    int? targetSteamDuration,
    int? targetHotWaterTemp,
    int? targetHotWaterVolume,
    int? targetHotWaterDuration,
    int? targetShotVolume,
    double? groupTemp,
  }) {
    return De1ShotSettings(
      steamSetting: steamSetting ?? this.steamSetting,
      targetSteamTemp: targetSteamTemp ?? this.targetSteamTemp,
      targetSteamDuration: targetSteamDuration ?? this.targetSteamDuration,
      targetHotWaterTemp: targetHotWaterTemp ?? this.targetHotWaterTemp,
      targetHotWaterVolume: targetHotWaterVolume ?? this.targetHotWaterVolume,
      targetHotWaterDuration:
          targetHotWaterDuration ?? this.targetHotWaterDuration,
      targetShotVolume: targetShotVolume ?? this.targetShotVolume,
      groupTemp: groupTemp ?? this.groupTemp,
    );
  }
}

final class De1WaterLevels {
  final int currentLevel;
  final int refillLevel;

  De1WaterLevels({
    required this.currentLevel,
    required this.refillLevel,
  });

  Map<String, dynamic> toJson() {
    return {
      'currentLevel': currentLevel,
      'refillLevel': refillLevel,
    };
  }
}


