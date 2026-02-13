import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';

/// Android-specific BLE transport that wraps flutter_blue_plus with
/// workarounds for the Android Bluetooth stack.
///
/// Key differences from the standard BluePlusTransport:
///
/// 1. **No MTU on connect:** Requesting MTU 517 at connect time causes
///    GATT error 133 on older Android devices (e.g. Android 9 on Teclast
///    tablets). MTU is requested separately after connection is stable.
///
/// 2. **Post-connect settle delay:** The Android BLE stack needs a brief
///    period after establishing a connection before service discovery
///    works reliably, especially on older devices.
///
/// 3. **Service discovery retry:** Service discovery can return empty
///    results or fail if called too soon after connection on Android.
///
/// 4. **Connection priority:** Requests high connection priority
///    immediately after connect to speed up GATT operations.
class AndroidBluePlusTransport implements BLETransport {
  final Logger _log;
  final BluetoothDevice _device;

  /// Post-connect settle delay for Android BLE stack.
  static const Duration _postConnectDelay = Duration(milliseconds: 200);

  /// Maximum number of service discovery attempts.
  static const int _maxDiscoveryRetries = 3;

  /// Delay between service discovery retry attempts.
  static const Duration _discoveryRetryDelay = Duration(milliseconds: 500);

  AndroidBluePlusTransport({required String remoteId})
    : _device = BluetoothDevice(remoteId: DeviceIdentifier(remoteId)),
      _log = Logger("AndroidBPTransport-$remoteId");

  @override
  Future<void> connect() async {
    _log.info("Connecting...");

    if (_device.isConnected) {
      _log.info("Already connected, skipping connect");
      return;
    }

    // Connect without MTU — requesting MTU at connect time causes
    // GATT error 133 on older Android devices.
    try {
      await _device.connect(
        license: License.free,
        timeout: const Duration(seconds: 15),
      );
    } on FlutterBluePlusException catch (e) {
      if (e.code == 133) {
        _log.warning("Connection failed with GATT error 133, retrying");
        await Future.delayed(const Duration(milliseconds: 500));
        await _device.connect(
          license: License.free,
          timeout: const Duration(seconds: 15),
        );
      } else {
        rethrow;
      }
    }

    // Post-connect settle delay — gives the Android BLE stack time
    // to finalize GATT client setup before service discovery.
    _log.fine("Connected, waiting ${_postConnectDelay.inMilliseconds}ms "
        "for BLE stack to settle");
    await Future.delayed(_postConnectDelay);

    // Request high connection priority to speed up service discovery
    // and GATT operations on slower BLE stacks.
    try {
      await _device.requestConnectionPriority(
        connectionPriorityRequest: ConnectionPriority.high,
      );
      _log.fine("Requested high connection priority");
    } catch (e) {
      _log.fine("Connection priority request failed: $e");
    }

    // Request higher MTU after connection is stable (best-effort).
    try {
      await _device.requestMtu(517);
      _log.fine("MTU negotiation successful");
    } catch (e) {
      _log.fine("MTU negotiation failed (using default): $e");
    }

    _log.info("Connection established");
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
        return list.map((e) => e.remoteId.str).toList();
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
    await characteristic.setNotifyValue(true);
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
    await _device.requestConnectionPriority(
      connectionPriorityRequest:
          prioritized ? ConnectionPriority.high : ConnectionPriority.balanced,
    );
  }
}
