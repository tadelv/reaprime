import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/device.dart' as device;
import 'package:reaprime/src/models/device/transport/ble_timeout_exception.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:rxdart/rxdart.dart';

class BluePlusTransport implements BLETransport {
  final Logger _log;
  final BluetoothDevice _device;

  final BehaviorSubject<device.ConnectionState> _connectionStateSubject =
      BehaviorSubject<device.ConnectionState>.seeded(
        device.ConnectionState.discovered,
      );
  StreamSubscription? _nativeConnectionSub;

  BluePlusTransport({required String remoteId})
    : _device = BluetoothDevice(remoteId: DeviceIdentifier(remoteId)),
      _log = Logger("BPTransport-$remoteId");

  @override
  Future<void> connect() async {
    // Forward native connection state to our subject
    _nativeConnectionSub?.cancel();
    _nativeConnectionSub = _device.connectionState.listen(
      (state) {
        _connectionStateSubject.add(
          state == BluetoothConnectionState.connected
              ? device.ConnectionState.connected
              : device.ConnectionState.disconnected,
        );
      },
      onError: (e) {
        _log.warning("native connection error", e);
        _connectionStateSubject.add(device.ConnectionState.disconnected);
      },
    );

    try {
      await _device.connect(license: License.free, mtu: 517);
    } on FlutterBluePlusException catch (e) {
      if (e.platform == ErrorPlatform.android && e.code == 133) {
        // try auto re-connect again
        _log.warning("MTU negotiation failed, attempting re-connect");
        await _device.connect(license: License.free);
      }
    }
  }

  @override
  Stream<device.ConnectionState> get connectionState =>
      _connectionStateSubject.stream;

  @override
  Future<void> disconnect() async {
    // Keep `_nativeConnectionSub` alive here — it's the channel that
    // forwards the eventual `disconnected` state from the platform
    // stream to `_connectionStateSubject`, which higher-level code
    // relies on to clear `_de1` on next reconnect. The subscription
    // is cycled (cancel+reassign) at the start of each `connect()`
    // so it doesn't accumulate across reconnect cycles
    // (comms-harden #12 — closed by the new `dispose()` only).
    try {
      await _device.disconnect(queue: false, timeout: 5);
    } catch (e) {
      _log.warning("Error during disconnect: $e");
      _connectionStateSubject.add(device.ConnectionState.disconnected);
    }
  }

  /// End-of-life cleanup — close the connection-state subject so
  /// downstream listeners see `onDone`. Also cancels any lingering
  /// native subscription. Safe to call more than once; re-using this
  /// transport after dispose is not supported.
  void dispose() {
    _nativeConnectionSub?.cancel();
    _nativeConnectionSub = null;
    if (!_connectionStateSubject.isClosed) {
      _connectionStateSubject.close();
    }
  }

  @override
  Future<List<String>> discoverServices() async {
    final list = await _device.discoverServices();
    return list.map((e) => e.serviceUuid.str).toList();
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
    try {
      await characteristic.write(
        data.toList(),
        withoutResponse: !withResponse,
        timeout: timeout?.inSeconds ?? 15,
      );
    } on FlutterBluePlusException catch (e) {
      if (e.description != null && e.description!.contains('Timed out')) {
        throw BleTimeoutException('writeCharacteristic', e);
      }
      rethrow;
    }
  }

  @override
  Future<void> setTransportPriority(bool prioritized) async {
    await _device.requestConnectionPriority(
      connectionPriorityRequest:
          prioritized ? ConnectionPriority.high : ConnectionPriority.balanced,
    );
  }
}
