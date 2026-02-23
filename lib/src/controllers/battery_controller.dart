import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/charging_logic.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:rxdart/rxdart.dart';

class BatteryController {
  final De1Controller _de1Controller;
  final SettingsController _settingsController;
  final Battery _battery = Battery();
  final Logger _log = Logger("Battery");

  late Timer _checkTimer;
  bool _wasCharging = false;

  final BehaviorSubject<ChargingState> _stateSubject =
      BehaviorSubject<ChargingState>();

  Stream<ChargingState> get chargingState => _stateSubject.stream;
  ChargingState? get currentChargingState => _stateSubject.valueOrNull;

  BatteryController({
    required De1Controller de1Controller,
    required SettingsController settingsController,
  })  : _de1Controller = de1Controller,
        _settingsController = settingsController {
    _checkTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _tick(),
    );
    // Run immediately on construction
    _tick();
  }

  Future<void> _tick() async {
    try {
      final batteryPercent = await _battery.batteryLevel;
      final now = DateTime.now();

      final chargingMode = _settingsController.chargingMode;
      final nightModeEnabled = _settingsController.nightModeEnabled;

      NightModeConfig? nightConfig;
      if (nightModeEnabled) {
        nightConfig = NightModeConfig(
          sleepTimeMinutes: _settingsController.nightModeSleepTime,
          morningTimeMinutes: _settingsController.nightModeMorningTime,
        );
      }

      final decision = decide(
        batteryPercent: batteryPercent,
        currentTime: now,
        chargingMode: chargingMode,
        nightModeConfig: nightConfig,
        wasCharging: _wasCharging,
      );

      _wasCharging = decision.shouldCharge;

      _log.fine(
        'Battery: $batteryPercent%, '
        'phase: ${decision.nightPhase.name}, '
        'charge: ${decision.shouldCharge}, '
        'reason: ${decision.reason}',
      );

      // Apply to DE1
      try {
        final de1 = _de1Controller.connectedDe1();
        await de1.setUsbChargerMode(decision.shouldCharge);
      } catch (e) {
        _log.warning('Failed to set USB charger mode', e);
      }

      // Emit state
      _stateSubject.add(ChargingState(
        mode: chargingMode,
        nightModeEnabled: nightModeEnabled,
        currentPhase: decision.nightPhase,
        batteryPercent: batteryPercent,
        usbChargerOn: decision.shouldCharge,
        isEmergency: decision.reason == 'emergency',
      ));
    } catch (e, st) {
      _log.warning('Battery check failed', e, st);
    }
  }

  void dispose() {
    _checkTimer.cancel();
    _stateSubject.close();
  }
}
