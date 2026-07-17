/// Domain-level BLE connection failure.
///
/// Wraps the underlying BLE library's native exception so library types
/// (`FlutterBluePlusException`, `UniversalBleException`) never leak past the
/// `services/ble/` transport boundary. Transports map their native error into
/// this type; consumers (e.g. `ConnectionManager`) inspect it for telemetry
/// detail without depending on any BLE package.
class BleConnectException implements Exception {
  /// Native error code, stringified (e.g. Android GATT `"133"`, or a
  /// universal_ble `UniversalBleErrorCode` name). Null when the library does
  /// not provide one.
  final String? code;

  /// Human-readable description from the native exception, if any.
  final String? description;

  /// Which native function failed (e.g. `"connect"`).
  final String? function;

  /// The original native exception, retained for logging.
  final Object? cause;

  BleConnectException({this.code, this.description, this.function, this.cause});

  @override
  String toString() =>
      'BleConnectException: '
      '${function ?? 'connect'}'
      '${code != null ? ' (code: $code)' : ''}'
      '${description != null ? ' — $description' : ''}';
}
