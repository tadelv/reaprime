import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/impl/combustion/combustion_constants.dart';
import 'package:reaprime/src/models/device/impl/combustion/combustion_protocol.dart';

void main() {
  group('CombustionProtocol.parseManufacturerData', () {
    test('parses adv_normal_1 fixture serial and mode', () {
      final bytes = _loadFixture('adv_normal_1.hex');
      final reading = CombustionProtocol.parseManufacturerData(
        bytes,
        timestamp: _fixedTimestamp,
      );

      expect(reading, isNotNull);
      expect(reading!.serialNumber, 0x00ABCDEF);
      expect(reading.mode, CombustionProbeMode.normal);
      expect(reading.timestamp, _fixedTimestamp);
      expect(reading.t1, -20.0);
      expect(reading.t2, -20.0);
    });

    test('parses adv_normal_2 fixture with different serial', () {
      final bytes = _loadFixture('adv_normal_2.hex');
      final reading = CombustionProtocol.parseManufacturerData(bytes);

      expect(reading, isNotNull);
      expect(reading!.serialNumber, 0x00345678);
      expect(reading.mode, CombustionProbeMode.normal);
    });

    test('parses adv_instant_read_1 fixture as instant read mode', () {
      final bytes = _loadFixture('adv_instant_read_1.hex');
      final reading = CombustionProtocol.parseManufacturerData(bytes);

      expect(reading, isNotNull);
      expect(reading!.mode, CombustionProbeMode.instantRead);
      expect(reading.t1, -20.0);
      expect(reading.t2, isNull);
      expect(reading.t8, isNull);
    });

    test('returns null for short or corrupt manufacturer blocks', () {
      expect(CombustionProtocol.parseManufacturerData(<int>[]), isNull);
      expect(CombustionProtocol.parseManufacturerData([0xC7, 0x09]), isNull);
      expect(
        CombustionProtocol.parseManufacturerData(
          List<int>.filled(25, 0xFF),
        ),
        isNull,
      );
      expect(
        CombustionProtocol.parseManufacturerData(
          List<int>.filled(25, 0),
        ),
        isNull,
      );
    });

    test('does not throw on corrupt packets', () {
      expect(
        () => CombustionProtocol.parseManufacturerData([1, 2, 3]),
        returnsNormally,
      );
    });
  });

  group('CombustionProtocol temperature decode', () {
    test('applies celsius = (raw * 0.05) - 20', () {
      final payload = _manufacturerBlock(
        temperatureData: _encodeThermistorField([
          _rawFromCelsius(25.0),
          _rawFromCelsius(62.5),
          CombustionConstants.invalidRawTemperature,
          0,
          0,
          0,
          0,
          0,
        ]),
      );

      final reading = CombustionProtocol.parseManufacturerData(payload);
      expect(reading, isNotNull);
      expect(reading!.t1, closeTo(25.0, 0.0001));
      expect(reading.t2, closeTo(62.5, 0.0001));
      expect(reading.t3, isNull);
      expect(reading.t4, -20.0);
    });

    test('handles edge temperatures at range bounds', () {
      final payload = _manufacturerBlock(
        temperatureData: _encodeThermistorField([
          _rawFromCelsius(-20.0),
          _rawFromCelsius(369.0),
          0,
          0,
          0,
          0,
          0,
          0,
        ]),
      );

      final reading = CombustionProtocol.parseManufacturerData(payload);
      expect(reading, isNotNull);
      expect(reading!.t1, -20.0);
      expect(reading.t2, 369.0);
    });

    test('treats 0x1FFF raw as missing sensor', () {
      final payload = _manufacturerBlock(
        temperatureData: _encodeThermistorField(
          List<int>.filled(8, CombustionConstants.invalidRawTemperature),
        ),
      );

      final reading = CombustionProtocol.parseManufacturerData(payload);
      expect(reading, isNotNull);
      expect(reading!.thermistors.every((value) => value == null), isTrue);
    });
  });

  group('CombustionProtocol virtual sensors', () {
    test('maps virtual core, surface, and ambient from battery byte', () {
      // Core=T3 (2), Surface=T6 (2), Ambient=T8 (3).
      const virtualPacked = (2) | (2 << 3) | (3 << 5);
      const batteryVirtualByte = virtualPacked << 1;
      final payload = _manufacturerBlock(
        temperatureData: _encodeThermistorField([
          _rawFromCelsius(10),
          _rawFromCelsius(20),
          _rawFromCelsius(30),
          _rawFromCelsius(40),
          _rawFromCelsius(50),
          _rawFromCelsius(60),
          _rawFromCelsius(70),
          _rawFromCelsius(80),
        ]),
        batteryVirtualByte: batteryVirtualByte,
      );

      final reading = CombustionProtocol.parseManufacturerData(payload);
      expect(reading, isNotNull);
      expect(reading!.virtualCore, closeTo(30.0, 0.0001));
      expect(reading.virtualSurface, closeTo(60.0, 0.0001));
      expect(reading.virtualAmbient, closeTo(80.0, 0.0001));
    });
  });

  group('CombustionProtocol.parseProbeStatusNotification', () {
    test('parses thermistor block after 8-byte log range', () {
      final notification = Uint8List(23);
      notification.setRange(8, 21, _encodeThermistorField([
        _rawFromCelsius(55.0),
        0,
        0,
        0,
        0,
        0,
        0,
        0,
      ]));
      notification[21] = 0x00;
      notification[22] = 0x00;

      final reading = CombustionProtocol.parseProbeStatusNotification(
        notification,
        timestamp: _fixedTimestamp,
      );

      expect(reading, isNotNull);
      expect(reading!.t1, closeTo(55.0, 0.0001));
      expect(reading.serialNumber, isNull);
      expect(reading.timestamp, _fixedTimestamp);
    });

    test('returns null for short probe status payloads', () {
      expect(
        CombustionProtocol.parseProbeStatusNotification([1, 2, 3]),
        isNull,
      );
    });
  });
}

final DateTime _fixedTimestamp = DateTime.utc(2026, 7, 1, 12, 0, 0);

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
