import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';

class BatteryController {
  final De1Controller _controller;

  late Timer _batteryCheckTimer;
  final Battery _battery = Battery();
  final Logger _log = Logger("Battery");

  BatteryController(this._controller) {
    _batteryCheckTimer = Timer.periodic(Duration(minutes: 1), (Timer t) async {
      var chargeLevel = await _battery.batteryLevel;
      var batteyState = await _battery.batteryState;
      _log.fine("checking battery: ${chargeLevel}, ${batteyState.name}");
      try {
        var de1 = _controller.connectedDe1();
        if (chargeLevel < 30) {
          await de1.setUsbChargerMode(true);
        } else if (chargeLevel > 70) {
          await de1.setUsbChargerMode(false);
        }
      } catch (e) {
        _log.warning("failed to set charger mode", e);
      }
    });
  }
}
