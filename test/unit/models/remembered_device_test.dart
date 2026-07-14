import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/remembered_device.dart';
import 'package:reaprime/src/models/device/simulated_device.dart';
import 'package:reaprime/src/models/device/device_implementation.dart';
import 'package:reaprime/src/models/device/transport/data_transport.dart';

class _RealDevice implements Device {
  @override
  final String deviceId;
  @override
  final String name;
  @override
  final DeviceType type;
  @override
  DeviceImplementation get implementation => DeviceImplementation.unifiedDe1;
  @override
  TransportType get transportType => TransportType.unknown;
  _RealDevice(this.deviceId, this.name, this.type);
  @override
  Stream<ConnectionState> get connectionState => const Stream.empty();
  @override
  Future<void> onConnect() async {}
  @override
  Future<void> disconnect() async {}
}

class _MockDevice extends _RealDevice implements SimulatedDevice {
  _MockDevice(super.id, super.name, super.type);
}

void main() {
  group('RememberedDevice.fromDevice', () {
    test('builds a record from a real device', () {
      final r = RememberedDevice.fromDevice(
          _RealDevice('wifi:hds.local', 'HDS', DeviceType.scale));
      expect(r, isNotNull);
      expect(r!.id, 'wifi:hds.local');
      expect(r.type, DeviceType.scale);
    });

    test('returns null for a simulated device (never remembered)', () {
      expect(
          RememberedDevice.fromDevice(
              _MockDevice('MockScale', 'Mock Scale', DeviceType.scale)),
          isNull);
    });
  });

  group('RememberedDevice', () {
    test('toJson/fromJson round-trips', () {
      const d = RememberedDevice(
          id: 'wifi:hds.local', name: 'Half Decent Scale (WiFi)', type: DeviceType.scale);
      final back = RememberedDevice.fromJson(d.toJson());
      expect(back, isNotNull);
      expect(back!.id, d.id);
      expect(back.name, d.name);
      expect(back.type, DeviceType.scale);
    });

    test('fromJson rejects malformed / unknown type / empty id', () {
      expect(RememberedDevice.fromJson({'id': 'x'}), isNull);
      expect(
          RememberedDevice.fromJson(
              {'id': 'x', 'name': 'n', 'type': 'spaceship'}),
          isNull);
      expect(RememberedDevice.fromJson({'id': 1, 'name': 'n', 'type': 'scale'}),
          isNull);
      // Empty id is rejected so decodeList never trips the constructor assert.
      expect(RememberedDevice.fromJson({'id': '', 'name': 'n', 'type': 'scale'}),
          isNull);
    });

    test('sameMetadata compares name + type, not id', () {
      const a = RememberedDevice(id: 'a', name: 'N', type: DeviceType.scale);
      const aRenamed =
          RememberedDevice(id: 'a', name: 'Other', type: DeviceType.scale);
      const bSameMeta =
          RememberedDevice(id: 'b', name: 'N', type: DeviceType.scale);
      expect(a.sameMetadata(bSameMeta), isTrue);
      expect(a.sameMetadata(aRenamed), isFalse);
    });

    test('storedCount counts stored records before validity filtering', () {
      // Two stored, one valid → decodeList drops one; storedCount sees both.
      const json = '[{"id":"a","name":"A","type":"scale"},{"id":"b"}]';
      expect(RememberedDevice.storedCount(json), 2);
      expect(RememberedDevice.decodeList(json), hasLength(1));
      expect(RememberedDevice.storedCount('not json'), 0);
      expect(RememberedDevice.storedCount('{}'), 0);
    });

    test('encodeList/decodeList round-trips a list', () {
      final list = [
        const RememberedDevice(id: 'a', name: 'DE1', type: DeviceType.machine),
        const RememberedDevice(id: 'b', name: 'Scale', type: DeviceType.scale),
      ];
      final decoded = RememberedDevice.decodeList(RememberedDevice.encodeList(list));
      expect(decoded.map((d) => d.id).toList(), ['a', 'b']);
      expect(decoded[0].type, DeviceType.machine);
    });

    test('decodeList tolerates malformed input', () {
      expect(RememberedDevice.decodeList(''), isEmpty);
      expect(RememberedDevice.decodeList('not json'), isEmpty);
      expect(RememberedDevice.decodeList('{}'), isEmpty);
      // Mixed: one good, one bad → keeps the good one.
      final mixed = '[{"id":"a","name":"A","type":"scale"},{"id":"b"}]';
      expect(RememberedDevice.decodeList(mixed).map((d) => d.id).toList(), ['a']);
    });

    test('equality is by id', () {
      const a1 = RememberedDevice(id: 'a', name: 'A', type: DeviceType.scale);
      const a2 = RememberedDevice(id: 'a', name: 'Renamed', type: DeviceType.machine);
      const b = RememberedDevice(id: 'b', name: 'B', type: DeviceType.scale);
      expect(a1, a2);
      expect(a1, isNot(b));
      expect({a1, a2, b}.length, 2);
    });
  });
}
