import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';

class De1Controller {
  final DeviceController _deviceController;

  late De1Interface? _de1;

  De1Controller({required DeviceController controller})
    : _deviceController = controller {
    _deviceController.deviceStream.listen((devices) async {
      var de1List = devices.whereType<De1Interface>().toList();
      if (de1List.firstOrNull != null) {
        var de1 = de1List.first;
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
