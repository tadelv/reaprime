import 'package:reaprime/src/models/device/machine.dart';

/// One sample collected during steaming. Analogue of [ShotSnapshot]:
/// wraps the full [MachineSnapshot] and adds the milk-probe reading
/// when one is available. `milkTemperature` is `null` until a sensor
/// is registered with `SensorController` and emits a reading.
class SteamSnapshot {
  final MachineSnapshot machine;
  final double? milkTemperature;

  SteamSnapshot({required this.machine, this.milkTemperature});

  SteamSnapshot copyWith({MachineSnapshot? machine, double? milkTemperature}) {
    return SteamSnapshot(
      machine: machine ?? this.machine,
      milkTemperature: milkTemperature ?? this.milkTemperature,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'machine': machine.toJson(),
      'milkTemperature': milkTemperature,
    };
  }

  factory SteamSnapshot.fromJson(Map<String, dynamic> json) {
    return SteamSnapshot(
      machine: MachineSnapshot.fromJson(json['machine']),
      milkTemperature: (json['milkTemperature'] as num?)?.toDouble(),
    );
  }
}
