import 'dart:math';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/de1_rawmessage.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.utils.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1_transport.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/transport/data_transport.dart';
import 'package:rxdart/transformers.dart';

part 'unified_de1.mmr.dart';
part 'unified_de1.parsing.dart';

class UnifiedDe1 implements De1Interface {
  final UnifiedDe1Transport _transport;

  final Logger _log = Logger("DE1");

  UnifiedDe1({required DataTransport transport})
    : _transport = UnifiedDe1Transport(transport: transport);

  @override
  Stream<ConnectionState> get connectionState => _transport.connectionState.map(
    (e) => e ? ConnectionState.connected : ConnectionState.disconnected,
  );

  @override
  Stream<MachineSnapshot> get currentSnapshot =>
      _transport.state.withLatestFrom(_transport.shotSample, (st, snp) {
        return _parseStateAndShotSample(st, snp);
      });

  @override
  String get deviceId => _transport.id;

  @override
  disconnect() {
    // TODO: Future.sync?
    _transport.disconnect();
  }

  @override
  Future<int> getFanThreshhold() async {
    return _unpackMMRInt( await _mmrRead(MMRItem.fanThreshold));
  }

  @override
  Future<double> getFlushFlow() async {
    final result = await _mmrRead(MMRItem.flushFlowRate);
    return _unpackMMRInt(result).toDouble() / 10;
  }

  @override
  Future<double> getFlushTemperature() async {
    final result = await _mmrRead(MMRItem.flushTemp);
    return _unpackMMRInt(result).toDouble() / 10;
  }

  @override
  Future<double> getFlushTimeout() async {
    final result = await _mmrRead(MMRItem.flushTimeout);
    return _unpackMMRInt(result).toDouble() / 10;
  }

  @override
  Future<double> getHeaterIdleTemp() async {
    final result = await _mmrRead(MMRItem.waterHeaterIdleTemp);
    return _unpackMMRInt(result).toDouble() / 10;
  }

  @override
  Future<double> getHeaterPhase1Flow() async {
    final result = await _mmrRead(MMRItem.heaterUp1Flow);
    return _unpackMMRInt(result).toDouble() / 10;
  }

  @override
  Future<double> getHeaterPhase2Flow() async {
    final result = await _mmrRead(MMRItem.heaterUp2Flow);
    return _unpackMMRInt(result).toDouble() / 10;
  }

  @override
  Future<double> getHeaterPhase2Timeout() async {
    final result = await _mmrRead(MMRItem.heaterUp2Timeout);
    return _unpackMMRInt(result).toDouble() / 10;
  }

  @override
  Future<double> getHotWaterFlow() async {
    final result = await _mmrRead(MMRItem.hotWaterFlowRate);
    return _unpackMMRInt(result).toDouble() / 10;
  }

  @override
  Future<double> getSteamFlow() async {
    final result = await _mmrRead(MMRItem.targetSteamFlow);
    return _unpackMMRInt(result).toDouble() / 100;
  }

  @override
  Future<int> getTankTempThreshold() async {
    final result = await _mmrRead(MMRItem.tankTemp);
    return _unpackMMRInt(result);
  }

  @override
  Future<bool> getUsbChargerMode() async {
    final result = await _mmrRead(MMRItem.allowUSBCharging);
    return _unpackMMRInt(result) == 1;
  }

  @override
  String get name => "DE1";

  @override
  Future<void> onConnect() async {
    await _transport.connect();
  }

  @override
  // TODO: implement rawOutStream
  Stream<De1RawMessage> get rawOutStream => Stream.empty();

  @override
  Stream<bool> get ready => _transport.connectionState.asBroadcastStream();

  @override
  Future<void> requestState(MachineState newState) async {
    Uint8List data = Uint8List(1);
    data[0] = De1StateEnum.fromMachineState(newState).hexValue;
    await _transport.write(Endpoint.requestedState, data);
  }

  @override
  void sendRawMessage(De1RawMessage message) {
    // TODO: implement sendRawMessage
  }

  @override
  Future<void> setFanThreshhold(int temp) async {
    await _mmrWrite(MMRItem.fanThreshold, _packMMRInt(min(50, temp)));
  }

  @override
  Future<void> setFlushFlow(double newFlow) async {
    final value = _packMMRInt((newFlow * 10).toInt());
    await _mmrWrite(MMRItem.flushFlowRate, value);
  }

  @override
  Future<void> setFlushTemperature(double newTemp) async {
    final value = _packMMRInt((newTemp * 10).toInt());
    await _mmrWrite(MMRItem.flushTemp, value);
  }

  @override
  Future<void> setFlushTimeout(double newTimeout) async {
    final value = _packMMRInt((newTimeout * 10).toInt());
    await _mmrWrite(MMRItem.flushTimeout, value);
  }

  @override
  Future<void> setHeaterIdleTemp(double val) async {
    final value = _packMMRInt((val * 10).toInt());
    await _mmrWrite(MMRItem.waterHeaterIdleTemp, value);
  }

  @override
  Future<void> setHeaterPhase1Flow(double val) async {
    final value = _packMMRInt((val * 10).toInt());
    await _mmrWrite(MMRItem.heaterUp1Flow, value);
  }

  @override
  Future<void> setHeaterPhase2Flow(double val) async {
    final value = _packMMRInt((val * 10).toInt());
    await _mmrWrite(MMRItem.heaterUp2Flow, value);
  }

  @override
  Future<void> setHeaterPhase2Timeout(double val) async {
    final value = _packMMRInt((val * 10).toInt());
    await _mmrWrite(MMRItem.heaterUp2Timeout, value);
  }

  @override
  Future<void> setHotWaterFlow(double newFlow) async {
    final value = _packMMRInt((newFlow * 10).toInt());
    await _mmrWrite(MMRItem.hotWaterFlowRate, value);
  }

  @override
  Future<void> setProfile(Profile profile) {
    // TODO: implement setProfile
    throw UnimplementedError();
  }

  @override
  Future<void> setSteamFlow(double newFlow) async {
    final value = _packMMRInt((newFlow * 100).toInt());
    await _mmrWrite(MMRItem.targetSteamFlow, value);
  }

  @override
  Future<void> setTankTempThreshold(int temp) async {
    final value = _packMMRInt(temp);
    await _mmrWrite(MMRItem.tankTemp, value);
  }

  @override
  Future<void> setUsbChargerMode(bool t) async {
    await _mmrWrite(MMRItem.allowUSBCharging, _packMMRInt(t ? 1 : 0));
  }

  @override
  Future<void> setWaterLevelWarning(int newThresholdPercentage) {
    // TODO: implement setWaterLevelWarning
    throw UnimplementedError();
  }

  @override
  // TODO: implement shotSettings
  Stream<De1ShotSettings> get shotSettings => Stream.empty();

  @override
  DeviceType get type => DeviceType.machine;

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
