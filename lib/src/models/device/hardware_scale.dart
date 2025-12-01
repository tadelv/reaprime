import 'device.dart';

abstract class HardwareScale extends Device {
  Stream<ScaleSnapshot> get currentSnapshot;

  // TODO: commands
  Future<void> tare();
}

class ScaleSnapshot {
  final DateTime timestamp;
  final double weight;
  final int batteryLevel;

  ScaleSnapshot({
    required this.timestamp,
    required this.weight,
    required this.batteryLevel,
  });

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'weight': weight,
      'batteryLevel': batteryLevel,
    };
  }
}
