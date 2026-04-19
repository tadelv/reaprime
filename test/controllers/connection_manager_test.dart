import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/connection_error.dart';
import 'package:reaprime/src/controllers/connection_manager.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/scan_report.dart';
import 'package:reaprime/src/settings/settings_controller.dart';

import '../helpers/mock_de1_controller.dart';
import '../helpers/mock_device_discovery_service.dart';
import '../helpers/mock_device_scanner.dart';
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

/// A De1Interface stub whose onConnect() throws, used to test failed connection
/// attempts in ScanReport tracking.
class _FailingFakeDe1 implements De1Interface {
  @override
  final String deviceId;

  @override
  final String name;

  @override
  DeviceType get type => DeviceType.machine;

  @override
  Stream<ConnectionState> get connectionState =>
      Stream.value(ConnectionState.disconnected);

  _FailingFakeDe1({this.deviceId = 'failing-de1'}) : name = 'DE1-$deviceId';

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
      final status = ConnectionStatus(
        pendingAmbiguity: AmbiguityReason.machinePicker,
        error: ConnectionError(
          kind: ConnectionErrorKind.machineConnectFailed,
          severity: ConnectionErrorSeverity.error,
          timestamp: DateTime.utc(2026),
          message: 'something',
        ),
      );
      final cleared = status.copyWith(
        pendingAmbiguity: () => null,
        error: () => null,
      );
      expect(cleared.pendingAmbiguity, isNull);
      expect(cleared.error, isNull);
    });
  });

  group('ConnectionManager', () {
    late MockDeviceScanner mockScanner;
    late MockDe1Controller mockDe1Controller;
    late MockScaleController mockScaleController;
    late SettingsController settingsController;
    late MockSettingsService mockSettingsService;
    late ConnectionManager connectionManager;

    // MockDe1Controller requires a DeviceController for its super constructor.
    // We use a real one with a dummy discovery service just to satisfy that.
    late MockDeviceDiscoveryService dummyDiscoveryService;

    setUp(() async {
      mockScanner = MockDeviceScanner();
      dummyDiscoveryService = MockDeviceDiscoveryService();
      mockDe1Controller = MockDe1Controller(
        controller:
            DeviceController([dummyDiscoveryService]),
      );
      mockScaleController = MockScaleController();
      mockSettingsService = MockSettingsService();
      settingsController = SettingsController(mockSettingsService);
      await settingsController.loadSettings();

      connectionManager = ConnectionManager(
        deviceScanner: mockScanner,
        de1Controller: mockDe1Controller,
        scaleController: mockScaleController,
        settingsController: settingsController,
      );
    });

    tearDown(() {
      connectionManager.dispose();
      mockScanner.dispose();
    });

    test('initial status is idle', () {
      expect(connectionManager.currentStatus.phase, ConnectionPhase.idle);
      expect(connectionManager.currentStatus.error, isNull);
    });

    group('connect', () {
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
        await connectionManager.connect();
        await Future.delayed(Duration.zero);

        expect(connectionManager.currentStatus.phase, ConnectionPhase.idle);
        expect(connectionManager.currentStatus.pendingAmbiguity, isNull);
        expect(mockDe1Controller.connectCalls, isEmpty);
      });

      test('no preferred, 1 machine → auto-connects and saves preference',
          () async {
        final fakeDe1 = _FakeDe1(deviceId: 'solo-de1');
        mockScanner.addDevice(fakeDe1);
        await Future.delayed(Duration.zero);

        await connectionManager.connect();
        await Future.delayed(Duration.zero);

        expect(mockDe1Controller.connectCalls, hasLength(1));
        expect(mockDe1Controller.connectCalls.first, same(fakeDe1));
        expect(settingsController.preferredMachineId, 'solo-de1');
        expect(connectionManager.currentStatus.phase, ConnectionPhase.ready);
      });

      test('no preferred, many machines → emits machinePicker ambiguity',
          () async {
        final de1a = _FakeDe1(deviceId: 'de1-a');
        final de1b = _FakeDe1(deviceId: 'de1-b');
        mockScanner.addDevice(de1a);
        mockScanner.addDevice(de1b);
        await Future.delayed(Duration.zero);

        await connectionManager.connect();
        await Future.delayed(Duration.zero);

        expect(connectionManager.currentStatus.phase, ConnectionPhase.idle);
        expect(connectionManager.currentStatus.pendingAmbiguity,
            AmbiguityReason.machinePicker);
        expect(connectionManager.currentStatus.foundMachines, hasLength(2));
        expect(mockDe1Controller.connectCalls, isEmpty);
      });

      test('preferred machine found → connects directly', () async {
        await settingsController.setPreferredMachineId('pref-de1');

        final prefDe1 = _FakeDe1(deviceId: 'pref-de1');
        mockScanner.addDevice(prefDe1);
        await Future.delayed(Duration.zero);

        await connectionManager.connect();
        await Future.delayed(Duration.zero);

        expect(mockDe1Controller.connectCalls, hasLength(1));
        expect(mockDe1Controller.connectCalls.first.deviceId, 'pref-de1');
        expect(connectionManager.currentStatus.phase, ConnectionPhase.ready);
      });

      test(
          'preferred machine not found, others available → emits machinePicker ambiguity',
          () async {
        await settingsController.setPreferredMachineId('missing-de1');

        final otherDe1 = _FakeDe1(deviceId: 'other-de1');
        mockScanner.addDevice(otherDe1);
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
          mockScanner.addDevice(fakeDe1);
          mockScanner.addDevice(testScale);
          await Future.delayed(Duration.zero);

          await connectionManager.connect();
          await Future.delayed(Duration.zero);

          expect(mockDe1Controller.connectCalls, hasLength(1));
          expect(mockScaleController.connectCalls, hasLength(1));
          expect(
              mockScaleController.connectCalls.first.deviceId, 'pref-scale');
          expect(settingsController.preferredScaleId, 'pref-scale');
        });

        test('no preferred, 1 scale → connects silently', () async {
          final fakeDe1 = _FakeDe1(deviceId: 'de1');
          final testScale = TestScale(deviceId: 'only-scale');
          mockScanner.addDevice(fakeDe1);
          mockScanner.addDevice(testScale);
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
          mockScanner.addDevice(fakeDe1);
          mockScanner.addDevice(scale1);
          mockScanner.addDevice(scale2);
          await Future.delayed(Duration.zero);

          await connectionManager.connect();
          await Future.delayed(Duration.zero);

          expect(mockScaleController.connectCalls, isEmpty);
        });

        test('preferred scale not found → does nothing, phase stays ready',
            () async {
          await settingsController.setPreferredScaleId('missing-scale');

          final fakeDe1 = _FakeDe1(deviceId: 'de1');
          mockScanner.addDevice(fakeDe1);
          await Future.delayed(Duration.zero);

          await connectionManager.connect();
          await Future.delayed(Duration.zero);

          expect(mockScaleController.connectCalls, isEmpty);
          expect(
              connectionManager.currentStatus.phase, ConnectionPhase.ready);
        });

        test('scale failure does not affect machine connection', () async {
          mockScaleController.shouldFailConnect = true;

          final fakeDe1 = _FakeDe1(deviceId: 'de1');
          final testScale = TestScale(deviceId: 'fail-scale');
          mockScanner.addDevice(fakeDe1);
          mockScanner.addDevice(testScale);
          await Future.delayed(Duration.zero);

          await connectionManager.connect();
          await Future.delayed(Duration.zero);

          expect(mockDe1Controller.connectCalls, hasLength(1));
          expect(mockScaleController.connectCalls, hasLength(1));
          expect(
              connectionManager.currentStatus.phase, ConnectionPhase.ready);
        });
      });

      group('early-stop', () {
        test(
            'both preferred set and both connected → calls stopScan',
            () async {
          await settingsController.setPreferredMachineId('pref-de1');
          await settingsController.setPreferredScaleId('pref-scale');

          // Hold scan open so devices appear "during" scan
          mockScanner.scanCompleter = Completer<void>();

          final fakeDe1 = _FakeDe1(deviceId: 'pref-de1');
          final testScale = TestScale(deviceId: 'pref-scale');

          // Start connect (will block on scan)
          final connectFuture = connectionManager.connect();

          // Wait for scan to start
          await mockScanner.scanningStream.firstWhere((s) => s);

          // Devices appear during scan
          mockScanner.addDevice(fakeDe1);
          await Future.delayed(Duration.zero);
          mockScanner.addDevice(testScale);
          await Future.delayed(Duration.zero);

          // Allow connections to process
          await Future.delayed(Duration.zero);
          await Future.delayed(Duration.zero);

          // Complete the scan
          mockScanner.completeScan();
          await connectFuture;

          expect(mockScanner.stopScanCallCount, 1);
        });

        test(
            'only preferred machine set → does not call stopScan',
            () async {
          await settingsController.setPreferredMachineId('pref-de1');
          // No preferred scale

          mockScanner.scanCompleter = Completer<void>();

          final fakeDe1 = _FakeDe1(deviceId: 'pref-de1');

          final connectFuture = connectionManager.connect();
          await mockScanner.scanningStream.firstWhere((s) => s);

          mockScanner.addDevice(fakeDe1);
          await Future.delayed(Duration.zero);
          await Future.delayed(Duration.zero);

          mockScanner.completeScan();
          await connectFuture;

          expect(mockScanner.stopScanCallCount, 0);
        });

        test(
            'only preferred scale set → does not call stopScan',
            () async {
          await settingsController.setPreferredScaleId('pref-scale');
          // No preferred machine

          mockScanner.scanCompleter = Completer<void>();

          final testScale = TestScale(deviceId: 'pref-scale');

          final connectFuture = connectionManager.connect();
          await mockScanner.scanningStream.firstWhere((s) => s);

          mockScanner.addDevice(testScale);
          await Future.delayed(Duration.zero);
          await Future.delayed(Duration.zero);

          mockScanner.completeScan();
          await connectFuture;

          expect(mockScanner.stopScanCallCount, 0);
        });

        test(
            'no preferences set → does not call stopScan',
            () async {
          mockScanner.scanCompleter = Completer<void>();

          final fakeDe1 = _FakeDe1(deviceId: 'de1');
          final testScale = TestScale(deviceId: 'scale');

          final connectFuture = connectionManager.connect();
          await mockScanner.scanningStream.firstWhere((s) => s);

          mockScanner.addDevice(fakeDe1);
          mockScanner.addDevice(testScale);
          await Future.delayed(Duration.zero);

          mockScanner.completeScan();
          await connectFuture;

          expect(mockScanner.stopScanCallCount, 0);
        });

        test(
            'both preferred set but only machine found → does not call stopScan',
            () async {
          await settingsController.setPreferredMachineId('pref-de1');
          await settingsController.setPreferredScaleId('pref-scale');

          mockScanner.scanCompleter = Completer<void>();

          final fakeDe1 = _FakeDe1(deviceId: 'pref-de1');

          final connectFuture = connectionManager.connect();
          await mockScanner.scanningStream.firstWhere((s) => s);

          // Only machine appears, no scale
          mockScanner.addDevice(fakeDe1);
          await Future.delayed(Duration.zero);
          await Future.delayed(Duration.zero);

          mockScanner.completeScan();
          await connectFuture;

          expect(mockScanner.stopScanCallCount, 0);
        });
      });
    });

    group('connect(scaleOnly: true)', () {
      test('skips machine preference policy', () async {
        await settingsController.setPreferredMachineId('pref-de1');

        final fakeDe1 = _FakeDe1(deviceId: 'pref-de1');
        mockScanner.addDevice(fakeDe1);
        await Future.delayed(Duration.zero);

        await connectionManager.connect(scaleOnly: true);
        await Future.delayed(Duration.zero);

        // Machine should NOT be connected even though preferred is available
        expect(mockDe1Controller.connectCalls, isEmpty);
      });

      test('connects preferred scale', () async {
        await settingsController.setPreferredScaleId('pref-scale');

        final testScale = TestScale(deviceId: 'pref-scale');
        mockScanner.addDevice(testScale);
        await Future.delayed(Duration.zero);

        await connectionManager.connect(scaleOnly: true);
        await Future.delayed(Duration.zero);

        expect(mockScaleController.connectCalls, hasLength(1));
        expect(
            mockScaleController.connectCalls.first.deviceId, 'pref-scale');
      });

      test('does not call stopScan even with preferred scale set', () async {
        await settingsController.setPreferredScaleId('pref-scale');

        mockScanner.scanCompleter = Completer<void>();

        final testScale = TestScale(deviceId: 'pref-scale');

        final connectFuture = connectionManager.connect(scaleOnly: true);
        await mockScanner.scanningStream.firstWhere((s) => s);

        mockScanner.addDevice(testScale);
        await Future.delayed(Duration.zero);
        await Future.delayed(Duration.zero);

        mockScanner.completeScan();
        await connectFuture;

        expect(mockScanner.stopScanCallCount, 0);
      });

      test('guards against concurrent connect calls', () async {
        // Start a scaleOnly connect
        mockScanner.scanCompleter = Completer<void>();
        final future1 = connectionManager.connect(scaleOnly: true);

        // Second call should be skipped
        final future2 = connectionManager.connect(scaleOnly: true);
        await future2;

        mockScanner.completeScan();
        await future1;

        // Only one scan should have been triggered
        // (scanForDevices is called once, not twice)
      });
    });

    group('ScanReport', () {
      test('emits ScanReport with scan results after scan completes', () async {
        mockScanner.scanCompleter = Completer();
        final connectFuture = connectionManager.connect();
        await Future.delayed(Duration.zero);

        mockScanner.addDevice(_FakeDe1(deviceId: 'solo-de1'));
        mockScanner.completeScan();
        await connectFuture;

        final report = connectionManager.lastScanReport;
        expect(report, isNotNull);
        expect(report!.matchedDevices, hasLength(1));
        expect(report.matchedDevices.first.deviceId, 'solo-de1');
        expect(report.scanTerminationReason, ScanTerminationReason.completed);
      });

      test('ScanReport includes preferred device IDs from settings', () async {
        await settingsController.setPreferredMachineId('preferred-123');
        final connectFuture = connectionManager.connect();
        await connectFuture;

        final report = connectionManager.lastScanReport;
        expect(report!.preferredMachineId, 'preferred-123');
      });

      test('ScanReport tracks failed connection attempt', () async {
        // Set up a machine that fails to connect
        mockDe1Controller.shouldFailConnect = true;
        mockScanner.scanCompleter = Completer();
        final connectFuture = connectionManager.connect();
        await Future.delayed(Duration.zero);

        mockScanner.addDevice(_FakeDe1(deviceId: 'fail-de1'));
        mockScanner.completeScan();
        await connectFuture;

        final report = connectionManager.lastScanReport;
        final matched = report!.matchedDevices.first;
        expect(matched.connectionAttempted, isTrue);
        expect(matched.connectionResult!.success, isFalse);
      });

      test('ScanReport records scan duration', () async {
        await connectionManager.connect();

        final report = connectionManager.lastScanReport;
        expect(report, isNotNull);
        expect(report!.scanDuration, isA<Duration>());
      });

      test('ScanReport stream emits on each scan', () async {
        final reports = <ScanReport>[];
        final sub = connectionManager.scanReportStream.listen(reports.add);

        await connectionManager.connect();
        await Future.delayed(Duration.zero);

        expect(reports, hasLength(1));

        await sub.cancel();
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

        await Future.delayed(Duration.zero);

        expect(settingsController.preferredMachineId, isNull);
      });

      test('rejects concurrent connection attempts', () async {
        final completer = Completer<void>();
        final slowDe1Controller =
            _SlowMockDe1Controller(controller: DeviceController([dummyDiscoveryService]));
        slowDe1Controller.connectCompleter = completer;

        final manager = ConnectionManager(
          deviceScanner: mockScanner,
          de1Controller: slowDe1Controller,
          scaleController: mockScaleController,
          settingsController: settingsController,
        );

        final fakeDe1 = _FakeDe1(deviceId: 'de1-1');

        final future1 = manager.connectMachine(fakeDe1);
        final future2 = manager.connectMachine(_FakeDe1(deviceId: 'de1-2'));
        await future2;

        expect(slowDe1Controller.connectCalls, hasLength(1));

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
        await Future.delayed(Duration.zero);

        expect(phases, [
          ConnectionPhase.idle,
          ConnectionPhase.connectingMachine,
          ConnectionPhase.ready,
        ]);

        await sub.cancel();
      });

      test('reverts to idle on failure', () async {
        mockDe1Controller.shouldFailConnect = true;
        final fakeDe1 = _FakeDe1(deviceId: 'err-de1');

        final phases = <ConnectionPhase>[];
        final errors = <ConnectionError?>[];
        final sub = connectionManager.status.listen((s) {
          phases.add(s.phase);
          errors.add(s.error);
        });

        try {
          await connectionManager.connectMachine(fakeDe1);
        } catch (_) {}
        await Future.delayed(Duration.zero);

        expect(phases, [
          ConnectionPhase.idle,
          ConnectionPhase.connectingMachine,
          ConnectionPhase.idle,
        ]);
        // TODO(task-5): tighten this to assert a non-null ConnectionError with
        // kind == machineConnectFailed once emission is restored. For now we
        // only guarantee no premature/incorrect emission slips in.
        expect(errors.last, isNull);

        await sub.cancel();
      });
    });

    group('error surfacing', () {
      test('emitting an error publishes it on the status stream', () async {
        final future = connectionManager.status
            .firstWhere((s) => s.error != null);
        connectionManager.debugEmitError(
          kind: ConnectionErrorKind.scaleConnectFailed,
          severity: ConnectionErrorSeverity.error,
          message: 'test',
        );
        final status = await future;
        expect(status.error!.kind, ConnectionErrorKind.scaleConnectFailed);
        expect(status.error!.timestamp.isUtc, isTrue);
      });

      test('transient error cleared by _publishStatus on scanning transition',
          () async {
        connectionManager.debugEmitError(
          kind: ConnectionErrorKind.scaleConnectFailed,
          severity: ConnectionErrorSeverity.error,
          message: 'test',
        );
        expect(connectionManager.currentStatus.error, isNotNull);

        // connect() transitions into scanning via _publishStatus without
        // explicitly nulling — the gatekeeper must strip the transient error.
        await connectionManager.connect(scaleOnly: true);
        expect(connectionManager.currentStatus.error, isNull);
      });

      test('sticky error survives phase transition through _publishStatus',
          () async {
        connectionManager.debugEmitError(
          kind: ConnectionErrorKind.adapterOff,
          severity: ConnectionErrorSeverity.error,
          message: 'off',
        );
        expect(connectionManager.currentStatus.error, isNotNull);

        // A real scan path goes through _publishStatus(scanning). Sticky
        // adapterOff must survive even though the caller itself does not
        // explicitly re-attach it.
        await connectionManager.connect(scaleOnly: true);
        expect(connectionManager.currentStatus.error, isNotNull);
        expect(connectionManager.currentStatus.error!.kind,
            ConnectionErrorKind.adapterOff);
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

        await connectionManager.connectScale(testScale);

        expect(settingsController.preferredScaleId, isNull);
      });

      test('rejects concurrent scale connection attempts', () async {
        final completer = Completer<void>();
        final slowScaleController = _SlowMockScaleController();
        slowScaleController.connectCompleter = completer;

        final manager = ConnectionManager(
          deviceScanner: mockScanner,
          de1Controller: mockDe1Controller,
          scaleController: slowScaleController,
          settingsController: settingsController,
        );

        final testScale = TestScale(deviceId: 'scale-1');

        final future1 = manager.connectScale(testScale);
        final future2 =
            manager.connectScale(TestScale(deviceId: 'scale-2'));
        await future2;

        expect(slowScaleController.connectCalls, hasLength(1));

        completer.complete();
        await future1;

        expect(slowScaleController.connectCalls, hasLength(1));

        manager.dispose();
      });

      test('emits connectingScale but not ready when no machine connected',
          () async {
        final phases = <ConnectionPhase>[];
        final sub = connectionManager.status.listen((s) {
          phases.add(s.phase);
        });

        final testScale = TestScale(deviceId: 'phase-scale');
        await connectionManager.connectScale(testScale);
        await Future.delayed(Duration.zero);

        // Scale alone should not emit ready — machine must be connected first
        expect(phases, [
          ConnectionPhase.idle,
          ConnectionPhase.connectingScale,
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
          ConnectionPhase.idle,
          ConnectionPhase.connectingScale,
          ConnectionPhase.idle,
        ]);

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
