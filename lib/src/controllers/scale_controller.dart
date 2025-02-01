import 'dart:async';

import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:reaprime/src/models/device/device.dart';

class ScaleController {
  final DeviceController _deviceController;

  Scale? _scale;

  StreamSubscription<ConnectionState>? _scaleConnection;

  final Logger log = Logger('ScaleController');

  ScaleController({required DeviceController controller})
      : _deviceController = controller {
    _deviceController.deviceStream.listen((devices) async {
      var scales = devices.whereType<Scale>().toList();
      if (_scale == null && scales.firstOrNull != null) {
        var scale = scales.first;
        _scaleConnection = scale.connectionState.listen((d) {
          log.info('scale connection update: ${d.name}');
          if (d == ConnectionState.disconnected) {
            _scale = null;
            _scaleConnection = null;
          }
        });
        await scale.onConnect();
        _scale = scale;
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
