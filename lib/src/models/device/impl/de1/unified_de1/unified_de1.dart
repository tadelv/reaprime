import 'dart:typed_data';

import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/de1_rawmessage.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1_transport.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/transport/data_transport.dart';

class UnifiedDe1 implements De1Interface {
  final UnifiedDe1Transport _transport;

  UnifiedDe1({required DataTransport transport})
    : _transport = UnifiedDe1Transport(transport: transport);

  @override
  // TODO: implement connectionState
  Stream<ConnectionState> get connectionState => throw UnimplementedError();

  @override
  // TODO: implement currentSnapshot
  Stream<MachineSnapshot> get currentSnapshot => throw UnimplementedError();

  @override
  // TODO: implement deviceId
  String get deviceId => throw UnimplementedError();

  @override
  disconnect() {
    // TODO: implement disconnect
    throw UnimplementedError();
  }

  @override
  Future<int> getFanThreshhold() {
    // TODO: implement getFanThreshhold
    throw UnimplementedError();
  }

  @override
  Future<double> getFlushFlow() {
    // TODO: implement getFlushFlow
    throw UnimplementedError();
  }

  @override
  Future<double> getFlushTemperature() {
    // TODO: implement getFlushTemperature
    throw UnimplementedError();
  }

  @override
  Future<double> getFlushTimeout() {
    // TODO: implement getFlushTimeout
    throw UnimplementedError();
  }

  @override
  Future<double> getHeaterIdleTemp() {
    // TODO: implement getHeaterIdleTemp
    throw UnimplementedError();
  }

  @override
  Future<double> getHeaterPhase1Flow() {
    // TODO: implement getHeaterPhase1Flow
    throw UnimplementedError();
  }

  @override
  Future<double> getHeaterPhase2Flow() {
    // TODO: implement getHeaterPhase2Flow
    throw UnimplementedError();
  }

  @override
  Future<double> getHeaterPhase2Timeout() {
    // TODO: implement getHeaterPhase2Timeout
    throw UnimplementedError();
  }

  @override
  Future<double> getHotWaterFlow() {
    // TODO: implement getHotWaterFlow
    throw UnimplementedError();
  }

  @override
  Future<double> getSteamFlow() {
    // TODO: implement getSteamFlow
    throw UnimplementedError();
  }

  @override
  Future<int> getTankTempThreshold() {
    // TODO: implement getTankTempThreshold
    throw UnimplementedError();
  }

  @override
  Future<bool> getUsbChargerMode() {
    // TODO: implement getUsbChargerMode
    throw UnimplementedError();
  }

  @override
  // TODO: implement name
  String get name => throw UnimplementedError();

  @override
  Future<void> onConnect() {
    // TODO: implement onConnect
    throw UnimplementedError();
  }

  @override
  // TODO: implement rawOutStream
  Stream<De1RawMessage> get rawOutStream => throw UnimplementedError();

  @override
  // TODO: implement ready
  Stream<bool> get ready => throw UnimplementedError();

  @override
  Future<void> requestState(MachineState newState) {
    // TODO: implement requestState
    throw UnimplementedError();
  }

  @override
  void sendRawMessage(De1RawMessage message) {
    // TODO: implement sendRawMessage
  }

  @override
  Future<void> setFanThreshhold(int temp) {
    // TODO: implement setFanThreshhold
    throw UnimplementedError();
  }

  @override
  Future<void> setFlushFlow(double newFlow) {
    // TODO: implement setFlushFlow
    throw UnimplementedError();
  }

  @override
  Future<void> setFlushTemperature(double newTemp) {
    // TODO: implement setFlushTemperature
    throw UnimplementedError();
  }

  @override
  Future<void> setFlushTimeout(double newTimeout) {
    // TODO: implement setFlushTimeout
    throw UnimplementedError();
  }

  @override
  Future<void> setHeaterIdleTemp(double val) {
    // TODO: implement setHeaterIdleTemp
    throw UnimplementedError();
  }

  @override
  Future<void> setHeaterPhase1Flow(double val) {
    // TODO: implement setHeaterPhase1Flow
    throw UnimplementedError();
  }

  @override
  Future<void> setHeaterPhase2Flow(double val) {
    // TODO: implement setHeaterPhase2Flow
    throw UnimplementedError();
  }

  @override
  Future<void> setHeaterPhase2Timeout(double val) {
    // TODO: implement setHeaterPhase2Timeout
    throw UnimplementedError();
  }

  @override
  Future<void> setHotWaterFlow(double newFlow) {
    // TODO: implement setHotWaterFlow
    throw UnimplementedError();
  }

  @override
  Future<void> setProfile(Profile profile) {
    // TODO: implement setProfile
    throw UnimplementedError();
  }

  @override
  Future<void> setSteamFlow(double newFlow) {
    // TODO: implement setSteamFlow
    throw UnimplementedError();
  }

  @override
  Future<void> setTankTempThreshold(int temp) {
    // TODO: implement setTankTempThreshold
    throw UnimplementedError();
  }

  @override
  Future<void> setUsbChargerMode(bool t) {
    // TODO: implement setUsbChargerMode
    throw UnimplementedError();
  }

  @override
  Future<void> setWaterLevelWarning(int newThresholdPercentage) {
    // TODO: implement setWaterLevelWarning
    throw UnimplementedError();
  }

  @override
  // TODO: implement shotSettings
  Stream<De1ShotSettings> get shotSettings => throw UnimplementedError();

  @override
  // TODO: implement type
  DeviceType get type => throw UnimplementedError();

  @override
  Future<void> updateFirmware(
    Uint8List fwImage, {
    required void Function(double progress) onProgress,
  }) {
    // TODO: implement updateFirmware
    throw UnimplementedError();
  }

  @override
  Future<void> updateShotSettings(De1ShotSettings newSettings) {
    // TODO: implement updateShotSettings
    throw UnimplementedError();
  }

  @override
  // TODO: implement waterLevels
  Stream<De1WaterLevels> get waterLevels => throw UnimplementedError();
}
