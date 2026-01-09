import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/de1_rawmessage.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.utils.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/de1_firmwaremodel.dart';
import 'package:logging/logging.dart' as logging;
import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';
import 'package:rxdart/subjects.dart';

part 'de1.subscriptions.dart';
part 'de1.rw.dart';
part 'de1.profile.dart';
part 'de1.mmr.dart';
part 'de1.raw.dart';
part 'de1.firmware.dart';

class De1 implements De1Interface {
  static String advertisingUUID = BleUuidParser.string('ffff');

  final String _deviceId;

  final BleDevice _device;
  //
  late BleService _service;

  final StreamController<De1RawMessage> _rawOutStream =
      StreamController.broadcast();

  @override
  Stream<De1RawMessage> get rawOutStream => _rawOutStream.stream;

  final StreamController<De1RawMessage> _rawInStream = StreamController();

  final _log = logging.Logger("DE1");

  De1({required String deviceId})
    : _deviceId = deviceId,
      _device = BleDevice(deviceId: deviceId, name: "De1 $deviceId") {
    _snapshotStream.add(_currentSnapshot);
  }

  De1.withDevice({required BleDevice device})
    : _deviceId = device.deviceId,
      _device = device {
    _snapshotStream.add(_currentSnapshot);
  }

  factory De1.fromId(String id) {
    return De1(deviceId: id);
  }

  @override
  String get deviceId => _deviceId;

  @override
  String get name => "DE1";

  @override
  DeviceType get type => DeviceType.machine;

  @override
    // TODO: implement machineInfo
    MachineInfo get machineInfo => throw UnimplementedError();

  MachineSnapshot _currentSnapshot = MachineSnapshot(
    flow: 0,
    state: MachineStateSnapshot(
      state: MachineState.booting,
      substate: MachineSubstate.idle,
    ),
    steamTemperature: 0,
    profileFrame: 0,
    targetFlow: 0,
    targetPressure: 0,
    targetMixTemperature: 0,
    targetGroupTemperature: 0,
    timestamp: DateTime.now(),
    groupTemperature: 0,
    mixTemperature: 0,
    pressure: 0,
  );

  final StreamController<MachineSnapshot> _snapshotStream =
      StreamController<MachineSnapshot>.broadcast();
  final BehaviorSubject<De1ShotSettings> _shotSettingsController =
      BehaviorSubject();
  final BehaviorSubject<De1WaterLevels> _waterLevelsController =
      BehaviorSubject();

  final StreamController<List<int>> _mmrController =
      StreamController.broadcast();

  final BehaviorSubject<bool> _onReadyStream = BehaviorSubject.seeded(false);

  final List<StreamSubscription<Uint8List>> _subscriptions = [];

  @override
  Stream<bool> get ready => _onReadyStream.stream;

  @override
  Stream<MachineSnapshot> get currentSnapshot => _snapshotStream.stream;

  final StreamController<ConnectionState> _connectionStateController =
      BehaviorSubject.seeded(ConnectionState.connecting);

  @override
  Stream<ConnectionState> get connectionState =>
      _connectionStateController.stream;

  @override
  Future<void> onConnect() async {
    _snapshotStream.add(_currentSnapshot);

    StreamSubscription<bool>? subscription;
    subscription = _device.connectionStream.listen((bool state) async {
      switch (state) {
        case true:
          if (await _connectionStateController.stream.first ==
              ConnectionState.connected) {
            _log.info("Already connected, not signalling again");
            break;
          }
          _log.fine("state changed to connected");
          _connectionStateController.add(ConnectionState.connected);
          var services = await _device.discoverServices();
          _service = services.firstWhere(
            (s) => s.uuid == BleUuidParser.string(de1ServiceUUID),
          );
          await _onConnected();
          break;
        case false:
          if (await _connectionStateController.stream.first ==
              ConnectionState.connected) {
            _connectionStateController.add(ConnectionState.disconnected);
          }
          subscription?.cancel();
          for (var sub in _subscriptions) {
            sub.cancel();
          }
          await _device.disconnect();
          break;
      }
    });
    _log.info("connecting ...");
    await _device.connect();
  }

  @override
  disconnect() async {
    await _device.disconnect();
  }

