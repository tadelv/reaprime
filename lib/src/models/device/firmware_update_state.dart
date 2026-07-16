/// Observable state of the machine-level firmware update operation.
///
/// Exposed read-only through [De1Interface.firmwareUpdateState] for GET/UI
/// reporting. Callers must not use a check-then-start sequence as the
/// concurrency lock — see [FirmwareUpdateInProgressException].
enum FirmwareUpdateState {
  /// No firmware operation is active.
  idle,

  /// The machine is erasing its flash.
  erasing,

  /// Firmware bytes are being uploaded.
  uploading,

  /// Post-upload verification is in progress.
  verifying,

  /// Cancellation has been requested; the operation is winding down.
  cancelling,
}
