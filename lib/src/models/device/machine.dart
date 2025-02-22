import 'package:reaprime/src/models/device/device.dart';

abstract class Machine extends Device {
  Stream<MachineSnapshot> get currentSnapshot;

  Future<void> requestState(MachineState newState);
}

class MachineSnapshot {
  final DateTime timestamp;
  final MachineStateSnapshot state;
  final double flow;
  final double pressure;
  final double targetFlow;
  final double targetPressure;
  final double mixTemperature;
  final double groupTemperature;
  final double targetMixTemperature;
  final double targetGroupTemperature;
  final int profileFrame;
  final int steamTemperature;

  MachineSnapshot({
    required this.timestamp,
    required this.state,
    required this.flow,
    required this.pressure,
    required this.targetFlow,
    required this.targetPressure,
    required this.mixTemperature,
    required this.groupTemperature,
    required this.targetMixTemperature,
    required this.targetGroupTemperature,
    required this.profileFrame,
    required this.steamTemperature,
  });

  // CopyWith Method
  MachineSnapshot copyWith({
    DateTime? timestamp,
    MachineStateSnapshot? state,
    double? flow,
    double? pressure,
    double? targetFlow,
    double? targetPressure,
    double? mixTemperature,
    double? groupTemperature,
    double? targetMixTemperature,
    double? targetGroupTemperature,
    int? profileFrame,
    int? steamTemperature,
  }) {
    return MachineSnapshot(
      timestamp: timestamp ?? this.timestamp,
      state: state ?? this.state,
      flow: flow ?? this.flow,
      pressure: pressure ?? this.pressure,
      targetFlow: targetFlow ?? this.targetFlow,
      targetPressure: targetPressure ?? this.targetPressure,
      mixTemperature: mixTemperature ?? this.mixTemperature,
      groupTemperature: groupTemperature ?? this.groupTemperature,
      targetMixTemperature: targetMixTemperature ?? this.targetMixTemperature,
      targetGroupTemperature:
          targetGroupTemperature ?? this.targetGroupTemperature,
      profileFrame: profileFrame ?? this.profileFrame,
      steamTemperature: steamTemperature ?? this.steamTemperature,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'state': {'state': state.state.name, 'substate': state.substate.name},
      'flow': flow,
      'pressure': pressure,
      'targetFlow': targetFlow,
      'targetPressure': targetPressure,
      'mixTemperature': mixTemperature,
      'groupTemperature': groupTemperature,
      'targetMixTemperature': targetMixTemperature,
      'targetGroupTemperature': targetGroupTemperature,
      'profileFrame': profileFrame,
      'steamTemperature': steamTemperature,
    };
  }

  factory MachineSnapshot.fromJson(Map<String, dynamic> json) {
    return MachineSnapshot(
      timestamp: DateTime.parse(json["timestamp"]),
      state: MachineStateSnapshot(
        state: MachineState.values
            .firstWhere((e) => e.name == json["state"]["state"]),
        substate: MachineSubstate.values
            .firstWhere((e) => e.name == json["state"]["substate"]),
      ),
      flow: json["flow"],
      pressure: json["pressure"],
      targetFlow: json["targetFlow"],
      targetPressure: json["targetPressure"],
      mixTemperature: json["mixTemperature"],
      groupTemperature: json["groupTemperature"],
      targetMixTemperature: json["targetMixTemperature"],
      targetGroupTemperature: json["targetGroupTemperature"],
      profileFrame: json["profileFrame"],
      steamTemperature: json["steamTemperature"],
    );
  }
}

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
  skipStep,
  cleaning,
  descaling,
  transportMode,
  needsWater,
  error,
}

enum MachineSubstate {
  idle,
  preparingForShot, // water heating, stabilizing water temp, ...
  preinfusion,
  pouring,
  pouringDone,
  cleaningStart, // same for descale
  cleaingGroup, // same for descale
  cleanSoaking,
  cleaningSteam,
}

class MachineStateSnapshot {
  const MachineStateSnapshot({required this.state, required this.substate});
  final MachineState state;
  final MachineSubstate substate;
}
