import 'dart:async';
import 'dart:math';

import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:rxdart/subjects.dart';

class MockDe1 implements De1Interface {
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
  Stream<MachineSnapshot> get currentSnapshot => _snapshotStream.stream;

  @override
  String get deviceId => "MockDe1";

  @override
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
  disconnect() {}

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
        mixTemperature: _lastSnapshot.mixTemperature > 95
            ? _lastSnapshot.mixTemperature - 0.1
            : _lastSnapshot.mixTemperature + 0.1,
        groupTemperature: _lastSnapshot.groupTemperature > 96
            ? _lastSnapshot.groupTemperature - 0.1
            : _lastSnapshot.groupTemperature + 0.1,
        targetMixTemperature: 100,
        targetGroupTemperature: 90,
        profileFrame: 0,
        steamTemperature: min(_lastSnapshot.steamTemperature + 0.1, 150),
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
      BehaviorSubject.seeded(De1ShotSettings(
          steamSetting: 0,
          targetSteamTemp: 150,
          targetSteamDuration: 60,
          targetHotWaterTemp: 85,
          targetHotWaterVolume: 100,
          targetHotWaterDuration: 35,
          targetShotVolume: 36,
          groupTemp: 94));

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

  @override
  Stream<ConnectionState> get connectionState =>
      BehaviorSubject.seeded(ConnectionState.connected);

  @override
  Future<int> getFanThreshhold() {
    // TODO: implement getFanThreshhold
    throw UnimplementedError();
  }

  @override
  Future<void> setFanThreshhold(int temp) {
    // TODO: implement setFanThreshhold
    throw UnimplementedError();
  }

  @override
  Future<double> getSteamFlow() {
    // TODO: implement getSteamFlow
    throw UnimplementedError();
  }

  @override
  Future<void> setSteamFlow(double newFlow) {
    // TODO: implement setSteamFlow
    throw UnimplementedError();
  }

  @override
  Future<double> getHotWaterFlow() {
    // TODO: implement getHotWaterFlow
    throw UnimplementedError();
  }

  @override
  Future<void> setHotWaterFlow(double newFlow) {
    // TODO: implement setHotWaterFlow
    throw UnimplementedError();
  }

  @override
  Future<double> getFlushFlow() {
    // TODO: implement getFlushFlow
    throw UnimplementedError();
  }

  @override
  Future<void> setFlushFlow(double newFlow) {
    // TODO: implement setFlushFlow
    throw UnimplementedError();
  }

  @override
  Future<void> setFlushTimeout(double newTimeout) {
    // TODO: implement setFlushTimeout
    throw UnimplementedError();
  }

  @override
  Future<double> getFlushTimeout() {
    // TODO: implement getFlushTimeout
    throw UnimplementedError();
  }

  @override
  Future<double> getFlushTemperature() {
    // TODO: implement getFlushTemperature
    throw UnimplementedError();
  }

  @override
  Future<void> setFlushTemperature(double newTemp) {
    // TODO: implement setFlushTemperature
    throw UnimplementedError();
  }

  @override
  Future<int> getTankTempThreshold() {
    // TODO: implement getTankTempThreshold
    throw UnimplementedError();
  }

  @override
  Future<void> setTankTempThreshold(int temp) {
    // TODO: implement setTankTempThreshold
    throw UnimplementedError();
  }
}
