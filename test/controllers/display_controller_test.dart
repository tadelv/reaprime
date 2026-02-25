import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/display_controller.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/de1_rawmessage.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:rxdart/subjects.dart';

// ---------------------------------------------------------------------------
// Test-local mocks
// ---------------------------------------------------------------------------

/// Minimal DeviceDiscoveryService for constructing DeviceController.
class _FakeDiscoveryService implements DeviceDiscoveryService {
  @override
  Stream<List<Device>> get devices => const Stream.empty();
  @override
  Future<void> initialize() async {}
  @override
  Future<void> scanForDevices() async {}
  @override
  Future<void> scanForSpecificDevices(List<String> deviceIds) async {}
}

/// A De1Interface test double with a controllable snapshot stream.
class _TestDe1 implements De1Interface {
  final BehaviorSubject<MachineSnapshot> _snapshotSubject =
      BehaviorSubject.seeded(
    MachineSnapshot(
      timestamp: DateTime(2026, 1, 15, 8, 0),
      state: const MachineStateSnapshot(
        state: MachineState.idle,
        substate: MachineSubstate.idle,
      ),
      flow: 0,
      pressure: 0,
      targetFlow: 0,
      targetPressure: 0,
      mixTemperature: 90,
      groupTemperature: 90,
      targetMixTemperature: 93,
      targetGroupTemperature: 93,
      profileFrame: 0,
      steamTemperature: 0,
    ),
  );

  final List<MachineState> requestedStates = [];

  void emitState(MachineState state) {
    final current = _snapshotSubject.value;
    _snapshotSubject.add(current.copyWith(
      state: MachineStateSnapshot(
        state: state,
        substate: MachineSubstate.idle,
      ),
    ));
  }

  @override
  Stream<MachineSnapshot> get currentSnapshot => _snapshotSubject.stream;

  @override
  Future<void> sendUserPresent() async {}

  @override
  Future<void> requestState(MachineState newState) async {
    requestedStates.add(newState);
    emitState(newState);
  }

  // --- Below: stubs for the rest of De1Interface ---
  @override
  String get deviceId => 'test-de1';
  @override
  String get name => 'TestDe1';
  @override
  DeviceType get type => DeviceType.machine;
  @override
  Future<void> onConnect() async {}
  @override
  Future<void> disconnect() async {}
  @override
  Stream<ConnectionState> get connectionState =>
      BehaviorSubject.seeded(ConnectionState.connected).stream;
  @override
  Stream<bool> get ready => Stream.value(true);
  @override
  MachineInfo get machineInfo => MachineInfo(
        version: '1',
        model: '1',
        serialNumber: '1',
        groupHeadControllerPresent: false,
        extra: {},
      );
  @override
  Stream<De1ShotSettings> get shotSettings => const Stream.empty();
  @override
  Future<void> updateShotSettings(De1ShotSettings newSettings) async {}
  @override
  Stream<De1WaterLevels> get waterLevels => const Stream.empty();
  @override
  Future<void> setRefillLevel(int newRefillLevel) async {}
  @override
  Future<void> setProfile(Profile profile) async {}
  @override
  Future<void> setFanThreshhold(int temp) async {}
  @override
  Future<int> getFanThreshhold() async => 0;
  @override
  Future<int> getTankTempThreshold() async => 0;
  @override
  Future<void> setTankTempThreshold(int temp) async {}
  @override
  Future<void> setSteamFlow(double newFlow) async {}
  @override
  Future<double> getSteamFlow() async => 0;
  @override
  Future<void> setHotWaterFlow(double newFlow) async {}
  @override
  Future<double> getHotWaterFlow() async => 0;
  @override
  Future<void> setFlushFlow(double newFlow) async {}
  @override
  Future<double> getFlushFlow() async => 0;
  @override
  Future<void> setFlushTimeout(double newTimeout) async {}
  @override
  Future<double> getFlushTimeout() async => 0;
  @override
  Future<double> getFlushTemperature() async => 0;
  @override
  Future<void> setFlushTemperature(double newTemp) async {}
  @override
  Future<double> getFlowEstimation() async => 1.0;
  @override
  Future<void> setFlowEstimation(double multiplier) async {}
  @override
  Future<bool> getUsbChargerMode() async => false;
  @override
  Future<void> setUsbChargerMode(bool t) async {}
  @override
  Future<void> setSteamPurgeMode(int mode) async {}
  @override
  Future<int> getSteamPurgeMode() async => 0;
  @override
  Future<void> enableUserPresenceFeature() async {}
  @override
  Stream<De1RawMessage> get rawOutStream => const Stream.empty();
  @override
  void sendRawMessage(De1RawMessage message) {}
  @override
  Future<double> getHeaterPhase1Flow() async => 0;
  @override
  Future<void> setHeaterPhase1Flow(double val) async {}
  @override
  Future<double> getHeaterPhase2Flow() async => 0;
  @override
  Future<void> setHeaterPhase2Flow(double val) async {}
  @override
  Future<double> getHeaterPhase2Timeout() async => 0;
  @override
  Future<void> setHeaterPhase2Timeout(double val) async {}
  @override
  Future<double> getHeaterIdleTemp() async => 0;
  @override
  Future<void> setHeaterIdleTemp(double val) async {}
  @override
  Future<void> updateFirmware(Uint8List fwImage,
      {required void Function(double progress) onProgress}) async {}
  @override
  Future<void> cancelFirmwareUpload() async {}
}

