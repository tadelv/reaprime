/// Centralised durations used by the connection / comms layer.
///
/// Per-implementation internals (transport post-connect delays, BlueZ
/// cache-refresh scan, per-platform MTU settle times, etc.) stay with
/// their owners — those are tuned for one platform and don't benefit
/// from cross-file visibility. What lives here is the handful of
/// timings the review surfaced as "magic numbers that a future reader
/// would want to find in one place" (comms-harden #24).
class ConnectionTimings {
  /// Per-device `connectionState.first` timeout during the
  /// pre-scan staleness check in `DeviceController`.
  static const preScanDeviceCheckTimeout = Duration(seconds: 2);

  /// Settle delay after all services report scan-complete, before
  /// flipping `scanningStream` to `false`. Gives downstream UI a
  /// stable "scanning" window rather than a zero-duration flicker.
  static const postScanSettleDelay = Duration(milliseconds: 200);

  /// Debounce window for `De1Controller` shot-settings pushes. Coalesces
  /// the flurry of calls that come from consecutive UI adjustments
  /// (`setSteamFlow`, `setHotWaterFlow`, `updateShotSettings`) into one
  /// MMR round-trip.
  static const shotSettingsDebounce = Duration(milliseconds: 100);

  /// Post-profile-upload wait before allowing the next state change.
  /// Works around a firmware `ProfileDownloadInProgress` race where a
  /// state=espresso request that hits the loop before the flash write
  /// returns aborts the shot to HeaterDown.
  static const profileDownloadGuard = Duration(milliseconds: 500);
}
