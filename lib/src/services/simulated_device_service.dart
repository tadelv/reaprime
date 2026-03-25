import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/mock_de1/mock_de1.dart';
import 'package:reaprime/src/models/device/impl/mock_scale/mock_scale.dart';
import 'package:reaprime/src/models/device/impl/sensor/mock/mock_debug_port.dart';
import 'package:reaprime/src/models/device/impl/sensor/mock/mock_sensor_basket.dart';
import 'package:reaprime/src/settings/settings_service.dart';

class SimulatedDeviceService
    with ChangeNotifier
    implements DeviceDiscoveryService {
  final Map<String, Device> _devices = {};

  final StreamController<List<Device>> _deviceStreamController =
      StreamController.broadcast();

  Set<SimulatedDevicesTypes> enabledDevices = {};

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
    if (enabledDevices.isEmpty) {
      return;
    }
    if (enabledDevices.contains(SimulatedDevicesTypes.machine)) {
      _devices["MockDe1"] = MockDe1();
    } else {
      _devices.remove("MockDe1");
    }
    if (enabledDevices.contains(SimulatedDevicesTypes.scale)) {
      _devices["MockScale"] = MockScale();
    } else {
      _devices.remove("MockScale");
    }
    if (enabledDevices.contains(SimulatedDevicesTypes.sensor)) {
      _devices["MockSensorBasket"] = MockSensorBasket();
      _devices["MockDebugPort"] = MockDebugPort();
    } else {
      _devices.remove("MockSensorBasket");
      _devices.remove("MockDebugPort");
    }
    _deviceStreamController.add(_devices.values.toList());
    notifyListeners();
    scanCount++;
  }
}
