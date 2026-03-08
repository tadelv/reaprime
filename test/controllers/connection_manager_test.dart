import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/connection_manager.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/settings/settings_controller.dart';

import '../helpers/mock_de1_controller.dart';
import '../helpers/mock_device_discovery_service.dart';
import '../helpers/mock_scale_controller.dart';
import '../helpers/mock_settings_service.dart';
import '../helpers/test_scale.dart';

/// Minimal De1Interface stub for testing.
/// Uses noSuchMethod so we don't need to implement every member.
/// Provides real implementations for fields that DeviceController accesses.
class _FakeDe1 implements De1Interface {
  @override
  final String deviceId;

  @override
  final String name;

  @override
  DeviceType get type => DeviceType.machine;

  @override
  Stream<ConnectionState> get connectionState =>
      Stream.value(ConnectionState.connected);

  _FakeDe1({this.deviceId = 'fake-de1'}) : name = 'DE1-$deviceId';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('ConnectionStatus', () {
    test('defaults to idle with empty lists', () {
      const status = ConnectionStatus();
      expect(status.phase, ConnectionPhase.idle);
      expect(status.foundMachines, isEmpty);
      expect(status.foundScales, isEmpty);
      expect(status.pendingAmbiguity, isNull);
      expect(status.error, isNull);
    });

    test('copyWith preserves fields not overridden', () {
      const status = ConnectionStatus(phase: ConnectionPhase.scanning);
      final updated = status.copyWith(phase: ConnectionPhase.ready);
      expect(updated.phase, ConnectionPhase.ready);
      expect(updated.foundMachines, isEmpty);
    });

    test('copyWith can null out optional fields', () {
      const status = ConnectionStatus(
        pendingAmbiguity: AmbiguityReason.machinePicker,
        error: 'something',
      );
      final cleared = status.copyWith(
        pendingAmbiguity: () => null,
        error: () => null,
      );
      expect(cleared.pendingAmbiguity, isNull);
      expect(cleared.error, isNull);
    });
  });

  group('MockDe1Controller', () {
    late MockDeviceDiscoveryService discoveryService;
    late DeviceController deviceController;
    late MockDe1Controller mockDe1Controller;

    setUp(() {
      discoveryService = MockDeviceDiscoveryService();
      deviceController = DeviceController([discoveryService]);
      mockDe1Controller = MockDe1Controller(controller: deviceController);
    });

    test('records connectToDe1 calls', () async {
      final fakeDe1 = _FakeDe1();
      await mockDe1Controller.connectToDe1(fakeDe1);

      expect(mockDe1Controller.connectCalls, hasLength(1));
      expect(mockDe1Controller.connectCalls.first, same(fakeDe1));
    });

    test('emits de1 on stream after successful connect', () async {
      final fakeDe1 = _FakeDe1();
      await mockDe1Controller.connectToDe1(fakeDe1);

      expect(mockDe1Controller.de1Subject.value, same(fakeDe1));
    });

    test('throws when shouldFailConnect is true', () async {
      mockDe1Controller.shouldFailConnect = true;
      final fakeDe1 = _FakeDe1();

      expect(
        () => mockDe1Controller.connectToDe1(fakeDe1),
        throwsA(isA<Exception>()),
      );
      // Call was still recorded
      expect(mockDe1Controller.connectCalls, hasLength(1));
    });

    test('de1 stream starts with null', () {
      expect(mockDe1Controller.de1Subject.value, isNull);
    });
  });

  group('MockScaleController', () {
    late MockScaleController mockScaleController;

    setUp(() {
      mockScaleController = MockScaleController();
    });

    test('records connectToScale calls', () async {
      final testScale = TestScale();
      await mockScaleController.connectToScale(testScale);

      expect(mockScaleController.connectCalls, hasLength(1));
      expect(mockScaleController.connectCalls.first, same(testScale));
    });

    test('emits connected state after successful connect', () async {
      final testScale = TestScale();
      await mockScaleController.connectToScale(testScale);

      expect(
        mockScaleController.connectionStateSubject.value,
        ConnectionState.connected,
      );
    });

    test('throws when shouldFailConnect is true', () async {
      mockScaleController.shouldFailConnect = true;
      final testScale = TestScale();

      expect(
        () => mockScaleController.connectToScale(testScale),
        throwsA(isA<Exception>()),
      );
      // Call was still recorded
      expect(mockScaleController.connectCalls, hasLength(1));
    });

    test('connectionState starts with discovered', () {
      expect(
        mockScaleController.connectionStateSubject.value,
        ConnectionState.discovered,
      );
    });

  });

