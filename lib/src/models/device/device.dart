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

  /// Scan for a specific device by ID.
  ///
  /// Implementations should validate whether [deviceId] belongs to their
  /// transport (BLE MAC format for BLE services, port path for serial, etc.)
  /// and no-op if it does not. This avoids BLE services scanning for USB IDs
  /// and vice versa.
  Future<void> scanForSpecificDevice(String deviceId) async {
    // Default: no-op. Override in services that support targeted scanning.
  }
}
