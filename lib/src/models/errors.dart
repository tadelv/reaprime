/// Thrown by BLE discovery services when the Bluetooth runtime
/// permission is not granted.
class PermissionDeniedException implements Exception {
  final String? message;
  const PermissionDeniedException([this.message]);

  @override
  String toString() =>
      message == null ? 'PermissionDeniedException' : 'PermissionDeniedException: $message';
}

/// Which kind of device produced a [DeviceNotConnectedException].
enum DeviceKind { machine, scale }

/// Thrown when a controller is asked to act on a device that is not
/// currently connected. Replaces ad-hoc raw-string throws of
/// "De1 not connected yet" / "No scale connected" so callers can
/// dispatch on type rather than message text.
class DeviceNotConnectedException implements Exception {
  final DeviceKind kind;

  const DeviceNotConnectedException(this.kind);
  const DeviceNotConnectedException.machine() : kind = DeviceKind.machine;
  const DeviceNotConnectedException.scale() : kind = DeviceKind.scale;

  @override
  String toString() =>
      'DeviceNotConnectedException: ${kind.name} not connected';
}

/// Thrown by `_mmrRead` in `UnifiedDe1` when a DE1 memory-mapped
/// register read does not receive a matching notification within the
/// bounded timeout. Prevents connect attempts from hanging forever on
/// a dropped BLE notify.
class MmrTimeoutException implements Exception {
  final String mmrItemName;
  final Duration timeout;

  const MmrTimeoutException(this.mmrItemName, this.timeout);

  @override
  String toString() =>
      'MmrTimeoutException: no response for $mmrItemName within $timeout';
}