  @override
  Future<void> requestState(MachineState newState) async {
    Uint8List data = Uint8List(1);
    data[0] = De1StateEnum.fromMachineState(newState).hexValue;
    await _write(Endpoint.requestedState, data);
  }

  Future<void> _onConnected() async {
    _log.info("Connected, subscribing to services");
    initRawStream();
    _snapshotStream.add(
      MachineSnapshot(
        flow: 0,
        state: MachineStateSnapshot(
          state: MachineState.sleeping,
          substate: MachineSubstate.idle,
        ),
        steamTemperature: 0,
        profileFrame: 0,
        targetFlow: 0,
        targetPressure: 0,
        targetMixTemperature: 0,
        targetGroupTemperature: 0,
        timestamp: DateTime.now(),
        groupTemperature: 0,
        mixTemperature: 0,
        pressure: 0,
      ),
    );

    _parseStatus(await _read(Endpoint.stateInfo));
    _parseShotSettings(await _read(Endpoint.shotSettings));
    _parseWaterLevels(await _read(Endpoint.waterLevels));
    _parseVersion(await _read(Endpoint.versions));

    await _subscribe(Endpoint.stateInfo, _parseStatus);
    await _subscribe(Endpoint.shotSample, _parseShot);
    await _subscribe(Endpoint.shotSettings, _parseShotSettings);
    await _subscribe(Endpoint.waterLevels, _parseWaterLevels);
    await _subscribe(Endpoint.readFromMMR, _mmrNotification);

    _onReadyStream.add(true);
  }

  @override
  Future<void> setProfile(Profile profile) async {
    await _sendProfile(profile);
  }

  @override
  Future<void> setRefillLevel(int newThresholdPercentage) {
    ByteData value = ByteData(4);
    try {
      // 00 00 0c 00
      // 00 00 00 07
      value.setInt16(0, 0, Endian.big);
      value.setInt16(2, newThresholdPercentage * 256, Endian.big);

      return _writeWithResponse(
        Endpoint.waterLevels,
        value.buffer.asUint8List(),
      );
    } catch (e) {
      _log.severe("failed to set water warning", e);
      rethrow;
    }
  }

  @override
  Stream<De1ShotSettings> get shotSettings =>
      _shotSettingsController.stream.asBroadcastStream();

  @override
  Future<void> updateShotSettings(De1ShotSettings newSettings) async {
    Uint8List data = Uint8List(9);

    int index = 0;
    data[index] = newSettings.steamSetting;
    index++;
    data[index] = newSettings.targetSteamTemp;
    index++;
    data[index] = newSettings.targetSteamDuration;
    index++;
    data[index] = newSettings.targetHotWaterTemp;
    index++;
    data[index] = newSettings.targetHotWaterVolume;
    index++;
    data[index] = newSettings.targetHotWaterDuration;
    index++;
    data[index] = newSettings.targetShotVolume;
    index++;

    data[index] = newSettings.groupTemp.toInt();
    index++;
    data[index] =
        ((newSettings.groupTemp - newSettings.groupTemp.floor()) * 256.0)
            .toInt();
    index++;

    await _writeWithResponse(Endpoint.shotSettings, data);
    await _parseShotSettings(await _read(Endpoint.shotSettings));
  }

  @override
  Stream<De1WaterLevels> get waterLevels => _waterLevelsController.stream;

  @override
  Future<bool> getUsbChargerMode() async {
    var result = await _mmrRead(MMRItem.allowUSBCharging);
    return _unpackMMRInt(result) == 1;
  }

  @override
  Future<void> setUsbChargerMode(bool t) async {
    await _mmrWrite(MMRItem.allowUSBCharging, _packMMRInt(t ? 1 : 0));
  }

  @override
  Future<int> getFanThreshhold() async {
    var result = await _mmrRead(MMRItem.fanThreshold);
    return _unpackMMRInt(result);
  }

  @override
  Future<void> setFanThreshhold(int temp) async {
    await _mmrWrite(MMRItem.fanThreshold, _packMMRInt(min(50, temp)));
  }

  @override
  Future<double> getSteamFlow() async {
    var result = await _mmrRead(MMRItem.targetSteamFlow);
    return _unpackMMRInt(result).toDouble() / 100;
  }