/// A De1Controller subclass that exposes a settable de1 subject.
class _TestDe1Controller extends De1Controller {
  final BehaviorSubject<De1Interface?> _de1Subject =
      BehaviorSubject.seeded(null);

  _TestDe1Controller({required super.controller});

  @override
  Stream<De1Interface?> get de1 => _de1Subject.stream;

  void setDe1(De1Interface? de1) {
    _de1Subject.add(de1);
  }
}

/// Creates a DisplayController with no-op platform operations for testing.
/// This allows tests to verify actual state transitions without platform deps.
DisplayController _createController(_TestDe1Controller de1Controller) {
  return DisplayController(
    de1Controller: de1Controller,
    setBrightness: (_) async {},
    resetBrightness: () async {},
    enableWakeLock: () async {},
    disableWakeLock: () async {},
  );
}

void main() {
  late _TestDe1Controller de1Controller;
  late _TestDe1 testDe1;

  setUp(() {
    final discoveryService = _FakeDiscoveryService();
    final deviceController = DeviceController([discoveryService]);
    de1Controller = _TestDe1Controller(controller: deviceController);
    testDe1 = _TestDe1();
  });

  group('initial state', () {
    test('starts with wake-lock disabled, normal brightness, no override', () {
      fakeAsync((async) {
        final controller = _createController(de1Controller);
        controller.initialize();
        async.flushMicrotasks();

        final state = controller.currentState;
        expect(state.wakeLockEnabled, isFalse);
        expect(state.brightness, DisplayBrightness.normal);
        expect(state.wakeLockOverride, isFalse);

        controller.dispose();
      });
    });

    test('platformSupported reports correct values', () {
      fakeAsync((async) {
        final controller = _createController(de1Controller);
        controller.initialize();
        async.flushMicrotasks();

        final state = controller.currentState;
        // wakeLock is always true (wakelock_plus supports all platforms)
        expect(state.platformSupported.wakeLock, isTrue);
        // brightness depends on platform — on macOS (test env) it should be true
        expect(state.platformSupported.brightness, isTrue);

        controller.dispose();
      });
    });
  });

  group('auto wake-lock', () {
    test('enables wake-lock when DE1 connects', () {
      fakeAsync((async) {
        final controller = _createController(de1Controller);
        controller.initialize();
        async.flushMicrotasks();

        de1Controller.setDe1(testDe1);
        async.flushMicrotasks();

        expect(controller.currentState.wakeLockEnabled, isTrue);

        controller.dispose();
      });
    });

    test('disables wake-lock when DE1 disconnects', () {
      fakeAsync((async) {
        final controller = _createController(de1Controller);
        controller.initialize();
        async.flushMicrotasks();

        de1Controller.setDe1(testDe1);
        async.flushMicrotasks();
        expect(controller.currentState.wakeLockEnabled, isTrue);

        de1Controller.setDe1(null);
        async.flushMicrotasks();
        expect(controller.currentState.wakeLockEnabled, isFalse);

        controller.dispose();
      });
    });

    test('disables wake-lock when machine enters sleep', () {
      fakeAsync((async) {
        final controller = _createController(de1Controller);
        controller.initialize();
        async.flushMicrotasks();

        de1Controller.setDe1(testDe1);
        async.flushMicrotasks();
        expect(controller.currentState.wakeLockEnabled, isTrue);

        testDe1.emitState(MachineState.sleeping);
        async.flushMicrotasks();
        expect(controller.currentState.wakeLockEnabled, isFalse);

        controller.dispose();
      });
    });

    test('re-enables wake-lock when machine wakes from sleep', () {
      fakeAsync((async) {
        final controller = _createController(de1Controller);
        controller.initialize();
        async.flushMicrotasks();

        de1Controller.setDe1(testDe1);
        async.flushMicrotasks();

        testDe1.emitState(MachineState.sleeping);
        async.flushMicrotasks();
        expect(controller.currentState.wakeLockEnabled, isFalse);

        testDe1.emitState(MachineState.idle);
        async.flushMicrotasks();
        expect(controller.currentState.wakeLockEnabled, isTrue);

        controller.dispose();
      });
    });
  });

  group('wake-lock override', () {
    test('requestWakeLock enables wake-lock and sets override flag', () {
      fakeAsync((async) {
        final controller = _createController(de1Controller);
        controller.initialize();
        async.flushMicrotasks();

        controller.requestWakeLock();
        async.flushMicrotasks();

        expect(controller.currentState.wakeLockOverride, isTrue);
        expect(controller.currentState.wakeLockEnabled, isTrue);

        controller.dispose();
      });
    });

    test('releaseWakeLock clears override and disables wake-lock when disconnected',
        () {
      fakeAsync((async) {
        final controller = _createController(de1Controller);
        controller.initialize();
        async.flushMicrotasks();

        controller.requestWakeLock();
        async.flushMicrotasks();
        expect(controller.currentState.wakeLockOverride, isTrue);
        expect(controller.currentState.wakeLockEnabled, isTrue);

        controller.releaseWakeLock();
        async.flushMicrotasks();
        expect(controller.currentState.wakeLockOverride, isFalse);
        expect(controller.currentState.wakeLockEnabled, isFalse);

        controller.dispose();
      });
    });

    test('override keeps wake-lock enabled even when machine sleeps', () {
      fakeAsync((async) {
        final controller = _createController(de1Controller);
        controller.initialize();
        async.flushMicrotasks();

        de1Controller.setDe1(testDe1);
        async.flushMicrotasks();

        controller.requestWakeLock();
        async.flushMicrotasks();

        testDe1.emitState(MachineState.sleeping);
        async.flushMicrotasks();

        expect(controller.currentState.wakeLockEnabled, isTrue);
        expect(controller.currentState.wakeLockOverride, isTrue);

        controller.dispose();
      });
    });

    test('releasing override while machine sleeping disables wake-lock', () {
      fakeAsync((async) {
        final controller = _createController(de1Controller);
        controller.initialize();
        async.flushMicrotasks();

        de1Controller.setDe1(testDe1);
        async.flushMicrotasks();

        controller.requestWakeLock();
        async.flushMicrotasks();

        testDe1.emitState(MachineState.sleeping);
        async.flushMicrotasks();

        controller.releaseWakeLock();
        async.flushMicrotasks();

        expect(controller.currentState.wakeLockOverride, isFalse);
        expect(controller.currentState.wakeLockEnabled, isFalse);

        controller.dispose();
      });
    });
  });

  group('brightness', () {
    test('dim sets brightness to dimmed', () {
      fakeAsync((async) {
        final controller = _createController(de1Controller);
        controller.initialize();
        async.flushMicrotasks();

        controller.dim();
        async.flushMicrotasks();

        expect(controller.currentState.brightness, DisplayBrightness.dimmed);

        controller.dispose();
      });
    });

    test('restore sets brightness to normal', () {
      fakeAsync((async) {
        final controller = _createController(de1Controller);
        controller.initialize();
        async.flushMicrotasks();

        controller.dim();
        async.flushMicrotasks();
        expect(controller.currentState.brightness, DisplayBrightness.dimmed);

        controller.restore();
        async.flushMicrotasks();
        expect(controller.currentState.brightness, DisplayBrightness.normal);

        controller.dispose();
      });
    });

    test('auto-restores brightness when machine wakes from sleep', () {
      fakeAsync((async) {
        final controller = _createController(de1Controller);
        controller.initialize();
        async.flushMicrotasks();

        de1Controller.setDe1(testDe1);
        async.flushMicrotasks();

        controller.dim();
        async.flushMicrotasks();
        expect(controller.currentState.brightness, DisplayBrightness.dimmed);

        testDe1.emitState(MachineState.sleeping);
        async.flushMicrotasks();

        testDe1.emitState(MachineState.idle);
        async.flushMicrotasks();
        expect(controller.currentState.brightness, DisplayBrightness.normal);

        controller.dispose();
      });
    });
  });

  group('state broadcasting', () {
    test('stream emits initial state', () {
      fakeAsync((async) {
        final controller = _createController(de1Controller);
        controller.initialize();
        async.flushMicrotasks();

        final emissions = <DisplayState>[];
        final sub = controller.state.listen(emissions.add);
        async.flushMicrotasks();

        // BehaviorSubject immediately emits current value
        expect(emissions, isNotEmpty);
        expect(emissions.first.wakeLockEnabled, isFalse);
        expect(emissions.first.brightness, DisplayBrightness.normal);
        expect(emissions.first.wakeLockOverride, isFalse);

        sub.cancel();
        controller.dispose();
      });
    });

    test('stream emits on wake-lock override changes', () {
      fakeAsync((async) {
        final controller = _createController(de1Controller);
        controller.initialize();
        async.flushMicrotasks();

        final emissions = <DisplayState>[];
        final sub = controller.state.listen(emissions.add);
        async.flushMicrotasks();

        final initialCount = emissions.length;

        controller.requestWakeLock();
        async.flushMicrotasks();

        expect(emissions.length, greaterThan(initialCount));
        expect(emissions.last.wakeLockOverride, isTrue);
        expect(emissions.last.wakeLockEnabled, isTrue);

        controller.releaseWakeLock();
        async.flushMicrotasks();

        expect(emissions.last.wakeLockOverride, isFalse);

        sub.cancel();
        controller.dispose();
      });
    });

    test('stream emits on DE1 connect/disconnect', () {
      fakeAsync((async) {
        final controller = _createController(de1Controller);
        controller.initialize();
        async.flushMicrotasks();

        final emissions = <DisplayState>[];
        final sub = controller.state.listen(emissions.add);
        async.flushMicrotasks();

        final preConnectCount = emissions.length;

        de1Controller.setDe1(testDe1);
        async.flushMicrotasks();

        expect(emissions.length, greaterThan(preConnectCount));
        expect(emissions.last.wakeLockEnabled, isTrue);

        de1Controller.setDe1(null);
        async.flushMicrotasks();

        expect(emissions.last.wakeLockEnabled, isFalse);

        sub.cancel();
        controller.dispose();
      });
    });

    test('dispose closes state stream', () async {
      final controller = _createController(de1Controller);
      controller.initialize();

      final completer = Completer<void>();
      final sub = controller.state.listen(
        (_) {},
        onDone: () => completer.complete(),
      );

      controller.dispose();

      await completer.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => fail('Stream onDone was not called after dispose'),
      );

      await sub.cancel();
    });
  });

  group('snapshot deduplication', () {
    test('repeated same-state snapshots do not trigger redundant evaluations',
        () {
      fakeAsync((async) {
        final controller = _createController(de1Controller);
        controller.initialize();
        async.flushMicrotasks();

        de1Controller.setDe1(testDe1);
        async.flushMicrotasks();

        final emissions = <DisplayState>[];
        final sub = controller.state.listen(emissions.add);
        async.flushMicrotasks();

        final countAfterConnect = emissions.length;

        // Emit same state multiple times — guard should skip re-evaluation
        testDe1.emitState(MachineState.idle);
        async.flushMicrotasks();
        testDe1.emitState(MachineState.idle);
        async.flushMicrotasks();
        testDe1.emitState(MachineState.idle);
        async.flushMicrotasks();

        // No new emissions since machine state didn't change
        expect(emissions.length, countAfterConnect);

        sub.cancel();
        controller.dispose();
      });
    });
  });

  group('DisplayState', () {
    test('toJson returns correct structure', () {
      const state = DisplayState(
        wakeLockEnabled: true,
        wakeLockOverride: false,
        brightness: DisplayBrightness.dimmed,
        platformSupported: DisplayPlatformSupport(
          brightness: true,
          wakeLock: true,
        ),
      );

      final json = state.toJson();
      expect(json['wakeLockEnabled'], isTrue);
      expect(json['wakeLockOverride'], isFalse);
      expect(json['brightness'], 'dimmed');
      expect(json['platformSupported'], isA<Map>());
      expect(json['platformSupported']['brightness'], isTrue);
      expect(json['platformSupported']['wakeLock'], isTrue);
    });

    test('copyWith preserves unmodified fields', () {
      const original = DisplayState(
        wakeLockEnabled: true,
        wakeLockOverride: true,
        brightness: DisplayBrightness.dimmed,
        platformSupported: DisplayPlatformSupport(
          brightness: true,
          wakeLock: true,
        ),
      );

      final copied = original.copyWith(wakeLockEnabled: false);
      expect(copied.wakeLockEnabled, isFalse);
      expect(copied.wakeLockOverride, isTrue); // preserved
      expect(copied.brightness, DisplayBrightness.dimmed); // preserved
    });

    test('copyWith can change all fields', () {
      const original = DisplayState(
        wakeLockEnabled: false,
        wakeLockOverride: false,
        brightness: DisplayBrightness.normal,
        platformSupported: DisplayPlatformSupport(
          brightness: false,
          wakeLock: false,
        ),
      );

      final copied = original.copyWith(
        wakeLockEnabled: true,
        wakeLockOverride: true,
        brightness: DisplayBrightness.dimmed,
        platformSupported: const DisplayPlatformSupport(
          brightness: true,
          wakeLock: true,
        ),
      );

      expect(copied.wakeLockEnabled, isTrue);
      expect(copied.wakeLockOverride, isTrue);
      expect(copied.brightness, DisplayBrightness.dimmed);
      expect(copied.platformSupported.brightness, isTrue);
      expect(copied.platformSupported.wakeLock, isTrue);
    });
  });
}
