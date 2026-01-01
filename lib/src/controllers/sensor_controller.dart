import 'dart:async';

import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/sensor.dart';

class SensorController {
  final DeviceController _deviceController;

  Map<String, Sensor> _sensors = {};

  final Logger _log = Logger("SensorController");
  
  StreamSubscription<List<Device>>? _deviceStreamSubscription;

  SensorController({required DeviceController controller})
      : _deviceController = controller {
    _deviceStreamSubscription = _deviceController.deviceStream.listen(_processDevices);
  }

  Future<void> _processDevices(List<Device> devices) async {
    final sensors = devices.whereType<Sensor>().toList();
    _log.info("received sensors: $sensors");
    _sensors = sensors.fold({}, (val, s) {
      val[s.deviceId] = s;
      return val;
    });
    await Future.wait(sensors.map((s) => s.onConnect()));
  }

  Map<String, Sensor> get sensors => _sensors;

  void dispose() {
    _deviceStreamSubscription?.cancel();
    _deviceStreamSubscription = null;
  }
}
