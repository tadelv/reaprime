import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/services/serial/utils.dart';

void main() {
  group('computeUsbStableId', () {
    test('builds ID from vid, pid, and serial', () {
      expect(
        computeUsbStableId(vid: 0x1a86, pid: 0x7522, serial: 'ABC123'),
        equals('usb-1a86-7522-ABC123'),
      );
    });

    test('uses "unknown" when serial is null', () {
      expect(
        computeUsbStableId(vid: 0x1a86, pid: 0x7522, serial: null),
        equals('usb-1a86-7522-unknown'),
      );
    });

    test('uses "unknown" when serial is empty', () {
      expect(
        computeUsbStableId(vid: 0x1a86, pid: 0x7522, serial: ''),
        equals('usb-1a86-7522-unknown'),
      );
    });

    test('returns null when vid is null', () {
      expect(
        computeUsbStableId(vid: null, pid: 0x7522, serial: 'ABC'),
        isNull,
      );
    });

    test('returns null when pid is null', () {
      expect(
        computeUsbStableId(vid: 0x1a86, pid: null, serial: 'ABC'),
        isNull,
      );
    });
  });
}
