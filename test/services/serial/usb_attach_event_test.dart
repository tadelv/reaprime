import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/device_attach_notifier.dart';
import 'package:reaprime/src/services/serial/serial_service_android.dart';

// usb_serial is pulled in transitively via flutter_libserialport's git source,
// exactly as in serial_service_android.dart.
// ignore: depend_on_referenced_packages
import 'package:usb_serial/usb_serial.dart';

/// `ACTION_USB_DEVICE_ATTACHED` arrived, was logged, and was dropped in
/// `default:` — so a machine sat on the bus for 20.3 s (measured; up to 60 s at
/// the backoff cap) before the next scan found it.
///
/// `handleUsbEvent` is the extracted seam: these drive it directly, no Android
/// device required.
UsbEvent _event(String action, {UsbDevice? device}) {
  return UsbEvent()
    ..event = action
    ..device = device;
}

/// A USB serial machine as Android reports it: the TinyUSB/pico-sdk default
/// VID:PID and product string, and a factory serial that is stable across
/// power-cycles and reflashes (so the stable id survives a re-enumeration).
UsbDevice _machine({String? serial = '8549628789ABCDEF'}) => UsbDevice(
      '/dev/bus/usb/001/002',
      0x2E8A,
      0x000A,
      'TinyUSB Device',
      'Decent Espresso',
      1002,
      serial,
      1,
    );

UsbDevice _keyboard() => UsbDevice(
      '/dev/bus/usb/001/003',
      0x046D,
      0xC31C,
      'USB Keyboard',
      'Logitech',
      1003,
      'kbd-1',
      1,
    );

void main() {
  group('SerialServiceAndroid USB attach intent', () {
    test('is a DeviceAttachNotifier', () {
      expect(SerialServiceAndroid(), isA<DeviceAttachNotifier>());
    });

    test('an attach announces the device with its stable id', () async {
      final service = SerialServiceAndroid();
      final events = <DeviceAttachedEvent>[];
      final sub = service.deviceAttached.listen(events.add);

      service.handleUsbEvent(
        _event(UsbEvent.ACTION_USB_ATTACHED, device: _machine()),
      );
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events.single.deviceId, 'usb-2e8a-a-8549628789ABCDEF');
      expect(events.single.name, 'TinyUSB Device');
      await sub.cancel();
    });

    test('an attach whose device has no serial is still announced', () async {
      // The id degrades to `…-unknown`, but the arrival edge is what matters:
      // the scan that follows re-reads the descriptors with permission.
      final service = SerialServiceAndroid();
      final events = <DeviceAttachedEvent>[];
      final sub = service.deviceAttached.listen(events.add);

      service.handleUsbEvent(
        _event(UsbEvent.ACTION_USB_ATTACHED, device: _machine(serial: null)),
      );
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      await sub.cancel();
    });

    test('an attach with no device info at all is still announced', () async {
      final service = SerialServiceAndroid();
      final events = <DeviceAttachedEvent>[];
      final sub = service.deviceAttached.listen(events.add);

      service.handleUsbEvent(_event(UsbEvent.ACTION_USB_ATTACHED));
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events.single.deviceId, isNull);
      await sub.cancel();
    });

    test('an uninteresting device is announced too — the scan is the filter',
        () async {
      // The attach edge is a hint, not an admission decision. Announcing
      // everything keeps this notifier dumb, and dumb is right here: the scan
      // that follows already calls `_detectDevice` on every enumerated port, so
      // a keyboard costs one no-op scan and nothing else. Filtering *here*
      // would mean the notifier could wrongly suppress a real machine whose
      // descriptors Android reports late or incompletely — which it does (see
      // the null-serial case above).
      final service = SerialServiceAndroid();
      final events = <DeviceAttachedEvent>[];
      final sub = service.deviceAttached.listen(events.add);

      service.handleUsbEvent(
        _event(UsbEvent.ACTION_USB_ATTACHED, device: _keyboard()),
      );
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events.single.deviceId, 'usb-46d-c31c-kbd-1');
      await sub.cancel();
    });

    test('a detach announces nothing on the attach stream', () async {
      final service = SerialServiceAndroid();
      final events = <DeviceAttachedEvent>[];
      final sub = service.deviceAttached.listen(events.add);

      service.handleUsbEvent(
        _event(UsbEvent.ACTION_USB_DETACHED, device: _machine()),
      );
      await Future<void>.delayed(Duration.zero);

      expect(events, isEmpty);
      await sub.cancel();
    });

    test('an unknown USB action announces nothing', () async {
      final service = SerialServiceAndroid();
      final events = <DeviceAttachedEvent>[];
      final sub = service.deviceAttached.listen(events.add);

      service.handleUsbEvent(
        _event('android.hardware.usb.action.USB_ACCESSORY_ATTACHED'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(events, isEmpty);
      await sub.cancel();
    });

    test('the attach stream does not replay to a late subscriber', () async {
      // A replayed attach would make a late-attaching ConnectionManager scan
      // for a device that arrived (and possibly left again) long ago.
      final service = SerialServiceAndroid();
      service.handleUsbEvent(
        _event(UsbEvent.ACTION_USB_ATTACHED, device: _machine()),
      );
      await Future<void>.delayed(Duration.zero);

      final events = <DeviceAttachedEvent>[];
      final sub = service.deviceAttached.listen(events.add);
      await Future<void>.delayed(Duration.zero);

      expect(events, isEmpty);
      await sub.cancel();
    });
  });
}
