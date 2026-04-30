import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/impl/bengle/bengle.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1.dart';

import '../../helpers/fake_ble_transport.dart';

void main() {
  group('Firmware upload tuning', () {
    test('UnifiedDe1 default batch pause is non-zero on serial transport',
        () {
      // Default DE1: serial path needs UART backpressure pauses to avoid
      // overrunning the SPI flash writer. Anything >0 keeps that intact.
      final de1 = UnifiedDe1(transport: FakeBleTransport());
      // BLE transport → pause should be zero (writeWithResponse acks).
      // ignore: invalid_use_of_protected_member
      expect(de1.firmwareUploadBatchPause, equals(Duration.zero));
    });

    test('Bengle overrides firmware upload pause to zero', () {
      // Bengle's USB CDC has built-in flow control, so the artificial
      // batch pause isn't needed — full bandwidth is available.
      final bengle = Bengle(transport: FakeBleTransport());
      // ignore: invalid_use_of_protected_member
      expect(bengle.firmwareUploadBatchPause, equals(Duration.zero));
    });
  });
}
