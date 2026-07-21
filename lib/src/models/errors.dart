/// Thrown by BLE discovery services when the Bluetooth runtime
/// permission is not granted.
class PermissionDeniedException implements Exception {
  final String? message;
  const PermissionDeniedException([this.message]);

  @override
  String toString() => message == null
      ? 'PermissionDeniedException'
      : 'PermissionDeniedException: $message';
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

class DeviceIdentityMismatchException implements Exception {
  final String expected;
  final int actualModelValue;

  const DeviceIdentityMismatchException({
    required this.expected,
    required this.actualModelValue,
  });

  @override
  String toString() =>
      'DeviceIdentityMismatchException: expected $expected, got v13Model=$actualModelValue';
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
class EndpointUnavailableException implements Exception {
  final String endpointName;
  final Duration timeout;

  const EndpointUnavailableException(this.endpointName, this.timeout);

  @override
  String toString() =>
      'EndpointUnavailableException: no $endpointName frame within $timeout';
}

class MmrTimeoutException implements Exception {
  final String mmrItemName;
  final Duration timeout;

  const MmrTimeoutException(this.mmrItemName, this.timeout);

  @override
  String toString() =>
      'MmrTimeoutException: no response for $mmrItemName within $timeout';
}

/// Thrown synchronously by [De1Interface.updateFirmware] when a firmware
/// operation is already in progress. Callers receive this before any async
/// work begins, so an API handler can return HTTP 409 before opening a
/// streaming response.
class FirmwareUpdateInProgressException implements Exception {
  @override
  String toString() =>
      'FirmwareUpdateInProgressException: a firmware '
      'update is already in progress';
}

/// Thrown when an in-progress firmware update is cancelled, either by
/// [De1Interface.cancelFirmwareUpload] or by client disconnect.
class FirmwareUpdateCancelledException implements Exception {
  const FirmwareUpdateCancelledException();

  @override
  String toString() =>
      'FirmwareUpdateCancelledException: firmware update '
      'was cancelled';
}

/// Thrown when firmware image validation fails before starting the upload.
class FirmwareImageValidationException implements Exception {
  final String reason;

  const FirmwareImageValidationException(this.reason);

  @override
  String toString() => 'FirmwareImageValidationException: $reason';
}
