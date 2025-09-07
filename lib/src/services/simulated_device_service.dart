import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/mock_de1/mock_de1.dart';
import 'package:reaprime/src/models/device/impl/mock_scale/mock_scale.dart';
import 'package:reaprime/src/models/device/impl/sensor/mock/mock_sensor_basket.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/scale.dart';

class SimulatedDeviceService
    with ChangeNotifier
    implements DeviceDiscoveryService {
  final Map<String, Device> _devices = {};

  final StreamController<List<Device>> _deviceStreamController =
      StreamController.broadcast();

  bool simulationEnabled = false;

  @override
  Future<Machine> connectToMachine({String? deviceId}) async {
    return MockDe1();
  }

  @override
  Future<Scale> connectToScale({String? deviceId}) async {
    return _devices["MockScale"] as Scale;
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

  int scanCount = 0;

  @override
  Future<void> scanForDevices() async {
    if (!simulationEnabled) {
      return;
    }
    _devices["MockDe1"] = MockDe1();
    _devices["MockScale"] = MockScale();
    _devices["MockSensorBasket"] = MockSensorBasket();
    // if (scanCount > 1) {
    //   _devices["MockDe1 #2"] = MockDe1(deviceId: "MockDe1 #2");
    // }
    _deviceStreamController.add(_devices.values.toList());
    notifyListeners();
    scanCount++;
  }
}
