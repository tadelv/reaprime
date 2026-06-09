import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/impl/decent_scale/wifi_scale_id.dart';

void main() {
  group('WifiScaleId', () {
    test('forHost / hostOf round-trip', () {
      for (final host in ['hds.local', '192.168.1.42', 'hds.local.']) {
        final id = WifiScaleId.forHost(host);
        expect(id, 'wifi:$host');
        expect(WifiScaleId.hostOf(id), host);
      }
    });

    test('hostOf preserves a host containing a colon (e.g. IPv6)', () {
      const host = 'fe80::1';
      expect(WifiScaleId.hostOf(WifiScaleId.forHost(host)), host);
    });

    test('hostOf returns the input unchanged when the prefix is absent', () {
      expect(WifiScaleId.hostOf('192.168.1.42'), '192.168.1.42');
    });
  });
}
