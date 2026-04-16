import 'dart:async';
import 'dart:math';

import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:rxdart/subjects.dart';

class MockScale implements Scale {
  final BehaviorSubject<ConnectionState> _connectionSubject =
      BehaviorSubject.seeded(ConnectionState.connected);

  @override
  Stream<ConnectionState> get connectionState => _connectionSubject.stream;

  @override
  Stream<ScaleSnapshot> get currentSnapshot => _snapshotStream.stream;

  @override
  String get deviceId => "Mock Scale";

  @override
  disconnect() async {
    simulateDisconnect();
  }

  @override
  String get name => "Mock Scale";

  @override
  Future<void> onConnect() async {}

  @override
  Future<void> tare() async {
    _weight = 0;
  }

  @override
  Future<void> sleepDisplay() async {}

  @override
  Future<void> wakeDisplay() async {}

  @override
  DeviceType get type => DeviceType.scale;

  final StreamController<ScaleSnapshot> _snapshotStream =
      StreamController.broadcast();

  double _weight = 0;
  final Stopwatch _timerStopwatch = Stopwatch();
  Duration? _frozenTimerValue;
  bool _timerRunning = false;
  bool _stalled = false;
  Timer? _emissionTimer;

  MockScale() {
    _startEmission();
  }

  void _startEmission() {
    _emissionTimer?.cancel();
    _emissionTimer = Timer.periodic(Duration(milliseconds: 200), (_) {
      if (_stalled) return;
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

  /// Stop emitting weight snapshots. Scale stays "connected".
  void simulateDataStall() {
    _stalled = true;
  }

  /// Resume weight emission after a stall.
  void simulateResume() {
    _stalled = false;
  }

  /// Emit disconnected state and stop weight emission.
  void simulateDisconnect() {
    _stalled = true;
    _emissionTimer?.cancel();
    _emissionTimer = null;
    _connectionSubject.add(ConnectionState.disconnected);
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
