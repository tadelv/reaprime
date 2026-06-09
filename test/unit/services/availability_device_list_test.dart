import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/remembered_device.dart';
import 'package:reaprime/src/services/webserver_service.dart';

/// Minimal live Device for exercising the availability merge.
class _FakeDevice implements Device {
  @override
  final String deviceId;
  @override
  final String name;
  @override
  final DeviceType type;
  final ConnectionState _state;
  _FakeDevice(this.deviceId, this.name, this.type,
      [this._state = ConnectionState.connected]);

  @override
  Stream<ConnectionState> get connectionState => Stream.value(_state);
  @override
  Future<void> onConnect() async {}
  @override
  Future<void> disconnect() async {}
}

void main() {
  group('buildAvailabilityDeviceList', () {
    test('a present device is available:true with its real state', () async {
      final list = await buildAvailabilityDeviceList(
        [_FakeDevice('s1', 'Scale', DeviceType.scale, ConnectionState.connected)],
        const [],
      );
      expect(list, hasLength(1));
      expect(list[0]['id'], 's1');
      expect(list[0]['available'], isTrue);
      expect(list[0]['state'], 'connected');
    });

    test('a remembered-but-absent device is available:false, disconnected',
        () async {
      final list = await buildAvailabilityDeviceList(
        const [],
        [const RememberedDevice(id: 'wifi:hds.local', name: 'HDS', type: DeviceType.scale)],
      );
      expect(list, hasLength(1));
      expect(list[0]['id'], 'wifi:hds.local');
      expect(list[0]['available'], isFalse);
      expect(list[0]['state'], 'disconnected');
      expect(list[0]['type'], 'scale');
    });

    test('a remembered device that IS present is listed once, as available',
        () async {
      final list = await buildAvailabilityDeviceList(
        [_FakeDevice('s1', 'Scale', DeviceType.scale)],
        [const RememberedDevice(id: 's1', name: 'Scale', type: DeviceType.scale)],
      );
      expect(list, hasLength(1));
      expect(list[0]['available'], isTrue);
    });

    test('a non-remembered absent device does not appear', () async {
      // Only the live present device shows; nothing is synthesized.
      final list = await buildAvailabilityDeviceList(
        [_FakeDevice('present', 'P', DeviceType.machine)],
        const [],
      );
      expect(list.map((d) => d['id']), ['present']);
    });

    test('mix: present + remembered-absent', () async {
      final list = await buildAvailabilityDeviceList(
        [_FakeDevice('m1', 'DE1', DeviceType.machine)],
        [
          const RememberedDevice(id: 'm1', name: 'DE1', type: DeviceType.machine),
          const RememberedDevice(id: 's-gone', name: 'Scale', type: DeviceType.scale),
        ],
      );
      final byId = {for (final d in list) d['id']: d};
      expect(byId['m1']!['available'], isTrue);
      expect(byId['s-gone']!['available'], isFalse);
    });
  });
}
