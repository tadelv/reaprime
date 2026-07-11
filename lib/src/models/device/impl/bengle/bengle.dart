import 'package:flutter/foundation.dart';
import 'package:reaprime/src/models/device/bengle_interface.dart';
import 'package:reaprime/src/models/device/impl/bengle/bengle_mmr.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:rxdart/rxdart.dart';

class Bengle extends UnifiedDe1
    with
        IntegratedScaleCapability,
        LedStripCapability,
        ScaleCalibrationCapability
    implements BengleInterface {
  Bengle({required super.transport});

  @override
  String get name => "Bengle";

  /// Last requested cup-warmer target °C (`0` = off). Remembered so the
  /// RAM-only [BengleMmr.cupWarmerMode] can be re-asserted on reconnect.
  double _cupWarmerTarget = 0.0;

  @override
  Future<void> setCupWarmerTemperature(double celsius) async {
    _cupWarmerTarget = celsius.clamp(0.0, 80.0).toDouble();
    await writeMmrScaled(BengleMmr.matSetPoint, _cupWarmerTarget);
    // CupWarmerMode is the real enable — a temperature alone does nothing.
    // `> 0 °C` ⇒ On. It is RAM-only, so it is also re-pushed on every connect.
    await writeMmrInt(BengleMmr.cupWarmerMode, _cupWarmerTarget > 0 ? 1 : 0);
  }

  @override
  Future<double> getCupWarmerTemperature() =>
      readMmrScaled(BengleMmr.matSetPoint);

  @override
  Future<double?> getCupWarmerCurrentTemperature() async {
    // Defensive read: MatCurrentTemp exists only on newer
    // firmware (firmware register-table row 58). A raw 0 means "no valid reading" (NTC
    // open/short) and older FW may not answer at all — both map to null,
    // never fake data.
    try {
      final celsius = await readMmrScaled(BengleMmr.matCurrentTemp);
      return celsius > 0 ? celsius : null;
    } on Exception catch (e) {
      log.fine('MatCurrentTemp read failed (older firmware?): $e');
      return null;
    }
  }

  /// Bengle FW requires entering state 0x22 (`MachineState.fwUpgrade`) between
  /// the `requestState(sleeping)` step and the start of `.dat` upload.
  /// DE1 doesn't need this — see [UnifiedDe1.beforeFirmwareUpload]
  /// for the hook contract.
  @override
  @protected
  Future<void> beforeFirmwareUpload() async {
    await Future.delayed(Duration(milliseconds: 500), () async {
      await requestState(MachineState.fwUpgrade);
    });
  }

  /// Bengle has hardware flow control on the serial
  /// path, so the per-batch backpressure pause that DE1 needs (UART
  /// has none) is unnecessary. Stream chunks at full bandwidth.
  @override
  @protected
  Duration get firmwareUploadBatchPause => Duration.zero;

  // --- Milk-probe steam stop ------------------------------------------------
  //
  // The auto-stop TARGET is a real MMR write ([BengleSteamMmr.stopAtTemperatureTarget]
  // = TargetMilkTemp). The live probe READING is separate — it rides the
  // `0xA013` shot-sample stream, not an MMR — so `probeAttached`/`probeTemperature`
  // are surfaced by that pipeline, not here. (FW currently serialises MilkTemp as 0.)
  final BehaviorSubject<double> _stopAtTempTarget =
      BehaviorSubject<double>.seeded(0.0);
  final BehaviorSubject<bool> _probeAttached =
      BehaviorSubject<bool>.seeded(false);
  final PublishSubject<double> _probeTemperature = PublishSubject<double>();

  @override
  Stream<double> get stopAtTemperatureTarget => _stopAtTempTarget.stream;

  @override
  Stream<bool> get probeAttached => _probeAttached.stream;

  @override
  Stream<double> get probeTemperature => _probeTemperature.stream;

  @override
  Future<void> setStopAtTemperatureTarget(double celsius) async {
    final clamped = celsius.clamp(0.0, 85.0).toDouble();
    if (!_stopAtTempTarget.isClosed) {
      _stopAtTempTarget.add(clamped);
    }
    await writeMmrScaled(BengleSteamMmr.stopAtTemperatureTarget, clamped);
  }

  @override
  Future<double> getStopAtTemperatureTarget() async {
    final value = await readMmrScaled(BengleSteamMmr.stopAtTemperatureTarget);
    if (!_stopAtTempTarget.isClosed) {
      _stopAtTempTarget.add(value);
    }
    return value;
  }

  // --- integrated scale lifecycle ---

  @override
  Future<void> onConnect() async {
    await super.onConnect();
    await initIntegratedScale();
    await initScaleCalibration();
    await initLedStrip();
    // CupWarmerMode is RAM-only (FW resets it to 0 on boot) — re-assert the
    // desired state on every (re)connect so an enabled warmer survives.
    // Conditional on purpose: an app instance that never enabled the warmer
    // must write NOTHING here, or it would stomp state set by another client
    // sharing the machine.
    if (_cupWarmerTarget > 0) {
      await writeMmrScaled(BengleMmr.matSetPoint, _cupWarmerTarget);
      await writeMmrInt(BengleMmr.cupWarmerMode, 1);
    }
  }

  @override
  Future<void> onDisconnect() async {
    await disposeLedStrip();
    await disposeScaleCalibration();
    await disposeIntegratedScale();
    if (!_stopAtTempTarget.isClosed) {
      await _stopAtTempTarget.close();
    }
    if (!_probeAttached.isClosed) {
      await _probeAttached.close();
    }
    if (!_probeTemperature.isClosed) {
      await _probeTemperature.close();
    }
    await super.onDisconnect();
  }
}
