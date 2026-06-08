import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/services/wifi/wifi_ip_cache.dart';

void main() {
  group('WifiIpCache', () {
    test('connectHostFor falls back to the host when uncached', () {
      final cache = WifiIpCache();
      expect(cache.connectHostFor('hds.local'), 'hds.local');
      expect(cache.cachedIp('hds.local'), isNull);
    });

    test('prefers the cached IP once recorded', () {
      final cache = WifiIpCache()..record('hds.local', '192.168.1.42');
      expect(cache.connectHostFor('hds.local'), '192.168.1.42');
      expect(cache.cachedIp('hds.local'), '192.168.1.42');
    });

    test('re-resolve overwrites a stale entry (self-heal)', () {
      final cache = WifiIpCache()..record('hds.local', '192.168.1.42');
      cache.record('hds.local', '192.168.1.99');
      expect(cache.connectHostFor('hds.local'), '192.168.1.99');
    });

    test('invalidate falls back to the hostname for re-resolution', () {
      final cache = WifiIpCache()..record('hds.local', '192.168.1.42');
      cache.invalidate('hds.local');
      expect(cache.connectHostFor('hds.local'), 'hds.local');
    });

    test('ignores empty host or ip', () {
      final cache = WifiIpCache()
        ..record('', '1.2.3.4')
        ..record('hds.local', '');
      expect(cache.cachedIp('hds.local'), isNull);
      expect(cache.connectHostFor('hds.local'), 'hds.local');
    });
  });
}
