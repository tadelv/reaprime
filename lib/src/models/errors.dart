/// Thrown by BLE discovery services when the Bluetooth runtime
/// permission is not granted.
class PermissionDeniedException implements Exception {
  final String? message;
  const PermissionDeniedException([this.message]);

  @override
  String toString() =>
      message == null ? 'PermissionDeniedException' : 'PermissionDeniedException: $message';
}
