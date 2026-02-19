import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/mock_de1/mock_de1.dart';
import 'package:reaprime/src/models/device/impl/mock_scale/mock_scale.dart';
import 'package:reaprime/src/models/device/impl/sensor/mock/mock_debug_port.dart';
import 'package:reaprime/src/models/device/impl/sensor/mock/mock_sensor_basket.dart';

class SimulatedDeviceService
    with ChangeNotifier
    implements DeviceDiscoveryService {
  final Map<String, Device> _devices = {};

  final StreamController<List<Device>> _deviceStreamController =
      StreamController.broadcast();

  bool simulationEnabled = false;

  @override
  Stream<List<Device>> get devices => _deviceStreamController.stream;

  @override
  Future<void> initialize() async {}

  int scanCount = 0;

  @override
  Future<void> scanForSpecificDevices(List<String> deviceIds) async {
    // Simulated service: fall back to full scan
    await scanForDevices();
  }

  @override
  Future<void> scanForDevices() async {
    if (!simulationEnabled) {
      return;
    }
    _devices["MockDe1"] = MockDe1();
    _devices["MockScale"] = MockScale();
    _devices["MockSensorBasket"] = MockSensorBasket();
    _devices["MockDebugPort"] = MockDebugPort();
    // if (scanCount > 1) {
    //   _devices["MockDe1 #2"] = MockDe1(deviceId: "MockDe1 #2");
    // }
    _deviceStreamController.add(_devices.values.toList());
    notifyListeners();
    scanCount++;
  }
}
