import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/sensor.dart';

class SensorController {
  final DeviceController _deviceController;

  List<Sensor> _sensors = [];

  final Logger _log = Logger("SensorController");

  SensorController({required DeviceController controller})
      : _deviceController = controller {
    _deviceController.deviceStream.listen(_processDevices);
  }

  Future<void> _processDevices(List<Device> devices) async {
    final sensors = devices.whereType<Sensor>().toList();
    _sensors = sensors;
    await Future.wait(_sensors.map((s) => s.onConnect()));
  }

  List<Sensor> get sensors => _sensors;
}
