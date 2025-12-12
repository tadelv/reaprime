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

// Add this configuration class
class _MMRConfig {
  final MMRItem item;
  final double readScale;
  final double writeScale;
  final int? minValue;
  final int? maxValue;
  
  const _MMRConfig({
    required this.item,
    this.readScale = 1.0,
    this.writeScale = 1.0,
    this.minValue,
    this.maxValue,
  });
}

class UnifiedDe1 implements De1Interface {
  final UnifiedDe1Transport _transport;

  final Logger _log = Logger("DE1");

  // Add MMR configuration map
  static const Map<MMRItem, _MMRConfig> _mmrConfigs = {
    MMRItem.fanThreshold: _MMRConfig(
      item: MMRItem.fanThreshold,
      minValue: 0,
      maxValue: 50,
    ),
    MMRItem.flushFlowRate: _MMRConfig(
      item: MMRItem.flushFlowRate,
      readScale: 0.1,
      writeScale: 10.0,
    ),
    MMRItem.flushTemp: _MMRConfig(
      item: MMRItem.flushTemp,
      readScale: 0.1,
      writeScale: 10.0,
    ),
    MMRItem.flushTimeout: _MMRConfig(
      item: MMRItem.flushTimeout,
      readScale: 0.1,
      writeScale: 10.0,
    ),
    MMRItem.waterHeaterIdleTemp: _MMRConfig(
      item: MMRItem.waterHeaterIdleTemp,
      readScale: 0.1,
      writeScale: 10.0,
    ),
    MMRItem.heaterUp1Flow: _MMRConfig(
      item: MMRItem.heaterUp1Flow,
      readScale: 0.1,
      writeScale: 10.0,
    ),
    MMRItem.heaterUp2Flow: _MMRConfig(
      item: MMRItem.heaterUp2Flow,
      readScale: 0.1,
      writeScale: 10.0,
    ),
    MMRItem.heaterUp2Timeout: _MMRConfig(
      item: MMRItem.heaterUp2Timeout,
      readScale: 0.1,
      writeScale: 10.0,
    ),
    MMRItem.hotWaterFlowRate: _MMRConfig(
      item: MMRItem.hotWaterFlowRate,
      readScale: 0.1,
      writeScale: 10.0,
    ),
    MMRItem.targetSteamFlow: _MMRConfig(
      item: MMRItem.targetSteamFlow,
      readScale: 0.01,
      writeScale: 100.0,
    ),
    MMRItem.tankTemp: _MMRConfig(
      item: MMRItem.tankTemp,
    ),
    MMRItem.allowUSBCharging: _MMRConfig(
      item: MMRItem.allowUSBCharging,
    ),
  };

  UnifiedDe1({required DataTransport transport})
    : _transport = UnifiedDe1Transport(transport: transport);

  // MMR helper methods
  Future<int> _readMMRInt(MMRItem item) async {
    final result = await _mmrRead(item);
    return _unpackMMRInt(result);
  }

  Future<double> _readMMRScaled(MMRItem item) async {
    final config = _mmrConfigs[item]!;
    final rawValue = await _readMMRInt(item);
    return rawValue.toDouble() * config.readScale;
  }

  Future<void> _writeMMRInt(MMRItem item, int value) async {
    final config = _mmrConfigs[item];
    final clampedValue = config?.minValue != null && config?.maxValue != null
        ? min(config!.maxValue!, max(config.minValue!, value))
        : value;
    await _mmrWrite(item, _packMMRInt(clampedValue));
  }

  Future<void> _writeMMRScaled(MMRItem item, double value) async {
    final config = _mmrConfigs[item]!;
    final scaledValue = (value * config.writeScale).toInt();
    await _writeMMRInt(item, scaledValue);
  }

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
    return await _readMMRInt(MMRItem.fanThreshold);
  }

  @override
  Future<double> getFlushFlow() async {
    return await _readMMRScaled(MMRItem.flushFlowRate);
  }

  @override
  Future<double> getFlushTemperature() async {
    return await _readMMRScaled(MMRItem.flushTemp);
  }

  @override
  Future<double> getFlushTimeout() async {
    return await _readMMRScaled(MMRItem.flushTimeout);
  }

  @override
  Future<double> getHeaterIdleTemp() async {
    return await _readMMRScaled(MMRItem.waterHeaterIdleTemp);
  }

  @override
  Future<double> getHeaterPhase1Flow() async {
    return await _readMMRScaled(MMRItem.heaterUp1Flow);
  }

  @override
  Future<double> getHeaterPhase2Flow() async {
    return await _readMMRScaled(MMRItem.heaterUp2Flow);
  }

  @override
  Future<double> getHeaterPhase2Timeout() async {
    return await _readMMRScaled(MMRItem.heaterUp2Timeout);
  }

  @override
  Future<double> getHotWaterFlow() async {
    return await _readMMRScaled(MMRItem.hotWaterFlowRate);
  }

  @override
  Future<double> getSteamFlow() async {
    return await _readMMRScaled(MMRItem.targetSteamFlow);
  }

  @override
  Future<int> getTankTempThreshold() async {
    return await _readMMRInt(MMRItem.tankTemp);
  }

  @override
  Future<bool> getUsbChargerMode() async {
    final result = await _readMMRInt(MMRItem.allowUSBCharging);
    return result == 1;
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
    await _writeMMRInt(MMRItem.fanThreshold, temp);
  }

  @override
  Future<void> setFlushFlow(double newFlow) async {
    await _writeMMRScaled(MMRItem.flushFlowRate, newFlow);
  }

  @override
  Future<void> setFlushTemperature(double newTemp) async {
    await _writeMMRScaled(MMRItem.flushTemp, newTemp);
  }

  @override
  Future<void> setFlushTimeout(double newTimeout) async {
    await _writeMMRScaled(MMRItem.flushTimeout, newTimeout);
  }

  @override
  Future<void> setHeaterIdleTemp(double val) async {
    await _writeMMRScaled(MMRItem.waterHeaterIdleTemp, val);
  }

  @override
  Future<void> setHeaterPhase1Flow(double val) async {
    await _writeMMRScaled(MMRItem.heaterUp1Flow, val);
  }

  @override
  Future<void> setHeaterPhase2Flow(double val) async {
    await _writeMMRScaled(MMRItem.heaterUp2Flow, val);
  }

  @override
  Future<void> setHeaterPhase2Timeout(double val) async {
    await _writeMMRScaled(MMRItem.heaterUp2Timeout, val);
  }

  @override
  Future<void> setHotWaterFlow(double newFlow) async {
    await _writeMMRScaled(MMRItem.hotWaterFlowRate, newFlow);
  }

  @override
  Future<void> setProfile(Profile profile) {
    // TODO: implement setProfile
    throw UnimplementedError();
  }

  @override
  Future<void> setSteamFlow(double newFlow) async {
    await _writeMMRScaled(MMRItem.targetSteamFlow, newFlow);
  }

  @override
  Future<void> setTankTempThreshold(int temp) async {
    await _writeMMRInt(MMRItem.tankTemp, temp);
  }

  @override
  Future<void> setUsbChargerMode(bool t) async {
    await _writeMMRInt(MMRItem.allowUSBCharging, t ? 1 : 0);
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
