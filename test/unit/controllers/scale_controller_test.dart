import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:reaprime/src/models/device/device_implementation.dart';
import 'package:reaprime/src/models/device/transport/data_transport.dart';
import 'package:reaprime/src/models/errors.dart';
import 'package:rxdart/subjects.dart';

/// Minimal Scale that connects on [onConnect] and records [disconnect] calls.
class _TrackingScale implements Scale {
  @override
  final String deviceId;
  _TrackingScale(this.deviceId);

  final _conn = BehaviorSubject<ConnectionState>.seeded(
    ConnectionState.discovered,
  );
  final _snap = BehaviorSubject<ScaleSnapshot>();
  bool disconnected = false;

  @override
  String get name => deviceId;
  @override
  DeviceType get type => DeviceType.scale;

  @override
  DeviceImplementation get implementation => DeviceImplementation.unifiedDe1;

  @override
  TransportType get transportType => TransportType.unknown;
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

  void emitAt(DateTime t, double weight) => _snap.add(
    ScaleSnapshot(
      timestamp: t,
      weight: weight,
      batteryLevel: 50,
    ),
  );
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

/// A scale whose [onConnect] completes with an error — the WiFi HDS's expected
/// failure mode (bad manual IP / recognition timeout).
class _FailingScale extends _TrackingScale {
  _FailingScale(super.deviceId);

  @override
  Future<void> onConnect() async => throw StateError('connect failed');

  void emitSnapshot() => _snap.add(
    ScaleSnapshot(
      timestamp: DateTime.now(),
      weight: 1.0,
      batteryLevel: 100,
    ),
  );
}

void main() {
  test('a scale whose onConnect throws surfaces as disconnected and leaks no '
      'snapshot subscription', () async {
    final controller = ScaleController();
    final scale = _FailingScale('W');

    await expectLater(
      controller.connectToScale(scale),
      throwsA(isA<StateError>()),
    );

    // The controller did not retain the scale and reports disconnected.
    expect(
      () => controller.connectedScale(),
      throwsA(isA<DeviceNotConnectedException>()),
    );
    expect(controller.currentConnectionState, ConnectionState.disconnected);

    // The snapshot subscription opened before onConnect must have been
    // cancelled — a late frame must not reach the weight stream.
    final frames = <WeightSnapshot>[];
    final sub = controller.weightSnapshot.listen(frames.add);
    scale.emitSnapshot();
    await Future.delayed(Duration.zero);
    expect(
      frames,
      isEmpty,
      reason:
          'a failed connect must not leave the snapshot subscription '
          'live',
    );

    await sub.cancel();
    controller.dispose();
  });

  test('switching away from a handoff-capable scale releases it WITHOUT '
      'power-off (uses disconnectForHandoff)', () async {
    final controller = ScaleController();
    final a = _HandoffTrackingScale('A'); // e.g. BLE Decent Scale
    final b = _TrackingScale('B'); // e.g. WiFi HDS

    await controller.connectToScale(a);
    await controller.connectToScale(b);

    expect(
      a.handoffReleased,
      isTrue,
      reason: 'a transport switch must use the non-power-off handoff path',
    );
    expect(
      a.disconnected,
      isFalse,
      reason:
          'the destructive disconnect() (power-off) must NOT be used '
          'when switching the active scale',
    );

    controller.dispose();
  });

  test(
    'connecting a new scale disconnects the previously-connected scale',
    () async {
      final controller = ScaleController();
      final a = _TrackingScale('A');
      final b = _TrackingScale('B');

      await controller.connectToScale(a);
      expect(controller.connectedScale().deviceId, 'A');
      expect(a.disconnected, isFalse);

      await controller.connectToScale(b);
      expect(controller.connectedScale().deviceId, 'B');
      expect(
        a.disconnected,
        isTrue,
        reason: 'the previous scale must be disconnected (one active scale)',
      );
      expect(b.disconnected, isFalse);

      controller.dispose();
    },
  );

  test('reconnecting the SAME scale does not disconnect it', () async {
    final controller = ScaleController();
    final a = _TrackingScale('A');

    await controller.connectToScale(a);
    await controller.connectToScale(a); // same device id
    expect(
      a.disconnected,
      isFalse,
      reason: 'same-device reconnect should not toggle disconnect',
    );

    controller.dispose();
  });

  test('tare suppresses the flow transient for one smoothing window without '
      'touching weight', () async {
    final controller = ScaleController();
    final scale = _TrackingScale('A');
    await controller.connectToScale(scale);

    final frames = <WeightSnapshot>[];
    final sub = controller.weightSnapshot.listen(frames.add);

    final t0 = DateTime(2026, 1, 1, 12, 0, 0);
    // Pre-tare samples build up weight (and therefore a real flow reading) and
    // establish the latest scale-clock timestamp.
    scale.emitAt(t0, 10.0);
    scale.emitAt(t0.add(const Duration(milliseconds: 100)), 14.0);
    await Future.delayed(Duration.zero);
    expect(
      frames.last.weightFlow,
      greaterThan(0),
      reason: 'real flow flows before any tare',
    );

    await controller.tare();

    // Within one smoothing window (600ms) of the last pre-tare sample the scale
    // drops to ~0 — the spike that would otherwise appear must be suppressed,
    // but the (truthful) weight still passes through.
    scale.emitAt(t0.add(const Duration(milliseconds: 200)), 0.0);
    scale.emitAt(t0.add(const Duration(milliseconds: 500)), 0.0);
    await Future.delayed(Duration.zero);
    final settleFrames = frames
        .where(
          (f) => f.timestamp.isAfter(t0.add(const Duration(milliseconds: 150))),
        )
        .toList();
    expect(settleFrames, isNotEmpty);
    expect(
      settleFrames.every((f) => f.weightFlow == 0),
      isTrue,
      reason: 'the post-tare flow transient must be suppressed',
    );
    expect(
      frames.last.weight,
      0.0,
      reason: 'weight itself is never suppressed by tare',
    );

    // Past the smoothing window, real flow resumes from a clean baseline.
    scale.emitAt(t0.add(const Duration(milliseconds: 800)), 4.0);
    scale.emitAt(t0.add(const Duration(milliseconds: 900)), 8.0);
    await Future.delayed(Duration.zero);
    expect(frames.last.weight, 8.0);
    expect(
      frames.last.weightFlow,
      greaterThan(0),
      reason: 'real flow resumes once the window has cleared',
    );

    await sub.cancel();
    controller.dispose();
  });
}
