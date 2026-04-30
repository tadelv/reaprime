import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/impl/bengle/mock_bengle.dart';
import 'package:reaprime/src/models/device/impl/mock_de1/mock_de1.dart';
import 'package:reaprime/src/services/simulated_device_service.dart';
import 'package:reaprime/src/settings/settings_service.dart';

void main() {
  group('SimulatedDeviceService', () {
    test('emits a MockBengle when bengle is enabled', () async {
      final service = SimulatedDeviceService();
      service.enabledDevices = {SimulatedDevicesTypes.bengle};

      final emission = service.devices.first;
      await service.scanForDevices();
      final devices = await emission;

      expect(devices.whereType<MockBengle>(), hasLength(1));
    });

    test('does not emit MockBengle when only machine is enabled', () async {
      final service = SimulatedDeviceService();
      service.enabledDevices = {SimulatedDevicesTypes.machine};

      final emission = service.devices.first;
      await service.scanForDevices();
      final devices = await emission;

      expect(devices.whereType<MockDe1>(), hasLength(1));
      expect(devices.whereType<MockBengle>(), isEmpty);
    });

    test('emits both MockDe1 and MockBengle when both enabled', () async {
      final service = SimulatedDeviceService();
      service.enabledDevices = {
        SimulatedDevicesTypes.machine,
        SimulatedDevicesTypes.bengle,
      };

      final emission = service.devices.first;
      await service.scanForDevices();
      final devices = await emission;

      // MockBengle extends MockDe1, so the type filter matches both —
      // count by deviceId instead.
      final ids = devices.map((d) => d.deviceId).toSet();
      expect(ids, containsAll(['MockDe1', 'MockBengle']));
    });

    test('removes MockBengle when bengle becomes disabled', () async {
      final service = SimulatedDeviceService();
      service.enabledDevices = {SimulatedDevicesTypes.bengle};
      await service.scanForDevices();

      // Switching to a different non-empty set so the next scan still
      // emits (empty enabledDevices early-returns without emission).
      service.enabledDevices = {SimulatedDevicesTypes.machine};
      final emission = service.devices.first;
      await service.scanForDevices();
      final devices = await emission;

      expect(devices.whereType<MockBengle>(), isEmpty);
    });
  });
}
