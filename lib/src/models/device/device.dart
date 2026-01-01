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

}
