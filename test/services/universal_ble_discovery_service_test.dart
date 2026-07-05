import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/combustion/combustion_constants.dart';
import 'package:reaprime/src/models/device/impl/combustion/combustion_probe.dart';
import 'package:reaprime/src/models/device/impl/decent_scale/scale.dart';
import 'package:reaprime/src/services/universal_ble_discovery_service.dart';
import 'package:universal_ble/universal_ble.dart';

void main() {
  group('UniversalBleDiscoveryService', () {
    late UniversalBleDiscoveryService service;

    setUp(() {
      service = UniversalBleDiscoveryService();
    });

    Future<List<Device>> processAndAwaitDevices(BleDevice bleDevice) async {
      final devicesSeen = Completer<List<Device>>();
      final subscription = service.devices.listen(devicesSeen.complete);
      addTearDown(subscription.cancel);
      await service.processScannedDeviceForTesting(bleDevice);
      return devicesSeen.future;
    }

    test(
      'empty name with Combustion manufacturer ID discovers sensor',
      () async {
        final devices = await processAndAwaitDevices(
          BleDevice(
            deviceId: 'combustion-probe-1',
            name: '',
            manufacturerDataList: [
              ManufacturerData(
                CombustionConstants.manufacturerCompanyId,
                Uint8List(0),
              ),
            ],
          ),
        );

        expect(devices, hasLength(1));
        expect(devices.single, isA<CombustionProbe>());
        expect(devices.single.deviceId, 'combustion-probe-1');
      },
    );

    test('empty name without Combustion metadata is ignored', () async {
      var emissionCount = 0;
      final subscription = service.devices.listen((_) => emissionCount++);
      addTearDown(subscription.cancel);

      await service.processScannedDeviceForTesting(
        BleDevice(
          deviceId: 'unknown-peripheral',
          name: '',
          manufacturerDataList: [
            ManufacturerData(0x004C, Uint8List(0)),
          ],
        ),
      );

      expect(emissionCount, 0);
    });

    test('named Decent Scale still discovers via name match', () async {
      final devices = await processAndAwaitDevices(
        BleDevice(
          deviceId: 'decent-scale-1',
          name: 'Decent Scale',
        ),
      );

      expect(devices, hasLength(1));
      expect(devices.single, isA<DecentScale>());
    });
  });
}
