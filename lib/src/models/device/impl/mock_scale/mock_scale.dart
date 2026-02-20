import 'dart:async';
import 'dart:math';

import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/scale.dart';

class MockScale implements Scale {
  @override
  Stream<ConnectionState> get connectionState =>
      Stream.value(ConnectionState.connected);

  @override
  Stream<ScaleSnapshot> get currentSnapshot => _snapshotStream.stream;

  @override
  String get deviceId => "Mock Scale";

  @override
  disconnect() async {}

  @override
  String get name => "Mock Scale";

  @override
  Future<void> onConnect() async {}

  @override
  Future<void> tare() async {
    _weight = 0;
  }

  @override
  Future<void> sleepDisplay() async {
    // Mock scale - no-op (simulated scale doesn't need power management)
  }

  @override
  Future<void> wakeDisplay() async {
    // Mock scale - no-op (simulated scale doesn't need power management)
  }

  @override
  DeviceType get type => DeviceType.scale;

  final StreamController<ScaleSnapshot> _snapshotStream =
      StreamController.broadcast();

  double _weight = 0;
  final Stopwatch _timerStopwatch = Stopwatch();
  Duration? _frozenTimerValue;
  bool _timerRunning = false;

  MockScale() {
    Timer.periodic(Duration(milliseconds: 200), (_) {
      _weight += 1.1 * Random().nextDouble();
      if (_weight > 100) {
        _weight = 0;
      }
      Duration? timerValue;
      if (_timerRunning) {
        timerValue = _timerStopwatch.elapsed;
      } else if (_frozenTimerValue != null) {
        timerValue = _frozenTimerValue;
      }
      _snapshotStream.add(ScaleSnapshot(
          weight: _weight,
          timestamp: DateTime.now(),
          batteryLevel: 100,
          timerValue: timerValue));
    });
  }

  @override
  Future<void> startTimer() async {
    _frozenTimerValue = null;
    _timerStopwatch.start();
    _timerRunning = true;
  }

  @override
  Future<void> stopTimer() async {
    _timerStopwatch.stop();
    _frozenTimerValue = _timerStopwatch.elapsed;
    _timerRunning = false;
  }

  @override
  Future<void> resetTimer() async {
    _timerStopwatch.stop();
    _timerStopwatch.reset();
    _frozenTimerValue = null;
    _timerRunning = false;
  }
}
