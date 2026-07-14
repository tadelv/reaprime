import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/difluid/difluid_r2_protocol.dart';
import 'package:reaprime/src/models/device/impl/difluid/difluid_r2_sensor.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:reaprime/src/models/device/transport/data_transport.dart';
import 'package:reaprime/src/services/device_matcher.dart';
import 'package:rxdart/rxdart.dart';

typedef _WriteRecord = ({
  String serviceUuid,
  String characteristicUuid,
  Uint8List data,
  bool withResponse,
});

class _FakeR2Transport implements BLETransport {
  final BehaviorSubject<ConnectionState> _states = BehaviorSubject.seeded(
    ConnectionState.discovered,
  );
  final List<_WriteRecord> writes = [];
  void Function(Uint8List)? notificationHandler;
  List<String> services = [DifluidR2Sensor.serviceIdentifier.long];
  Uint8List? responsePacket;

  @override
  String get id => 'r2-test-id';

  @override
  String get name => 'DiFluid R2 301095';

  @override
  TransportType get transportType => TransportType.ble;

  @override
  Stream<ConnectionState> get connectionState => _states.stream;

  @override
  Future<ConnectionState> getConnectionState() async =>
      ConnectionState.disconnected;

  @override
  Future<void> connect() async {
    _states.add(ConnectionState.connected);
  }

  @override
  Future<void> disconnect() async {
    _states.add(ConnectionState.disconnected);
  }

  @override
  Future<void> dispose() async {
    await _states.close();
  }

  @override
  Future<List<String>> discoverServices() async => services;

  @override
  Future<Uint8List> read(
    String serviceUUID,
    String characteristicUUID, {
    Duration? timeout,
  }) async => Uint8List(0);

  @override
  Future<void> subscribe(
    String serviceUUID,
    String characteristicUUID,
    void Function(Uint8List) callback,
  ) async {
    notificationHandler = callback;
  }

  @override
  Future<void> write(
    String serviceUUID,
    String characteristicUUID,
    Uint8List data, {
    bool withResponse = true,
    Duration? timeout,
  }) async {
    writes.add((
      serviceUuid: serviceUUID,
      characteristicUuid: characteristicUUID,
      data: data,
      withResponse: withResponse,
    ));

    if (_sameBytes(data, DifluidR2Protocol.singleTestCommand()) &&
        responsePacket != null) {
      scheduleMicrotask(() => notificationHandler?.call(responsePacket!));
    }
  }

  @override
  Future<void> setTransportPriority(bool prioritized) async {}
}

bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void main() {
  group('DifluidR2Sensor', () {
    test('describes a TDS-capable measure command for skins', () {
      final sensor = DifluidR2Sensor(transport: _FakeR2Transport());

      expect(sensor.name, 'DiFluid R2');
      expect(sensor.info.vendor, 'DiFluid');
      expect(sensor.info.dataChannels.map((c) => c.key), contains('tds'));
      expect(sensor.info.commands?.map((c) => c.id), contains('measure'));
    });

    test('connects, subscribes, sets Celsius, and measures TDS', () async {
      final transport = _FakeR2Transport()
        ..responsePacket = Uint8List.fromList([
          0xDF,
          0xDF,
          0x03,
          0x00,
          0x03,
          0x02,
          0x03,
          0xCA,
          0x93,
        ]);
      final sensor = DifluidR2Sensor(transport: transport);

      await sensor.onConnect();
      final result = await sensor.execute('measure', {'timeout': 1});

      expect(result['reading'], isA<Map>());
      expect((result['reading'] as Map)['tds'], closeTo(9.7, 0.001));
      expect(transport.notificationHandler, isNotNull);
      expect(transport.writes, hasLength(2));
      expect(
        transport.writes.first.data,
        DifluidR2Protocol.setCelsiusCommand(),
      );
      expect(transport.writes.last.data, DifluidR2Protocol.singleTestCommand());
      expect(transport.writes.every((w) => w.withResponse), isTrue);
    });

    test('publishes readings to the data stream', () async {
      final transport = _FakeR2Transport()
        ..responsePacket = Uint8List.fromList([
          0xDF,
          0xDF,
          0x03,
          0x00,
          0x03,
          0x02,
          0x00,
          0x0C,
          0xD2,
        ]);
      final sensor = DifluidR2Sensor(transport: transport);

      await sensor.onConnect();
      final nextReading = sensor.data.first;
      await sensor.execute('measure', {'timeout': 1});

      expect(await nextReading, containsPair('tds', 0.12));
    });

    test('matches DiFluid R2 devices separately from DiFluid scales', () async {
      final matched = await DeviceMatcher.match(
        transport: _FakeR2Transport(),
        advertisedName: 'DiFluid R2 301095',
      );

      expect(matched, isA<DifluidR2Sensor>());
      expect(
        DeviceMatcher.serviceUuidsFor(DeviceType.sensor),
        contains(DifluidR2Sensor.serviceIdentifier.long),
      );
    });
  });
}
