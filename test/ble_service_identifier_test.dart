import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/ble_service_identifier.dart';

void main() {
  group('BleServiceIdentifier', () {
    test('short constructor expands to Bluetooth SIG base UUID', () {
      final identifier = BleServiceIdentifier.short('fff0');

      expect(identifier.short, equals('fff0'));
      expect(
          identifier.long, equals('0000fff0-0000-1000-8000-00805f9b34fb'));
    });
  });
}
