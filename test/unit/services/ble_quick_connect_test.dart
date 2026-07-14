import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/device_implementation.dart';
import 'package:reaprime/src/models/device/remembered_device.dart';
import 'package:reaprime/src/models/device/transport/data_transport.dart';
import 'package:reaprime/src/services/universal_ble_discovery_service.dart';

void main() {
  group('UniversalBleDiscoveryService.tryQuickConnect contract', () {
    final service = UniversalBleDiscoveryService();

    test('returns null when implementation is null', () async {
      const remembered = RememberedDevice(
        id: 'AA:11:11:11:11:11',
        name: 'DE1',
        type: DeviceType.machine,
        transportType: TransportType.ble,
      );
      final result = await service.tryQuickConnect(remembered);
      expect(result, isNull);
    });

    test('returns null when transportType is null', () async {
      const remembered = RememberedDevice(
        id: 'AA:11:11:11:11:11',
        name: 'DE1',
        type: DeviceType.machine,
        implementation: DeviceImplementation.unifiedDe1,
      );
      final result = await service.tryQuickConnect(remembered);
      expect(result, isNull);
    });

    test('returns null when transportType is not ble', () async {
      const remembered = RememberedDevice(
        id: 'serial-ttyUSB0',
        name: 'HDS',
        type: DeviceType.scale,
        implementation: DeviceImplementation.hdsSerial,
        transportType: TransportType.serial,
      );
      final result = await service.tryQuickConnect(remembered);
      expect(result, isNull);
    });

    test('returns null for serial-only implementation with ble transport', () async {
      const remembered = RememberedDevice(
        id: 'AA:11:11:11:11:11',
        name: 'HDS',
        type: DeviceType.scale,
        implementation: DeviceImplementation.hdsSerial,
        transportType: TransportType.ble,
      );
      final result = await service.tryQuickConnect(remembered);
      expect(result, isNull);
    });
  });
}