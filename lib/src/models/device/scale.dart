import 'device.dart';

abstract class Scale extends Device {
Stream<ScaleSnapshot> get currentSnapshot;

// TODO: commands
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
}
