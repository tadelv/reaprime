import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';

class BatteryController {
  final De1Controller _controller;

  late Timer _batteryCheckTimer;
  final Battery _battery = Battery();
  final Logger _log = Logger("Battery");
  bool _isCharging = false;

  BatteryController(this._controller) {
    _batteryCheckTimer = Timer.periodic(Duration(minutes: 1), (Timer t) async {
      var chargeLevel = await _battery.batteryLevel;
      var batteyState = await _battery.batteryState;
      _log.fine("checking battery: ${chargeLevel}, ${batteyState.name}");
      try {
        var de1 = _controller.connectedDe1();
        if (chargeLevel < 30) {
          _isCharging = true;
        } else if (chargeLevel > 70) {
          _isCharging = false;
        }
        // Force charge mode, otherwise it's reset after 10mins
        await de1.setUsbChargerMode(_isCharging);
      } catch (e) {
        _log.warning("failed to set charger mode", e);
      }
    });
  }
}
