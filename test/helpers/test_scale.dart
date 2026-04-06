import 'dart:async';

import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:rxdart/rxdart.dart';

/// A lightweight Scale for widget tests.
///
/// Unlike MockScale (which has a Timer.periodic that conflicts with
/// pumpAndSettle), this implementation has no timers or active streams.
///
/// Connection state defaults to [ConnectionState.connected] and can be
/// changed dynamically via [setConnectionState] for subscription lifecycle
/// tests.
class TestScale implements Scale {
  @override
  final String deviceId;

  @override
  final String name;

  final BehaviorSubject<ConnectionState> _connectionState;

  TestScale({
    this.deviceId = 'test-scale',
    this.name = 'Mock Scale',
    ConnectionState initialState = ConnectionState.connected,
  }) : _connectionState = BehaviorSubject.seeded(initialState);

  @override
  DeviceType get type => DeviceType.scale;

  @override
  Stream<ConnectionState> get connectionState => _connectionState.stream;

  /// Update the connection state. Listeners on [connectionState] will be
  /// notified immediately.
  void setConnectionState(ConnectionState state) {
    _connectionState.add(state);
  }

  final BehaviorSubject<ScaleSnapshot> _snapshotSubject = BehaviorSubject();

  /// Emit a [ScaleSnapshot] on the [currentSnapshot] stream.
  void emitSnapshot(ScaleSnapshot snapshot) {
    _snapshotSubject.add(snapshot);
  }

  void dispose() {
    _connectionState.close();
    _snapshotSubject.close();
  }

  @override
  Stream<ScaleSnapshot> get currentSnapshot => _snapshotSubject.stream;

  @override
  Future<void> onConnect() async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> tare() async {}

  @override
  Future<void> sleepDisplay() async {}

  @override
  Future<void> wakeDisplay() async {}

  @override
  Future<void> startTimer() async {}

  @override
  Future<void> stopTimer() async {}

  @override
  Future<void> resetTimer() async {}
}
