import 'device.dart';

abstract class Scale extends Device {
  Stream<ScaleSnapshot> get currentSnapshot;

  Future<void> tare();

  /// Will most likely cause a disconnect event as well.
  Future<void> powerDown();

  /// Tell scale to go to sleep (i.e. turn off display)
  /// Some scales might not implement this and choose to implement only powerDown 
  /// or disconnect
  Future<void> sleepDisplay();

  /// Tell the scale to wake the display (if supported)
  Future<void> wakeDisplay();

  // TODO: commands for timer
  // other interesting commands
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
