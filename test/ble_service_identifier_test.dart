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

    test('long constructor with base UUID pattern extracts short form', () {
      final identifier =
          BleServiceIdentifier.long('0000ff08-0000-1000-8000-00805f9b34fb');

      expect(identifier.short, equals('ff08'));
      expect(
          identifier.long, equals('0000ff08-0000-1000-8000-00805f9b34fb'));
    });

    test('long constructor with custom UUID cannot extract short form', () {
      final identifier =
          BleServiceIdentifier.long('06c31822-8682-4744-9211-febc93e3bece');

      expect(
          identifier.long, equals('06c31822-8682-4744-9211-febc93e3bece'));
      expect(() => identifier.short, throwsStateError);
    });
  });
}
