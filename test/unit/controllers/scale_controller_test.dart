import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:rxdart/subjects.dart';

/// Minimal Scale that connects on [onConnect] and records [disconnect] calls.
class _TrackingScale implements Scale {
  @override
  final String deviceId;
  _TrackingScale(this.deviceId);

  final _conn = BehaviorSubject<ConnectionState>.seeded(ConnectionState.discovered);
  final _snap = BehaviorSubject<ScaleSnapshot>();
  bool disconnected = false;

  @override
  String get name => deviceId;
  @override
  DeviceType get type => DeviceType.scale;
  @override
  Stream<ConnectionState> get connectionState => _conn.stream;
  @override
  Stream<ScaleSnapshot> get currentSnapshot => _snap.stream;

  @override
  Future<void> onConnect() async => _conn.add(ConnectionState.connected);
  @override
  Future<void> disconnect() async {
    disconnected = true;
    _conn.add(ConnectionState.disconnected);
  }

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

void main() {
  test('connecting a new scale disconnects the previously-connected scale',
      () async {
    final controller = ScaleController();
    final a = _TrackingScale('A');
    final b = _TrackingScale('B');

    await controller.connectToScale(a);
    expect(controller.connectedScale().deviceId, 'A');
    expect(a.disconnected, isFalse);

    await controller.connectToScale(b);
    expect(controller.connectedScale().deviceId, 'B');
    expect(a.disconnected, isTrue,
        reason: 'the previous scale must be disconnected (one active scale)');
    expect(b.disconnected, isFalse);

    controller.dispose();
  });

  test('reconnecting the SAME scale does not disconnect it', () async {
    final controller = ScaleController();
    final a = _TrackingScale('A');

    await controller.connectToScale(a);
    await controller.connectToScale(a); // same device id
    expect(a.disconnected, isFalse,
        reason: 'same-device reconnect should not toggle disconnect');

    controller.dispose();
  });
}
