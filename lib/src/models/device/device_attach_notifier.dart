/// Optional capability for a `DeviceDiscoveryService` whose transport is
/// *told* when a device appears, instead of only finding out by scanning.
///
/// USB is the motivating case: Android broadcasts
/// `ACTION_USB_DEVICE_ATTACHED` the instant the machine enumerates, but the
/// serial service used to throw the intent away, so a reconnect had to wait
/// for the next exponential-backoff scan (a measured 20.3 s,
/// up to 60 s). [ConnectionManager] listens to this and starts the scan +
/// connect immediately, keeping the backoff loop as the fallback.
///
/// Services that cannot be notified out-of-band (BLE, Wi-Fi, simulated)
/// simply do not implement it — [DeviceScanner.deviceAttached] then never
/// emits for them and every existing path is unchanged.
abstract class DeviceAttachNotifier {
  /// Fires once per platform attach notification for a device this service
  /// would actually try to talk to. Never fires on detach.
  Stream<DeviceAttachedEvent> get deviceAttached;
}

/// A device just appeared on a transport bus. Carries only what the platform
/// hands us at attach time; both fields can be null (Android's attach intent
/// sometimes has no serial, so no stable id can be computed yet).
///
/// It is deliberately NOT a promise that the device is usable, or that it is
/// the preferred machine — it is an "arrival" edge that says "rescan now,
/// don't wait for the timer".
class DeviceAttachedEvent {
  /// Stable device id, when the platform gave us enough to compute one.
  final String? deviceId;

  /// Human-readable device/product name, for logs.
  final String? name;

  const DeviceAttachedEvent({this.deviceId, this.name});

  @override
  String toString() =>
      'DeviceAttachedEvent(${name ?? 'unnamed'}, ${deviceId ?? 'unknown id'})';
}