  @override
  Future<void> setSteamFlow(double newFlow) async {
    var value = _packMMRInt((newFlow * 100).toInt());
    await _mmrWrite(MMRItem.targetSteamFlow, value);
  }

  @override
  Future<double> getHotWaterFlow() async {
    var result = await _mmrRead(MMRItem.hotWaterFlowRate);
    return _unpackMMRInt(result).toDouble() / 10;
  }

  @override
  Future<void> setHotWaterFlow(double newFlow) async {
    var value = _packMMRInt((newFlow * 10).toInt());
    await _mmrWrite(MMRItem.hotWaterFlowRate, value);
  }

  @override
  Future<double> getFlushFlow() async {
    var result = await _mmrRead(MMRItem.flushFlowRate);
    return _unpackMMRInt(result).toDouble() / 10;
  }

  @override
  Future<void> setFlushFlow(double newFlow) async {
    var value = _packMMRInt((newFlow * 10).toInt());
    await _mmrWrite(MMRItem.flushFlowRate, value);
  }

  @override
  Future<double> getFlushTimeout() async {
    var result = await _mmrRead(MMRItem.flushTimeout);
    return _unpackMMRInt(result).toDouble() / 10;
  }

  @override
  Future<void> setFlushTimeout(double newTimeout) async {
    var value = _packMMRInt((newTimeout * 10).toInt());
    await _mmrWrite(MMRItem.flushTimeout, value);
  }

  @override
  Future<double> getFlushTemperature() async {
    var result = await _mmrRead(MMRItem.flushTemp);
    return _unpackMMRInt(result).toDouble() / 10;
  }

  @override
  Future<void> setFlushTemperature(double newTemp) async {
    var value = _packMMRInt((newTemp * 10).toInt());
    await _mmrWrite(MMRItem.flushTemp, value);
  }

  @override
  Future<int> getTankTempThreshold() async {
    var result = await _mmrRead(MMRItem.tankTemp);
    return _unpackMMRInt(result);
  }

  @override
  Future<void> setTankTempThreshold(int temp) async {
    var value = _packMMRInt(temp);
    await _mmrWrite(MMRItem.tankTemp, value);
  }

  @override
  Future<double> getHeaterIdleTemp() async {
    var result = await _mmrRead(MMRItem.waterHeaterIdleTemp);
    return _unpackMMRInt(result).toDouble() / 10;
  }

  @override
  Future<double> getHeaterPhase1Flow() async {
    var result = await _mmrRead(MMRItem.heaterUp1Flow);
    return _unpackMMRInt(result).toDouble() / 10;
  }

  @override
  Future<double> getHeaterPhase2Flow() async {
    var result = await _mmrRead(MMRItem.heaterUp2Flow);
    return _unpackMMRInt(result).toDouble() / 10;
  }

  @override
  Future<double> getHeaterPhase2Timeout() async {
    var result = await _mmrRead(MMRItem.heaterUp2Timeout);
    return _unpackMMRInt(result).toDouble() / 10;
  }

  @override
  Future<void> setHeaterIdleTemp(double val) async {
    var value = _packMMRInt((val * 10).toInt());
    await _mmrWrite(MMRItem.waterHeaterIdleTemp, value);
  }

  @override
  Future<void> setHeaterPhase1Flow(double val) async {
    var value = _packMMRInt((val * 10).toInt());
    await _mmrWrite(MMRItem.heaterUp1Flow, value);
  }

  @override
  Future<void> setHeaterPhase2Flow(double val) async {
    var value = _packMMRInt((val * 10).toInt());
    await _mmrWrite(MMRItem.heaterUp2Flow, value);
  }

  @override
  Future<void> setHeaterPhase2Timeout(double val) async {
    var value = _packMMRInt((val * 10).toInt());
    await _mmrWrite(MMRItem.heaterUp2Timeout, value);
  }

  @override
  sendRawMessage(De1RawMessage message) {
    _rawInStream.add(message);
  }

  @override
  Future<void> updateFirmware(
    Uint8List fwImage, {
    required void Function(double) onProgress,
  }) async {
    await _updateFirmware(fwImage, onProgress);
  }
}
