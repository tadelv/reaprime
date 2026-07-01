import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/bengle/mock_bengle.dart';
import 'package:reaprime/src/models/device/impl/combustion/combustion_constants.dart';
import 'package:reaprime/src/models/device/impl/combustion/mock_combustion_probe.dart';
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

    test('reuses the same device instances across repeated scans', () async {
      final service = SimulatedDeviceService();
      service.enabledDevices = {
        SimulatedDevicesTypes.machine,
        SimulatedDevicesTypes.scale,
      };

      final firstEmission = service.devices.first;
      await service.scanForDevices();
      final first = await firstEmission;

      final secondEmission = service.devices.first;
      await service.scanForDevices();
      final second = await secondEmission;

      final firstMachine = first.firstWhere((d) => d.deviceId == 'MockDe1');
      final secondMachine = second.firstWhere((d) => d.deviceId == 'MockDe1');
      expect(identical(firstMachine, secondMachine), isTrue,
          reason: 'rescan must not replace the existing MockDe1 instance');

      final firstScale = first.firstWhere((d) => d.deviceId == 'MockScale');
      final secondScale = second.firstWhere((d) => d.deviceId == 'MockScale');
      expect(identical(firstScale, secondScale), isTrue,
          reason: 'rescan must not replace the existing MockScale instance');
    });

    test('keeps a connected device connected across a rescan', () async {
      final service = SimulatedDeviceService();
      service.enabledDevices = {SimulatedDevicesTypes.scale};

      final firstEmission = service.devices.first;
      await service.scanForDevices();
      final first = await firstEmission;
      final scale = first.firstWhere((d) => d.deviceId == 'MockScale');
      await scale.onConnect();
      expect(await scale.connectionState.first, ConnectionState.connected);

      // A subsequent scan (e.g. the preferred-scale reconnect retry) must
      // not clobber the connected instance with a fresh `discovered` one.
      final secondEmission = service.devices.first;
      await service.scanForDevices();
      final second = await secondEmission;
      final scaleAfter = second.firstWhere((d) => d.deviceId == 'MockScale');
      expect(await scaleAfter.connectionState.first, ConnectionState.connected,
          reason: 'rescan replaced the connected scale with a discovered one');
    });

    test('emits MockCombustionProbe when sensor is enabled', () async {
      final service = SimulatedDeviceService();
      service.enabledDevices = {SimulatedDevicesTypes.sensor};

      final emission = service.devices.first;
      await service.scanForDevices();
      final devices = await emission;

      expect(devices.whereType<MockCombustionProbe>(), hasLength(1));
    });

    test('does not emit MockCombustionProbe when only machine is enabled',
        () async {
      final service = SimulatedDeviceService();
      service.enabledDevices = {SimulatedDevicesTypes.machine};

      final emission = service.devices.first;
      await service.scanForDevices();
      final devices = await emission;

      expect(devices.whereType<MockCombustionProbe>(), isEmpty);
    });

    test('MockCombustionProbe exposes controllable temperature stream', () async {
      final service = SimulatedDeviceService();
      service.enabledDevices = {SimulatedDevicesTypes.sensor};

      final emission = service.devices.first;
      await service.scanForDevices();
      final devices = await emission;
      final probe = devices.whereType<MockCombustionProbe>().single;

      final readings = <Map<String, dynamic>>[];
      final sub = probe.data.listen(readings.add);
      await probe.onConnect();
      probe.setTemperature(65.5, core: 62.5, t1: 60.0);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      await probe.disconnect();

      expect(readings, isNotEmpty);
      expect(
        readings.last[CombustionConstants.channelTemperature],
        closeTo(62.5, 0.0001),
      );
      expect(readings.last[CombustionConstants.channelT1], closeTo(60.0, 0.0001));
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
