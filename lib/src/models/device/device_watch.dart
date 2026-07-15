import 'package:reaprime/src/models/device/watch_filter.dart';

/// Capability interface for discovery services that can run a
/// persistent, low-duty-cycle background device watch.
///
/// A separate interface (rather than default members on
/// `DeviceDiscoveryService`) because most services `implements` the
/// base class and would otherwise be forced to stub these out; the
/// capability check is `service is DeviceWatchCapable &&
/// service.supportsDeviceWatch`.
abstract class DeviceWatchCapable {
  /// Whether the watch is available right now. The type implements the
  /// capability; this gate covers runtime conditions (e.g. the BLE
  /// watch is Android-only — CoreBluetooth has no scan-duty-cycle knob).
  bool get supportsDeviceWatch;

  /// Start a persistent, low-duty-cycle watch for devices matching
  /// [filter]. Unlike `scanForDevices` this has no bounded duration —
  /// it runs until [stopDeviceWatch] and yields discoveries through the
  /// service's normal `devices` stream.
  Future<void> startDeviceWatch(DeviceWatchFilter filter);

  /// Stop a watch started with [startDeviceWatch]. Idempotent; safe to
  /// call when no watch is active.
  Future<void> stopDeviceWatch();
}
