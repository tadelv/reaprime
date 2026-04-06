import 'dart:typed_data';

import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/de1_rawmessage.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:rxdart/rxdart.dart';

/// A shared De1Interface test double with a controllable snapshot stream.
///
/// Unlike the test-local `_TestDe1` in presence_controller_test.dart,
/// [requestState] only records the call — it does NOT emit a new state.
/// Use [emitSnapshot] or [emitStateAndSubstate] to drive the stream explicitly.
class TestDe1 implements De1Interface {
  final BehaviorSubject<MachineSnapshot> snapshotSubject =
      BehaviorSubject.seeded(
    MachineSnapshot(
      timestamp: DateTime(2026, 1, 15, 8, 0),
      state: const MachineStateSnapshot(
        state: MachineState.idle,
        substate: MachineSubstate.idle,
      ),
      flow: 0,
      pressure: 0,
      targetFlow: 0,
      targetPressure: 0,
      mixTemperature: 90,
      groupTemperature: 90,
      targetMixTemperature: 93,
      targetGroupTemperature: 93,
      profileFrame: 0,
      steamTemperature: 0,
    ),
  );

  final BehaviorSubject<ConnectionState> _connectionState =
      BehaviorSubject.seeded(ConnectionState.connected);

  /// Records every [MachineState] passed to [requestState].
  final List<MachineState> requestedStates = [];

  /// Emit an arbitrary [MachineSnapshot].
  void emitSnapshot(MachineSnapshot snapshot) {
    snapshotSubject.add(snapshot);
  }

  /// Convenience: emit a snapshot that differs from the current one only in
  /// state and substate.
  void emitStateAndSubstate(MachineState state, MachineSubstate substate) {
    final current = snapshotSubject.value;
    snapshotSubject.add(current.copyWith(
      state: MachineStateSnapshot(state: state, substate: substate),
    ));
  }

  /// Update the connection state. Listeners on [connectionState] will be
  /// notified immediately.
  void setConnectionState(ConnectionState state) {
    _connectionState.add(state);
  }

  void dispose() {
    snapshotSubject.close();
    _connectionState.close();
  }

  // ---- Machine / Device ----

  @override
  Stream<MachineSnapshot> get currentSnapshot => snapshotSubject.stream;

  @override
  MachineInfo get machineInfo => MachineInfo(
        version: '1',
        model: '1',
        serialNumber: '1',
        groupHeadControllerPresent: false,
        extra: {},
      );

  @override
  Future<void> requestState(MachineState newState) async {
    requestedStates.add(newState);
  }

  @override
  String get deviceId => 'test-de1';
  @override
  String get name => 'TestDe1';
  @override
  DeviceType get type => DeviceType.machine;
  @override
  Future<void> onConnect() async {}
  @override
  Future<void> disconnect() async {}
  @override
  Stream<ConnectionState> get connectionState => _connectionState.stream;

  // ---- De1Interface ----

  @override
  Stream<bool> get ready => Stream.value(true);
  @override
  Stream<De1ShotSettings> get shotSettings => const Stream.empty();
  @override
  Future<void> updateShotSettings(De1ShotSettings newSettings) async {}
  @override
  Stream<De1WaterLevels> get waterLevels => const Stream.empty();
  @override
  Future<void> setRefillLevel(int newRefillLevel) async {}
  @override
  Future<void> setProfile(Profile profile) async {}
  @override
  Future<void> setFanThreshhold(int temp) async {}
  @override
  Future<int> getFanThreshhold() async => 0;
  @override
  Future<int> getTankTempThreshold() async => 0;
  @override
  Future<void> setTankTempThreshold(int temp) async {}
  @override
  Future<void> setSteamFlow(double newFlow) async {}
  @override
  Future<double> getSteamFlow() async => 0;
  @override
  Future<void> setHotWaterFlow(double newFlow) async {}
  @override
  Future<double> getHotWaterFlow() async => 0;
  @override
  Future<void> setFlushFlow(double newFlow) async {}
  @override
  Future<double> getFlushFlow() async => 0;
  @override
  Future<void> setFlushTimeout(double newTimeout) async {}
  @override
  Future<double> getFlushTimeout() async => 0;
  @override
  Future<double> getFlushTemperature() async => 0;
  @override
  Future<void> setFlushTemperature(double newTemp) async {}
  @override
  Future<double> getFlowEstimation() async => 1.0;
  @override
  Future<void> setFlowEstimation(double multiplier) async {}
  @override
  Future<bool> getUsbChargerMode() async => false;
  @override
  Future<void> setUsbChargerMode(bool t) async {}
  @override
  Future<void> setSteamPurgeMode(int mode) async {}
  @override
  Future<int> getSteamPurgeMode() async => 0;
  @override
  Future<void> enableUserPresenceFeature() async {}
  @override
  Future<void> sendUserPresent() async {}
  @override
  Stream<De1RawMessage> get rawOutStream => const Stream.empty();
  @override
  void sendRawMessage(De1RawMessage message) {}
  @override
  Future<double> getHeaterPhase1Flow() async => 0;
  @override
  Future<void> setHeaterPhase1Flow(double val) async {}
  @override
  Future<double> getHeaterPhase2Flow() async => 0;
  @override
  Future<void> setHeaterPhase2Flow(double val) async {}
  @override
  Future<double> getHeaterPhase2Timeout() async => 0;
  @override
  Future<void> setHeaterPhase2Timeout(double val) async {}
  @override
  Future<double> getHeaterIdleTemp() async => 0;
  @override
  Future<void> setHeaterIdleTemp(double val) async {}
  @override
  Future<void> updateFirmware(Uint8List fwImage,
      {required void Function(double progress) onProgress}) async {}
  @override
  Future<void> cancelFirmwareUpload() async {}
}
