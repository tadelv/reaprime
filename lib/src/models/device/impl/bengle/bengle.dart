import 'package:flutter/foundation.dart';
import 'package:reaprime/src/models/device/bengle_interface.dart';
import 'package:reaprime/src/models/device/impl/bengle/bengle_mmr.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/scale.dart';

class Bengle extends UnifiedDe1 implements BengleInterface {
  Bengle({required super.transport});

  @override
  String get name => "Bengle";

  @override
  Future<void> setCupWarmerTemperature(double celsius) =>
      writeMmrFloat32(BengleMmr.matSetPoint, celsius);

  @override
  Future<double> getCupWarmerTemperature() =>
      readMmrFloat32(BengleMmr.matSetPoint);

  @override
  Stream<ScaleSnapshot> get weightSnapshot {
    log.warning('Integrated scale not yet wired (Task 7 pending) — '
        'returning empty stream');
    return const Stream.empty();
  }
  // TODO(task-7): replace with IntegratedScaleCapability.weightSnapshot.

  @override
  Future<void> tareIntegratedScale() async {
    log.warning('Integrated scale tare ignored (Task 7 pending)');
  }
  // TODO(task-7): delegate to IntegratedScaleCapability.tareIntegratedScale().

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
}
