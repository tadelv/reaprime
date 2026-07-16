/// Filter for a persistent, low-duty-cycle background device watch.
///
/// Deliberately a separate type from [ScanFilter]: burst-scan semantics
/// (one bounded cycle, unfiltered, aggressive duty cycle) stay untouched,
/// and `ScanFilter.preferredDeviceId` — which cannot be pushed down to the
/// OS scanner (no address filter in universal_ble) — doesn't leak into the
/// watch API.
class DeviceWatchFilter {
  /// Advertised-name prefix for the scan. The universal_ble fork
  /// evaluates this plugin-side (the OS scan runs unfiltered either
  /// way), so it only reduces platform-channel/Dart traffic — it is
  /// NOT a hardware filter and does not keep the scan alive with the
  /// screen off. It must match the ADVERTISED name, not a friendly
  /// display name. `null` means no name filtering (the current scale
  /// watch always passes null and matches Dart-side via DeviceMatcher).
  final String? namePrefix;

  const DeviceWatchFilter({this.namePrefix});

  @override
  String toString() => 'DeviceWatchFilter(namePrefix: $namePrefix)';
}
