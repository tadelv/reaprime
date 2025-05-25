import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/de1_rawmessage.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:rxdart/subjects.dart';

enum _SimulationType {
  espresso,
  steam,
  hotWater,
  idle,
}

class MockDe1 implements De1Interface {
  MockDe1({String deviceId = "MockDe1"}) : _deviceId = deviceId;

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
  _SimulationType _simulationType = _SimulationType.idle;

  @override
  Stream<MachineSnapshot> get currentSnapshot => _snapshotStream.stream;

  String _deviceId = "MockDe1";

  @override
  String get deviceId => _deviceId;

  @override
  String get name => "MockDe1";

  @override
  Future<void> requestState(MachineState newState) async {
    _currentState = newState;
    if (_currentState == MachineState.espresso) {
      _simulationType = _SimulationType.espresso;
    } else {
      _simulationType = _SimulationType.idle;
    }
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

  DateTime lastIdleSnapshot = DateTime.now();
  _simulateState() {
    _snapshotStream.add(_lastSnapshot);

    _stateTimer = Timer.periodic(
      Duration(milliseconds: 100),
      (t) {
        MachineSnapshot newSnapshot;
        switch (_simulationType) {
          case _SimulationType.espresso:
            newSnapshot = _simulateEspresso();
            break;
          case _SimulationType.idle:
            if (DateTime.now().difference(lastIdleSnapshot).inMilliseconds <
                500) {
              return;
            }
            lastIdleSnapshot = DateTime.now();
            newSnapshot = _simulateIdle();
          default:
            newSnapshot = _simulateIdle();
        }
        _snapshotStream.add(newSnapshot);
        _lastSnapshot = newSnapshot;
      },
    );
  }

  MachineSnapshot _simulateIdle() {
    return MachineSnapshot(
      timestamp: lastIdleSnapshot,
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
      steamTemperature: min(_lastSnapshot.steamTemperature + 1, 150),
    );
  }

  _simulateEspresso() {
    MachineSubstate substate = _lastSnapshot.state.substate;
    switch (_lastSnapshot.pressure) {
      case < 0.5:
        substate = MachineSubstate.preparingForShot;
        break;
      case > 1.0:
        substate = MachineSubstate.pouring;
      case > 9:
        substate = MachineSubstate.pouringDone;

      default:
        break;
    }
    if (_lastSnapshot.pressure >= 9) {
      _simulationType = _SimulationType.idle;
      _currentState = MachineState.idle;
    }
    return MachineSnapshot(
      timestamp: DateTime.now(),
      state: MachineStateSnapshot(
        state: _currentState,
        substate: substate,
      ),
      flow: min(_lastSnapshot.flow + 0.05, 4.0),
      pressure: min(_lastSnapshot.pressure + 0.04, 9.0),
      targetFlow: 4.5,
      targetPressure: 9.0,
      mixTemperature: _lastSnapshot.mixTemperature > 95
          ? _lastSnapshot.mixTemperature - 0.1
          : _lastSnapshot.mixTemperature + 0.1,
      groupTemperature: _lastSnapshot.groupTemperature > 96
          ? _lastSnapshot.groupTemperature - 0.1
          : _lastSnapshot.groupTemperature + 0.1,
      targetMixTemperature: 100,
      targetGroupTemperature: 90,
      profileFrame: 0,
      steamTemperature: min(_lastSnapshot.steamTemperature + 1, 150),
    );
  }

  @override
  Future<void> onDisconnect() async {
    _stateTimer?.cancel();
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
    return Future(() {
      return 1.0;
    });
  }

  @override
  Future<void> setSteamFlow(double newFlow) {
    // TODO: implement setSteamFlow
    throw UnimplementedError();
  }

  double _hotWaterFlow = 1.0;
  @override
  Future<double> getHotWaterFlow() async {
    return _hotWaterFlow;
  }

  @override
  Future<void> setHotWaterFlow(double newFlow) async {
    _hotWaterFlow = newFlow;
  }

  double _flushFlow = 1.0;
  @override
  Future<double> getFlushFlow() async {
    return _flushFlow;
  }

  @override
  Future<void> setFlushFlow(double newFlow) async {
    _flushFlow = newFlow;
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

  @override
  Stream<bool> get ready => Stream.value(true);

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
  // TODO: implement rawOutStream
  Stream<De1RawMessage> get rawOutStream => throw UnimplementedError();

  @override
  void sendRawMessage(De1RawMessage message) {
    // TODO: implement sendRawMessage
  }

  @override
  Future<void> updateFirmware(Uint8List fwImage) async {
	  // uploading bytes ...
    await Future.delayed(Duration(seconds: 10));
  }
}
