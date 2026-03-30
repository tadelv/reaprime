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

enum ConnectionState { discovered, connecting, connected, disconnecting, disconnected }

abstract class DeviceDiscoveryService {
  Stream<List<Device>> get devices;

  Future<void> initialize() async {
    throw "Not implemented yet";
  }

  Future<void> scanForDevices() async {
    throw "Not implemented yet";
  }

  /// Stop an in-progress scan early.
  ///
  /// Default is a no-op. Implementations should cancel any pending scan
  /// timers and stop the underlying scan (e.g., BLE stopScan).
  void stopScan() {
    // Default: no-op.
  }
}
