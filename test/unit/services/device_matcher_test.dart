import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/impl/decent_scale/scale.dart';
import 'package:reaprime/src/models/device/impl/skale/skale2_scale.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:reaprime/src/services/device_matcher.dart';

class _MockBLETransport extends BLETransport {
  @override
  String get id => 'AA:BB:CC:DD:EE:FF';

  @override
  String get name => 'Mock';

  @override
  Stream<bool> get connectionState => Stream.value(false);

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<List<String>> discoverServices() async => [];

  @override
  Future<Uint8List> read(String serviceUUID, String characteristicUUID,
          {Duration? timeout}) async =>
      Uint8List(0);

  @override
  Future<void> subscribe(String serviceUUID, String characteristicUUID,
          void Function(Uint8List) callback) async {}

  @override
  Future<void> write(
          String serviceUUID, String characteristicUUID, Uint8List data,
          {bool withResponse = true, Duration? timeout}) async {}

  @override
  Future<void> setTransportPriority(bool prioritized) async {}
}

void main() {
  group('DeviceMatcher', () {
    late _MockBLETransport mockTransport;

    setUp(() {
      mockTransport = _MockBLETransport();
    });

    test('exact match for Decent Scale', () async {
      final device = await DeviceMatcher.match(
        transport: mockTransport,
        advertisedName: 'Decent Scale',
      );

      expect(device, isNotNull);
      expect(device, isA<DecentScale>());
    });

    test('exact match for Skale2', () async {
      final device = await DeviceMatcher.match(
        transport: mockTransport,
        advertisedName: 'Skale2',
      );

      expect(device, isNotNull);
      expect(device, isA<Skale2Scale>());
    });

    test('returns null for unknown name', () async {
      final device = await DeviceMatcher.match(
        transport: mockTransport,
        advertisedName: 'Unknown Device',
      );

      expect(device, isNull);
    });
  });
}
