import 'package:reaprime/src/models/device/bengle_interface.dart';
import 'package:reaprime/src/models/device/impl/mock_de1/mock_de1.dart';
import 'package:reaprime/src/models/device/machine.dart';

/// Simulated Bengle. Reuses [MockDe1]'s state machine — Bengle's behavior
/// today is functionally identical to a DE1 plus the FW-prelude hook
/// (which mocks bypass entirely, since `MockDe1.updateFirmware` is faked
/// at the public level rather than going through the `_updateFirmware`
/// template that calls `beforeFirmwareUpload`).
///
/// Capability surfaces (cup warmer, integrated scale, LED, milk probe)
/// land in steps 4–7; mirror them on this mock as they're added.
class MockBengle extends MockDe1 implements BengleInterface {
  MockBengle({super.deviceId = 'MockBengle'});

  @override
  String get name => 'MockBengle';

  double _cupWarmerTemp = 0.0;

  @override
  Future<void> setCupWarmerTemperature(double celsius) async {
    _cupWarmerTemp = celsius.clamp(0.0, 80.0).toDouble();
  }

  @override
  Future<double> getCupWarmerTemperature() async => _cupWarmerTemp;

  @override
  MachineInfo get machineInfo => MachineInfo(
    version: "1.0",
    model: "Bengle",
    serialNumber: "110010101",
    groupHeadControllerPresent: true,
    extra: {'voltage': 220, 'refillKit': false},
  );
}
