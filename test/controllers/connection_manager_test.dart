import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/connection_error.dart';
import 'package:reaprime/src/controllers/connection_manager.dart';
import 'package:reaprime/src/controllers/remembered_devices_controller.dart';
import 'package:reaprime/src/models/device/remembered_device.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/models/adapter_state.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/transport/ble_connect_exception.dart';
import 'package:reaprime/src/models/device/device_implementation.dart';
import 'package:reaprime/src/models/device/transport/data_transport.dart';
import 'package:reaprime/src/models/errors.dart';
import 'package:reaprime/src/models/scan_report.dart';
import 'package:reaprime/src/settings/scale_power_mode.dart';
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
  final StreamController<MachineSnapshot> _snapshotController =
      StreamController<MachineSnapshot>.broadcast();

  @override
  final String deviceId;

  @override
  final String name;

  @override
  DeviceType get type => DeviceType.machine;

  @override
  DeviceImplementation get implementation => DeviceImplementation.unifiedDe1;

  @override
  TransportType get transportType => TransportType.unknown;

  @override
  Stream<ConnectionState> get connectionState =>
      Stream.value(ConnectionState.connected);

  @override
  Stream<MachineSnapshot> get currentSnapshot => _snapshotController.stream;

  // Non-null so De1Controller.adoptDevice (quick-connect) can subscribe
  // and De1Controller.dispose can await teardown of an adopted device.
  @override
  Stream<bool> get ready => const Stream.empty();

  @override
  Future<void> dispose() async {}

  _FakeDe1({this.deviceId = 'fake-de1'}) : name = 'DE1-$deviceId';

  void emitState(MachineState state) {
    _snapshotController.add(_machineSnapshot(state));
  }

  @override
  Future<void> disconnect() async {}

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
  DeviceImplementation get implementation => DeviceImplementation.unifiedDe1;

  @override
  TransportType get transportType => TransportType.unknown;

  @override
  Stream<ConnectionState> get connectionState =>
      Stream.value(ConnectionState.disconnected);

  @override
  Stream<MachineSnapshot> get currentSnapshot => const Stream.empty();

  _FailingFakeDe1({this.deviceId = 'failing-de1'}) : name = 'DE1-$deviceId';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

