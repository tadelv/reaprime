import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/connection_manager.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/settings/settings_controller.dart';

import '../helpers/mock_de1_controller.dart';
import '../helpers/mock_device_discovery_service.dart';
import '../helpers/mock_device_scanner.dart';
import '../helpers/mock_scale_controller.dart';
import '../helpers/mock_settings_service.dart';

/// The Android serial service received `ACTION_USB_DEVICE_ATTACHED` and threw
/// it away, so a machine that was back on the bus at 15:46:55.102 was not
/// connected until the next backoff scan at 15:47:15.376 — 20.3 s of dead time,
/// and up to 60 s once the backoff stretches to its cap. The device is sitting
/// there, enumerated and ready, while the app waits out a timer.
///
/// These lock the reaction (immediate connect), the guards (no reconnect
/// storm), and the fallback (the backoff loop is still there if the attach
/// connect doesn't land).
class _FakeDe1 implements De1Interface {
  @override
  final String deviceId;

  @override
  String get name => 'DE1-$deviceId';

  @override
  DeviceType get type => DeviceType.machine;

  @override
  Stream<ConnectionState> get connectionState =>
      Stream.value(ConnectionState.connected);

  _FakeDe1({this.deviceId = 'usb-2e8a-a-8549628789ABCDEF'});

  @override
  Future<void> disconnect() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  late MockDeviceScanner mockScanner;
  late MockDe1Controller mockDe1Controller;
  late MockScaleController mockScaleController;
  late SettingsController settingsController;
  late ConnectionManager connectionManager;
  late MockDeviceDiscoveryService dummyDiscoveryService;

