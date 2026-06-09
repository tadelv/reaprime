import 'dart:async';

import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/decent_scale/scale_wifi.dart';
import 'package:reaprime/src/models/device/scan_filter.dart';
import 'package:reaprime/src/models/device/transport/web_socket_transport.dart';
import 'package:reaprime/src/services/wifi/bonsoir_wifi_scale_browser.dart';
import 'package:reaprime/src/services/wifi/wifi_ip_cache.dart';
import 'package:rxdart/subjects.dart';

/// A WiFi scale endpoint surfaced by the [WifiScaleBrowser].
class WifiScaleEndpoint {
  /// Logical host — the mDNS hostname (e.g. `hds.local`) when available,
  /// otherwise the resolved IP. Stable across reconnects; basis of the
  /// scale's `deviceId`.
  final String host;

  /// Resolved IPv4 address, if known. Cached for fast/resilient reconnect.
  final String? ip;

  const WifiScaleEndpoint({required this.host, this.ip});
}

/// Abstraction over the mDNS (DNS-SD) browser.
///
/// Keeping bonsoir behind this seam lets [WifiScaleDiscoveryService]'s
/// endpoint→device logic be unit-tested with a fake, while the real
/// bonsoir-backed [BonsoirWifiScaleBrowser] is verified on-device.
abstract class WifiScaleBrowser {
  /// The set of currently-visible resolved endpoints.
  Stream<List<WifiScaleEndpoint>> get endpoints;

  /// Start (or no-op if already started) browsing for `_decentscale._tcp`.
  Future<void> start();

  /// Stop browsing and release resources.
  Future<void> stop();
}

/// Persists manually-added WiFi scale hosts so they survive restarts and can
/// be re-emitted for auto-reconnect.
abstract class WifiManualEndpointStore {
  Future<List<String>> load();
  Future<void> save(List<String> hosts);
}

/// Discovers the WiFi Half Decent Scale on the local network (DNS-SD) and
/// surfaces manually-added endpoints, emitting an [HDSWifi] per known host
/// into the unified device stream.
///
/// Mirrors the USB HDS path: it constructs the scale *directly* rather than
/// routing through the BLE-coupled `DeviceMatcher`. Each scale is built with a
/// transport factory that connects to the cached IP first (then the hostname),
/// honoring the firmware's resolve-once / prefer-IPv4 guidance.
class WifiScaleDiscoveryService implements DeviceDiscoveryService {
  final _log = Logger('WifiScaleDiscovery');
  final WifiScaleBrowser _browser;
  final WifiIpCache _cache;
  final WifiManualEndpointStore _manualStore;

  /// Reused scale instances keyed by `deviceId` so a connected scale survives
  /// list rebuilds (never recreate an in-use HDSWifi).
  final Map<String, HDSWifi> _scales = {};
  List<WifiScaleEndpoint> _discovered = [];
  List<String> _manualHosts = [];
  StreamSubscription<List<WifiScaleEndpoint>>? _browserSub;
  bool _started = false;

  final BehaviorSubject<List<Device>> _devices =
      BehaviorSubject.seeded(<Device>[]);

  WifiScaleDiscoveryService({
    WifiScaleBrowser? browser,
    WifiIpCache? cache,
    WifiManualEndpointStore? manualStore,
  })  : _browser = browser ?? BonsoirWifiScaleBrowser(),
        _cache = cache ?? WifiIpCache(),
        _manualStore = manualStore ?? SharedPrefsWifiManualEndpointStore();

  @override
  Stream<List<Device>> get devices => _devices.stream;

  @override
  Future<void> initialize() async {
    _manualHosts = await _manualStore.load();
    _browserSub = _browser.endpoints.listen((eps) {
      _discovered = eps;
      _rebuild();
    });
    await _ensureStarted();
    _rebuild();
  }

  @override
  Future<void> scanForDevices({ScanFilter? filter}) async {
    // mDNS browsing is passive and continuous — a "scan" just ensures it is
    // running and re-publishes the current known endpoints.
    await _ensureStarted();
    _rebuild();
  }

  @override
  void stopScan() {
    // Leave the browser running; mDNS is passive and cheap, and stopping it
    // would drop endpoints needed for the next preferred-device match.
  }

  Future<void> _ensureStarted() async {
    if (_started) return;
    try {
      await _browser.start();
      _started = true;
    } catch (e, st) {
      // Discovery unavailable (e.g. Linux without Avahi). Manual-IP entry
      // still works; do not crash the scan.
      _log.warning('mDNS browser failed to start; manual entry still available',
          e, st);
    }
  }

  /// The currently-configured manually-added hosts (IPs or hostnames).
  List<String> get manualEndpoints => List.unmodifiable(_manualHosts);

  /// Add a manually-entered host (IP or hostname). Idempotent.
  Future<void> addManualEndpoint(String host) async {
    final h = host.trim();
    if (h.isEmpty || _manualHosts.contains(h)) return;
    _manualHosts = [..._manualHosts, h];
    await _manualStore.save(_manualHosts);
    _rebuild();
  }

  /// Remove a manually-added host and tear down its scale instance.
  Future<void> removeManualEndpoint(String host) async {
    if (!_manualHosts.contains(host)) return;
    _manualHosts = _manualHosts.where((h) => h != host).toList();
    await _manualStore.save(_manualHosts);
    final removed = _scales.remove('wifi:$host');
    await removed?.disconnect();
    _cache.invalidate(host);
    _rebuild();
  }

  void _rebuild() {
    for (final ep in _discovered) {
      if (ep.ip != null) _cache.record(ep.host, ep.ip!);
      _scales.putIfAbsent('wifi:${ep.host}', () => _buildScale(ep.host));
    }
    for (final host in _manualHosts) {
      _scales.putIfAbsent('wifi:$host', () => _buildScale(host));
    }
    if (!_devices.isClosed) {
      _devices.add(List<Device>.from(_scales.values));
    }
  }

  HDSWifi _buildScale(String host) => HDSWifi(
        host: host,
        // Connect to the cached IP when known (resolve-once), else the host.
        transportFactory: () =>
            WsTransport(host: _cache.connectHostFor(host)),
      );

  Future<void> dispose() async {
    await _browserSub?.cancel();
    await _browser.stop();
    if (!_devices.isClosed) await _devices.close();
  }
}
