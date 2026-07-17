/// Optional capability for discovery services that receive device-arrival
/// notifications outside their normal scan path.
abstract class DeviceAttachNotifier {
  /// Non-replaying hints that a device may now be discoverable.
  Stream<DeviceAttachedEvent> get deviceAttached;
}

class DeviceAttachedEvent {
  final String? deviceId;
  final String? name;

  const DeviceAttachedEvent({this.deviceId, this.name});

  @override
  String toString() =>
      'DeviceAttachedEvent(${name ?? 'unnamed'}, ${deviceId ?? 'unknown id'})';
}