  /// Pump enough turns for attach → settle timer → connect() → scan →
  /// connectMachine to complete. The settle delay is set to zero below, so
  /// zero-duration Timers fire between turns.
  Future<void> pumpCycles([int n = 12]) async {
    for (var i = 0; i < n; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() async {
    dummyDiscoveryService = MockDeviceDiscoveryService();
    mockScanner = MockDeviceScanner();
    mockDe1Controller = MockDe1Controller(
      controller: DeviceController([dummyDiscoveryService]),
    );
    mockScaleController = MockScaleController();
    settingsController = SettingsController(MockSettingsService());
    await settingsController.loadSettings();

    connectionManager = ConnectionManager(
      deviceScanner: mockScanner,
      de1Controller: mockDe1Controller,
      scaleController: mockScaleController,
      settingsController: settingsController,
    );
    // Drive the settle window and the backoff from the test, not the clock.
    connectionManager.deviceAttachSettleDelay = Duration.zero;
    connectionManager.machineReconnectBaseDelay = Duration.zero;
  });

  tearDown(() {
    mockScanner.dispose();
    dummyDiscoveryService.dispose();
  });

  group('USB attach → immediate connect', () {
    test('an attach connects the preferred machine without waiting for the '
        'backoff', () async {
      await settingsController.setPreferredMachineId(
        'usb-2e8a-a-8549628789ABCDEF',
      );
      final machine = _FakeDe1();
      mockScanner.addDevice(machine); // back on the bus, enumerable

      // No disconnect happened from ConnectionManager's point of view (the app
      // was started with the machine off, or the drop landed mid-connect), so
      // the recovery backoff is NOT running. The attach must still connect.
      expect(connectionManager.machineRecoveryActive, isFalse);

      mockScanner.mockDeviceAttached(
        deviceId: 'usb-2e8a-a-8549628789ABCDEF',
        name: 'DE1',
      );
      await pumpCycles();

      expect(connectionManager.attachTriggeredConnects, 1);
      expect(
        mockDe1Controller.connectCalls.map((d) => d.deviceId),
        contains('usb-2e8a-a-8549628789ABCDEF'),
      );
    });

    test('a burst of attach intents makes exactly one connect attempt',
        () async {
      await settingsController.setPreferredMachineId('pref-de1');
      mockScanner.addDevice(_FakeDe1(deviceId: 'pref-de1'));

      // A composite device broadcasts one intent per interface; a flapping
      // cable broadcasts many. One scan, not five.
      for (var i = 0; i < 5; i++) {
        mockScanner.mockDeviceAttached(deviceId: 'pref-de1', name: 'DE1');
      }
      await pumpCycles();

      expect(connectionManager.attachTriggeredConnects, 1);
      expect(mockDe1Controller.connectCalls.length, 1);
    });

    test('an attach while a connect is already in flight does not queue a '
        'second one', () async {
      await settingsController.setPreferredMachineId('pref-de1');
      mockScanner.addDevice(_FakeDe1(deviceId: 'pref-de1'));
      // Hold the scan open so the first attach-triggered connect stays running.
      mockScanner.scanCompleter = Completer<void>();

      mockScanner.mockDeviceAttached(deviceId: 'pref-de1');
      await pumpCycles(3);
      expect(connectionManager.attachTriggeredConnects, 1);

      mockScanner.mockDeviceAttached(deviceId: 'pref-de1');
      await pumpCycles(3);
      expect(
        connectionManager.attachTriggeredConnects,
        1,
        reason: 'the in-flight attach connect must absorb the second intent',
      );

      mockScanner.completeScan();
      await pumpCycles();
    });

    test('an attach while the machine is already connected does not scan',
        () async {
      await settingsController.setPreferredMachineId('pref-de1');
      mockDe1Controller.de1Subject.add(_FakeDe1(deviceId: 'pref-de1'));
      await pumpCycles(2);

      var scanStarts = 0;
      final sub = mockScanner.scanningStream.listen((s) {
        if (s) scanStarts++;
      });

      mockScanner.mockDeviceAttached(deviceId: 'pref-de1');
      await pumpCycles();

      expect(connectionManager.attachTriggeredConnects, 0);
      expect(scanStarts, 0);
      await sub.cancel();
    });

    test('an attach that finds nothing falls back to the reconnect backoff',
        () async {
      await settingsController.setPreferredMachineId('pref-de1');
      // Device is NOT in the scan results — e.g. the port was not ready yet.

      mockScanner.mockDeviceAttached(deviceId: 'pref-de1');
      await pumpCycles();

      expect(connectionManager.attachTriggeredConnects, 1);
      expect(mockDe1Controller.connectCalls, isEmpty);
      expect(
        connectionManager.machineRecoveryActive,
        isTrue,
        reason: 'the backoff loop must still be armed as the fallback',
      );

      // And the fallback actually reconnects once the port shows up.
      mockScanner.addDevice(_FakeDe1(deviceId: 'pref-de1'));
      await pumpCycles();
      expect(
        mockDe1Controller.connectCalls.map((d) => d.deviceId),
        contains('pref-de1'),
      );
    });

    test('no preferred machine → an attach still scans but never arms a '
        'background retry loop', () async {
      // A background retry with no preference could pop a machine picker; the
      // attach fast-path must respect the same rule as the recovery loop.
      mockScanner.mockDeviceAttached(deviceId: 'some-usb-thing');
      await pumpCycles();

      expect(connectionManager.attachTriggeredConnects, 1);
      expect(connectionManager.machineRecoveryActive, isFalse);
    });

    test('BLE-only setups are unaffected: no attach events, no extra scans',
        () async {
      // A BLE (or Wi-Fi, or simulated) service is not a DeviceAttachNotifier,
      // so DeviceScanner.deviceAttached never emits for it.
      await settingsController.setPreferredMachineId('ble-de1');
      mockScanner.addDevice(_FakeDe1(deviceId: 'ble-de1'));

      var scanStarts = 0;
      final sub = mockScanner.scanningStream.listen((s) {
        if (s) scanStarts++;
      });

      await pumpCycles();

      expect(connectionManager.attachTriggeredConnects, 0);
      expect(scanStarts, 0);
      expect(mockDe1Controller.connectCalls, isEmpty);
      await sub.cancel();
    });
  });
}
