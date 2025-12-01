import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/hardware_scale.dart';

enum DeviceType { machine, scale, sensor }

abstract class Device {
  String get deviceId;
  String get name;
  DeviceType get type;

  // discover and subscribe to services/characteristics
  Future<void> onConnect();

  // tear down any connections
  disconnect();

  Stream<ConnectionState> get connectionState;
}

enum ConnectionState {
  connecting,
  connected,
  disconnecting,
  disconnected,
}

abstract class DeviceDiscoveryService {
  Stream<List<Device>> get devices;

  Future<void> initialize() async {
    throw "Not implemented yet";
  }

  Future<void> scanForDevices() async {
    throw "Not implemented yet";
  }

  // return machine with specific id
  Future<Machine> connectToMachine({String? deviceId}) async {
    throw "Not implemented yet";
  }

  // return scale with specific id
  Future<HardwareScale> connectToScale({String? deviceId}) async {
    throw "Not implemented yet";
  }

  // disconnect (and dispose of?) device
  Future<void> disconnect(Device device) async {
    throw "Not implemented yet";
  }
}
