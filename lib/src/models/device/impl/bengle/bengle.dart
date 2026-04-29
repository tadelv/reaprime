import 'package:flutter/foundation.dart';
import 'package:reaprime/src/models/device/bengle_interface.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1.dart';
import 'package:reaprime/src/models/device/machine.dart';

class Bengle extends UnifiedDe1 implements BengleInterface {
  Bengle({required super.transport});

  @override
  String get name => "Bengle";

  /// Bengle FW requires entering state 0x22 (`MachineState.fwUpgrade`) between
  /// the `requestState(sleeping)` step and the start of `.dat` upload.
  /// DE1 doesn't need this — see [UnifiedDe1.beforeFirmwareUpload]
  /// for the hook contract.
  @override
  @protected
  Future<void> beforeFirmwareUpload() async {
    await requestState(MachineState.fwUpgrade);
  }
}
