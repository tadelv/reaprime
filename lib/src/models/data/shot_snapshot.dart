import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/models/device/machine.dart';

class ShotSnapshot {
  final MachineSnapshot machine;
  final WeightSnapshot? scale;
  final double? volume;

  ShotSnapshot({required this.machine, this.scale, this.volume});

  ShotSnapshot copyWith({
    MachineSnapshot? machine,
    WeightSnapshot? scale,
    double? volume,
  }) {
    return ShotSnapshot(
      machine: machine ?? this.machine,
      scale: scale ?? this.scale,
      volume: volume ?? this.volume,
    );
  }

  Map<String, Object?> toJson() {
    return {
      "machine": machine.toJson(),
      "scale": scale?.toJson(),
      "volume": volume,
    };
  }

  factory ShotSnapshot.fromJson(Map<String, dynamic> json) {
    return ShotSnapshot(
      machine: MachineSnapshot.fromJson(json["machine"]),
      scale: json['scale'] != null
          ? WeightSnapshot.fromJson(json["scale"])
          : null,
      volume: json['volume'] as double?,
    );
  }
}
