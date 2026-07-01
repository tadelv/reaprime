/// Combustion Inc. Predictive Probe BLE identifiers and data channel keys.
///
/// Protocol authority: combustion-documentation probe_ble_specification.rst
class CombustionConstants {
  CombustionConstants._();

  static const int manufacturerId = 0x09C7;

  /// Alias used by discovery matching (SP-003).
  static const int manufacturerCompanyId = manufacturerId;

  static const int productTypePredictiveProbe = 0x01;

  /// Full manufacturer-specific block including 2-byte vendor ID.
  static const int manufacturerBlockSizeBytes = 25;

  /// Manufacturer payload after vendor ID (product type through thermometer prefs).
  static const int manufacturerPayloadSizeBytes = 23;

  static const int rawTemperatureDataSizeBytes = 13;

  static const String probeStatusServiceUuid =
      '00000100-CAAB-3792-3D44-97AE51C1407A';
  static const String probeStatusCharacteristicUuid =
      '00000101-CAAB-3792-3D44-97AE51C1407A';
  static const String nordicUartServiceUuid =
      '6E400001-B5A3-F393-E0A9-E50E24DCCA9E';

  static const double temperatureScale = 0.05;
  static const double temperatureOffsetCelsius = -20.0;
  static const double minTemperatureCelsius = -20.0;
  static const double maxTemperatureCelsius = 369.0;
  static const int invalidRawTemperature = 0x1FFF;

  static const String channelTemperature = 'temperature';
  static const String channelT1 = 't1';
  static const String channelT2 = 't2';
  static const String channelT3 = 't3';
  static const String channelT4 = 't4';
  static const String channelT5 = 't5';
  static const String channelT6 = 't6';
  static const String channelT7 = 't7';
  static const String channelT8 = 't8';
  static const String channelCore = 'core';
  static const String channelSurface = 'surface';
  static const String channelAmbient = 'ambient';
}

/// Operating mode encoded in the Mode/ID byte (bits 0–1).
enum CombustionProbeMode {
  normal(0),
  instantRead(1),
  reserved(2),
  error(3);

  const CombustionProbeMode(this.value);

  final int value;

  static CombustionProbeMode fromRaw(int raw) {
    final modeBits = raw & 0x03;
    return CombustionProbeMode.values.firstWhere(
      (mode) => mode.value == modeBits,
      orElse: () => CombustionProbeMode.error,
    );
  }
}
