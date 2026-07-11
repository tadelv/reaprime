import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/services/serial/usb_ids.dart';

void main() {
  group('matchUsbDevice', () {
    const a = (0x1234, 0x5678);
    const b = (0xABCD, 0x0001);

    test('returns the model for a matching pair', () {
      const table = {
        UsbDeviceModel.de1: [a],
        UsbDeviceModel.bengle: [b],
      };
      expect(matchUsbDevice(table, vid: a.$1, pid: a.$2),
          equals(UsbDeviceModel.de1));
      expect(matchUsbDevice(table, vid: b.$1, pid: b.$2),
          equals(UsbDeviceModel.bengle));
    });

    test('returns null for an unknown pair', () {
      const table = {
        UsbDeviceModel.de1: [a],
      };
      expect(matchUsbDevice(table, vid: 0xFFFF, pid: 0xFFFF), isNull);
    });

    test('returns null when vid or pid is null', () {
      const table = {
        UsbDeviceModel.de1: [a],
      };
      expect(matchUsbDevice(table, vid: null, pid: a.$2), isNull);
      expect(matchUsbDevice(table, vid: a.$1, pid: null), isNull);
      expect(matchUsbDevice(table, vid: null, pid: null), isNull);
    });

    test('handles entries with multiple pairs per model', () {
      const c = (0x1111, 0x2222);
      const table = {
        UsbDeviceModel.de1: [a, c],
      };
      expect(matchUsbDevice(table, vid: c.$1, pid: c.$2),
          equals(UsbDeviceModel.de1));
    });
  });

  group('default usbDeviceTable', () {
    test('returns null for a clearly unrelated pair', () {
      // Sanity check: real table doesn't false-match on something random.
      expect(matchUsbDevice(usbDeviceTable, vid: 0xFFFF, pid: 0xFFFF), isNull);
    });
  });

  group('Bengle probe-candidate pair', () {
    test('bengleUsbIds stays empty — TinyUSB defaults are too generic', () {
      // 0x2E8A:0x000A is EVERY default pico-sdk CDC device. It may only
      // qualify a port for the v13Model probe (bengleProbeCandidateIds),
      // never identify one. Adding it here would claim random hobby
      // boards as espresso machines.
      expect(bengleUsbIds, isEmpty);
      expect(bengleProbeCandidateIds, contains((0x2E8A, 0x000A)));
    });

    test('the TinyUSB-default pair never direct-instantiates', () {
      expect(
        matchUsbDevice(usbDeviceTable, vid: 0x2E8A, pid: 0x000A),
        isNull,
        reason:
            'the pair feeds the probe path only — the v13Model read '
            'stays the authority on what the device is',
      );
    });
  });
}
