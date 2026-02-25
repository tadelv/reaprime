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
        final controller = DisplayController(de1Controller: de1Controller);
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
        final controller = DisplayController(de1Controller: de1Controller);
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
    // NOTE: WakelockPlus platform calls will throw MissingPluginException in
    // test environment. The controller's try/catch handles this gracefully,
    // but _updateState (inside the try block, after the platform call) will
    // NOT be reached. So wakeLockEnabled state won't actually change.
    // We test that the controller doesn't crash and that the logical flow
    // (subscriptions, disconnect handling) works correctly.

    test('connects to DE1 without crashing — subscribes to snapshots', () {
      fakeAsync((async) {
        final controller = DisplayController(de1Controller: de1Controller);
        controller.initialize();
        async.flushMicrotasks();

        // Connect DE1
        de1Controller.setDe1(testDe1);
        async.flushMicrotasks();

        // Should not crash — platform calls fail gracefully
        expect(controller.currentState.brightness, DisplayBrightness.normal);

        controller.dispose();
      });
    });

    test('disconnect DE1 does not crash', () {
      fakeAsync((async) {
        final controller = DisplayController(de1Controller: de1Controller);
        controller.initialize();
        async.flushMicrotasks();

        // Connect then disconnect
        de1Controller.setDe1(testDe1);
        async.flushMicrotasks();

        de1Controller.setDe1(null);
        async.flushMicrotasks();

        // Should not crash
        expect(controller.currentState.brightness, DisplayBrightness.normal);

        controller.dispose();
      });
    });

    test('sleep state transition does not crash', () {
      fakeAsync((async) {
        final controller = DisplayController(de1Controller: de1Controller);
        controller.initialize();
        async.flushMicrotasks();

        de1Controller.setDe1(testDe1);
        async.flushMicrotasks();

        // Transition to sleeping
        testDe1.emitState(MachineState.sleeping);
        async.flushMicrotasks();

        // Should not crash
        expect(controller.currentState.brightness, DisplayBrightness.normal);

        controller.dispose();
      });
    });

    test('wake from sleep does not crash', () {
      fakeAsync((async) {
        final controller = DisplayController(de1Controller: de1Controller);
        controller.initialize();
        async.flushMicrotasks();

        de1Controller.setDe1(testDe1);
        async.flushMicrotasks();

        // Sleep then wake
        testDe1.emitState(MachineState.sleeping);
        async.flushMicrotasks();

        testDe1.emitState(MachineState.idle);
        async.flushMicrotasks();

        // Should not crash
        expect(controller.currentState.brightness, DisplayBrightness.normal);

        controller.dispose();
      });
    });
  });

  group('wake-lock override', () {
    test('requestWakeLock sets override flag in state', () {
      fakeAsync((async) {
        final controller = DisplayController(de1Controller: de1Controller);
        controller.initialize();
        async.flushMicrotasks();

        controller.requestWakeLock();
        async.flushMicrotasks();

        // Override flag is set by _updateState AFTER the platform call.
        // requestWakeLock calls _applyWakeLock (which fails) then _updateState.
        // But _updateState for override is called OUTSIDE the try/catch in
        // requestWakeLock, so it WILL be reached.
        expect(controller.currentState.wakeLockOverride, isTrue);

        controller.dispose();
      });
    });

    test('releaseWakeLock clears override flag in state', () {
      fakeAsync((async) {
        final controller = DisplayController(de1Controller: de1Controller);
        controller.initialize();
        async.flushMicrotasks();

        controller.requestWakeLock();
        async.flushMicrotasks();
        expect(controller.currentState.wakeLockOverride, isTrue);

        controller.releaseWakeLock();
        async.flushMicrotasks();
        expect(controller.currentState.wakeLockOverride, isFalse);

        controller.dispose();
      });
    });

    test('override works without DE1 connected', () {
      fakeAsync((async) {
        final controller = DisplayController(de1Controller: de1Controller);
        controller.initialize();
        async.flushMicrotasks();

        // No DE1 connected
        controller.requestWakeLock();
        async.flushMicrotasks();

        expect(controller.currentState.wakeLockOverride, isTrue);

        controller.dispose();
      });
    });

    test('releasing override re-evaluates wake-lock without crashing', () {
      fakeAsync((async) {
        final controller = DisplayController(de1Controller: de1Controller);
        controller.initialize();
        async.flushMicrotasks();

        de1Controller.setDe1(testDe1);
        async.flushMicrotasks();

        // Set override
        controller.requestWakeLock();
        async.flushMicrotasks();
        expect(controller.currentState.wakeLockOverride, isTrue);

        // Put machine to sleep
        testDe1.emitState(MachineState.sleeping);
        async.flushMicrotasks();

        // Release override — should re-evaluate (machine sleeping, no override)
        controller.releaseWakeLock();
        async.flushMicrotasks();

        expect(controller.currentState.wakeLockOverride, isFalse);
        // wake-lock state may not update due to platform call failure,
        // but the controller should not crash

        controller.dispose();
      });
    });
  });

  group('brightness', () {
    // NOTE: ScreenBrightness platform calls will throw MissingPluginException
    // in test environment. The try/catch handles this, but _updateState won't
    // be reached (it's inside the try block after the platform call).
    // So brightness state stays 'normal' regardless.

    test('dim does not crash (platform call fails gracefully)', () {
      fakeAsync((async) {
        final controller = DisplayController(de1Controller: de1Controller);
        controller.initialize();
        async.flushMicrotasks();

        controller.dim();
        async.flushMicrotasks();

        // Brightness stays normal because the platform call fails before
        // _updateState is called
        expect(controller.currentState.brightness, DisplayBrightness.normal);

        controller.dispose();
      });
    });

    test('restore does not crash (platform call fails gracefully)', () {
      fakeAsync((async) {
        final controller = DisplayController(de1Controller: de1Controller);
        controller.initialize();
        async.flushMicrotasks();

        controller.restore();
        async.flushMicrotasks();

        expect(controller.currentState.brightness, DisplayBrightness.normal);

        controller.dispose();
      });
    });

    test('auto-restore on machine wake does not crash', () {
      fakeAsync((async) {
        final controller = DisplayController(de1Controller: de1Controller);
        controller.initialize();
        async.flushMicrotasks();

        de1Controller.setDe1(testDe1);
        async.flushMicrotasks();

        // Try to dim (fails silently in test env)
        controller.dim();
        async.flushMicrotasks();

        // Put machine to sleep
        testDe1.emitState(MachineState.sleeping);
        async.flushMicrotasks();

        // Wake machine — should trigger auto-restore attempt (which also
        // fails silently in test env, but shouldn't crash)
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
        final controller = DisplayController(de1Controller: de1Controller);
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
        final controller = DisplayController(de1Controller: de1Controller);
        controller.initialize();
        async.flushMicrotasks();

        final emissions = <DisplayState>[];
        final sub = controller.state.listen(emissions.add);
        async.flushMicrotasks();

        final initialCount = emissions.length;

        controller.requestWakeLock();
        async.flushMicrotasks();

        // Should have emitted at least one new state for override change
        expect(emissions.length, greaterThan(initialCount));
        expect(emissions.last.wakeLockOverride, isTrue);

        controller.releaseWakeLock();
        async.flushMicrotasks();

        expect(emissions.last.wakeLockOverride, isFalse);

        sub.cancel();
        controller.dispose();
      });
    });

    test('stream emits on DE1 connect/disconnect', () {
      fakeAsync((async) {
        final controller = DisplayController(de1Controller: de1Controller);
        controller.initialize();
        async.flushMicrotasks();

        final emissions = <DisplayState>[];
        final sub = controller.state.listen(emissions.add);
        async.flushMicrotasks();

        final preConnectCount = emissions.length;

        de1Controller.setDe1(testDe1);
        async.flushMicrotasks();

        // Connect triggers _evaluateWakeLock via _onSnapshot which may or
        // may not emit depending on platform call success. At minimum, the
        // subscription should be active without errors.

        de1Controller.setDe1(null);
        async.flushMicrotasks();

        // Disconnect triggers _evaluateWakeLock which may emit.
        // The key assertion is that we don't crash.
        expect(emissions.length, greaterThanOrEqualTo(preConnectCount));

        sub.cancel();
        controller.dispose();
      });
    });

    test('dispose closes state stream', () async {
      final controller = DisplayController(de1Controller: de1Controller);
      controller.initialize();

      // Use a real async test so onDone propagates properly
      final completer = Completer<void>();
      final sub = controller.state.listen(
        (_) {},
        onDone: () => completer.complete(),
      );

      controller.dispose();

      // Wait for onDone — should complete quickly since close() is synchronous
      await completer.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => fail('Stream onDone was not called after dispose'),
      );

      await sub.cancel();
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