MachineSnapshot _machineSnapshot(MachineState state) {
  return MachineSnapshot(
    timestamp: DateTime.utc(2026),
    state: MachineStateSnapshot(state: state, substate: MachineSubstate.idle),
    flow: 0,
    pressure: 0,
    targetFlow: 0,
    targetPressure: 0,
    mixTemperature: 0,
    groupTemperature: 0,
    targetMixTemperature: 0,
    targetGroupTemperature: 0,
    profileFrame: 0,
    steamTemperature: 0,
  );
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

      // Gap A — comms-harden #4: after a scale connect failure, a
      // subsequent connect() must re-attempt the scale. Current code
      // happens to pass this because _scaleConnected is guarded behind
      // a successful `await scaleController.connectToScale(...)`, but
      // the invariant must survive the Phase 2 state-derivation
      // refactor. These tests pin the contract.
      //
      // See: doc/plans/comms-harden.md #4,
      //      doc/plans/comms-phase-0-1.md Gap A.
      group('scale failure recovery (comms-harden #4)', () {
        test('after scaleOnly connect fails, next connect retries scale',
            () async {
          mockScaleController.shouldFailConnect = true;

          final scale = TestScale(deviceId: 'scale-1');
          mockScanner.addDevice(scale);
          await Future.delayed(Duration.zero);

          await connectionManager.connect(scaleOnly: true);
          await Future.delayed(Duration.zero);
          expect(mockScaleController.connectCalls, hasLength(1),
              reason: 'first scaleOnly attempt should call connectToScale');

          mockScaleController.shouldFailConnect = false;
          await connectionManager.connect(scaleOnly: true);
          await Future.delayed(Duration.zero);

          expect(mockScaleController.connectCalls, hasLength(2),
              reason:
                  'scale must be retried after a prior failed scaleOnly connect');
        });

        test(
            'after full connect fails on scale phase, next scaleOnly retries',
            () async {
          mockScaleController.shouldFailConnect = true;

          final fakeDe1 = _FakeDe1(deviceId: 'de1');
          final scale = TestScale(deviceId: 'scale-1');
          mockScanner.addDevice(fakeDe1);
          mockScanner.addDevice(scale);
          await Future.delayed(Duration.zero);

          await connectionManager.connect();
          await Future.delayed(Duration.zero);
          expect(mockScaleController.connectCalls, hasLength(1),
              reason: 'full connect reaches scale phase on first attempt');

          mockScaleController.shouldFailConnect = false;
          await connectionManager.connect(scaleOnly: true);
          await Future.delayed(Duration.zero);

          expect(mockScaleController.connectCalls, hasLength(2),
              reason:
                  'scale phase must retry after a prior full-connect failure');
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
            'only preferred machine set → calls stopScan on machine connect',
            () async {
          await settingsController.setPreferredMachineId('pref-de1');
          // No preferred scale — scan should stop as soon as machine connects.

          mockScanner.scanCompleter = Completer<void>();

          final fakeDe1 = _FakeDe1(deviceId: 'pref-de1');

          final connectFuture = connectionManager.connect();
          await mockScanner.scanningStream.firstWhere((s) => s);

          mockScanner.addDevice(fakeDe1);
          await Future.delayed(Duration.zero);
          await Future.delayed(Duration.zero);

          mockScanner.completeScan();
          await connectFuture;

          expect(mockScanner.stopScanCallCount, 1);
        });

        test(
            'only preferred machine, scale advertises after early-stop → '
            'deferred rescan connects it',
            () async {
          await settingsController.setPreferredMachineId('pref-de1');
          // No preferred scale. Fire the deferred rescan immediately.
          connectionManager.deferredScaleScanDelay = Duration.zero;

          mockScanner.scanCompleter = Completer<void>();

          final fakeDe1 = _FakeDe1(deviceId: 'pref-de1');

          final connectFuture = connectionManager.connect();
          await mockScanner.scanningStream.firstWhere((s) => s);

          // Machine early-connects; scan stops before any scale appears.
          mockScanner.addDevice(fakeDe1);
          await Future.delayed(Duration.zero);
          await Future.delayed(Duration.zero);

          mockScanner.completeScan();
          await connectFuture;

          // First pass: machine connected (ready), no scale connected,
          // scan stopped early. Rescan is armed in the background.
          expect(mockScanner.stopScanCallCount, 1);
          expect(mockScaleController.connectCalls, isEmpty);
          expect(
              connectionManager.currentStatus.phase, ConnectionPhase.ready);

          // Scale shows up only now — after the early stop.
          mockScanner.addDevice(TestScale(deviceId: 'late-scale'));

          // Let the deferred rescan fire (zero delay) and its scan run.
          await Future.delayed(const Duration(milliseconds: 1));
          await Future.delayed(Duration.zero);
          await Future.delayed(Duration.zero);
          await Future.delayed(Duration.zero);

          expect(mockScaleController.connectCalls, hasLength(1),
              reason: 'deferred rescan must connect the late scale');
          expect(
              mockScaleController.connectCalls.first.deviceId, 'late-scale');
          expect(
              connectionManager.currentStatus.phase, ConnectionPhase.ready);
        });

        test(
            'only preferred machine, no scale ever → deferred rescan is a '
            'no-op, machine stays ready',
            () async {
          await settingsController.setPreferredMachineId('pref-de1');
          connectionManager.deferredScaleScanDelay = Duration.zero;

          mockScanner.scanCompleter = Completer<void>();

          final fakeDe1 = _FakeDe1(deviceId: 'pref-de1');

          final connectFuture = connectionManager.connect();
          await mockScanner.scanningStream.firstWhere((s) => s);

          mockScanner.addDevice(fakeDe1);
          await Future.delayed(Duration.zero);
          await Future.delayed(Duration.zero);

          mockScanner.completeScan();
          await connectFuture;

          expect(
              connectionManager.currentStatus.phase, ConnectionPhase.ready);

          // Deferred rescan fires, finds no scale, leaves machine ready.
          await Future.delayed(const Duration(milliseconds: 1));
          await Future.delayed(Duration.zero);
          await Future.delayed(Duration.zero);
          await Future.delayed(Duration.zero);

          expect(mockScaleController.connectCalls, isEmpty);
          expect(
              connectionManager.currentStatus.phase, ConnectionPhase.ready);
        });

        test('machine disconnect cancels deferred scale rescan', () async {
          await settingsController.setPreferredMachineId('pref-de1');
          connectionManager.deferredScaleScanDelay =
              const Duration(milliseconds: 10);
          mockScanner.scanCompleter = Completer<void>();

          final fakeDe1 = _FakeDe1(deviceId: 'pref-de1');
          final connectFuture = connectionManager.connect();
          await mockScanner.scanningStream.firstWhere((s) => s);

          mockScanner.addDevice(fakeDe1);
          await Future.delayed(Duration.zero);
          await Future.delayed(Duration.zero);
          mockScanner.completeScan();
          await connectFuture;

          final scanningEvents = <bool>[];
          final sub = mockScanner.scanningStream.listen(scanningEvents.add);
          await Future<void>.delayed(Duration.zero);

          mockDe1Controller.de1Subject.add(null);
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await Future<void>.delayed(Duration.zero);

          expect(scanningEvents, isNot(contains(true)));
          expect(mockScaleController.connectCalls, isEmpty);
          await sub.cancel();
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
            'full scan completed (no early stop) → no deferred rescan armed',
            () async {
          // No preferences → no early-stop. A single machine auto-connects
          // via post-scan policy; the full scan already saw every scale, so
          // a scale appearing afterwards must NOT be auto-connected by a
          // rescan that should never have been armed.
          connectionManager.deferredScaleScanDelay = Duration.zero;

          mockScanner.scanCompleter = Completer<void>();

          final fakeDe1 = _FakeDe1(deviceId: 'de1');

          final connectFuture = connectionManager.connect();
          await mockScanner.scanningStream.firstWhere((s) => s);

          mockScanner.addDevice(fakeDe1);
          await Future.delayed(Duration.zero);

          mockScanner.completeScan();
          await connectFuture;

          expect(mockScanner.stopScanCallCount, 0);
          expect(mockScaleController.connectCalls, isEmpty);

          // A scale shows up after the (completed) scan. With no early stop
          // there is no armed rescan, so it stays unconnected.
          mockScanner.addDevice(TestScale(deviceId: 'late-scale'));
          await Future.delayed(const Duration(milliseconds: 1));
          await Future.delayed(Duration.zero);
          await Future.delayed(Duration.zero);

          expect(mockScaleController.connectCalls, isEmpty,
              reason: 'a completed full scan must not arm a deferred rescan');
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

      test(
          'auto-scans for preferred scale when machine is ready and scale is missing',
          () async {
        await settingsController.setPreferredScaleId('pref-scale');
        mockScanner.scanCompleter = Completer<void>();

        mockDe1Controller.de1Subject.add(_FakeDe1(deviceId: 'connected-de1'));
        await mockScanner.scanningStream.firstWhere((s) => s);

        final testScale = TestScale(deviceId: 'pref-scale');
        mockScanner.addDevice(testScale);
        await Future.delayed(Duration.zero);
        await Future.delayed(Duration.zero);

        expect(mockScaleController.connectCalls, hasLength(1));
        expect(mockScaleController.connectCalls.first.deviceId, 'pref-scale');
        expect(mockScanner.stopScanCallCount, 0);

        mockScanner.completeScan();
        await Future.delayed(Duration.zero);
      });

      test(
          'concurrent scaleOnly during another connect is queued and '
          'drained after the in-flight call (comms-harden #9)', () async {
        // Start a scaleOnly connect that will block on the scan
        // completer for deterministic timing.
        mockScanner.scanCompleter = Completer<void>();
        final future1 = connectionManager.connect(scaleOnly: true);

        // Second and third scaleOnly calls arrive while the first is
        // mid-scan. They must return Futures that complete after the
        // drain runs the scale-only scan.
        final future2 = connectionManager.connect(scaleOnly: true);
        final future3 = connectionManager.connect(scaleOnly: true);

        // No scan should have started for future2/future3 yet —
        // queued requests share the in-flight scan.
        await Future.delayed(Duration.zero);
        expect(future2, isA<Future<void>>());
        expect(future3, isA<Future<void>>());
        // future2 and future3 must share the same pending completer,
        // so they resolve at the same moment.
        var future2Done = false;
        var future3Done = false;
        future2.then((_) => future2Done = true);
        future3.then((_) => future3Done = true);
        await Future.delayed(Duration.zero);
        expect(future2Done, isFalse);
        expect(future3Done, isFalse);

        // Let the first scan finish. The drain runs a second scale-only
        // scan that resolves future2/future3.
        mockScanner.completeScan();
        await future1;
        // Second scan (the drain) runs its own scanForDevices call.
        // MockDeviceScanner.scanForDevices with no completer resolves
        // synchronously after a microtask, so await everything.
        await Future.delayed(Duration.zero);
        await Future.delayed(Duration.zero);

        await future2;
        await future3;
        expect(future2Done, isTrue);
        expect(future3Done, isTrue);
      });

      test(
          'non-scaleOnly concurrent connect is still dropped (no queue)',
          () async {
        mockScanner.scanCompleter = Completer<void>();
        final future1 = connectionManager.connect();

        // A full-connect call during another full-connect returns
        // immediately (silent drop), exactly as before.
        final future2 = connectionManager.connect();
        await future2;

        mockScanner.completeScan();
        await future1;
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

      test(
          'connect timeout: machine that never responds fails after 30s '
          '(comms-harden #31)',
          () {
        fakeAsync((async) {
          final completer = Completer<void>();
          final slowDe1Controller = _SlowMockDe1Controller(
              controller: DeviceController([dummyDiscoveryService]));
          slowDe1Controller.connectCompleter = completer;

          final manager = ConnectionManager(
            deviceScanner: mockScanner,
            de1Controller: slowDe1Controller,
            scaleController: mockScaleController,
            settingsController: settingsController,
          );

          final fakeDe1 = _FakeDe1(deviceId: 'timeout-de1');
          Object? caughtError;
          manager
              .connectMachine(fakeDe1)
              .catchError((e) => caughtError = e);

          // Advance past the 30s connect budget; the TimeoutException
          // in connectMachine should cause rethrow + machineConnectFailed.
          async.elapse(const Duration(seconds: 35));
          async.flushMicrotasks();

          expect(caughtError, isA<TimeoutException>(),
              reason: 'connectMachine must rethrow TimeoutException');
          final status = manager.currentStatus;
          expect(status.phase, ConnectionPhase.idle);
          expect(status.error?.kind, ConnectionErrorKind.machineConnectFailed);
          expect(
            status.error?.message,
            contains('did not respond within 30s'),
            reason: 'timeout-specific error message should surface',
          );

          manager.dispose();
        });
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

        // Two trailing idles: one from the phase revert, one from _emit
        // re-publishing the status with the structured error attached.
        expect(phases, [
          ConnectionPhase.idle,
          ConnectionPhase.connectingMachine,
          ConnectionPhase.idle,
          ConnectionPhase.idle,
        ]);
        final err = errors.last;
        expect(err, isNotNull);
        expect(err!.kind, ConnectionErrorKind.machineConnectFailed);
        expect(err.deviceId, 'err-de1');

        await sub.cancel();
      });

      test('emits machineConnectFailed on De1Controller.connectToDe1 throw',
          () async {
        mockDe1Controller.shouldFailConnect = true;
        final fakeDe1 = _FailingFakeDe1(deviceId: 'D9:11:0B:E6:9F:86');

        try {
          await connectionManager.connectMachine(fakeDe1);
        } catch (_) {
          // connectMachine rethrows — that's expected.
        }
        await Future<void>.delayed(Duration.zero);

        final err = connectionManager.currentStatus.error!;
        expect(err.kind, ConnectionErrorKind.machineConnectFailed);
        expect(err.deviceId, 'D9:11:0B:E6:9F:86');
        expect(err.deviceName, 'DE1-D9:11:0B:E6:9F:86');
        expect(err.severity, ConnectionErrorSeverity.error);
      });

      test(
          'emits machineConnectFailed with ble_code in details when '
          'BleConnectException thrown', () async {
        mockDe1Controller.failNextConnectWith = BleConnectException(
            code: '133', description: 'GATT Error 133', function: 'connect');
        final fakeDe1 = _FailingFakeDe1(deviceId: 'D9:11:0B:E6:9F:86');

        try {
          await connectionManager.connectMachine(fakeDe1);
        } catch (_) {}
        await Future<void>.delayed(Duration.zero);

        final err = connectionManager.currentStatus.error!;
        expect(err.details, containsPair('ble_code', '133'));
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

      test('does not save preference on failure', () async {
        mockScaleController.shouldFailConnect = true;
        final testScale = TestScale(deviceId: 'fail-scale');

        await connectionManager.connectScale(testScale);

        expect(settingsController.preferredScaleId, isNull);
        // Failure now surfaces a structured error (no longer silent).
        expect(connectionManager.currentStatus.error, isNotNull);
      });

      test('reports the real outcome so scan reports cannot claim success',
          () async {
        final okResult =
            await connectionManager.connectScale(TestScale(deviceId: 'ok'));
        expect(okResult.success, isTrue);

        mockScaleController.shouldFailConnect = true;
        final failResult = await connectionManager
            .connectScale(TestScale(deviceId: 'fail-scale'));
        expect(failResult.success, isFalse);
        expect(failResult.error, isNotNull);
      });

      test('emits scaleConnectFailed when the scale controller throws',
          () async {
        mockScaleController.shouldFailConnect = true;
        final fakeScale =
            TestScale(deviceId: '50:78:7D:1F:AE:E1', name: 'Decent Scale');

        await connectionManager.connectScale(fakeScale);

        final err = connectionManager.currentStatus.error;
        expect(err, isNotNull);
        expect(err!.kind, ConnectionErrorKind.scaleConnectFailed);
        expect(err.deviceId, '50:78:7D:1F:AE:E1');
        expect(err.deviceName, 'Decent Scale');
        expect(err.severity, ConnectionErrorSeverity.error);
      });

      test(
          'emits scaleConnectFailed with ble_code in details when '
          'BleConnectException thrown', () async {
        mockScaleController.failNextConnectWith = BleConnectException(
            code: 'connectionFailed', description: 'Timed out',
            function: 'connect');
        final fakeScale =
            TestScale(deviceId: '50:78:7D:1F:AE:E1', name: 'Decent Scale');

        await connectionManager.connectScale(fakeScale);

        final err = connectionManager.currentStatus.error!;
        expect(err.details, containsPair('ble_code', 'connectionFailed'));
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

      test(
          'emits scaleConnectFailed even when fallback phase is ready (machine connected)',
          () async {
        // Seed connected-machine state so the scale-fail catch falls through
        // to phase=ready (a clearing phase). The _emit must survive the
        // gatekeeper's strip rule — if ordering regresses, this test fails.
        final fakeMachine = _FakeDe1(deviceId: 'D9:11:0B:E6:9F:86');
        await connectionManager.connectMachine(fakeMachine);
        expect(connectionManager.currentStatus.phase, ConnectionPhase.ready);

        mockScaleController.shouldFailConnect = true;
        final fakeScale =
            TestScale(deviceId: '50:78:7D:1F:AE:E1', name: 'Decent Scale');
        await connectionManager.connectScale(fakeScale);

        expect(connectionManager.currentStatus.phase, ConnectionPhase.ready);
        expect(connectionManager.currentStatus.error, isNotNull);
        expect(connectionManager.currentStatus.error!.kind,
            ConnectionErrorKind.scaleConnectFailed);
      });

      test('sleep during scale connect settles back to ready', () async {
        await connectionManager.dispose();
        final slowScaleController = _SlowMockScaleController();
        connectionManager = ConnectionManager(
          deviceScanner: mockScanner,
          de1Controller: mockDe1Controller,
          scaleController: slowScaleController,
          settingsController: settingsController,
        );
        await settingsController.setScalePowerMode(ScalePowerMode.disconnect);

        final fakeMachine = _FakeDe1(deviceId: 'D9:11:0B:E6:9F:86');
        mockDe1Controller.de1Subject.add(fakeMachine);
        await Future<void>.delayed(Duration.zero);
        fakeMachine.emitState(MachineState.idle);
        await Future<void>.delayed(Duration.zero);

        final connectCompleter = Completer<void>();
        slowScaleController.connectCompleter = connectCompleter;
        final future =
            connectionManager.connectScale(TestScale(deviceId: 'pref-scale'));
        await Future<void>.delayed(Duration.zero);
        expect(connectionManager.currentStatus.phase,
            ConnectionPhase.connectingScale);

        fakeMachine.emitState(MachineState.sleeping);
        await Future<void>.delayed(Duration.zero);
        connectCompleter.complete();
        await future;
        await Future<void>.delayed(Duration.zero);

        expect(connectionManager.currentStatus.phase, ConnectionPhase.ready);
        expect(connectionManager.currentStatus.error, isNull);
        expect(settingsController.preferredScaleId, isNull);

        slowScaleController.mockEmitConnectionState(ConnectionState.disconnected);
        await Future<void>.delayed(Duration.zero);
        expect(connectionManager.currentStatus.error, isNull);
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

        // Two trailing idles: one from the phase revert, one from _emit
        // re-publishing on the same phase with the error attached.
        expect(phases, [
          ConnectionPhase.idle,
          ConnectionPhase.connectingScale,
          ConnectionPhase.idle,
          ConnectionPhase.idle,
        ]);

        final err = connectionManager.currentStatus.error;
        expect(err, isNotNull);
        expect(err!.kind, ConnectionErrorKind.scaleConnectFailed);

        await sub.cancel();
      });
    });

    group('deliberate disconnect tracking', () {
      test('markExpectingDisconnect suppresses next disconnect error', () {
        connectionManager.markExpectingDisconnect('50:78:7D:1F:AE:E1');
        connectionManager.debugNotifyScaleDisconnected('50:78:7D:1F:AE:E1');
        expect(connectionManager.currentStatus.error, isNull);
      });

      test('unexpected disconnect emits scaleDisconnected', () {
        connectionManager.debugNotifyScaleDisconnected('50:78:7D:1F:AE:E1');
        expect(connectionManager.currentStatus.error?.kind,
            ConnectionErrorKind.scaleDisconnected);
        expect(connectionManager.currentStatus.error?.deviceId,
            '50:78:7D:1F:AE:E1');
      });

      test('TTL clears expectation after 10 seconds', () {
        fakeAsync((async) {
          connectionManager.markExpectingDisconnect('50:78:7D:1F:AE:E1');
          async.elapse(const Duration(seconds: 11));
          connectionManager.debugNotifyScaleDisconnected('50:78:7D:1F:AE:E1');
          expect(connectionManager.currentStatus.error?.kind,
              ConnectionErrorKind.scaleDisconnected);
        });
      });

      test('only one matching disconnect is consumed per mark', () {
        connectionManager.markExpectingDisconnect('50:78:7D:1F:AE:E1');
        connectionManager.debugNotifyScaleDisconnected('50:78:7D:1F:AE:E1');
        expect(connectionManager.currentStatus.error, isNull);

        connectionManager.debugNotifyScaleDisconnected('50:78:7D:1F:AE:E1');
        expect(connectionManager.currentStatus.error?.kind,
            ConnectionErrorKind.scaleDisconnected);
      });

      test('marks for different devices are independent', () {
        connectionManager.markExpectingDisconnect('50:78:7D:1F:AE:E1');
        connectionManager.debugNotifyMachineDisconnected('D9:11:0B:E6:9F:86');
        expect(connectionManager.currentStatus.error?.kind,
            ConnectionErrorKind.machineDisconnected);
      });
    });

    group('disconnect subscribers', () {
      test('scale disconnect during expected flow suppresses error', () async {
        // Pretend scale was connected.
        mockScaleController
            .mockEmitConnectionState(ConnectionState.connected);
        mockScaleController.debugSetLastConnectedId('50:78:7D:1F:AE:E1');
        await Future<void>.delayed(Duration.zero);

        // Mark expected, then emit disconnect.
        connectionManager.markExpectingDisconnect('50:78:7D:1F:AE:E1');
        mockScaleController
            .mockEmitConnectionState(ConnectionState.disconnected);
        await Future<void>.delayed(Duration.zero);

        expect(connectionManager.currentStatus.error, isNull);
      });

      test('expected scale disconnect does not trigger preferred-scale scan',
          () async {
        await settingsController.setScalePowerMode(ScalePowerMode.disconnect);
        final fakeDe1 = _FakeDe1(deviceId: 'connected-de1');
        mockScaleController.mockEmitConnectionState(ConnectionState.connected);
        mockScaleController.debugSetLastConnectedId('pref-scale');
        await settingsController.setPreferredScaleId('pref-scale');
        mockDe1Controller.de1Subject.add(fakeDe1);
        await Future<void>.delayed(Duration.zero);
        fakeDe1.emitState(MachineState.sleeping);
        final scanningEvents = <bool>[];
        final sub = mockScanner.scanningStream.listen(scanningEvents.add);
        await Future<void>.delayed(Duration.zero);

        connectionManager.markExpectingDisconnect('pref-scale');
        mockScaleController.mockEmitConnectionState(ConnectionState.disconnected);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(connectionManager.currentStatus.error, isNull);
        expect(scanningEvents, isNot(contains(true)),
            reason: 'power-mode disconnects are deliberate and must not start BLE');
        expect(mockScaleController.connectCalls, isEmpty);
        await sub.cancel();
      });

      test('unexpected preferred scale disconnect keeps scanning and reconnects',
          () async {
        await settingsController.setPreferredScaleId('pref-scale');
        final fakeDe1 = _FakeDe1(deviceId: 'connected-de1');
        mockScaleController.mockEmitConnectionState(ConnectionState.connected);
        mockScaleController.debugSetLastConnectedId('pref-scale');
        mockDe1Controller.de1Subject.add(fakeDe1);
        await Future<void>.delayed(Duration.zero);
        fakeDe1.emitState(MachineState.idle);
        await Future<void>.delayed(Duration.zero);

        mockScanner.scanCompleter = Completer<void>();
        mockScaleController.mockEmitConnectionState(ConnectionState.disconnected);
        await mockScanner.scanningStream.firstWhere((s) => s);

        mockScanner.addDevice(TestScale(deviceId: 'pref-scale'));
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        mockScanner.completeScan();
        await Future<void>.delayed(Duration.zero);

        expect(mockScaleController.connectCalls, hasLength(1));
        expect(mockScaleController.connectCalls.first.deviceId, 'pref-scale');
      });

      test('scale power disconnect pauses while sleeping and resumes when awake',
          () async {
        await settingsController.setPreferredScaleId('pref-scale');
        await settingsController.setScalePowerMode(ScalePowerMode.disconnect);

        final fakeDe1 = _FakeDe1(deviceId: 'connected-de1');
        mockScaleController.mockEmitConnectionState(ConnectionState.connected);
        mockScaleController.debugSetLastConnectedId('pref-scale');
        mockDe1Controller.de1Subject.add(fakeDe1);
        await Future<void>.delayed(Duration.zero);
        fakeDe1.emitState(MachineState.idle);
        await Future<void>.delayed(Duration.zero);

        final scanningEvents = <bool>[];
        final sub = mockScanner.scanningStream.listen(scanningEvents.add);

        fakeDe1.emitState(MachineState.sleeping);
        connectionManager.markExpectingDisconnect('pref-scale');
        mockScaleController.mockEmitConnectionState(ConnectionState.disconnected);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(scanningEvents, isNot(contains(true)),
            reason: 'sleeping + ScalePowerMode.disconnect must not scan');

        mockScanner.scanCompleter = Completer<void>();
        fakeDe1.emitState(MachineState.idle);
        await mockScanner.scanningStream.firstWhere((s) => s);

        mockScanner.addDevice(TestScale(deviceId: 'pref-scale'));
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        mockScanner.completeScan();
        await Future<void>.delayed(Duration.zero);

        expect(mockScaleController.connectCalls, hasLength(1));
        expect(mockScaleController.connectCalls.first.deviceId, 'pref-scale');
        await sub.cancel();
      });

      test('sleeping during an active scale scan stops it and blocks reconnect',
          () async {
        await settingsController.setPreferredScaleId('pref-scale');
        await settingsController.setScalePowerMode(ScalePowerMode.disconnect);

        final fakeDe1 = _FakeDe1(deviceId: 'connected-de1');
        mockScaleController.mockEmitConnectionState(ConnectionState.connected);
        mockScaleController.debugSetLastConnectedId('pref-scale');
        mockDe1Controller.de1Subject.add(fakeDe1);
        await Future<void>.delayed(Duration.zero);
        fakeDe1.emitState(MachineState.idle);
        await Future<void>.delayed(Duration.zero);

        mockScanner.scanCompleter = Completer<void>();
        mockScaleController.mockEmitConnectionState(ConnectionState.disconnected);
        await mockScanner.scanningStream.firstWhere((s) => s);

        fakeDe1.emitState(MachineState.sleeping);
        connectionManager.markExpectingDisconnect('pref-scale');
        mockScanner.addDevice(TestScale(deviceId: 'pref-scale'));
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        mockScanner.completeScan();
        await Future<void>.delayed(Duration.zero);

        expect(mockScanner.stopScanCallCount, 1);
        expect(mockScaleController.connectCalls, isEmpty);
      });

      test('unexpected scale disconnect emits scaleDisconnected', () async {
        mockScaleController
            .mockEmitConnectionState(ConnectionState.connected);
        mockScaleController.debugSetLastConnectedId('50:78:7D:1F:AE:E1');
        await Future<void>.delayed(Duration.zero);

        mockScaleController
            .mockEmitConnectionState(ConnectionState.disconnected);
        await Future<void>.delayed(Duration.zero);

        expect(connectionManager.currentStatus.error?.kind,
            ConnectionErrorKind.scaleDisconnected);
        expect(connectionManager.currentStatus.error?.deviceId,
            '50:78:7D:1F:AE:E1');
      });
    });

    group('adapter state', () {
      test('adapter off emits adapterOff error', () async {
        mockScanner.mockAdapterState(AdapterState.poweredOff);
        await Future<void>.delayed(Duration.zero);
        expect(connectionManager.currentStatus.error?.kind,
            ConnectionErrorKind.adapterOff);
      });

      test('adapter on clears adapterOff', () async {
        mockScanner.mockAdapterState(AdapterState.poweredOff);
        await Future<void>.delayed(Duration.zero);
        expect(connectionManager.currentStatus.error?.kind,
            ConnectionErrorKind.adapterOff);

        mockScanner.mockAdapterState(AdapterState.poweredOn);
        await Future<void>.delayed(Duration.zero);
        expect(connectionManager.currentStatus.error, isNull);
      });

      test('adapter on does NOT clear an unrelated transient error',
          () async {
        connectionManager.debugEmitError(
          kind: ConnectionErrorKind.scaleConnectFailed,
          severity: ConnectionErrorSeverity.error,
          message: 'x',
        );
        mockScanner.mockAdapterState(AdapterState.poweredOn);
        await Future<void>.delayed(Duration.zero);
        expect(connectionManager.currentStatus.error?.kind,
            ConnectionErrorKind.scaleConnectFailed);
      });
    });

    group('scan failures', () {
      test('scan throwing permission error emits bluetoothPermissionDenied',
          () async {
        mockScanner.failNextScanWith =
            const PermissionDeniedException('denied');
        await connectionManager.connect(scaleOnly: true);
        expect(connectionManager.currentStatus.error?.kind,
            ConnectionErrorKind.bluetoothPermissionDenied);
      });

      test('scan throwing generic error emits scanFailed', () async {
        mockScanner.failNextScanWith = Exception('adapter busy');
        await connectionManager.connect(scaleOnly: true);
        expect(connectionManager.currentStatus.error?.kind,
            ConnectionErrorKind.scanFailed);
      });

      test('exception containing "permission" classified as permissionDenied',
          () async {
        mockScanner.failNextScanWith =
            Exception('Missing bluetooth permission');
        await connectionManager.connect(scaleOnly: true);
        expect(connectionManager.currentStatus.error?.kind,
            ConnectionErrorKind.bluetoothPermissionDenied);
      });

      test('successful scan-start clears prior scanFailed', () async {
        connectionManager.debugEmitError(
          kind: ConnectionErrorKind.scanFailed,
          severity: ConnectionErrorSeverity.error,
          message: 'prior fail',
        );
        expect(connectionManager.currentStatus.error, isNotNull);
        await connectionManager.connect(scaleOnly: true);
        expect(connectionManager.currentStatus.error, isNull);
      });
    });

    group('machine auto-reconnect', () {
      /// Pump enough microtask/zero-timer turns for a drop → timer →
      /// connect() → scan → connect-machine cycle to complete.
      Future<void> pumpCycles([int n = 8]) async {
        for (var i = 0; i < n; i++) {
          await Future<void>.delayed(Duration.zero);
        }
      }

      test(
          'unexpected machine disconnect starts recovery scans and '
          'reconnects the preferred machine', () async {
        connectionManager.machineReconnectBaseDelay = Duration.zero;
        await settingsController.setPreferredMachineId('pref-de1');
        final fakeDe1 = _FakeDe1(deviceId: 'pref-de1');
        mockScanner.addDevice(fakeDe1); // still advertising / came back
        mockDe1Controller.de1Subject.add(fakeDe1);
        await Future<void>.delayed(Duration.zero);

        mockDe1Controller.de1Subject.add(null); // unexpected drop
        await pumpCycles();

        expect(
          mockDe1Controller.connectCalls.map((d) => d.deviceId),
          contains('pref-de1'),
          reason: 'recovery loop must rescan and reconnect the machine',
        );
      });

      test('recovery keeps retrying until the machine reappears, then stops',
          () async {
        connectionManager.machineReconnectBaseDelay = Duration.zero;
        await settingsController.setPreferredMachineId('pref-de1');
        final fakeDe1 = _FakeDe1(deviceId: 'pref-de1');
        mockDe1Controller.de1Subject.add(fakeDe1);
        await Future<void>.delayed(Duration.zero);

        var scanStarts = 0;
        final sub = mockScanner.scanningStream.listen((s) {
          if (s) scanStarts++;
        });

        // Machine drops and is NOT in scan results yet.
        mockDe1Controller.de1Subject.add(null);
        await pumpCycles();
        expect(scanStarts, greaterThan(0),
            reason: 'loop must scan even while the machine is absent');
        expect(mockDe1Controller.connectCalls, isEmpty);

        // Machine comes back — next cycle reconnects and the loop stops.
        mockScanner.addDevice(fakeDe1);
        await pumpCycles();
        expect(
          mockDe1Controller.connectCalls.map((d) => d.deviceId),
          contains('pref-de1'),
        );

        final scansAfterReconnect = scanStarts;
        await pumpCycles();
        expect(scanStarts, scansAfterReconnect,
            reason: 'loop must stop once the machine is connected');
        await sub.cancel();
      });

      test('expected machine disconnect does not start recovery', () async {
        connectionManager.machineReconnectBaseDelay = Duration.zero;
        await settingsController.setPreferredMachineId('pref-de1');
        final fakeDe1 = _FakeDe1(deviceId: 'pref-de1');
        mockScanner.addDevice(fakeDe1);
        mockDe1Controller.de1Subject.add(fakeDe1);
        await Future<void>.delayed(Duration.zero);

        var scanStarts = 0;
        final sub = mockScanner.scanningStream.listen((s) {
          if (s) scanStarts++;
        });

        connectionManager.markExpectingDisconnect('pref-de1');
        mockDe1Controller.de1Subject.add(null);
        await pumpCycles();

        expect(scanStarts, 0,
            reason: 'expected disconnects must not trigger background scans');
        expect(mockDe1Controller.connectCalls, isEmpty);
        await sub.cancel();
      });

      test('deliberate disconnectMachine does not start recovery', () async {
        connectionManager.machineReconnectBaseDelay = Duration.zero;
        await settingsController.setPreferredMachineId('pref-de1');
        final fakeDe1 = _FakeDe1(deviceId: 'pref-de1');
        mockScanner.addDevice(fakeDe1);
        mockDe1Controller.de1Subject.add(fakeDe1);
        await Future<void>.delayed(Duration.zero);

        var scanStarts = 0;
        final sub = mockScanner.scanningStream.listen((s) {
          if (s) scanStarts++;
        });

        await connectionManager.disconnectMachine();
        await pumpCycles();

        expect(scanStarts, 0);
        expect(mockDe1Controller.connectCalls, isEmpty);
        await sub.cancel();
      });

      test('no preferred machine → no recovery scans', () async {
        connectionManager.machineReconnectBaseDelay = Duration.zero;
        final fakeDe1 = _FakeDe1(deviceId: 'some-de1');
        mockScanner.addDevice(fakeDe1);
        mockDe1Controller.de1Subject.add(fakeDe1);
        await Future<void>.delayed(Duration.zero);

        var scanStarts = 0;
        final sub = mockScanner.scanningStream.listen((s) {
          if (s) scanStarts++;
        });

        mockDe1Controller.de1Subject.add(null);
        await pumpCycles();

        expect(scanStarts, 0,
            reason: 'without a preferred machine a background retry could '
                'pop a picker — must stay off');
        await sub.cancel();
      });

      test('recovery retries use exponential backoff', () {
        fakeAsync((async) {
          final manager = ConnectionManager(
            deviceScanner: mockScanner,
            de1Controller: mockDe1Controller,
            scaleController: mockScaleController,
            settingsController: settingsController,
          );
          settingsController.setPreferredMachineId('pref-de1');
          async.flushMicrotasks();
          mockDe1Controller.de1Subject.add(_FakeDe1(deviceId: 'pref-de1'));
          async.flushMicrotasks();

          var scanStarts = 0;
          mockScanner.scanningStream.listen((s) {
            if (s) scanStarts++;
          });

          mockDe1Controller.de1Subject.add(null); // unexpected drop at t=0
          async.flushMicrotasks();

          // First retry at t=5s (base delay).
          async.elapse(const Duration(seconds: 4));
          expect(scanStarts, 0, reason: 'no retry before the base delay');
          async.elapse(const Duration(seconds: 2)); // t=6
          expect(scanStarts, 1, reason: 'first retry fires at 5s');

          // Second retry doubles: due 10s after the first (t≈15s).
          async.elapse(const Duration(seconds: 8)); // t=14
          expect(scanStarts, 1, reason: 'second retry must back off to 10s');
          async.elapse(const Duration(seconds: 2)); // t=16
          expect(scanStarts, 2);

          manager.dispose();
          async.flushMicrotasks();
        });
      });
    });

    group('snapshot staleness watchdog', () {
      // The watchdog Timer must be created inside the fakeAsync zone, so
      // each test constructs a fresh ConnectionManager here (the setUp
      // instance lives in the real zone — its Timer wouldn't be visible
      // to async.elapse). Mirrors the 'recovery retries use exponential
      // backoff' test.

      ConnectionManager newManager() => ConnectionManager(
            deviceScanner: mockScanner,
            de1Controller: mockDe1Controller,
            scaleController: mockScaleController,
            settingsController: settingsController,
          );

      test('fires after 10s with no snapshots and forces a reconnect', () {
        fakeAsync((async) {
          final manager = newManager();
          final fakeDe1 = _FakeDe1(deviceId: 'stale-de1');
          mockDe1Controller.de1Subject.add(fakeDe1);
          async.flushMicrotasks();
          // First snapshot frame arms (and re-arms) the watchdog.
          fakeDe1.emitState(MachineState.idle);
          async.flushMicrotasks();

          expect(manager.snapshotStalenessReconnects, 0);
          async.elapse(const Duration(seconds: 9));
          expect(manager.snapshotStalenessReconnects, 0,
              reason: 'must not fire before the staleness timeout');
          // Counter increments synchronously at the top of the force
          // action, so it is observable the moment the Timer fires. The
          // counter proves the watchdog fired and the force path ran
          // (disconnectMachine → connect). We don't assert on
          // fakeDe1.disconnectCalls here: BehaviorSubject's Rx.defer
          // replay doesn't settle under flushMicrotasks/elapse(0) in
          // fakeAsync, so the async chain only resumes after dispose —
          // making that assertion flaky without proving anything the
          // counter doesn't already show.
          async.elapse(const Duration(seconds: 2)); // 11s elapsed
          expect(manager.snapshotStalenessReconnects, 1,
              reason: 'a silent push channel must trigger a forced reconnect');

          manager.dispose();
          async.flushMicrotasks();
        });
      });

      test('a deduped snapshot within the window re-arms the watchdog', () {
        fakeAsync((async) {
          final manager = newManager();
          final fakeDe1 = _FakeDe1(deviceId: 'stale-de1');
          mockDe1Controller.de1Subject.add(fakeDe1);
          async.flushMicrotasks();
          fakeDe1.emitState(MachineState.idle);
          async.flushMicrotasks();

          async.elapse(const Duration(seconds: 9));
          // Same state — deduped by _latestMachineState — but still proves
          // the push channel is alive; watchdog must re-arm.
          fakeDe1.emitState(MachineState.idle);
          async.flushMicrotasks();

          async.elapse(const Duration(seconds: 9)); // 18s total, 9s since re-arm
          expect(manager.snapshotStalenessReconnects, 0,
              reason: 'a deduped frame must re-arm the watchdog');

          manager.dispose();
          async.flushMicrotasks();
        });
      });

      test('deliberate disconnectMachine cancels the watchdog (no fire, no error)',
          () {
        fakeAsync((async) {
          final manager = newManager();
          final fakeDe1 = _FakeDe1(deviceId: 'stale-de1');
          mockDe1Controller.de1Subject.add(fakeDe1);
          async.flushMicrotasks();
          fakeDe1.emitState(MachineState.idle);
          async.flushMicrotasks();

          // Deliberate disconnect cancels the watchdog and bumps the
          // generation token.
          manager.disconnectMachine();
          async.flushMicrotasks();

          async.elapse(const Duration(seconds: 15));
          expect(manager.snapshotStalenessReconnects, 0,
              reason: 'deliberate disconnect must cancel the watchdog');
          expect(manager.currentStatus.error, isNull,
              reason: 'deliberate disconnect must not surface an error banner');

          manager.dispose();
          async.flushMicrotasks();
        });
      });

      test('initial grace: no fire before the first snapshot at 9s, fire at 11s',
          () {
        fakeAsync((async) {
          final manager = newManager();
          final fakeDe1 = _FakeDe1(deviceId: 'stale-de1');
          mockDe1Controller.de1Subject.add(fakeDe1);
          async.flushMicrotasks();
          // No snapshot emitted — only the initial-grace arm at watch setup.

          async.elapse(const Duration(seconds: 9));
          expect(manager.snapshotStalenessReconnects, 0,
              reason: 'must not fire within the initial grace window');

          async.elapse(const Duration(seconds: 2)); // 11s
          expect(manager.snapshotStalenessReconnects, 1,
              reason: 'watchdog armed at watch setup must fire if no frame '
                  'ever lands');

          manager.dispose();
          async.flushMicrotasks();
        });
      });

      test('stale generation after a forced reconnect bails (no double-reconnect)',
          () {
        fakeAsync((async) {
          final manager = newManager();
          final fakeDe1 = _FakeDe1(deviceId: 'stale-de1');
          mockDe1Controller.de1Subject.add(fakeDe1);
          async.flushMicrotasks();
          fakeDe1.emitState(MachineState.idle);
          async.flushMicrotasks();

          async.elapse(const Duration(seconds: 11));
          expect(manager.snapshotStalenessReconnects, 1);
          async.flushMicrotasks();

          // The forced reconnect cancelled the watchdog and bumped the
          // generation. With no new machine connected and no new frames,
          // no watchdog is re-armed — a long elapse must not trigger a
          // second forced reconnect.
          async.elapse(const Duration(seconds: 30));
          expect(manager.snapshotStalenessReconnects, 1,
              reason: 'a stale-generation Timer must bail, not re-fire');

          manager.dispose();
          async.flushMicrotasks();
        });
      });

      // Runs in the real async zone (not fakeAsync): the forced reconnect's
      // `disconnectMachine → connect` chain awaits `de1Controller.de1.first`,
      // which a BehaviorSubject does not settle under fakeAsync — so the
      // strand safety-net in the `finally` only runs with real microtasks.
      // A short overridden staleness timeout keeps the test fast.
      test(
          'a forced reconnect that cannot recover the machine hands off to '
          'the recovery loop (no strand)', () async {
        await settingsController.setPreferredMachineId('stale-de1');
        // Non-zero base delay avoids a hot recovery loop within the wait
        // window; we only assert the loop is armed, not how often it scans.
        connectionManager.machineReconnectBaseDelay =
            const Duration(milliseconds: 50);
        connectionManager.snapshotStalenessTimeout =
            const Duration(milliseconds: 20);
        final fakeDe1 = _FakeDe1(deviceId: 'stale-de1');
        mockDe1Controller.de1Subject.add(fakeDe1);
        await Future<void>.delayed(Duration.zero);
        fakeDe1.emitState(MachineState.idle);
        await Future<void>.delayed(Duration.zero);

        // Let the 20ms watchdog fire and force a reconnect. The scanner
        // surfaces no machine, so the forced `connect()` completes without
        // reconnecting → the machine is left disconnected.
        // `disconnectMachine` marked the drop expected, so the
        // unexpected-disconnect path never armed recovery; without the
        // safety net nothing would retry.
        await Future<void>.delayed(const Duration(milliseconds: 60));

        expect(connectionManager.snapshotStalenessReconnects, greaterThan(0),
            reason: 'the watchdog must have forced a reconnect');
        expect(connectionManager.machineRecoveryActive, isTrue,
            reason: 'a stranded forced reconnect must hand off to the '
                'machine-recovery loop, not leave the machine disconnected');
      });
    });

    group('background scale watch', () {
      const scaleId = 'pref-scale';

      ConnectionManager buildWatchManager() => ConnectionManager(
            deviceScanner: mockScanner,
            de1Controller: mockDe1Controller,
            scaleController: mockScaleController,
            settingsController: settingsController,
          );

      setUp(() async {
        // Retire the shared legacy manager from the outer setUp — it
        // listens to the same subjects and, with supportsWatch flipped
        // on, would double-arm the watch alongside this group's manager.
        await connectionManager.dispose();
        mockScanner.supportsWatch = true;
      });

      test(
          'machine connect with preferred scale missing arms the watch '
          'and never runs backoff bursts', () {
        fakeAsync((async) {
          final manager = buildWatchManager();
          settingsController.setPreferredScaleId(scaleId);
          async.flushMicrotasks();
          mockDe1Controller.de1Subject.add(_FakeDe1(deviceId: 'connected-de1'));
          async.flushMicrotasks();

          expect(mockScanner.startWatchCallCount, 1,
              reason: 'watch must arm on machine connect with scale missing');
          expect(mockScanner.lastWatchFilter?.namePrefix, isNull,
              reason: 'no OS name filter — remembered friendly names do not '
                  'match advertised names; Dart-side matching owns this');

          // The load-bearing regression assertion: past the full legacy
          // backoff ladder (5→60s), no burst scan may fire — the watch
          // replaces the loop entirely.
          async.elapse(const Duration(seconds: 70));
          async.flushMicrotasks();
          expect(mockScanner.scanCallCount, 0,
              reason: 'watch replaces the backoff-burst reconnect loop');

          manager.dispose();
          async.flushMicrotasks();
        });
      });

      test('watch sighting connects the scale and stops the watch', () async {
        connectionManager = buildWatchManager();
        await settingsController.setPreferredScaleId(scaleId);
        mockDe1Controller.de1Subject.add(_FakeDe1(deviceId: 'connected-de1'));
        await Future<void>.delayed(Duration.zero);
        expect(mockScanner.watchActive, isTrue);

        mockScanner.addDevice(TestScale(deviceId: scaleId));
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(
          mockScaleController.connectCalls.map((s) => s.deviceId),
          contains(scaleId),
        );
        expect(mockScanner.watchActive, isFalse,
            reason: 'watch stops once the scale is connected');
        expect(connectionManager.currentStatus.phase, ConnectionPhase.ready);
        expect(mockScanner.scanCallCount, 0,
            reason: 'the connect must not go through a burst scan');
      });

      test('failed watch connect re-arms the watch', () async {
        connectionManager = buildWatchManager();
        await settingsController.setPreferredScaleId(scaleId);
        mockScaleController.shouldFailConnect = true;
        mockDe1Controller.de1Subject.add(_FakeDe1(deviceId: 'connected-de1'));
        await Future<void>.delayed(Duration.zero);
        expect(mockScanner.startWatchCallCount, 1);

        mockScanner.addDevice(TestScale(deviceId: scaleId));
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(mockScaleController.connectCalls, isNotEmpty);
        expect(mockScanner.startWatchCallCount, 2,
            reason: 'a failed connect must restart the watch');
        expect(mockScanner.watchActive, isTrue);
      });

      test('unexpected preferred scale disconnect arms the watch', () async {
        connectionManager = buildWatchManager();
        await settingsController.setPreferredScaleId(scaleId);
        mockScaleController.mockEmitConnectionState(ConnectionState.connected);
        mockScaleController.debugSetLastConnectedId(scaleId);
        mockDe1Controller.de1Subject.add(_FakeDe1(deviceId: 'connected-de1'));
        await Future<void>.delayed(Duration.zero);
        expect(mockScanner.startWatchCallCount, 0,
            reason: 'scale is connected — nothing to watch for');

        mockScaleController
            .mockEmitConnectionState(ConnectionState.disconnected);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(mockScanner.startWatchCallCount, 1);
        expect(mockScanner.scanCallCount, 0,
            reason: 'no burst scan on unexpected disconnect either');
      });

      test(
          'power-mode sleep stops the watch and wake re-arms it '
          'without a burst', () async {
        await settingsController.setScalePowerMode(ScalePowerMode.disconnect);
        connectionManager = buildWatchManager();
        await settingsController.setPreferredScaleId(scaleId);
        final fakeDe1 = _FakeDe1(deviceId: 'connected-de1');
        mockDe1Controller.de1Subject.add(fakeDe1);
        await Future<void>.delayed(Duration.zero);
        fakeDe1.emitState(MachineState.idle);
        await Future<void>.delayed(Duration.zero);
        expect(mockScanner.watchActive, isTrue,
            reason: 'machine awake + scale missing → watch armed');

        fakeDe1.emitState(MachineState.sleeping);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(mockScanner.watchActive, isFalse,
            reason: 'sleeping + ScalePowerMode.disconnect must stop the watch');

        final startsBeforeWake = mockScanner.startWatchCallCount;
        fakeDe1.emitState(MachineState.idle);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(mockScanner.startWatchCallCount, startsBeforeWake + 1,
            reason: 'wake must re-arm the watch');
        expect(mockScanner.scanCallCount, 0);
      });

      test('machine disconnect stops the watch', () async {
        connectionManager = buildWatchManager();
        await settingsController.setPreferredScaleId(scaleId);
        mockDe1Controller.de1Subject.add(_FakeDe1(deviceId: 'connected-de1'));
        await Future<void>.delayed(Duration.zero);
        expect(mockScanner.watchActive, isTrue);

        mockDe1Controller.de1Subject.add(null);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(mockScanner.watchActive, isFalse,
            reason: 'no machine → nothing to reacquire a scale for');
      });

      test(
          'machine quick-connect arms the watch, not the legacy backoff loop',
          () {
        // Quick-connect is the common startup path when a preferred
        // machine is remembered; its success branch must route scale
        // reacquisition through the watch selector like every other
        // machine-connected site — not schedule backoff bursts alongside
        // the watch.
        fakeAsync((async) {
          mockSettingsService.setRememberedDevices(RememberedDevice.encodeList([
            const RememberedDevice(
              id: 'pref-de1',
              name: 'DE1',
              type: DeviceType.machine,
            ),
          ]));
          final remembered = RememberedDevicesController(
            machineConnections: const Stream.empty(),
            scaleConnections: const Stream.empty(),
            settings: mockSettingsService,
          );
          remembered.initialize();
          async.flushMicrotasks();

          final fakeDe1 = _FakeDe1(deviceId: 'pref-de1');
          mockScanner.quickConnectResult = fakeDe1;
          // Fresh controller: the group setUp disposed the shared one
          // (closing its subjects), which would make adoptDevice throw.
          final qcDe1Controller = MockDe1Controller(
            controller: DeviceController([dummyDiscoveryService]),
          );
          final manager = ConnectionManager(
            deviceScanner: mockScanner,
            de1Controller: qcDe1Controller,
            scaleController: mockScaleController,
            settingsController: settingsController,
            rememberedDevices: remembered,
          );
          settingsController.setPreferredMachineId('pref-de1');
          settingsController.setPreferredScaleId(scaleId);
          async.flushMicrotasks();

          manager.connect();
          async.flushMicrotasks();
          expect(mockScanner.quickConnectCallCount, 1,
              reason: 'the quick-connect path must be the one exercised');

          // Production: adoptDevice propagates onto the de1 stream and
          // the supervisor fires machine-connected; simulate that here
          // (MockDe1Controller overrides the stream adoptDevice feeds).
          qcDe1Controller.de1Subject.add(fakeDe1);
          async.flushMicrotasks();

          expect(mockScanner.startWatchCallCount, 1,
              reason: 'watch must arm after a quick-connected machine');
          async.elapse(const Duration(seconds: 70));
          async.flushMicrotasks();
          expect(mockScanner.scanCallCount, 0,
              reason: 'quick-connect success must not schedule legacy '
                  'backoff bursts alongside the watch');

          manager.dispose();
          remembered.dispose();
          async.flushMicrotasks();
        });
      });

      test('watch start failure falls back to the legacy backoff loop', () {
        fakeAsync((async) {
          final manager = buildWatchManager();
          settingsController.setPreferredScaleId(scaleId);
          async.flushMicrotasks();
          mockScanner.failNextWatchWith = Exception('watch unavailable');
          mockDe1Controller.de1Subject.add(_FakeDe1(deviceId: 'connected-de1'));
          async.flushMicrotasks();

          expect(mockScanner.startWatchCallCount, 0,
              reason: 'the start attempt threw before recording');
          // Legacy backoff base delay is 5s — the fallback burst fires then.
          async.elapse(const Duration(seconds: 6));
          async.flushMicrotasks();
          expect(mockScanner.scanCallCount, 1,
              reason: 'watch failure must fall back to backoff bursts');

          manager.dispose();
          async.flushMicrotasks();
        });
      });

      test('a watch that dies mid-flight falls back to legacy backoff', () {
        fakeAsync((async) {
          final manager = buildWatchManager();
          settingsController.setPreferredScaleId(scaleId);
          async.flushMicrotasks();
          mockDe1Controller.de1Subject.add(_FakeDe1(deviceId: 'connected-de1'));
          async.flushMicrotasks();
          expect(mockScanner.startWatchCallCount, 1);

          // Simulates a failed refresh / post-burst resume / adapter
          // recovery inside the discovery service.
          mockScanner.emitWatchFailure();
          async.flushMicrotasks();

          async.elapse(const Duration(seconds: 6));
          async.flushMicrotasks();
          expect(mockScanner.scanCallCount, 1,
              reason: 'the legacy backoff loop must take over when the '
                  'watch dies — scale reacquisition must never be '
                  'silently off');

          manager.dispose();
          async.flushMicrotasks();
        });
      });

      test('dispose stops the watch', () async {
        connectionManager = buildWatchManager();
        await settingsController.setPreferredScaleId(scaleId);
        mockDe1Controller.de1Subject.add(_FakeDe1(deviceId: 'connected-de1'));
        await Future<void>.delayed(Duration.zero);
        expect(mockScanner.watchActive, isTrue);

        await connectionManager.dispose();
        expect(mockScanner.watchActive, isFalse);
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
