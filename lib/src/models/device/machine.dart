import 'package:flutter/material.dart';
import 'package:reaprime/src/models/device/device.dart';

abstract class Machine extends Device with ChangeNotifier {
  late MachineSnapshot _currentSnapshot;

  MachineSnapshot get currentSnapshot => _currentSnapshot;
}

typedef MachineSnapshot =
    ({
      DateTime timestamp,
      MachineStateSnapshot state,
      double flow,
      double pressure,
      double targetFlow,
      double targetPressure,
      double mixTemperature,
      double groupTemperature,
      double targetMixTemperature,
      double targetGroupTemperature,
      int profileFrame,
      double steamTemperature,
    });

enum MachineState {
  idle,
  booting,
  sleeping,
  heating,
  preheating,
  espresso,
  hotWater,
  flush,
  steam,
  cleaning,
  descaling,
  transportMode,
}

enum MachineSubstate { preinfusion, pouring }

typedef MachineStateSnapshot = ({MachineState state, MachineSubstate substate});
