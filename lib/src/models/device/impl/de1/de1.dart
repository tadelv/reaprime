import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.utils.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:logging/logging.dart' as logging;
import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';
import 'package:rxdart/subjects.dart';

part 'de1.subscriptions.dart';
part 'de1.rw.dart';

class De1 implements De1Interface {
  static String advertisingUUID = '0000FFFF-0000-1000-8000-00805F9B34FB';

  final String _deviceId;

  final _ble = FlutterReactiveBle();

  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  final List<StreamSubscription<dynamic>> _notificationSubscriptions = [];

  final _log = logging.Logger("DE1");

  De1({required String deviceId}) : _deviceId = deviceId {
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

  @override
  Stream<MachineSnapshot> get currentSnapshot => _snapshotStream.stream;

  @override
  Future<void> onConnect() async {
    _snapshotStream.add(_currentSnapshot);

    _connectionSubscription = _ble.connectToDevice(id: _deviceId).listen((
      data,
    ) async {
      _log.info("connection update: ${data}");
      if (data.connectionState == DeviceConnectionState.connected) {
        await _onConnected();
      }
    });
  }

  @override
  Future<void> requestState(MachineState newState) async {
    Uint8List data = Uint8List(1);
    data[0] = De1StateEnum.fromMachineState(newState).hexValue;
    await _write(Endpoint.requestedState, data);
  }

  Future<void> _onConnected() async {
    _log.info("Connected, subscribing to services");
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

    _subscribe(Endpoint.stateInfo, _parseStatus);
    _subscribe(Endpoint.shotSample, _parseShot);
    _subscribe(Endpoint.shotSettings, _parseShotSettings);
		_subscribe(Endpoint.waterLevels, _parseWaterLevels);
  }

  @override
  Future<void> setProfile(Profile profile) {
    // TODO: implement setProfile
    throw UnimplementedError();
  }

  @override
  Future<void> setWaterLevelWarning(int newThresholdPercentage) {
    // TODO: implement setWaterLevelWarning
    throw UnimplementedError();
  }

  @override
  Stream<De1ShotSettings> get shotSettings => _shotSettingsController.stream.asBroadcastStream();

  @override
  Future<void> updateShotSettings(De1ShotSettings newSettings) {
    // TODO: implement updateShotSettings
    throw UnimplementedError();
  }

  @override
  Stream<De1WaterLevels> get waterLevels => _waterLevelsController.stream;
}
