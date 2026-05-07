import 'package:reaprime/src/models/device/device.dart';

/// Filter parameters for targeted BLE scans.
///
/// Carries intent (what to scan for), not implementation (how to filter).
/// [BluePlusDiscoveryService] converts to platform-specific filter parameters
/// at the BLE edge.
class ScanFilter {
  /// If set, filter scan results to this specific remote device ID.
  /// Maps to `withRemoteIds` in flutter_blue_plus.
  final String? preferredDeviceId;

  /// If set, filter scan results to these device types.
  /// `null` means all devices. `{DeviceType.scale}` means only scales.
  /// Maps to `withServices` (by service UUID) in flutter_blue_plus.
  final Set<DeviceType>? deviceTypes;

  const ScanFilter({this.preferredDeviceId, this.deviceTypes});

  bool get isFiltered =>
      preferredDeviceId != null ||
      (deviceTypes != null && deviceTypes!.isNotEmpty);
}
