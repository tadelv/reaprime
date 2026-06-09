import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/impl/mock_de1/mock_de1.dart';
import 'package:reaprime/src/models/device/impl/mock_scale/mock_scale.dart';
import 'package:reaprime/src/models/device/simulated_device.dart';

void main() {
  test('every simulated-device mock implements the SimulatedDevice marker',
      () async {
    // Forcing function: a new mock added WITHOUT the marker would be wrongly
    // eligible for the remembered registry — RememberedDevice.fromDevice only
    // skips devices that are `is SimulatedDevice`. If you add a new mock, add it
    // here and make it implement SimulatedDevice.
    final de1 = MockDe1();
    expect(de1, isA<SimulatedDevice>());
    await de1.dispose();

    final scale = MockScale();
    expect(scale, isA<SimulatedDevice>());
    await scale.disconnect(); // stops the emission timer
  });
}
