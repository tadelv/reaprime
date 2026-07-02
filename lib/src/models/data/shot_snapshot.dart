import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/models/device/machine.dart';

class ShotSnapshot {
  final MachineSnapshot machine;
  final WeightSnapshot? scale;
  final double? volume;

  /// Combustion probe reading in Celsius (T1 / immersed tip per OD-2).
  /// `null` when no probe was active for this sample.
  final double? probeTemperature;

  ShotSnapshot({
    required this.machine,
    this.scale,
    this.volume,
    this.probeTemperature,
  });

  ShotSnapshot copyWith({
    MachineSnapshot? machine,
    WeightSnapshot? scale,
    double? volume,
    double? probeTemperature,
  }) {
    return ShotSnapshot(
      machine: machine ?? this.machine,
      scale: scale ?? this.scale,
      volume: volume ?? this.volume,
      probeTemperature: probeTemperature ?? this.probeTemperature,
    );
  }

  Map<String, Object?> toJson() {
    return {
      "machine": machine.toJson(),
      "scale": scale?.toJson(),
      "volume": volume,
      "probeTemperature": probeTemperature,
    };
  }

  factory ShotSnapshot.fromJson(Map<String, dynamic> json) {
    return ShotSnapshot(
      machine: MachineSnapshot.fromJson(json["machine"]),
      scale:
          json['scale'] != null ? WeightSnapshot.fromJson(json["scale"]) : null,
      volume: (json['volume'] as num?)?.toDouble(),
      probeTemperature: (json['probeTemperature'] as num?)?.toDouble(),
    );
  }
}
