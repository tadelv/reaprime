import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/machine.dart';

class MockDe1 with ChangeNotifier implements De1Interface {
  MockDe1();

  StreamController<MachineSnapshot> _snapshotStream =
      StreamController.broadcast();

  Timer? _stateTimer;

  MachineSnapshot _lastSnapshot = MachineSnapshot(
    flow: 0,
    state: MachineStateSnapshot(
      state: MachineState.idle,
      substate: MachineSubstate.pouring,
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

  MachineState _currentState = MachineState.booting;

  @override
  // TODO: implement currentSnapshot
  Stream<MachineSnapshot> get currentSnapshot => _snapshotStream.stream;

  @override
  // TODO: implement deviceId
  String get deviceId => "MockDe1";

  @override
  // TODO: implement name
  String get name => "MockDe1";

  @override
  Future<void> requestState(MachineState newState) async {
    _currentState = newState;
  }

  @override
  Future<void> onConnect() async {
    _currentState = MachineState.idle;
    _simulateState();
  }

  @override
  DeviceType get type => DeviceType.machine;

  _simulateState() {
    _snapshotStream.add(_lastSnapshot);

    _stateTimer = Timer.periodic(Duration(milliseconds: 500), (t) {
      var newSnapshot = MachineSnapshot(
        timestamp: DateTime.now(),
        state: MachineStateSnapshot(
          state: _currentState,
          substate: MachineSubstate.idle,
        ),
        flow: 0,
        pressure: 0,
        targetFlow: 0,
        targetPressure: 0,
        mixTemperature: _lastSnapshot.mixTemperature + 0.1,
        groupTemperature: _lastSnapshot.mixTemperature + 0.1,
        targetMixTemperature: 100,
        targetGroupTemperature: 90,
        profileFrame: 0,
        steamTemperature: _lastSnapshot.steamTemperature + 0.1,
      );

      _snapshotStream.add(newSnapshot);
      _lastSnapshot = newSnapshot;
    });
  }

  bool _chargerOn = false;

  @override
  Future<bool> getUsbChargerMode() async {
    return _chargerOn;
  }

  @override
  Future<void> setUsbChargerMode(bool t) async {
    _chargerOn = t;
  }

  @override
  Future<void> setProfile(Profile profile) async {}

  @override
  Future<void> setWaterLevelWarning(int newThresholdPercentage) async {}

  final StreamController<De1ShotSettings> _shotSettingsController =
      StreamController.broadcast();

  @override
  Stream<De1ShotSettings> get shotSettings => _shotSettingsController.stream;

  @override
  Future<void> updateShotSettings(De1ShotSettings newSettings) async {
    _shotSettingsController.add(newSettings);
  }

  @override
  Stream<De1WaterLevels> get waterLevels =>
      Stream.periodic(Duration(seconds: 1), (_) {
        return De1WaterLevels(
          currentPercentage: 50,
          warningThresholdPercentage: 5,
        );
      });
}
