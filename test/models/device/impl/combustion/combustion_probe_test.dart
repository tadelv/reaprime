import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/combustion/combustion_constants.dart';
import 'package:reaprime/src/models/device/impl/combustion/combustion_probe.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:rxdart/rxdart.dart';

void main() {
  group('CombustionProbe', () {
    late _MockCombustionTransport transport;
    late CombustionProbe probe;

    setUp(() {
      transport = _MockCombustionTransport();
      probe = CombustionProbe(transport: transport);
    });

    tearDown(() async {
      await probe.disconnect();
      await transport.dispose();
    });

    test('exposes Combustion BLE identifiers', () {
      expect(CombustionProbe.manufacturerId, 0x09C7);
      expect(
        CombustionProbe.serviceIdentifier.long.toLowerCase(),
        CombustionConstants.probeStatusServiceUuid.toLowerCase(),
      );
    });

    test('SensorInfo declares temperature and extended channels', () {
      final keys = probe.info.dataChannels
          .map((channel) => channel.key)
          .toList();

      expect(keys, contains(CombustionConstants.channelTemperature));
      expect(keys, contains(CombustionConstants.channelCore));
      expect(keys, contains(CombustionConstants.channelSurface));
      expect(keys, contains(CombustionConstants.channelAmbient));
      expect(keys, contains(CombustionConstants.channelT1));
      expect(keys, contains(CombustionConstants.channelT8));
    });

    test('onConnect registers adv listener without GATT connect', () async {
      await probe.onConnect();

      expect(transport.connectCallCount, 0);
      expect(transport.discoverServicesCallCount, 0);
      expect(transport.subscribeCallCount, 0);
      expect(await probe.connectionState.first, ConnectionState.connected);
    });

    test(
      'adv payload produces temperature on data stream (virtual core)',
      () async {
        final readings = <Map<String, dynamic>>[];
        final sub = probe.data.listen(readings.add);

        await probe.onConnect();
        transport.emitManufacturerData(
          _manufacturerBlock(
            temperatureData: _encodeThermistorField([
              _rawFromCelsius(10),
              _rawFromCelsius(20),
              _rawFromCelsius(62.5),
              _rawFromCelsius(40),
              _rawFromCelsius(50),
              _rawFromCelsius(60),
              _rawFromCelsius(70),
              _rawFromCelsius(80),
            ]),
            batteryVirtualByte: (2 << 1),
          ),
        );

        await Future<void>.delayed(Duration.zero);
        await sub.cancel();

        expect(readings, isNotEmpty);
        expect(readings.single['temperature'], closeTo(62.5, 0.0001));
        expect(readings.single['core'], closeTo(62.5, 0.0001));
        expect(readings.single['t3'], closeTo(62.5, 0.0001));
        expect(readings.single['timestamp'], isA<String>());
      },
    );

    test('parses adv_normal_1 fixture through data stream', () async {
      final readings = <Map<String, dynamic>>[];
      final sub = probe.data.listen(readings.add);

      await probe.onConnect();
      transport.emitManufacturerData(_loadFixture('adv_normal_1.hex'));

      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(readings, isNotEmpty);
      expect(readings.single['temperature'], -20.0);
    });

    test('disconnect stops advertisement updates on data stream', () async {
      final readings = <Map<String, dynamic>>[];
      final sub = probe.data.listen(readings.add);

      await probe.onConnect();
      await probe.disconnect();
      transport.emitManufacturerData(_loadFixture('adv_normal_1.hex'));

      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(await probe.connectionState.first, ConnectionState.disconnected);
      expect(readings, isEmpty);
    });
  });
}

class _MockCombustionTransport extends BLETransport
    implements CombustionAdvertisingTransport {
  final BehaviorSubject<ConnectionState> _connectionState =
      BehaviorSubject.seeded(ConnectionState.discovered);
  final StreamController<Uint8List> _manufacturerDataController =
      StreamController<Uint8List>.broadcast();

  int connectCallCount = 0;
  int discoverServicesCallCount = 0;
  int subscribeCallCount = 0;

  @override
  String get id => 'combustion-test-id';

  @override
  String get name => '00ABCDEF';

  @override
  Stream<ConnectionState> get connectionState => _connectionState.stream;

  @override
  Stream<Uint8List> get manufacturerDataStream =>
      _manufacturerDataController.stream;

  void emitManufacturerData(List<int> data) {
    _manufacturerDataController.add(Uint8List.fromList(data));
  }

  @override
  Future<ConnectionState> getConnectionState() async => _connectionState.value;

  @override
  Future<void> connect() async {
    connectCallCount++;
    _connectionState.add(ConnectionState.connected);
  }

  @override
  Future<void> disconnect() async {
    _connectionState.add(ConnectionState.disconnected);
  }

  @override
  Future<void> dispose() async {
    await _manufacturerDataController.close();
    await _connectionState.close();
  }

  @override
  Future<List<String>> discoverServices() async {
    discoverServicesCallCount++;
    return [];
  }

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
    subscribeCallCount++;
  }

  @override
  Future<void> write(
    String serviceUUID,
    String characteristicUUID,
    Uint8List data, {
    bool withResponse = true,
    Duration? timeout,
  }) async {}

  @override
  Future<void> setTransportPriority(bool prioritized) async {}
}

Uint8List _loadFixture(String name) {
  final path = 'test/fixtures/combustion/$name';
  final hex = File(path).readAsStringSync().trim();
  return Uint8List.fromList(_decodeHex(hex));
}

List<int> _decodeHex(String hex) {
  final bytes = <int>[];
  for (var index = 0; index < hex.length; index += 2) {
    bytes.add(int.parse(hex.substring(index, index + 2), radix: 16));
  }
  return bytes;
}

int _rawFromCelsius(double celsius) {
  return ((celsius - CombustionConstants.temperatureOffsetCelsius) /
          CombustionConstants.temperatureScale)
      .round();
}

Uint8List _encodeThermistorField(List<int> rawValues) {
  expect(rawValues.length, 8);
  final bytes = Uint8List(CombustionConstants.rawTemperatureDataSizeBytes);
  for (var sensorIndex = 0; sensorIndex < 8; sensorIndex++) {
    _setBits(bytes, sensorIndex * 13, 13, rawValues[sensorIndex]);
  }
  return bytes;
}

void _setBits(Uint8List data, int bitOffset, int bitCount, int value) {
  for (var bitIndex = 0; bitIndex < bitCount; bitIndex++) {
    final currentBit = bitOffset + bitIndex;
    final byteIndex = currentBit ~/ 8;
    final bitInByte = currentBit % 8;
    if (((value >> bitIndex) & 0x01) == 0x01) {
      data[byteIndex] |= 1 << bitInByte;
    }
  }
}

Uint8List _manufacturerBlock({
  required Uint8List temperatureData,
  int serialNumber = 0x00ABCDEF,
  int modeByte = 0x00,
  int batteryVirtualByte = 0x00,
}) {
  final block = Uint8List(CombustionConstants.manufacturerBlockSizeBytes);
  block[0] = CombustionConstants.manufacturerId & 0xFF;
  block[1] = CombustionConstants.manufacturerId >> 8;
  block[2] = CombustionConstants.productTypePredictiveProbe;
  block[3] = serialNumber & 0xFF;
  block[4] = (serialNumber >> 8) & 0xFF;
  block[5] = (serialNumber >> 16) & 0xFF;
  block[6] = (serialNumber >> 24) & 0xFF;
  block.setRange(7, 20, temperatureData);
  block[20] = modeByte;
  block[21] = batteryVirtualByte;
  return block;
}
