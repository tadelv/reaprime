/// Thrown when a BLE operation times out.
///
/// Used to signal timeout conditions across the transport boundary
/// without leaking BLE library types into the app domain.
class BleTimeoutException implements Exception {
  final String operation;
  final Object? cause;

  BleTimeoutException(this.operation, [this.cause]);

  @override
  String toString() => 'BleTimeoutException: $operation timed out'
      '${cause != null ? ' (cause: $cause)' : ''}';
}