  group('ConnectionManager', () {
    late MockDeviceDiscoveryService discoveryService;
    late DeviceController deviceController;
    late MockDe1Controller mockDe1Controller;
    late MockScaleController mockScaleController;
    late SettingsController settingsController;
    late MockSettingsService mockSettingsService;
    late ConnectionManager connectionManager;

    setUp(() async {
      discoveryService = MockDeviceDiscoveryService();
      deviceController = DeviceController([discoveryService]);
      mockDe1Controller = MockDe1Controller(controller: deviceController);
      mockScaleController = MockScaleController();
      mockSettingsService = MockSettingsService();
      settingsController = SettingsController(mockSettingsService);
      await settingsController.loadSettings();

      connectionManager = ConnectionManager(
        deviceController: deviceController,
        de1Controller: mockDe1Controller,
        scaleController: mockScaleController,
        settingsController: settingsController,
      );
    });

    tearDown(() {
      connectionManager.dispose();
    });

    test('initial status is idle', () {
      expect(connectionManager.currentStatus.phase, ConnectionPhase.idle);
      expect(connectionManager.currentStatus.error, isNull);
    });

    group('connect', () {
      setUp(() async {
        // connect() requires DeviceController to be initialized so
        // device discovery streams are wired up.
        await deviceController.initialize();
      });

      test('emits scanning phase during scan', () async {
        final phases = <ConnectionPhase>[];
        final sub = connectionManager.status.listen((s) {
          phases.add(s.phase);
        });

        await connectionManager.connect();
        await Future.delayed(Duration.zero);

        expect(phases, contains(ConnectionPhase.scanning));

        await sub.cancel();
      });

      test('no preferred, 0 machines → stays idle', () async {
        // No devices added → scan finds nothing
        await connectionManager.connect();
        await Future.delayed(Duration.zero);

        expect(connectionManager.currentStatus.phase, ConnectionPhase.idle);
        expect(connectionManager.currentStatus.pendingAmbiguity, isNull);
        expect(mockDe1Controller.connectCalls, isEmpty);
      });

      test('no preferred, 1 machine → auto-connects and saves preference',
          () async {
        final fakeDe1 = _FakeDe1(deviceId: 'solo-de1');
        discoveryService.addDevice(fakeDe1);
        // Let stream propagate
        await Future.delayed(Duration.zero);

        await connectionManager.connect();
        await Future.delayed(Duration.zero);

        expect(mockDe1Controller.connectCalls, hasLength(1));
        expect(mockDe1Controller.connectCalls.first, same(fakeDe1));
        expect(settingsController.preferredMachineId, 'solo-de1');
        expect(
            connectionManager.currentStatus.phase, ConnectionPhase.ready);
      });

      test('no preferred, many machines → emits machinePicker ambiguity',
          () async {
        final de1a = _FakeDe1(deviceId: 'de1-a');
        final de1b = _FakeDe1(deviceId: 'de1-b');
        discoveryService.addDevice(de1a);
        discoveryService.addDevice(de1b);
        await Future.delayed(Duration.zero);

        await connectionManager.connect();
        await Future.delayed(Duration.zero);

        expect(connectionManager.currentStatus.phase, ConnectionPhase.idle);
        expect(connectionManager.currentStatus.pendingAmbiguity,
            AmbiguityReason.machinePicker);
        expect(
            connectionManager.currentStatus.foundMachines, hasLength(2));
        expect(mockDe1Controller.connectCalls, isEmpty);
      });

      test('preferred machine found → connects directly', () async {
        await settingsController.setPreferredMachineId('pref-de1');

        final prefDe1 = _FakeDe1(deviceId: 'pref-de1');
        discoveryService.addDevice(prefDe1);
        await Future.delayed(Duration.zero);

        await connectionManager.connect();
        await Future.delayed(Duration.zero);

        expect(mockDe1Controller.connectCalls, hasLength(1));
        expect(
            mockDe1Controller.connectCalls.first.deviceId, 'pref-de1');
        expect(
            connectionManager.currentStatus.phase, ConnectionPhase.ready);
      });

      test(
          'preferred machine not found, others available → emits machinePicker ambiguity',
          () async {
        await settingsController.setPreferredMachineId('missing-de1');

        final otherDe1 = _FakeDe1(deviceId: 'other-de1');
        discoveryService.addDevice(otherDe1);
        await Future.delayed(Duration.zero);

        await connectionManager.connect();
        await Future.delayed(Duration.zero);

        expect(connectionManager.currentStatus.phase, ConnectionPhase.idle);
        expect(connectionManager.currentStatus.pendingAmbiguity,
            AmbiguityReason.machinePicker);
        expect(mockDe1Controller.connectCalls, isEmpty);
      });

      test('preferred machine not found, no others → stays idle', () async {
        await settingsController.setPreferredMachineId('missing-de1');

        await connectionManager.connect();
        await Future.delayed(Duration.zero);

        expect(connectionManager.currentStatus.phase, ConnectionPhase.idle);
        expect(connectionManager.currentStatus.pendingAmbiguity, isNull);
        expect(mockDe1Controller.connectCalls, isEmpty);
      });

      group('scale phase', () {
        test('preferred scale found → connects after machine', () async {
          await settingsController.setPreferredScaleId('pref-scale');

          final fakeDe1 = _FakeDe1(deviceId: 'de1');
          final testScale = TestScale(deviceId: 'pref-scale');
          discoveryService.addDevice(fakeDe1);
          discoveryService.addDevice(testScale);
          await Future.delayed(Duration.zero);

          await connectionManager.connect();
          await Future.delayed(Duration.zero);

          expect(mockDe1Controller.connectCalls, hasLength(1));
          expect(mockScaleController.connectCalls, hasLength(1));
          expect(mockScaleController.connectCalls.first.deviceId,
              'pref-scale');
          expect(settingsController.preferredScaleId, 'pref-scale');
        });

        test('no preferred, 1 scale → connects silently', () async {
          final fakeDe1 = _FakeDe1(deviceId: 'de1');
          final testScale = TestScale(deviceId: 'only-scale');
          discoveryService.addDevice(fakeDe1);
          discoveryService.addDevice(testScale);
          await Future.delayed(Duration.zero);

          await connectionManager.connect();
          await Future.delayed(Duration.zero);

          expect(mockScaleController.connectCalls, hasLength(1));
          expect(
              mockScaleController.connectCalls.first.deviceId, 'only-scale');
        });

        test('no preferred, many scales → skips scale', () async {
          final fakeDe1 = _FakeDe1(deviceId: 'de1');
          final scale1 = TestScale(deviceId: 'scale-1');
          final scale2 = TestScale(deviceId: 'scale-2');
          discoveryService.addDevice(fakeDe1);
          discoveryService.addDevice(scale1);
          discoveryService.addDevice(scale2);
          await Future.delayed(Duration.zero);

          await connectionManager.connect();
          await Future.delayed(Duration.zero);

          expect(mockScaleController.connectCalls, isEmpty);
        });

        test('preferred scale not found → does nothing, phase stays ready',
            () async {
          await settingsController.setPreferredScaleId('missing-scale');

          final fakeDe1 = _FakeDe1(deviceId: 'de1');
          discoveryService.addDevice(fakeDe1);
          await Future.delayed(Duration.zero);

          await connectionManager.connect();
          await Future.delayed(Duration.zero);

          expect(mockScaleController.connectCalls, isEmpty);
          expect(connectionManager.currentStatus.phase,
              ConnectionPhase.ready);
        });

        test('scale failure does not affect machine connection', () async {
          mockScaleController.shouldFailConnect = true;

          final fakeDe1 = _FakeDe1(deviceId: 'de1');
          final testScale = TestScale(deviceId: 'fail-scale');
          discoveryService.addDevice(fakeDe1);
          discoveryService.addDevice(testScale);
          await Future.delayed(Duration.zero);

          await connectionManager.connect();
          await Future.delayed(Duration.zero);

          // Machine connected successfully
          expect(mockDe1Controller.connectCalls, hasLength(1));
          // Scale attempted but failed
          expect(mockScaleController.connectCalls, hasLength(1));
          // Phase stays ready (machine is connected)
          expect(connectionManager.currentStatus.phase,
              ConnectionPhase.ready);
        });
      });
    });

    group('connectMachine', () {
      test('delegates to De1Controller and saves preference on success',
          () async {
        final fakeDe1 = _FakeDe1(deviceId: 'my-de1');
        await connectionManager.connectMachine(fakeDe1);

        expect(mockDe1Controller.connectCalls, hasLength(1));
        expect(mockDe1Controller.connectCalls.first, same(fakeDe1));
        expect(settingsController.preferredMachineId, 'my-de1');
      });

      test('does not save preference on failure', () async {
        mockDe1Controller.shouldFailConnect = true;
        final fakeDe1 = _FakeDe1(deviceId: 'fail-de1');

        expect(
          () => connectionManager.connectMachine(fakeDe1),
          throwsA(isA<Exception>()),
        );

        // Wait for the future to settle
        await Future.delayed(Duration.zero);

        expect(settingsController.preferredMachineId, isNull);
      });

      test('rejects concurrent connection attempts', () async {
        // Make connectToDe1 slow by using a completer
        final completer = Completer<void>();

        // Override the mock to use a completer for the first call
        final slowDe1Controller =
            _SlowMockDe1Controller(controller: deviceController);
        slowDe1Controller.connectCompleter = completer;

        final manager = ConnectionManager(
          deviceController: deviceController,
          de1Controller: slowDe1Controller,
          scaleController: mockScaleController,
          settingsController: settingsController,
        );

        final fakeDe1 = _FakeDe1(deviceId: 'de1-1');

        // Start first connection (will block on completer)
        final future1 = manager.connectMachine(fakeDe1);

        // Second call should return immediately (guard)
        final future2 = manager.connectMachine(_FakeDe1(deviceId: 'de1-2'));
        await future2; // Should complete immediately

        // Only one call should have been made
        expect(slowDe1Controller.connectCalls, hasLength(1));

        // Complete the first connection
        completer.complete();
        await future1;

        expect(slowDe1Controller.connectCalls, hasLength(1));

        manager.dispose();
      });

      test('emits connectingMachine then ready phases', () async {
        final phases = <ConnectionPhase>[];
        final sub = connectionManager.status.listen((s) {
          phases.add(s.phase);
        });

        final fakeDe1 = _FakeDe1(deviceId: 'phase-de1');
        await connectionManager.connectMachine(fakeDe1);
        // Allow stream listeners to process the final emission
        await Future.delayed(Duration.zero);

        // BehaviorSubject emits current value immediately on listen,
        // then connectingMachine, then ready
        expect(phases, [
          ConnectionPhase.idle, // initial from BehaviorSubject
          ConnectionPhase.connectingMachine,
          ConnectionPhase.ready,
        ]);

        await sub.cancel();
      });

      test('emits error and reverts to idle on failure', () async {
        mockDe1Controller.shouldFailConnect = true;
        final fakeDe1 = _FakeDe1(deviceId: 'err-de1');

        final phases = <ConnectionPhase>[];
        final errors = <String?>[];
        final sub = connectionManager.status.listen((s) {
          phases.add(s.phase);
          errors.add(s.error);
        });

        try {
          await connectionManager.connectMachine(fakeDe1);
        } catch (_) {}
        await Future.delayed(Duration.zero);

        expect(phases, [
          ConnectionPhase.idle, // initial
          ConnectionPhase.connectingMachine,
          ConnectionPhase.idle, // reverted on error
        ]);
        expect(errors.last, isNotNull);
        expect(errors.last, contains('simulated connection failure'));

        await sub.cancel();
      });
    });

    group('connectScale', () {
      test('delegates to ScaleController and saves preference on success',
          () async {
        final testScale = TestScale(deviceId: 'my-scale');
        await connectionManager.connectScale(testScale);

        expect(mockScaleController.connectCalls, hasLength(1));
        expect(mockScaleController.connectCalls.first, same(testScale));
        expect(settingsController.preferredScaleId, 'my-scale');
      });

      test('does not save preference on failure (silent)', () async {
        mockScaleController.shouldFailConnect = true;
        final testScale = TestScale(deviceId: 'fail-scale');

        // Should NOT throw
        await connectionManager.connectScale(testScale);

        expect(settingsController.preferredScaleId, isNull);
      });

      test('rejects concurrent scale connection attempts', () async {
        final completer = Completer<void>();
        final slowScaleController =
            _SlowMockScaleController();
        slowScaleController.connectCompleter = completer;

        final manager = ConnectionManager(
          deviceController: deviceController,
          de1Controller: mockDe1Controller,
          scaleController: slowScaleController,
          settingsController: settingsController,
        );

        final testScale = TestScale(deviceId: 'scale-1');

        // Start first connection (will block on completer)
        final future1 = manager.connectScale(testScale);

        // Second call should return immediately (guard)
        final future2 =
            manager.connectScale(TestScale(deviceId: 'scale-2'));
        await future2; // Should complete immediately

        // Only one call should have been made
        expect(slowScaleController.connectCalls, hasLength(1));

        // Complete the first connection
        completer.complete();
        await future1;

        expect(slowScaleController.connectCalls, hasLength(1));

        manager.dispose();
      });

      test('emits connectingScale then ready phases', () async {
        final phases = <ConnectionPhase>[];
        final sub = connectionManager.status.listen((s) {
          phases.add(s.phase);
        });

        final testScale = TestScale(deviceId: 'phase-scale');
        await connectionManager.connectScale(testScale);
        await Future.delayed(Duration.zero);

        expect(phases, [
          ConnectionPhase.idle, // initial from BehaviorSubject
          ConnectionPhase.connectingScale,
          ConnectionPhase.ready,
        ]);

        await sub.cancel();
      });

      test('stays at idle on failure when no machine connected', () async {
        mockScaleController.shouldFailConnect = true;

        final phases = <ConnectionPhase>[];
        final sub = connectionManager.status.listen((s) {
          phases.add(s.phase);
        });

        final testScale = TestScale(deviceId: 'fail-scale');
        await connectionManager.connectScale(testScale);
        await Future.delayed(Duration.zero);

        expect(phases, [
          ConnectionPhase.idle, // initial
          ConnectionPhase.connectingScale,
          ConnectionPhase.idle, // no machine connected, so idle
        ]);

        // Error should be null (silently handled)
        expect(connectionManager.currentStatus.error, isNull);

        await sub.cancel();
      });
    });
  });
}

/// A De1Controller mock that uses a Completer to control when connectToDe1 completes.
class _SlowMockDe1Controller extends MockDe1Controller {
  Completer<void>? connectCompleter;

  _SlowMockDe1Controller({required super.controller});

  @override
  Future<void> connectToDe1(De1Interface de1Interface) async {
    connectCalls.add(de1Interface);
    if (connectCompleter != null) {
      await connectCompleter!.future;
    }
    de1Subject.add(de1Interface);
  }
}

/// A ScaleController mock that uses a Completer to control when connectToScale completes.
class _SlowMockScaleController extends MockScaleController {
  Completer<void>? connectCompleter;

  _SlowMockScaleController();

  @override
  Future<void> connectToScale(scale) async {
    connectCalls.add(scale);
    if (connectCompleter != null) {
      await connectCompleter!.future;
    }
    connectionStateSubject.add(ConnectionState.connected);
  }
}
