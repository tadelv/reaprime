import 'dart:typed_data';

import 'package:reaprime/src/models/device/impl/combustion/combustion_constants.dart';

/// Parsed temperature frame from Combustion advertising or Probe Status data.
class CombustionReading {
  CombustionReading({
    required this.timestamp,
    required this.t1,
    required this.t2,
    required this.t3,
    required this.t4,
    required this.t5,
    required this.t6,
    required this.t7,
    required this.t8,
    this.virtualCore,
    this.virtualSurface,
    this.virtualAmbient,
    this.serialNumber,
    this.mode = CombustionProbeMode.normal,
    this.lowBattery = false,
  });

  final DateTime timestamp;
  final double? t1;
  final double? t2;
  final double? t3;
  final double? t4;
  final double? t5;
  final double? t6;
  final double? t7;
  final double? t8;
  final double? virtualCore;
  final double? virtualSurface;
  final double? virtualAmbient;
  final int? serialNumber;
  final CombustionProbeMode mode;
  final bool lowBattery;

  List<double?> get thermistors => [t1, t2, t3, t4, t5, t6, t7, t8];
}

/// Pure Dart decode for Combustion manufacturer data and Probe Status payloads.
class CombustionProtocol {
  CombustionProtocol._();

  static CombustionReading? parseManufacturerData(
    List<int> data, {
    DateTime? timestamp,
  }) {
    final bytes = _asUint8List(data);
    final payload = _manufacturerPayload(bytes);
    if (payload == null) {
      return null;
    }
    return _parseManufacturerPayload(
      payload,
      timestamp: timestamp ?? DateTime.now().toUtc(),
    );
  }

  static CombustionReading? parseProbeStatusNotification(
    List<int> data, {
    DateTime? timestamp,
  }) {
    final bytes = _asUint8List(data);
    const logRangeSizeBytes = 8;
    const minimumSizeBytes =
        logRangeSizeBytes + CombustionConstants.rawTemperatureDataSizeBytes + 2;
    if (bytes.length < minimumSizeBytes) {
      return null;
    }

    final temperatureData = bytes.sublist(
      logRangeSizeBytes,
      logRangeSizeBytes + CombustionConstants.rawTemperatureDataSizeBytes,
    );
    final modeByte = bytes[logRangeSizeBytes + 13];
    final batteryVirtualByte = bytes[logRangeSizeBytes + 14];

    return _buildReading(
      temperatureData: temperatureData,
      modeByte: modeByte,
      batteryVirtualByte: batteryVirtualByte,
      serialNumber: null,
      timestamp: timestamp ?? DateTime.now().toUtc(),
    );
  }

  static Uint8List? _manufacturerPayload(Uint8List bytes) {
    if (bytes.length >= CombustionConstants.manufacturerBlockSizeBytes &&
        bytes[0] == (CombustionConstants.manufacturerId & 0xFF) &&
        bytes[1] == (CombustionConstants.manufacturerId >> 8)) {
      return bytes;
    }

    if (bytes.length >= CombustionConstants.manufacturerPayloadSizeBytes &&
        bytes[0] == CombustionConstants.productTypePredictiveProbe) {
      final withVendor = Uint8List(
        CombustionConstants.manufacturerBlockSizeBytes,
      );
      withVendor[0] = CombustionConstants.manufacturerId & 0xFF;
      withVendor[1] = CombustionConstants.manufacturerId >> 8;
      withVendor.setRange(2, 2 + bytes.length, bytes);
      return withVendor;
    }

    return null;
  }

  static CombustionReading? _parseManufacturerPayload(
    Uint8List payload, {
    required DateTime timestamp,
  }) {
    if (payload.length < CombustionConstants.manufacturerBlockSizeBytes) {
      return null;
    }
    if (payload[2] != CombustionConstants.productTypePredictiveProbe) {
      return null;
    }

    final serialNumber = _readUint32Le(payload, 3);
    final temperatureData = payload.sublist(7, 20);
    final modeByte = payload[20];
    final batteryVirtualByte = payload[21];

    return _buildReading(
      temperatureData: temperatureData,
      modeByte: modeByte,
      batteryVirtualByte: batteryVirtualByte,
      serialNumber: serialNumber,
      timestamp: timestamp,
    );
  }

