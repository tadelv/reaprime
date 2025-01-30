import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';

class De1Controller {
  final DeviceController _deviceController;

  late De1Interface? _de1;
  final Logger _log = Logger("De1Controller");

  De1Controller({required DeviceController controller})
    : _deviceController = controller {
    _log.info("checking ${_deviceController.devices}");
    _deviceController.deviceStream.listen((devices) async {
      var de1List = devices.whereType<De1Interface>().toList();
      if (de1List.firstOrNull != null) {
        var de1 = de1List.first;
        _log.fine("found de1, connecting");
        await de1.onConnect();
        _de1 = de1;
      }
    });
  }

  Future<De1Interface> connectedDe1() async {
    if (_de1 == null) {
      throw "De1 not connected yet";
    }
    return _de1!;
  }
}
