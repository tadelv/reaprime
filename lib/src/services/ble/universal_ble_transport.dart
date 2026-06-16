import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/device.dart' as device;
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:reaprime/src/services/ble/ble_exception_mapper.dart';
import 'package:rxdart/subjects.dart';
import 'package:universal_ble/universal_ble.dart';

class UniversalBleTransport implements BLETransport {
  final BleDevice _device;

  late Logger _log;

  final BehaviorSubject<device.ConnectionState> _connectionStateSubject = BehaviorSubject.seeded(
    device.ConnectionState.discovered,
  );

  StreamSubscription? _connectionStateSubscription;

  // BlueZ-specific timings (Linux only). universal_ble's Linux backend is the
  // pure-Dart `bluez` client, which needs the same handling the former
  // LinuxBluePlusTransport applied: connecting while (or right after) a scan
  // triggers `le-connection-abort-by-local`, so we stop scanning and let the
  // adapter settle before connecting; GATT service resolution also needs
  // retries because BlueZ resolves services asynchronously after connect.
  static const Duration _bluezPostConnectDelay = Duration(milliseconds: 500);
  static const Duration _bluezScanSettleDelay = Duration(seconds: 2);
  static const Duration _bluezCacheRefreshScan = Duration(seconds: 4);
  static const int _bluezDiscoveryRetries = 3;
  static const Duration _bluezDiscoveryRetryDelay = Duration(seconds: 1);

  bool get _isLinux => Platform.isLinux;

  UniversalBleTransport({required BleDevice device}) : _device = device {
    _log = Logger("BLETransport-${device.deviceId}");
  }

  @override
  Future<void> connect() async {
    _connectionStateSubscription = UniversalBle.connectionStream(
      _device.deviceId,
    ).listen((d) {
      _connectionStateSubject.add(
        d ? device.ConnectionState.connected : device.ConnectionState.disconnected,
      );
    });
    if (_isLinux) {
      await _connectBlueZ();
      return;
    }
    try {
      await UniversalBle.connect(
        _device.deviceId,
        timeout: Duration(seconds: 10),
      );
    } on UniversalBleException catch (e) {
      throw mapUniversalConnectError(e);
    }
  }

  /// BlueZ connect with the mitigations the native fbp Linux path needed.
  /// First attempt stops any scan and lets BlueZ settle, then connects. On
  /// failure, run a brief refresh scan (BlueZ can drop the device from its
  /// cache after a disconnect) and retry once.
  Future<void> _connectBlueZ() async {
    try {
      await _doConnectBlueZ();
    } on UniversalBleException catch (e) {
      _log.warning(
        "BlueZ connect failed ($e); refreshing device cache and retrying",
      );
      await _refreshDeviceCache();
      try {
        await _doConnectBlueZ();
      } on UniversalBleException catch (e2) {
        throw mapUniversalConnectError(e2);
      }
    }
  }

  Future<void> _doConnectBlueZ() async {
    // Stop scanning and let the adapter settle — connecting while a scan is
    // active (or immediately after) causes le-connection-abort-by-local.
    await _stopScanAndSettle();
    await UniversalBle.connect(
      _device.deviceId,
      timeout: Duration(seconds: 15),
    );
    // BlueZ finalizes GATT client setup slightly after connect reports success.
    await Future.delayed(_bluezPostConnectDelay);
  }

  Future<void> _stopScanAndSettle() async {
    try {
      await UniversalBle.stopScan();
    } catch (e) {
      _log.fine("stopScan before BlueZ connect failed (ignored): $e");
    }
    _log.fine(
      "Waiting ${_bluezScanSettleDelay.inSeconds}s for BlueZ to settle "
      "before connect",
    );
    await Future.delayed(_bluezScanSettleDelay);
  }

  /// Brief scan to repopulate BlueZ's device cache (the device can drop out of
  /// the adapter's object tree after a disconnect), then settle before retry.
  Future<void> _refreshDeviceCache() async {
    try {
      await UniversalBle.stopScan();
      await Future.delayed(const Duration(milliseconds: 500));
      await UniversalBle.startScan(scanFilter: ScanFilter(withServices: []));
      await Future.delayed(_bluezCacheRefreshScan);
      await UniversalBle.stopScan();
      await Future.delayed(_bluezScanSettleDelay);
    } catch (e) {
      _log.warning("BlueZ cache-refresh scan failed: $e");
      try {
        await UniversalBle.stopScan();
      } catch (_) {}
    }
  }

  @override
  Stream<device.ConnectionState> get connectionState =>
      _connectionStateSubject.asBroadcastStream();

