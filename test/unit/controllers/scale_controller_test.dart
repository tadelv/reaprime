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

/// A handoff-capable scale (like the BLE Decent Scale) that records whether it
/// was released via the destructive [disconnect] (power-off) or the
/// non-destructive [disconnectForHandoff].
class _HandoffTrackingScale extends _TrackingScale
    implements TransportHandoffScale {
  _HandoffTrackingScale(super.deviceId);
  bool handoffReleased = false;

  @override
  Future<void> disconnectForHandoff() async {
    handoffReleased = true;
    _conn.add(ConnectionState.disconnected);
  }
}

void main() {
  test(
      'switching away from a handoff-capable scale releases it WITHOUT '
      'power-off (uses disconnectForHandoff)', () async {
    final controller = ScaleController();
    final a = _HandoffTrackingScale('A'); // e.g. BLE Decent Scale
    final b = _TrackingScale('B'); // e.g. WiFi HDS

    await controller.connectToScale(a);
    await controller.connectToScale(b);

    expect(a.handoffReleased, isTrue,
        reason: 'a transport switch must use the non-power-off handoff path');
    expect(a.disconnected, isFalse,
        reason: 'the destructive disconnect() (power-off) must NOT be used '
            'when switching the active scale');

    controller.dispose();
  });

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
