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

  // --- SAW: lives entirely in IntegratedScaleCapability mixin, same
  // shape as LedStripCapability (own MMR enum, log-once stub, cache
  // is authoritative until FW publishes the address).

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
