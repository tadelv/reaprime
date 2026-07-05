import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/connection_manager.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/models/device/bengle_interface.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:reaprime/src/settings/settings_controller.dart';

import '../helpers/mock_de1_controller.dart';
import '../helpers/mock_device_discovery_service.dart';
import '../helpers/mock_device_scanner.dart';
import '../helpers/mock_scale_controller.dart';
import '../helpers/mock_settings_service.dart';
import '../helpers/test_scale.dart';

/// Minimal BengleInterface stub. Implements only what ConnectionManager
/// touches during connect — `noSuchMethod` swallows the rest.
class _FakeBengle implements BengleInterface {
  @override
  final String deviceId;

  @override
  final String name;

  @override
  DeviceType get type => DeviceType.machine;

  @override
  Stream<ConnectionState> get connectionState =>
      Stream.value(ConnectionState.connected);

  @override
  Stream<ScaleSnapshot> get weightSnapshot => const Stream.empty();

  _FakeBengle({this.deviceId = 'fake-bengle'}) : name = 'Bengle-$deviceId';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Minimal De1Interface stub for the regression-guard test.
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
  group('ConnectionManager + Bengle integrated scale', () {
    late MockDeviceScanner mockScanner;
    late MockDe1Controller mockDe1Controller;
    late MockScaleController mockScaleController;
    late SettingsController settingsController;
    late MockSettingsService mockSettingsService;
    late ConnectionManager connectionManager;
    late MockDeviceDiscoveryService dummyDiscoveryService;

    setUp(() async {
      mockScanner = MockDeviceScanner();
      dummyDiscoveryService = MockDeviceDiscoveryService();
      mockDe1Controller = MockDe1Controller(
        controller: DeviceController([dummyDiscoveryService]),
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

    test(
      'auto-attaches BengleVirtualScale on Bengle machine connect',
      () async {
        // Bengle is the preferred machine, no external scale advertised, no
        // preferredScaleId set.
        await settingsController.setPreferredMachineId('bengle-1');
        final bengle = _FakeBengle(deviceId: 'bengle-1');
        mockScanner.addDevice(bengle);
        await Future.delayed(Duration.zero);

        await connectionManager.connect();
        await Future.delayed(Duration.zero);

        expect(mockDe1Controller.connectCalls, hasLength(1));
        expect(mockDe1Controller.connectCalls.first, same(bengle));

        // The scale slot is taken by the virtual scale, not anything from
        // the scan.
        expect(mockScaleController.connectCalls, hasLength(1));
        expect(
          mockScaleController.connectCalls.first.deviceId,
          startsWith('bengle-internal-'),
        );
      },
    );

    test(
      'skips external scale phase when Bengle is the machine '
      '(even with preferredScaleId set + external scale discoverable)',
      () async {
        // Synchronous co-discovery case: both Bengle and external scale
        // are visible to the scanner before connect() begins, so a single
        // _onDevicesUpdate sees both and the Bengle-inference arm of the
        // gate fires. The interleaved-discovery race (external scale
        // visible before Bengle) is covered by the next test.
        await settingsController.setPreferredMachineId('bengle-1');
        await settingsController.setPreferredScaleId('external-scale');

        final bengle = _FakeBengle(deviceId: 'bengle-1');
        final externalScale = TestScale(deviceId: 'external-scale');
        mockScanner.addDevice(bengle);
        mockScanner.addDevice(externalScale);
        await Future.delayed(Duration.zero);

        await connectionManager.connect();
        await Future.delayed(Duration.zero);

        // Exactly one scale was attached, and it's the virtual one — the
        // external scale was never even attempted.
        expect(mockScaleController.connectCalls, hasLength(1));
        expect(
          mockScaleController.connectCalls.first.deviceId,
          startsWith('bengle-internal-'),
        );
        expect(
          mockScaleController.connectCalls.any(
            (s) => s.deviceId == 'external-scale',
          ),
          isFalse,
          reason:
              'external scale must not be attempted while Bengle is the '
              'connected machine',
        );
      },
    );

    test('external scale visible BEFORE Bengle still loses the slot to the '
        'virtual scale', () async {
      // Regression for the interleaved-discovery race the synchronous
      // co-discovery test cannot exercise: the external scale appears
      // in scan results FIRST, then the Bengle joins mid-scan. Without
      // the conservative-skip gate, the external scale would
      // early-connect (Bengle-inference returns false because Bengle
      // isn't yet visible to the scanner and `latestMachine` is still
      // null), and the post-scan virtual-attach would short-circuit
      // because the slot is taken.
      await settingsController.setPreferredMachineId('bengle-1');
      await settingsController.setPreferredScaleId('external-scale');

      final bengle = _FakeBengle(deviceId: 'bengle-1');
      final externalScale = TestScale(deviceId: 'external-scale');

      // Only the external scale is visible at scan-start.
      mockScanner.addDevice(externalScale);

      // Hold the scan open so we can add the Bengle mid-scan. Without
      // this, scanForDevices() completes synchronously and the
      // EarlyConnectWatcher never sees the second device emission.
      final scanCompleter = Completer<void>();
      mockScanner.scanCompleter = scanCompleter;

      // Stage the Bengle to arrive after connect() begins. Using
      // Future.microtask keeps timing deterministic — the microtask
      // runs after scanForDevices() has emitted its initial
      // `scanning: true` + replayed devices, so the watcher sees the
      // external scale first, then the Bengle as a separate update.
      // The completeScan() call ends the hold-open.
      Future.microtask(() async {
        // Yield once so the watcher processes the external-scale-only
        // emission before the Bengle arrives.
        await Future.delayed(Duration.zero);
        mockScanner.addDevice(bengle);
        await Future.delayed(Duration.zero);
        mockScanner.completeScan();
      });

      await connectionManager.connect();
      await Future.delayed(Duration.zero);

      // The Bengle is the connected machine.
      expect(mockDe1Controller.connectCalls, hasLength(1));
      expect(mockDe1Controller.connectCalls.first, same(bengle));

      // Exactly one scale was attached, and it's the virtual one.
      expect(mockScaleController.connectCalls, hasLength(1));
      expect(
        mockScaleController.connectCalls.first.deviceId,
        startsWith('bengle-internal-'),
      );
      expect(
        mockScaleController.connectCalls.any(
          (s) => s.deviceId == 'external-scale',
        ),
        isFalse,
        reason:
            'external scale must not be attempted when a Bengle is the '
            'preferred machine, even if the external scale appears first',
      );
    });

    test('non-Bengle machine still runs external scale phase', () async {
      await settingsController.setPreferredMachineId('de1-1');
      await settingsController.setPreferredScaleId('ext-scale');

      final de1 = _FakeDe1(deviceId: 'de1-1');
      final scale = TestScale(deviceId: 'ext-scale');
      mockScanner.addDevice(de1);
      mockScanner.addDevice(scale);
      await Future.delayed(Duration.zero);

      await connectionManager.connect();
      await Future.delayed(Duration.zero);

      expect(mockScaleController.connectCalls, hasLength(1));
      expect(mockScaleController.connectCalls.first.deviceId, 'ext-scale');
    });
  });
}
