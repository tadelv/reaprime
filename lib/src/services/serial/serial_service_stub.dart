import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:rxdart/subjects.dart';

DeviceDiscoveryService createSerialService() => SerialServiceStub();

class SerialServiceStub implements DeviceDiscoveryService {
  @override
  Future<Machine> connectToMachine({String? deviceId}) {
    throw UnimplementedError();
  }

  @override
  Future<Scale> connectToScale({String? deviceId}) {
    throw UnimplementedError();
  }

  @override
  Stream<List<Device>> get devices => BehaviorSubject.seeded(<Device>[]).stream;

  @override
  Future<void> disconnect(Device device) {
    throw UnimplementedError();
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> scanForDevices() async {}
}
