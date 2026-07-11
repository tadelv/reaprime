import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/connection_manager.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/settings/settings_controller.dart';

import '../helpers/mock_de1_controller.dart';
import '../helpers/mock_device_discovery_service.dart';
import '../helpers/mock_device_scanner.dart';
import '../helpers/mock_scale_controller.dart';
import '../helpers/mock_settings_service.dart';

/// Minimal De1Interface stub (mirrors connection_manager_test.dart's
/// _FakeDe1) whose deviceId can look like a USB stable id or a BLE MAC.
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

  @override
  Stream<MachineSnapshot> get currentSnapshot => const Stream.empty();

  _FakeDe1({required this.deviceId, String? name})
    : name = name ?? 'DE1-$deviceId';

  @override
  Future<void> disconnect() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// invariant 12f: the preferred machine is stored per TRANSPORT id
/// (`connectMachine` saves `machine.deviceId`; a serial device's id is the
/// `usb-<vid>-<pid>-<serial>` stable id, a BLE device's is its MAC).
/// Nothing maps a BLE preference onto the same physical machine's USB
/// identity — deliberately. So the first wired session ends at the picker;
/// picking the USB machine once makes IT the preference, and later
/// launches auto-connect over the wire. Do not "fix" this by aliasing
/// identities.
void main() {
  const bleMac = 'AA:BB:CC:DD:EE:FF';
  const usbStableId = 'usb-2e8a-a-unknown';

  late MockDeviceScanner mockScanner;
  late MockDe1Controller mockDe1Controller;
  late MockScaleController mockScaleController;
  late SettingsController settingsController;

  ConnectionManager buildManager() => ConnectionManager(
    deviceScanner: mockScanner,
    de1Controller: mockDe1Controller,
    scaleController: mockScaleController,
    settingsController: settingsController,
  );

  setUp(() async {
    mockScanner = MockDeviceScanner();
    mockDe1Controller = MockDe1Controller(
      controller: DeviceController([MockDeviceDiscoveryService()]),
    );
    mockScaleController = MockScaleController();
    settingsController = SettingsController(MockSettingsService());
    await settingsController.loadSettings();
  });

  tearDown(() {
    mockScanner.dispose();
  });

  test('first wired session ends at the picker (BLE preference does not '
      'match the USB identity)', () async {
    // The user has been connecting over BLE — the stored preference is
    // the machine's BLE MAC.
    await settingsController.setPreferredMachineId(bleMac);

    // Today only the wire finds the machine (e.g. Bluetooth off): the
    // same physical machine appears under its USB stable id.
    final wiredDe1 = _FakeDe1(deviceId: usbStableId, name: 'Bengle');
    mockScanner.addDevice(wiredDe1);
    await Future.delayed(Duration.zero);

    final manager = buildManager();
    addTearDown(manager.dispose);
    await manager.connect();
    await Future.delayed(Duration.zero);

    expect(
      mockDe1Controller.connectCalls,
      isEmpty,
      reason: 'the BLE preference must not auto-claim the USB identity',
    );
    expect(manager.currentStatus.phase, ConnectionPhase.idle);
    expect(
      manager.currentStatus.pendingAmbiguity,
      AmbiguityReason.machinePicker,
      reason: 'the wired-only first session must surface the picker',
    );
    expect(manager.currentStatus.foundMachines, [wiredDe1]);
  });

  test(
    'picking the USB machine stores its stable id as the preference',
    () async {
      await settingsController.setPreferredMachineId(bleMac);
      final wiredDe1 = _FakeDe1(deviceId: usbStableId, name: 'Bengle');

      final manager = buildManager();
      addTearDown(manager.dispose);
      await manager.connectMachine(wiredDe1);

      expect(mockDe1Controller.connectCalls, [same(wiredDe1)]);
      expect(
        settingsController.preferredMachineId,
        usbStableId,
        reason:
            'the preference is per transport id — picking the wired '
            'machine replaces the BLE MAC with the USB stable id',
      );
      expect(manager.currentStatus.phase, ConnectionPhase.ready);
    },
  );

  test('a later launch auto-connects the preferred wired machine', () async {
    // The previous session picked the USB machine; its stable id is now
    // the preference.
    await settingsController.setPreferredMachineId(usbStableId);

    final wiredDe1 = _FakeDe1(deviceId: usbStableId, name: 'Bengle');
    mockScanner.addDevice(wiredDe1);
    await Future.delayed(Duration.zero);

    // A fresh manager, as on app launch.
    final manager = buildManager();
    addTearDown(manager.dispose);
    await manager.connect();
    await Future.delayed(Duration.zero);

    expect(mockDe1Controller.connectCalls, hasLength(1));
    expect(mockDe1Controller.connectCalls.single.deviceId, usbStableId);
    expect(manager.currentStatus.phase, ConnectionPhase.ready);
    expect(
      manager.currentStatus.pendingAmbiguity,
      isNull,
      reason: 'no picker on later launches — the wire auto-connects',
    );
  });
}
