import 'device.dart';

abstract class Scale extends Device {
  Stream<ScaleSnapshot> get currentSnapshot;

  Future<void> tare();

  /// Tell scale to go to sleep (turn off display)
  /// If scale doesn't support display control, should disconnect instead
  Future<void> sleepDisplay();

  /// Tell the scale to wake the display
  /// If scale doesn't support display control, this is a no-op
  Future<void> wakeDisplay();

  Future<void> startTimer() async {}
  Future<void> stopTimer() async {}
  Future<void> resetTimer() async {}
}

class ScaleSnapshot {
  final DateTime timestamp;
  final double weight;
  final int batteryLevel;
  final Duration? timerValue;

  ScaleSnapshot({
    required this.timestamp,
    required this.weight,
    required this.batteryLevel,
    this.timerValue,
  });

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'weight': weight,
      'batteryLevel': batteryLevel,
      'timerValue': timerValue?.inMilliseconds,
    };
  }
}

