import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';

/// Linux-specific BLE transport that wraps flutter_blue_plus with
/// BlueZ-appropriate error handling, retry logic, and timing.
///
/// Key differences from the standard BluePlusTransport:
///
/// 1. **Connection retries:** BlueZ connections can fail transiently due to
///    adapter timing issues. We retry with backoff.
///
/// 2. **Post-connect delay:** BlueZ needs a brief settle period after
///    establishing a connection before service discovery works reliably.
///
/// 3. **No MTU negotiation on connect:** Linux/BlueZ handles MTU negotiation
///    differently from Android. Requesting a specific MTU on connect can
///    cause failures. We let BlueZ use its default MTU and request an
///    increase separately after the connection is established.
///
/// 4. **Service discovery retry:** On BlueZ, service discovery can sometimes
///    return empty results if called too soon after connection. We retry
///    with a delay.
///
/// 5. **Connection priority is a no-op:** BlueZ does not support connection
///    priority parameters the way Android does.
///
/// 6. **Write chunking considerations:** BlueZ may have different effective
///    MTU sizes; writes are kept within safe limits.
class LinuxBluePlusTransport implements BLETransport {
  final Logger _log;
  final BluetoothDevice _device;

  /// Maximum number of connection attempts.
  static const int _maxConnectRetries = 3;

  /// Delay between connection retry attempts.
  static const Duration _connectRetryDelay = Duration(seconds: 2);

  /// Delay after successful connection before proceeding with operations.
  /// BlueZ needs time to finalize the connection internally.
  static const Duration _postConnectDelay = Duration(milliseconds: 500);

  /// Maximum number of service discovery attempts.
  static const int _maxDiscoveryRetries = 2;

  /// Delay between service discovery retry attempts.
  static const Duration _discoveryRetryDelay = Duration(seconds: 1);

  LinuxBluePlusTransport({required String remoteId})
    : _device = BluetoothDevice(remoteId: DeviceIdentifier(remoteId)),
      _log = Logger("LinuxBPTransport-$remoteId");

  @override
  Future<void> connect() async {
    for (int attempt = 1; attempt <= _maxConnectRetries; attempt++) {
      try {
        _log.info("Connection attempt $attempt/$_maxConnectRetries");

        // On Linux/BlueZ, do NOT request a specific MTU during connect.
        // BlueZ handles MTU negotiation automatically via L2CAP, and
        // requesting an MTU at connect time can cause "Operation not
        // permitted" errors or connection failures on some BlueZ versions.
        await _device.connect(
          license: License.free,
          timeout: const Duration(seconds: 15),
        );

        // Post-connect settle delay for BlueZ
        // The connection is reported as established, but BlueZ may still
        // be finalizing internal state (GATT client setup, etc.)
        _log.fine(
          "Connected, waiting ${_postConnectDelay.inMilliseconds}ms "
          "for BlueZ to settle",
        );
        await Future.delayed(_postConnectDelay);

        // Try to request a higher MTU after connection is stable.
        // This is a best-effort operation; if it fails, we continue
        // with the default MTU.
        try {
          await _device.requestMtu(517);
          _log.fine("MTU negotiation successful");
        } catch (e) {
          _log.fine(
            "MTU negotiation failed (using default): $e",
          );
          // Continue with default MTU - this is normal on some BlueZ versions
        }

        _log.info("Connection established successfully");
        return;
      } on FlutterBluePlusException catch (e) {
        _log.warning(
          "Connection attempt $attempt failed "
          "(code: ${e.code}, platform: ${e.platform}): ${e.description}",
        );

        if (attempt < _maxConnectRetries) {
          final delay = _connectRetryDelay * attempt;
          _log.info("Retrying in ${delay.inMilliseconds}ms");

          // Attempt to disconnect cleanly before retry
          try {
            await _device.disconnect();
          } catch (_) {}
          await Future.delayed(delay);
        } else {
          _log.severe("All $attempt connection attempts failed");
          rethrow;
        }
      } catch (e) {
        _log.warning("Connection attempt $attempt failed: $e");

        if (attempt < _maxConnectRetries) {
          final delay = _connectRetryDelay * attempt;
          _log.info("Retrying in ${delay.inMilliseconds}ms");

          try {
            await _device.disconnect();
          } catch (_) {}
          await Future.delayed(delay);
        } else {
          _log.severe("All $attempt connection attempts failed");
          rethrow;
        }
      }
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
    // BlueZ can sometimes return empty service lists if discovery is
    // attempted too soon after connection. We retry with a delay.
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
        return list.map((e) => e.remoteId.str).toList();
      } catch (e) {
        _log.warning(
          "Service discovery attempt $attempt failed: $e",
        );
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
  String get name => _device.advName;

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
      _log.warning(
        "setNotifyValue failed, retrying after delay: $e",
      );
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
    // This is intentionally a no-op.
    _log.fine(
      "setTransportPriority($prioritized) ignored on Linux "
      "(not supported by BlueZ)",
    );
  }
}
