import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:rxdart/subjects.dart';

import 'package:usb_serial/usb_serial.dart';

DeviceDiscoveryService createSerialService() => SerialServiceAndroid();

class SerialServiceAndroid implements DeviceDiscoveryService {
  final _log = Logger("Serial service");

  @override
  Future<Machine> connectToMachine({String? deviceId}) {
    // TODO: implement connectToMachine
    throw UnimplementedError();
  }

  @override
  Future<Scale> connectToScale({String? deviceId}) {
    // TODO: implement connectToScale
    throw UnimplementedError();
  }

  @override
  Stream<List<Device>> get devices => BehaviorSubject.seeded(<Device>[]).stream;

  @override
  Future<void> disconnect(Device device) {
    // TODO: implement disconnect
    throw UnimplementedError();
  }

  @override
  Future<void> initialize() async {
    List<UsbDevice> devices = await UsbSerial.listDevices();
		_log.shout("found ${devices}");
  }

  @override
  Future<void> scanForDevices() async {
  }
}
