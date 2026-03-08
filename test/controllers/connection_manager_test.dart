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
class _FakeDe1 implements De1Interface {
  @override
  final String deviceId;

  _FakeDe1({this.deviceId = 'fake-de1'});

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
    late MockDeviceDiscoveryService discoveryService;
    late DeviceController deviceController;
    late MockScaleController mockScaleController;

    setUp(() {
      discoveryService = MockDeviceDiscoveryService();
      deviceController = DeviceController([discoveryService]);
      mockScaleController = MockScaleController(controller: deviceController);
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

    test('does not auto-connect when devices appear', () async {
      // Add a scale to discovery — the mock should NOT auto-connect
      final testScale = TestScale(deviceId: 'auto-scale');
      discoveryService.addDevice(testScale);

      // Give the stream time to propagate
      await Future.delayed(Duration.zero);

      expect(mockScaleController.connectCalls, isEmpty);
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
      mockScaleController = MockScaleController(controller: deviceController);
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
            _SlowMockScaleController(controller: deviceController);
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

      test('stays at ready phase on failure (non-blocking)', () async {
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
          ConnectionPhase.ready, // non-blocking failure
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

  _SlowMockScaleController({required super.controller});

  @override
  Future<void> connectToScale(scale) async {
    connectCalls.add(scale);
    if (connectCompleter != null) {
      await connectCompleter!.future;
    }
    connectionStateSubject.add(ConnectionState.connected);
  }
}
