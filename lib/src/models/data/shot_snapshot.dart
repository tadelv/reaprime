import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/models/device/machine.dart';

class ShotSnapshot {
  final MachineSnapshot machine;
  final WeightSnapshot? scale;

  ShotSnapshot({required this.machine, this.scale});

  copyWith({MachineSnapshot? machine, WeightSnapshot? scale}) {
    return ShotSnapshot(
      machine: machine ?? this.machine,
      scale: scale ?? this.scale,
    );
  }

  toJson() {
    return {
      "machine": machine.toJson(),
      "scale": scale?.toJson(),
    };
  }

  factory ShotSnapshot.fromJson(Map<String, dynamic> json) {
    return ShotSnapshot(
      machine: MachineSnapshot.fromJson(json["machine"]),
      scale: WeightSnapshot.fromJson(json["scale"]),
    );
  }
}
