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

    test('both constructor accepts explicit short and long UUIDs', () {
      final identifier = BleServiceIdentifier.both(
          'fff0', '0000fff0-0000-1000-8000-00805f9b34fb');

      expect(identifier.short, equals('fff0'));
      expect(
          identifier.long, equals('0000fff0-0000-1000-8000-00805f9b34fb'));
    });

    test('short constructor validates 4 hex chars', () {
      expect(() => BleServiceIdentifier.short('fff'), throwsArgumentError);
      expect(() => BleServiceIdentifier.short('fffff'), throwsArgumentError);
      expect(() => BleServiceIdentifier.short('gggg'), throwsArgumentError);
    });

    test('long constructor validates UUID pattern', () {
      expect(() => BleServiceIdentifier.long('invalid'), throwsArgumentError);
      expect(() => BleServiceIdentifier.long('0000fff0'), throwsArgumentError);
    });

    test('both constructor requires at least one UUID', () {
      expect(() => BleServiceIdentifier.both('', ''), throwsArgumentError);
    });

    test('identifiers with same long form are equal', () {
      final id1 = BleServiceIdentifier.short('fff0');
      final id2 =
          BleServiceIdentifier.long('0000fff0-0000-1000-8000-00805f9b34fb');

      expect(id1, equals(id2));
      expect(id1.hashCode, equals(id2.hashCode));
    });

    test('identifiers with different long forms are not equal', () {
      final id1 = BleServiceIdentifier.short('fff0');
      final id2 = BleServiceIdentifier.short('ff08');

      expect(id1, isNot(equals(id2)));
    });

    test('parse auto-detects short UUID', () {
      final id = BleServiceIdentifier.parse('fff0');
      expect(id.short, equals('fff0'));
      expect(id.long, equals('0000fff0-0000-1000-8000-00805f9b34fb'));
    });

    test('parse auto-detects long UUID', () {
      final id = BleServiceIdentifier.parse(
          '06c31822-8682-4744-9211-febc93e3bece');
      expect(id.long, equals('06c31822-8682-4744-9211-febc93e3bece'));
    });

    test('parse throws on invalid UUID', () {
      expect(() => BleServiceIdentifier.parse('zzzz'), throwsArgumentError);
      expect(() => BleServiceIdentifier.parse('invalid'), throwsArgumentError);
    });

    test('parse result equals explicitly constructed identifiers', () {
      final parsed = BleServiceIdentifier.parse('fff0');
      final explicit = BleServiceIdentifier.short('fff0');
      expect(parsed, equals(explicit));
    });

    test('can be used as Map keys', () {
      final map = <BleServiceIdentifier, String>{};
      final key1 = BleServiceIdentifier.short('fff0');
      final key2 =
          BleServiceIdentifier.long('0000fff0-0000-1000-8000-00805f9b34fb');

      map[key1] = 'value';
      expect(map[key2], equals('value'));
    });
  });
}