  static CombustionReading? _buildReading({
    required List<int> temperatureData,
    required int modeByte,
    required int batteryVirtualByte,
    required int? serialNumber,
    required DateTime timestamp,
  }) {
    if (temperatureData.length <
        CombustionConstants.rawTemperatureDataSizeBytes) {
      return null;
    }

    final mode = CombustionProbeMode.fromRaw(modeByte);
    final thermistors = _decodeThermistors(
      Uint8List.fromList(temperatureData),
      instantRead: mode == CombustionProbeMode.instantRead,
    );
    final virtualSensors = _decodeVirtualSensors(batteryVirtualByte);

    return CombustionReading(
      timestamp: timestamp,
      t1: thermistors[0],
      t2: thermistors[1],
      t3: thermistors[2],
      t4: thermistors[3],
      t5: thermistors[4],
      t6: thermistors[5],
      t7: thermistors[6],
      t8: thermistors[7],
      virtualCore: _virtualCoreTemperature(thermistors, virtualSensors.core),
      virtualSurface: _virtualSurfaceTemperature(
        thermistors,
        virtualSensors.surface,
      ),
      virtualAmbient: _virtualAmbientTemperature(
        thermistors,
        virtualSensors.ambient,
      ),
      serialNumber: serialNumber,
      mode: mode,
      lowBattery: (batteryVirtualByte & 0x01) == 0x01,
    );
  }

  static List<double?> _decodeThermistors(
    Uint8List data, {
    required bool instantRead,
  }) {
    final values = List<double?>.filled(8, null);
    for (var index = 0; index < 8; index++) {
      if (instantRead && index > 0) {
        values[index] = null;
        continue;
      }
      final raw = _getBits(data, index * 13, 13);
      values[index] = _decodeTemperature(raw);
    }
    return values;
  }

  static double? _decodeTemperature(int raw) {
    if (raw == CombustionConstants.invalidRawTemperature) {
      return null;
    }
    final celsius =
        (raw * CombustionConstants.temperatureScale) +
        CombustionConstants.temperatureOffsetCelsius;
    if (celsius < CombustionConstants.minTemperatureCelsius ||
        celsius > CombustionConstants.maxTemperatureCelsius) {
      return null;
    }
    return celsius;
  }

  static _VirtualSensorIndices _decodeVirtualSensors(int batteryVirtualByte) {
    final packed = batteryVirtualByte >> 1;
    return _VirtualSensorIndices(
      core: packed & 0x07,
      surface: (packed >> 3) & 0x03,
      ambient: (packed >> 5) & 0x03,
    );
  }

  static double? _virtualCoreTemperature(
    List<double?> thermistors,
    int index,
  ) {
    const mapping = [0, 1, 2, 3, 4, 5];
    if (index < 0 || index >= mapping.length) {
      return null;
    }
    return thermistors[mapping[index]];
  }

  static double? _virtualSurfaceTemperature(
    List<double?> thermistors,
    int index,
  ) {
    const mapping = [3, 4, 5, 6];
    if (index < 0 || index >= mapping.length) {
      return null;
    }
    return thermistors[mapping[index]];
  }

  static double? _virtualAmbientTemperature(
    List<double?> thermistors,
    int index,
  ) {
    const mapping = [4, 5, 6, 7];
    if (index < 0 || index >= mapping.length) {
      return null;
    }
    return thermistors[mapping[index]];
  }

  static int _getBits(Uint8List data, int bitOffset, int bitCount) {
    var value = 0;
    for (var bitIndex = 0; bitIndex < bitCount; bitIndex++) {
      final currentBit = bitOffset + bitIndex;
      final byteIndex = currentBit ~/ 8;
      if (byteIndex >= data.length) {
        break;
      }
      final bitInByte = currentBit % 8;
      if (((data[byteIndex] >> bitInByte) & 0x01) == 0x01) {
        value |= 1 << bitIndex;
      }
    }
    return value;
  }

  static int _readUint32Le(Uint8List data, int offset) {
    return data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24);
  }

  static Uint8List _asUint8List(List<int> data) {
    return data is Uint8List ? data : Uint8List.fromList(data);
  }
}

class _VirtualSensorIndices {
  const _VirtualSensorIndices({
    required this.core,
    required this.surface,
    required this.ambient,
  });

  final int core;
  final int surface;
  final int ambient;
}
