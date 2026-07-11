import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/services/serial/serial_service_android.dart';
import 'package:reaprime/src/services/serial/usb_ids.dart';
import 'package:reaprime/src/services/serial/utils.dart';

// usb_serial is pulled in transitively via flutter_libserialport's git source.
// ignore: depend_on_referenced_packages
import 'package:usb_serial/usb_serial.dart';

UsbDevice _usbDevice({String? productName, int? vid, int? pid}) => UsbDevice(
  '/dev/bus/usb/001/002',
  vid,
  pid,
  productName,
  null, // manufacturerName
  42, // deviceId
  null, // serial
  1, // interfaceCount
);

void main() {
  group('serialProbeAllowsProductName', () {
    test('allows "Bengle"', () {
      expect(
        serialProbeAllowsProductName('Bengle'),
        isTrue,
        reason:
            'the pre-filter used to drop a Bengle board before the '
            'v13Model probe ever ran',
      );
    });

    test('allows "DE1"', () {
      expect(serialProbeAllowsProductName('DE1'), isTrue);
    });

    test('allows "Half Decent Scale"', () {
      expect(serialProbeAllowsProductName('Half Decent Scale'), isTrue);
    });

    test('allows generic serial adapters (name contains "Serial")', () {
      expect(serialProbeAllowsProductName('USB Serial Port'), isTrue);
      expect(serialProbeAllowsProductName('CP2102 USB to Serial'), isTrue);
    });

    test('allows unknown (null) product names — probe decides', () {
      expect(serialProbeAllowsProductName(null), isTrue);
    });

    test('rejects unrelated devices', () {
      expect(serialProbeAllowsProductName('Gaming Mouse'), isFalse);
      expect(
        serialProbeAllowsProductName('bengle'),
        isFalse,
        reason: 'exact match only — the USB descriptor string is fixed',
      );
    });
  });

  group('isBengleProbeCandidate', () {
    test('admits the captured Bengle VID:PID (TinyUSB defaults)', () {
      expect(
        isBengleProbeCandidate(vid: 0x2E8A, pid: 0x000A),
        isTrue,
        reason:
            'firmware enumerates as "TinyUSB Device", so the name '
            'gate alone would drop a real Bengle',
      );
    });

    test('rejects other ids and null', () {
      expect(
        isBengleProbeCandidate(vid: 0x2E8A, pid: 0x000C),
        isFalse,
        reason: 'Pi debug probe shares the vendor id',
      );
      expect(isBengleProbeCandidate(vid: null, pid: 0x000A), isFalse);
    });
  });

  group('SerialServiceAndroid.shouldProbeUsbDevice — the OR call-site '
      '', () {
    // This is the gate `_detectDevice` actually evaluates: name gate OR
    // probe candidate. The predicate tests above don't lock the
    // combination, and the combination IS the fix — the old inline check
    // dropped a TinyUSB-default Bengle before any shortcut/probe ran.
    test(
      'TinyUSB-default Bengle passes on VID:PID despite the useless name',
      () {
        expect(
          SerialServiceAndroid.shouldProbeUsbDevice(
            _usbDevice(
              productName: 'TinyUSB Device',
              vid: 0x2E8A,
              pid: 0x000A,
            ),
          ),
          isTrue,
          reason:
              '"TinyUSB Device" fails the name gate; the probe-candidate '
              'VID:PID must still admit it',
        );
      },
    );

    test('a named Bengle passes even with unknown ids', () {
      expect(
        SerialServiceAndroid.shouldProbeUsbDevice(
          _usbDevice(productName: 'Bengle', vid: 0x1234, pid: 0x5678),
        ),
        isTrue,
      );
    });

    test('null name with null ids still reaches the probe', () {
      expect(
        SerialServiceAndroid.shouldProbeUsbDevice(_usbDevice()),
        isTrue,
        reason: 'Android often reports null before permission is granted',
      );
    });

    test('unrelated name + unrelated ids is skipped', () {
      expect(
        SerialServiceAndroid.shouldProbeUsbDevice(
          _usbDevice(productName: 'Gaming Mouse', vid: 0x046D, pid: 0xC08B),
        ),
        isFalse,
      );
    });

    test('the Pi debug probe (shared vendor id) is skipped', () {
      expect(
        SerialServiceAndroid.shouldProbeUsbDevice(
          _usbDevice(
            productName: 'Debug Probe (CMSIS-DAP)',
            vid: 0x2E8A,
            pid: 0x000C,
          ),
        ),
        isFalse,
      );
    });
  });
}
