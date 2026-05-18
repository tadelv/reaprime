import 'package:flutter/foundation.dart';
import 'package:reaprime/src/models/device/bengle_interface.dart';
import 'package:reaprime/src/models/device/impl/bengle/bengle_mmr.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1.dart';
import 'package:reaprime/src/models/device/machine.dart';

class Bengle extends UnifiedDe1
    with IntegratedScaleCapability, LedStripCapability
    implements BengleInterface {
  Bengle({required super.transport});

  @override
  String get name => "Bengle";

  @override
  Future<void> setCupWarmerTemperature(double celsius) =>
      writeMmrScaled(BengleMmr.matSetPoint, celsius);

  @override
  Future<double> getCupWarmerTemperature() =>
      readMmrScaled(BengleMmr.matSetPoint);

  @override
  Future<void> setStopAtWeightTarget(double grams) async {
    final clamped = grams.clamp(0.0, 200.0).toDouble();
    notifyStopAtWeightTarget(clamped);
    if (BengleMmr.stopAtWeightTarget.address == 0x00000000) {
      log.info('Bengle: SAW target ${clamped}g cached locally — FW slot TBD.');
      return;
    }
    await writeMmrScaled(BengleMmr.stopAtWeightTarget, clamped);
  }

  @override
  Future<double> getStopAtWeightTarget() async {
    if (BengleMmr.stopAtWeightTarget.address == 0x00000000) {
      return currentStopAtWeightTarget;
    }
    final value = await readMmrScaled(BengleMmr.stopAtWeightTarget);
    notifyStopAtWeightTarget(value);
    return value;
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

  // --- integrated scale lifecycle ---

  @override
  Future<void> onConnect() async {
    await super.onConnect();
    await initIntegratedScale();
    await initLedStrip();
  }

  @override
  Future<void> onDisconnect() async {
    await disposeLedStrip();
    await disposeIntegratedScale();
    await super.onDisconnect();
  }

  // --- LED strip ---
  // TODO: when LED api is available





}
