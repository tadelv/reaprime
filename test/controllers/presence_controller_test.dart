import 'dart:async';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/presence_controller.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/de1_rawmessage.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/wake_schedule.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:rxdart/subjects.dart';

import '../helpers/mock_settings_service.dart';

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

/// A De1Interface test double that records calls to sendUserPresent and
/// requestState, and exposes a controllable snapshot stream.
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

  int sendUserPresentCount = 0;
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
  Future<void> sendUserPresent() async {
    sendUserPresentCount++;
  }

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
  late SettingsController settingsController;
  late _TestDe1 testDe1;

  setUp(() async {
    final discoveryService = _FakeDiscoveryService();
    final deviceController = DeviceController([discoveryService]);
    de1Controller = _TestDe1Controller(controller: deviceController);

    final mockSettings = MockSettingsService();
    settingsController = SettingsController(mockSettings);
    await settingsController.loadSettings();

    testDe1 = _TestDe1();
  });

  group('heartbeat() throttling', () {
    test('two calls within 30s = only 1 sendUserPresent() call', () {
      fakeAsync((async) {
        final controller = PresenceController(
          de1Controller: de1Controller,
          settingsController: settingsController,
          clock: () => clock.now(),
        );
        controller.initialize();
        de1Controller.setDe1(testDe1);

        // Flush microtasks for stream subscriptions
        async.flushMicrotasks();

        controller.heartbeat();
        async.elapse(const Duration(seconds: 10));
        controller.heartbeat();
        async.elapse(const Duration(seconds: 5));

        expect(testDe1.sendUserPresentCount, 1);

        controller.dispose();
      });
    });

    test('second call after 30s is allowed, total = 2 sendUserPresent()', () {
      fakeAsync((async) {
        final controller = PresenceController(
          de1Controller: de1Controller,
          settingsController: settingsController,
          clock: () => clock.now(),
        );
        controller.initialize();
        de1Controller.setDe1(testDe1);
        async.flushMicrotasks();

        controller.heartbeat();
        async.elapse(const Duration(seconds: 31));
        controller.heartbeat();
        async.elapse(const Duration(seconds: 1));

        expect(testDe1.sendUserPresentCount, 2);

        controller.dispose();
      });
    });
  });

  group('sleep timeout', () {
    test('heartbeat resets sleep timer - no sleep if heartbeat before timeout',
        () {
      fakeAsync((async) {
        // Set 5-minute timeout for faster test
        settingsController.setSleepTimeoutMinutes(5);
        async.flushMicrotasks();

        final controller = PresenceController(
          de1Controller: de1Controller,
          settingsController: settingsController,
          clock: () => clock.now(),
        );
        controller.initialize();
        de1Controller.setDe1(testDe1);
        async.flushMicrotasks();

        controller.heartbeat();
        async.flushMicrotasks();

        // Advance to just before timeout (4 min 50 sec)
        async.elapse(const Duration(minutes: 4, seconds: 50));
        expect(testDe1.requestedStates, isEmpty);

        // Heartbeat resets the timer
        controller.heartbeat();
        async.flushMicrotasks();

        // Advance past original timeout (another 20 sec — total 5 min 10 sec from start)
        async.elapse(const Duration(seconds: 20));
        expect(
          testDe1.requestedStates.contains(MachineState.sleeping),
          isFalse,
          reason: 'heartbeat should have reset the timer',
        );

        controller.dispose();
      });
    });

    test('no heartbeat for configured minutes sends requestState(sleeping)',
        () {
      fakeAsync((async) {
        settingsController.setSleepTimeoutMinutes(5);
        async.flushMicrotasks();

        final controller = PresenceController(
          de1Controller: de1Controller,
          settingsController: settingsController,
          clock: () => clock.now(),
        );
        controller.initialize();
        de1Controller.setDe1(testDe1);
        async.flushMicrotasks();

        controller.heartbeat();
        async.flushMicrotasks();

        async.elapse(const Duration(minutes: 5, seconds: 1));

        expect(testDe1.requestedStates, contains(MachineState.sleeping));

        controller.dispose();
      });
    });

    test('timeout = 0 means disabled — no sleep even after long time', () {
      fakeAsync((async) {
        settingsController.setSleepTimeoutMinutes(0);
        async.flushMicrotasks();

        final controller = PresenceController(
          de1Controller: de1Controller,
          settingsController: settingsController,
          clock: () => clock.now(),
        );
        controller.initialize();
        de1Controller.setDe1(testDe1);
        async.flushMicrotasks();

        controller.heartbeat();
        async.flushMicrotasks();

        async.elapse(const Duration(hours: 2));

        expect(testDe1.requestedStates, isEmpty);

        controller.dispose();
      });
    });

    test('sleep timeout paused during espresso — timer restarts instead', () {
      fakeAsync((async) {
        settingsController.setSleepTimeoutMinutes(5);
        async.flushMicrotasks();

        final controller = PresenceController(
          de1Controller: de1Controller,
          settingsController: settingsController,
          clock: () => clock.now(),
        );
        controller.initialize();
        de1Controller.setDe1(testDe1);
        async.flushMicrotasks();

        controller.heartbeat();
        async.flushMicrotasks();

        // Put machine in espresso state before timeout
        testDe1.emitState(MachineState.espresso);
        async.flushMicrotasks();

        // Advance past timeout
        async.elapse(const Duration(minutes: 5, seconds: 1));

        // Should NOT have slept — should have restarted timer
        expect(
          testDe1.requestedStates.where((s) => s == MachineState.sleeping),
          isEmpty,
          reason: 'Machine in espresso should not be put to sleep',
        );

        // Return to idle
        testDe1.emitState(MachineState.idle);
        async.flushMicrotasks();

        // Now advance past the restarted timeout
        async.elapse(const Duration(minutes: 5, seconds: 1));

        expect(testDe1.requestedStates, contains(MachineState.sleeping));

        controller.dispose();
      });
    });
  });

  group('scheduled wake', () {
    test('wakes sleeping machine at matching schedule time', () {
      fakeAsync((async) {
        // Create a schedule for 07:00 every day
        final schedule = WakeSchedule(
          id: 'test-1',
          hour: 7,
          minute: 0,
          daysOfWeek: {},
          enabled: true,
        );
        settingsController
            .setWakeSchedules(WakeSchedule.serializeList([schedule]));
        async.flushMicrotasks();

        final controller = PresenceController(
          de1Controller: de1Controller,
          settingsController: settingsController,
          clock: () => DateTime(2026, 1, 15, 6, 59),
        );
        controller.initialize();
        de1Controller.setDe1(testDe1);
        async.flushMicrotasks();

        // Set machine to sleeping
        testDe1.emitState(MachineState.sleeping);
        async.flushMicrotasks();

        // Move clock to 07:00, advance time for schedule checker to fire
        controller.clockOverride = () => DateTime(2026, 1, 15, 7, 0);
        async.elapse(const Duration(seconds: 31));

        expect(testDe1.requestedStates, contains(MachineState.schedIdle));

        controller.dispose();
      });
    });

    test('schedule does not wake non-sleeping machine', () {
      fakeAsync((async) {
        final schedule = WakeSchedule(
          id: 'test-2',
          hour: 7,
          minute: 0,
          daysOfWeek: {},
          enabled: true,
        );
        settingsController
            .setWakeSchedules(WakeSchedule.serializeList([schedule]));
        async.flushMicrotasks();

        final controller = PresenceController(
          de1Controller: de1Controller,
          settingsController: settingsController,
          clock: () => DateTime(2026, 1, 15, 7, 0),
        );
        controller.initialize();
        de1Controller.setDe1(testDe1);
        async.flushMicrotasks();

        // Machine is idle (not sleeping)
        testDe1.emitState(MachineState.idle);
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 61));

        expect(
          testDe1.requestedStates.where((s) => s == MachineState.schedIdle),
          isEmpty,
          reason:
              'Schedule should not wake a machine that is not in sleeping state',
        );

        controller.dispose();
      });
    });
  });

  group('disconnected DE1', () {
    test('heartbeat returns -1 when no DE1 connected', () {
      fakeAsync((async) {
        final controller = PresenceController(
          de1Controller: de1Controller,
          settingsController: settingsController,
          clock: () => clock.now(),
        );
        controller.initialize();
        async.flushMicrotasks();

        // No DE1 connected
        final result = controller.heartbeat();
        expect(result, -1);

        controller.dispose();
      });
    });

    test('heartbeat returns -1 when presence not enabled', () {
      fakeAsync((async) {
        settingsController.setUserPresenceEnabled(false);
        async.flushMicrotasks();

        final controller = PresenceController(
          de1Controller: de1Controller,
          settingsController: settingsController,
          clock: () => clock.now(),
        );
        controller.initialize();
        de1Controller.setDe1(testDe1);
        async.flushMicrotasks();

        final result = controller.heartbeat();
        expect(result, -1);

        controller.dispose();
      });
    });
  });

  group('settings change', () {
    test('changing sleepTimeoutMinutes resets the active timer', () {
      fakeAsync((async) {
        settingsController.setSleepTimeoutMinutes(5);
        async.flushMicrotasks();

        final controller = PresenceController(
          de1Controller: de1Controller,
          settingsController: settingsController,
          clock: () => clock.now(),
        );
        controller.initialize();
        de1Controller.setDe1(testDe1);
        async.flushMicrotasks();

        controller.heartbeat();
        async.flushMicrotasks();

        // Advance 4 minutes
        async.elapse(const Duration(minutes: 4));
        expect(testDe1.requestedStates, isEmpty);

        // Change timeout to 10 minutes — this should reset the timer
        settingsController.setSleepTimeoutMinutes(10);
        async.flushMicrotasks();

        // Advance 6 more minutes (total 10 from start, but only 6 since reset)
        async.elapse(const Duration(minutes: 6));
        expect(
          testDe1.requestedStates.contains(MachineState.sleeping),
          isFalse,
          reason:
              'Timer should have been reset to 10 min when settings changed',
        );

        // Advance to full 10 minutes from the settings change
        async.elapse(const Duration(minutes: 4, seconds: 1));
        expect(testDe1.requestedStates, contains(MachineState.sleeping));

        controller.dispose();
      });
    });
  });
}
