import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';

/// Linux-specific BLE transport that wraps flutter_blue_plus with
/// BlueZ-appropriate handling.
///
/// Key differences from the standard BluePlusTransport:
///
/// 1. **No MTU on connect:** Linux/BlueZ handles MTU negotiation via L2CAP.
///    Requesting a specific MTU at connect time can cause failures.
///    We request MTU separately after the connection is established.
///
/// 2. **Post-connect delay:** BlueZ needs a brief settle period after
///    establishing a connection before service discovery works reliably.
///
/// 3. **Service discovery retry:** On BlueZ, service discovery can sometimes
///    return empty results if called too soon after connection.
///
/// 4. **Connection priority is a no-op:** BlueZ does not support connection
///    priority parameters the way Android does.
///
/// When connecting outside of the discovery flow (e.g. via the REST API),
/// the device may no longer be in `flutter_blue_plus_linux`'s internal
/// cache. This transport handles that by catching the resulting
/// [StateError] and running a brief BLE scan to repopulate the cache
/// before retrying the connection.
class LinuxBluePlusTransport implements BLETransport {
  final Logger _log;
  final BluetoothDevice _device;

  /// Delay after successful connection before proceeding with operations.
  static const Duration _postConnectDelay = Duration(milliseconds: 500);

  /// Maximum number of service discovery attempts.
  static const int _maxDiscoveryRetries = 3;

  /// Delay between service discovery retry attempts.
  static const Duration _discoveryRetryDelay = Duration(seconds: 1);

  /// Duration of the brief scan used to refresh BlueZ's device cache.
  static const Duration _cacheRefreshScanDuration = Duration(seconds: 4);

  /// Settle time after stopping the cache-refresh scan before connecting.
  static const Duration _cacheRefreshSettleDelay = Duration(seconds: 2);

  LinuxBluePlusTransport({required String remoteId})
    : _device = BluetoothDevice(remoteId: DeviceIdentifier(remoteId)),
      _log = Logger("LinuxBPTransport-$remoteId");

  @override
  Future<void> connect() async {
    _log.info("Connecting...");

    // Skip if already connected.
    if (_device.isConnected) {
      _log.info("Already connected, skipping connect");
      return;
    }

    try {
      await _doConnect();
    } on StateError catch (e) {
      // "Bad state: No element" — flutter_blue_plus_linux lost the device
      // from its internal cache (happens after disconnect on BlueZ).
      // Run a brief scan to repopulate the cache, then retry.
      _log.warning(
        "Device not in BlueZ plugin cache ($e), "
        "running refresh scan before retry",
      );
      await _refreshDeviceCache();
      await _doConnect();
    }
  }

  /// Perform the actual BLE connect + post-connect setup.
  Future<void> _doConnect() async {
    // On Linux/BlueZ, do NOT request a specific MTU during connect.
    // BlueZ handles MTU negotiation automatically via L2CAP, and
    // requesting an MTU at connect time can cause "Operation not
    // permitted" errors or connection failures on some BlueZ versions.
    await _device.connect(
      license: License.free,
      timeout: const Duration(seconds: 15),
    );

    // Post-connect settle delay for BlueZ.
    // The connection is reported as established, but BlueZ may still
    // be finalizing internal state (GATT client setup, etc.)
    _log.fine("Connected, waiting ${_postConnectDelay.inMilliseconds}ms "
        "for BlueZ to settle");
    await Future.delayed(_postConnectDelay);

    // Try to request a higher MTU after connection is stable.
    // Best-effort: if it fails, we continue with the default MTU.
    try {
      await _device.requestMtu(517);
      _log.fine("MTU negotiation successful");
    } catch (e) {
      _log.fine("MTU negotiation failed (using default): $e");
    }

    _log.info("Connection established");
  }

