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
/// Identifies the general class of a device (machine vs scale vs unknown).
/// An [unknown] device is a transport that hasn't been classified yet —
/// used by lower-level BLE transport error handlers that don't know
/// whether they're connected to a machine or a scale.
enum DeviceKind { machine, scale, unknown }

/// Thrown when a controller is asked to act on a device that is not
/// currently connected. Replaces ad-hoc raw-string throws of
/// "De1 not connected yet" / "No scale connected" so callers can
/// dispatch on type rather than message text.
class DeviceNotConnectedException implements Exception {
  final DeviceKind kind;

  const DeviceNotConnectedException(this.kind);
  const DeviceNotConnectedException.machine() : kind = DeviceKind.machine;
  const DeviceNotConnectedException.scale() : kind = DeviceKind.scale;
  const DeviceNotConnectedException.unknown() : kind = DeviceKind.unknown;

  @override
  String toString() =>
      'DeviceNotConnectedException: ${kind.name} not connected';
}

/// Recorded as a non-fatal (never thrown) when `UnifiedDe1Transport.connect`
/// re-runs BLE setup on a transport that already reports `connected` — the
/// no-op reconnect that, before the per-characteristic subscription guard,
/// stacked duplicate notification listeners and delivered every frame twice.
/// The setup is now idempotent; this type exists purely so the condition
/// surfaces in telemetry and we can measure how often it fires in the field.
///
/// This is logged as the `error` of a WARNING and forwarded to Crashlytics
/// verbatim (the telemetry bridge does not scrub the error object), so
/// [anonymizedDeviceId] MUST already be anonymized by the caller (e.g.
/// `Anonymization.anonymizeMac`) — never pass a raw BLE MAC / device id.
class DuplicateBleSubscription implements Exception {
  final String anonymizedDeviceId;

  const DuplicateBleSubscription(this.anonymizedDeviceId);

  @override
  String toString() =>
      'DuplicateBleSubscription: BLE setup re-run on already-connected '
      'transport ($anonymizedDeviceId)';
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
