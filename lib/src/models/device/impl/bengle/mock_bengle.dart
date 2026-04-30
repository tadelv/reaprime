import 'package:reaprime/src/models/device/bengle_interface.dart';
import 'package:reaprime/src/models/device/impl/mock_de1/mock_de1.dart';

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
}
