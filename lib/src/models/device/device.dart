enum DeviceType { machine, scale, sensor }

abstract class Device {
  String get deviceId;
  String get name;
  DeviceType get type;

  // discover and subscribe to services/characteristics
  Future<void> onConnect();

  // tear down any connections
  Future<void> disconnect();

  Stream<ConnectionState> get connectionState;
}

enum ConnectionState { connecting, connected, disconnecting, disconnected }

abstract class DeviceDiscoveryService {
  Stream<List<Device>> get devices;

  Future<void> initialize() async {
    throw "Not implemented yet";
  }

  Future<void> scanForDevices() async {
    throw "Not implemented yet";
  }

  /// Scan for specific devices by ID.
  ///
  /// Implementations should filter [deviceIds] to those belonging to their
  /// transport (BLE MAC format for BLE services, port path for serial, etc.)
  /// and no-op if none match. This avoids BLE services scanning for USB IDs
  /// and vice versa.
  ///
  /// For BLE services, all matching IDs are passed to a single scan so that
  /// one BLE scan can discover multiple devices (machine + scale).
  Future<void> scanForSpecificDevices(List<String> deviceIds) async {
    // Default: no-op. Override in services that support targeted scanning.
  }
}