  @override
  Future<void> disconnect() async {
    try {
      _log.fine("disconnect");
      for (var sub in _subscriptions.keys) {
        final split = sub.split('--');
        UniversalBle.unsubscribe(_device.deviceId, split[0], split[1]);
        _subscriptions[sub]?.cancel();
      }
      await UniversalBle.disconnect(
        _device.deviceId,
        timeout: Duration(seconds: 5),
      );
    } catch (e) {
      _log.warning("failed to disconnect", e);
      _connectionStateSubject.add(device.ConnectionState.disconnected);
    }
    _connectionStateSubscription?.cancel();
  }

  @override
  Future<List<String>> discoverServices() async {
    if (!_isLinux) {
      final services = await UniversalBle.discoverServices(
        _device.deviceId,
        timeout: Duration(seconds: 10),
      );
      _log.fine(
        "discovered services: ${services.map((e) => e.toString()).toList().join('\n')}",
      );
      return services.map((s) => s.uuid).toList();
    }

    // BlueZ resolves GATT services asynchronously after connect; a query too
    // soon can throw "Failed to resolve services" or return empty. Retry a
    // few times (ported from LinuxBluePlusTransport).
    for (int attempt = 1; attempt <= _bluezDiscoveryRetries; attempt++) {
      try {
        final services = await UniversalBle.discoverServices(
          _device.deviceId,
          timeout: Duration(seconds: 15),
        );
        if (services.isEmpty && attempt < _bluezDiscoveryRetries) {
          _log.warning(
            "discoverServices returned empty "
            "(attempt $attempt/$_bluezDiscoveryRetries), retrying",
          );
          await Future.delayed(_bluezDiscoveryRetryDelay);
          continue;
        }
        _log.fine("discovered ${services.length} services");
        return services.map((s) => s.uuid).toList();
      } on UniversalBleException catch (e) {
        _log.warning(
          "discoverServices attempt $attempt/$_bluezDiscoveryRetries "
          "failed: $e",
        );
        if (attempt < _bluezDiscoveryRetries) {
          await Future.delayed(_bluezDiscoveryRetryDelay);
        } else {
          rethrow;
        }
      }
    }
    return [];
  }

  @override
  String get id => _device.deviceId;

  @override
  String get name => _device.name ?? "Unknown";

  @override
  Future<Uint8List> read(String serviceUUID, String characteristicUUID, {Duration? timeout}) async {
    return await UniversalBle.read(
      _device.deviceId,
      serviceUUID,
      characteristicUUID,
      timeout: timeout
    );
  }

  final Map<String, StreamSubscription<Uint8List>> _subscriptions = {};

  @override
  Future<void> subscribe(
    String serviceUUID,
    String characteristicUUID,
    void Function(Uint8List) callback,
  ) async {
    _log.fine("subscribe to: $serviceUUID, $characteristicUUID");
    final key = "$serviceUUID--$characteristicUUID";
    // Cancel any prior listener for this characteristic before replacing it.
    // A re-subscribe without an intervening disconnect (no-op reconnect)
    // would otherwise stack listeners and deliver every notification twice.
    await _subscriptions.remove(key)?.cancel();
    final sub = UniversalBle.characteristicValueStream(
      _device.deviceId,
      characteristicUUID,
    ).listen(callback);
    _subscriptions[key] = sub;

    await UniversalBle.subscribeNotifications(
      _device.deviceId,
      serviceUUID,
      characteristicUUID,
    );
  }

  @override
  Future<void> write(
    String serviceUUID,
    String characteristicUUID,
    Uint8List data, {
    bool withResponse = true,
    Duration? timeout,
  }) async {
    await UniversalBle.write(
      _device.deviceId,
      BleUuidParser.string(serviceUUID),
      BleUuidParser.string(characteristicUUID),
      data,
      withoutResponse: !withResponse,
      timeout: timeout
    );
  }

  @override
  Future<void> setTransportPriority(bool prioritized) async {
    // Android-only in universal_ble 2.x; throws `notSupported` elsewhere.
    if (!BleCapabilities.supportsConnectionPriorityApi) return;
    try {
      await UniversalBle.requestConnectionPriority(
        _device.deviceId,
        prioritized
            ? BleConnectionPriority.highPerformance
            : BleConnectionPriority.balanced,
      );
    } on UniversalBleException catch (e) {
      // Best-effort hint; never fail a connection over it.
      _log.fine("requestConnectionPriority not applied: ${e.code}");
    }
  }

  @override
  Future<void> dispose() async {
    _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null;
    for (final sub in _subscriptions.values) {
      await sub.cancel();
    }
    _subscriptions.clear();
    if (!_connectionStateSubject.isClosed) {
      _connectionStateSubject.close();
    }
  }
}
