import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/models/device/scale.dart';

class ScaleController {
  final DeviceController _deviceController;

  Scale? _scale;

  ScaleController({required DeviceController controller})
    : _deviceController = controller {
    _deviceController.deviceStream.listen((devices) async {
      var scales = devices.whereType<Scale>().toList();
      if (scales.firstOrNull != null) {
        //var scale = scales.first;
        //await scale.onConnect();
        //_scale = scale;
      }
    });
  }

  Scale connectedScale() {
    if (_scale == null) {
      throw "No scale connected";
    }
    return _scale!;
  }
}
