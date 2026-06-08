import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/services/wifi/wifi_scale_discovery_service.dart';
import 'package:rxdart/subjects.dart';

class FakeWifiScaleBrowser implements WifiScaleBrowser {
  final BehaviorSubject<List<WifiScaleEndpoint>> _ctrl =
      BehaviorSubject.seeded(<WifiScaleEndpoint>[]);
  bool started = false;
  bool failStart = false;

  @override
  Stream<List<WifiScaleEndpoint>> get endpoints => _ctrl.stream;

  @override
  Future<void> start() async {
    if (failStart) throw StateError('mDNS unavailable (no Avahi)');
    started = true;
  }

  @override
  Future<void> stop() async {
    if (!_ctrl.isClosed) await _ctrl.close();
  }

  void emit(List<WifiScaleEndpoint> eps) => _ctrl.add(eps);
}

class InMemoryManualStore implements WifiManualEndpointStore {
  List<String> hosts;
  InMemoryManualStore([this.hosts = const []]);

  @override
  Future<List<String>> load() async => List.of(hosts);

  @override
  Future<void> save(List<String> h) async => hosts = List.of(h);
}

/// Latest device list, after letting microtasks settle.
Future<List<Device>> _latest(WifiScaleDiscoveryService svc) async {
  await Future.delayed(Duration.zero);
  return svc.devices.first;
}

void main() {
  group('WifiScaleDiscoveryService', () {
    test('a discovered service becomes a wifi-scoped scale device', () async {
      final browser = FakeWifiScaleBrowser();
      final svc = WifiScaleDiscoveryService(
        browser: browser,
        manualStore: InMemoryManualStore(),
      );
      await svc.initialize();
      expect(await _latest(svc), isEmpty);

      browser.emit([
        const WifiScaleEndpoint(host: 'hds.local', ip: '192.168.1.42'),
      ]);
      final devices = await _latest(svc);
      expect(devices, hasLength(1));
      expect(devices.single.deviceId, 'wifi:hds.local');
      expect(devices.single.type, DeviceType.scale);
    });

    test('no service and no manual host yields an empty list, no error',
        () async {
      final svc = WifiScaleDiscoveryService(
        browser: FakeWifiScaleBrowser(),
        manualStore: InMemoryManualStore(),
      );
      await svc.initialize();
      expect(await _latest(svc), isEmpty);
    });

    test('discovery unavailable does not crash; manual host still surfaces',
        () async {
      final browser = FakeWifiScaleBrowser()..failStart = true;
      final svc = WifiScaleDiscoveryService(
        browser: browser,
        manualStore: InMemoryManualStore(['192.168.1.7']),
      );
      // Must not throw even though the browser failed to start.
      await svc.initialize();
      final devices = await _latest(svc);
      expect(devices.single.deviceId, 'wifi:192.168.1.7');
    });

    test('persisted manual endpoints are emitted on init (reconnect path)',
        () async {
      final svc = WifiScaleDiscoveryService(
        browser: FakeWifiScaleBrowser(),
        manualStore: InMemoryManualStore(['hds.local']),
      );
      await svc.initialize();
      expect((await _latest(svc)).single.deviceId, 'wifi:hds.local');
    });

    test('discovered and manual endpoints are unioned', () async {
      final browser = FakeWifiScaleBrowser();
      final svc = WifiScaleDiscoveryService(
        browser: browser,
        manualStore: InMemoryManualStore(['192.168.1.7']),
      );
      await svc.initialize();
      browser.emit([const WifiScaleEndpoint(host: 'hds.local', ip: '10.0.0.5')]);
      final ids = (await _latest(svc)).map((d) => d.deviceId).toSet();
      expect(ids, {'wifi:192.168.1.7', 'wifi:hds.local'});
    });

    test('addManualEndpoint persists and surfaces a device', () async {
      final store = InMemoryManualStore();
      final svc = WifiScaleDiscoveryService(
        browser: FakeWifiScaleBrowser(),
        manualStore: store,
      );
      await svc.initialize();
      await svc.addManualEndpoint('192.168.1.50');
      expect(store.hosts, ['192.168.1.50']);
      expect((await _latest(svc)).single.deviceId, 'wifi:192.168.1.50');
    });

    test('the same scale instance is reused across rebuilds', () async {
      final browser = FakeWifiScaleBrowser();
      final svc = WifiScaleDiscoveryService(
        browser: browser,
        manualStore: InMemoryManualStore(),
      );
      await svc.initialize();
      browser.emit([const WifiScaleEndpoint(host: 'hds.local', ip: '10.0.0.5')]);
      final first = (await _latest(svc)).single;
      browser.emit([const WifiScaleEndpoint(host: 'hds.local', ip: '10.0.0.9')]);
      final second = (await _latest(svc)).single;
      expect(identical(first, second), isTrue);
    });
  });
}
