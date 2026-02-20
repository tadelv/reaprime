import 'dart:async';

import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/scale.dart';

/// A lightweight Scale for widget tests.
///
/// Unlike MockScale (which has a Timer.periodic that conflicts with
/// pumpAndSettle), this implementation has no timers or active streams.
class TestScale implements Scale {
  @override
  final String deviceId;

  @override
  final String name;

  TestScale({this.deviceId = 'test-scale', this.name = 'Mock Scale'});

  @override
  DeviceType get type => DeviceType.scale;

  @override
  Stream<ConnectionState> get connectionState =>
      Stream.value(ConnectionState.connected);

  @override
  Stream<ScaleSnapshot> get currentSnapshot => const Stream.empty();

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
