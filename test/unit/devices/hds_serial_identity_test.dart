import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/impl/decent_scale/scale_serial.dart';

import 'hds_serial_disconnect_test.dart';

void main() {
  group('HDSSerial identity', () {
    test('deviceId comes from transport.id', () {
      final transport = MockSerialTransport();
      // MockSerialTransport.id returns 'mock-serial'
      final hds = HDSSerial(transport: transport);
      expect(hds.deviceId, equals('mock-serial'));
    });

    test('deviceId is transport.id not transport.name', () {
      final transport = MockSerialTransport();
      // id = 'mock-serial', name = 'MockSerial'
      final hds = HDSSerial(transport: transport);
      expect(hds.deviceId, isNot(equals('MockSerial')));
      expect(hds.deviceId, equals('mock-serial'));
    });
  });
}
