import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';
import 'package:reaprime/src/models/device/machine.dart';

/// The firmware-update machine state is `FirmwareUp = 0x16`
/// (APIDataTypes.hpp), not the `0x22` reaprime used to hard-code.
///
/// The old value worked for *writes* only by accident (the firmware
/// clamped 0x22 down to its max 0x16), and broke *readback*: the machine
/// reports 0x16, which had no case and fell through to `error`, so the app
/// could never see the machine enter firmware-update. This locks in both
/// directions.
void main() {
  group('De1StateEnum.fwUpgrade', () {
    test('fwUpgrade encodes as 0x16 on the wire', () {
      expect(De1StateEnum.fwUpgrade.hexValue, 0x16);
    });

    test('fromHexValue(0x16) decodes to fwUpgrade (readback works)', () {
      expect(De1StateEnum.fromHexValue(0x16), De1StateEnum.fwUpgrade);
    });

    test('the old 0x22 value no longer maps to any state', () {
      // Regression: the firmware never emits 0x22; if the constant ever
      // regresses to 0x22, this flips.
      expect(De1StateEnum.fromHexValue(0x22), De1StateEnum.unknown);
    });

    test('fromMachineState(fwUpgrade) round-trips to the 0x16 wire byte', () {
      final state = De1StateEnum.fromMachineState(MachineState.fwUpgrade);
      expect(state, De1StateEnum.fwUpgrade);
      expect(state.hexValue, 0x16);
    });
  });
}
