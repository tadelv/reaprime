import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/machine.dart';

class MockDe1 with ChangeNotifier implements Machine {
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
  Future<void> onConnect() async {
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
          state: MachineState.heating,
          substate: MachineSubstate.pouring,
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
}
