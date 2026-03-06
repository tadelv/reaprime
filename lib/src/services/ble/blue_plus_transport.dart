import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/transport/ble_timeout_exception.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:rxdart/rxdart.dart';

class BluePlusTransport implements BLETransport {
  final Logger _log;
  final BluetoothDevice _device;

  final BehaviorSubject<bool> _connectionStateSubject = BehaviorSubject<bool>.seeded(false);
  StreamSubscription? _nativeConnectionSub;

  BluePlusTransport({required String remoteId})
    : _device = BluetoothDevice(remoteId: DeviceIdentifier(remoteId)),
      _log = Logger("BPTransport-$remoteId");

  @override
  Future<void> connect() async {
    // Forward native connection state to our subject
    _nativeConnectionSub?.cancel();
    _nativeConnectionSub = _device.connectionState.listen((state) {
      _connectionStateSubject
          .add(state == BluetoothConnectionState.connected);
    });

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
  Stream<bool> get connectionState => _connectionStateSubject.stream;

  @override
  Future<void> disconnect() async {
    try {
      await _device.disconnect(queue: false, timeout: 5);
    } catch (e) {
      _log.warning("Error during disconnect: $e");
      _connectionStateSubject.add(false);
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
      await characteristic.write(data.toList(), withoutResponse: !withResponse, timeout: timeout?.inSeconds ?? 15);
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
