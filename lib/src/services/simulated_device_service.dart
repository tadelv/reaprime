import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/mock_de1/mock_de1.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/scale.dart';

class SimulatedDeviceService with ChangeNotifier implements DeviceDiscoveryService {
  final Map<String, Device> _devices = {};

	final StreamController<List<Device>> _deviceStreamController = StreamController.broadcast();

  @override
  Future<Machine> connectToMachine({String? deviceId}) async {
    return MockDe1();
  }

  @override
  Future<Scale> connectToScale({String? deviceId}) {
    // TODO: implement connectToScale
    throw UnimplementedError();
  }

  @override
  Stream<List<Device>> get devices => _deviceStreamController.stream;

  @override
  Future<void> disconnect(Device device) async {
    // TODO: implement disconnect
    throw UnimplementedError();
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> scanForDevices() async {
    _devices["MockDe1"] = MockDe1();
		_deviceStreamController.add(_devices.values.toList());
    notifyListeners();
  }
}
