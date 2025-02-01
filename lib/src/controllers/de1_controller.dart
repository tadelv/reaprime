import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:rxdart/subjects.dart';

class De1Controller {
  final DeviceController _deviceController;

  De1Interface? _de1;
  final Logger _log = Logger("De1Controller");

	final BehaviorSubject<De1Interface?> _de1Controller = BehaviorSubject.seeded(null);

	Stream<De1Interface?> get de1 => _de1Controller.stream;

  De1Controller({required DeviceController controller})
    : _deviceController = controller {
    _log.info("checking ${_deviceController.devices}");
    _deviceController.deviceStream.listen((devices) async {
      var de1List = devices.whereType<De1Interface>().toList();
      if (de1List.firstOrNull != null && _de1 == null) {
        var de1 = de1List.first;
        _log.fine("found de1, connecting");
        await de1.onConnect();
        _de1 = de1;
				_de1Controller.add(_de1);
      }
    });
  }

  De1Interface connectedDe1() {
    if (_de1 == null) {
      throw "De1 not connected yet";
    }
    return _de1!;
  }
}