  /// Run a brief BLE scan to repopulate flutter_blue_plus_linux's internal
  /// device list. After disconnect on BlueZ, the plugin's `singleWhere`
  /// lookup fails because the device is no longer cached. Scanning makes
  /// the device visible again.
  Future<void> _refreshDeviceCache() async {
    _log.info("Running pre-connect scan to restore device in BlueZ cache");
    try {
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
        await Future.delayed(const Duration(milliseconds: 500));
      }

      await FlutterBluePlus.startScan(oneByOne: true);
      await Future.delayed(_cacheRefreshScanDuration);
      await FlutterBluePlus.stopScan();

      // Critical: wait for BlueZ to fully settle after the scan
      // before attempting to connect, otherwise we hit
      // le-connection-abort-by-local.
      _log.fine(
        "Cache refresh scan complete, waiting "
        "${_cacheRefreshSettleDelay.inSeconds}s for BlueZ to settle",
      );
      await Future.delayed(_cacheRefreshSettleDelay);
    } catch (e) {
      _log.warning("Pre-connect cache refresh scan failed: $e");
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
    }
  }

  @override
  Stream<bool> get connectionState =>
      _device.connectionState
          .map((e) => e == BluetoothConnectionState.connected)
          .asBroadcastStream();

  @override
  Future<void> disconnect() async {
    try {
      await _device.disconnect();
    } catch (e) {
      _log.warning("Error during disconnect: $e");
    }
  }

  @override
  Future<List<String>> discoverServices() async {
    for (int attempt = 1; attempt <= _maxDiscoveryRetries; attempt++) {
      try {
        final list = await _device.discoverServices(timeout: 15);
        if (list.isEmpty && attempt < _maxDiscoveryRetries) {
          _log.warning(
            "Service discovery returned empty results "
            "(attempt $attempt/$_maxDiscoveryRetries), retrying",
          );
          await Future.delayed(_discoveryRetryDelay);
          continue;
        }
        _log.fine("Discovered ${list.length} services");
        return list.map((e) => e.serviceUuid.str).toList();
      } catch (e) {
        _log.warning("Service discovery attempt $attempt failed: $e");
        if (attempt < _maxDiscoveryRetries) {
          await Future.delayed(_discoveryRetryDelay);
        } else {
          rethrow;
        }
      }
    }
    return [];
  }

  @override
  String get id => _device.remoteId.str;

  @override
  String get name => _device.platformName.isNotEmpty
      ? _device.platformName
      : _device.advName;

  @override
  Future<Uint8List> read(
    String serviceUUID,
    String characteristicUUID, {
    Duration? timeout,
  }) async {
    final service = _device.servicesList.firstWhere(
      (s) => s.serviceUuid == Guid(serviceUUID),
    );
    final characteristic = service.characteristics.firstWhere(
      (c) => c.characteristicUuid == Guid(characteristicUUID),
    );
    return Uint8List.fromList(
      await characteristic.read(timeout: timeout?.inSeconds ?? 15),
    );
  }

  @override
  Future<void> subscribe(
    String serviceUUID,
    String characteristicUUID,
    void Function(Uint8List) callback,
  ) async {
    final service = _device.servicesList.firstWhere(
      (s) => s.serviceUuid == Guid(serviceUUID),
    );
    final characteristic = service.characteristics.firstWhere(
      (c) => c.characteristicUuid == Guid(characteristicUUID),
    );

    final subscription = characteristic.onValueReceived.listen((data) {
      callback(Uint8List.fromList(data));
    });
    _device.cancelWhenDisconnected(subscription);

    // On BlueZ, setting notify value can occasionally fail if the
    // characteristic is not yet ready. A brief delay helps.
    try {
      await characteristic.setNotifyValue(true);
    } catch (e) {
      _log.warning("setNotifyValue failed, retrying after delay: $e");
      await Future.delayed(const Duration(milliseconds: 200));
      await characteristic.setNotifyValue(true);
    }
  }

  @override
  Future<void> write(
    String serviceUUID,
    String characteristicUUID,
    Uint8List data, {
    bool withResponse = true,
    Duration? timeout,
  }) async {
    final service = _device.servicesList.firstWhere(
      (s) => s.serviceUuid == Guid(serviceUUID),
    );
    final characteristic = service.characteristics.firstWhere(
      (c) => c.characteristicUuid == Guid(characteristicUUID),
    );
    await characteristic.write(
      data.toList(),
      withoutResponse: !withResponse,
      timeout: timeout?.inSeconds ?? 15,
    );
  }

  @override
  Future<void> setTransportPriority(bool prioritized) async {
    // Connection priority is not supported on Linux/BlueZ.
    // BlueZ manages connection parameters internally through the kernel.
    _log.fine(
      "setTransportPriority($prioritized) ignored on Linux "
      "(not supported by BlueZ)",
    );
  }
}
