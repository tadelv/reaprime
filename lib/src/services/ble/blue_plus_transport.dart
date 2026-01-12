import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BluePlusTransport implements BLETransport {
  final Logger _log;
  final BluetoothDevice _device;

  BluePlusTransport({required String remoteId})
    : _device = BluetoothDevice(remoteId: DeviceIdentifier(remoteId)),
      _log = Logger("BPTransport-$remoteId");

  @override
  Future<void> connect() async {
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
  Stream<bool> get connectionState =>
      _device.connectionState
          .map((e) => e == BluetoothConnectionState.connected)
          .asBroadcastStream();

  @override
  Future<void> disconnect() async {
    // TODO: implement disconnect
    await _device.disconnect();
  }

  @override
  Future<List<String>> discoverServices() async {
    final list = await _device.discoverServices();
    return list.map((e) => e.remoteId.str).toList();
  }

  @override
  String get id => _device.remoteId.str;

  @override
  String get name => _device.advName;

  @override
  Future<Uint8List> read(String serviceUUID, String characteristicUUID) async {
    final service = _device.servicesList.firstWhere(
      (s) => s.serviceUuid == Guid(serviceUUID),
    );
    final characteristic = service.characteristics.firstWhere(
      (c) => c.characteristicUuid == Guid(characteristicUUID),
    );
    return Uint8List.fromList(await characteristic.read());
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
    characteristic.setNotifyValue(true);
  }

  @override
  Future<void> write(
    String serviceUUID,
    String characteristicUUID,
    Uint8List data, {
    bool withResponse = true,
  }) async {
    final service = _device.servicesList.firstWhere(
      (s) => s.serviceUuid == Guid(serviceUUID),
    );
    final characteristic = service.characteristics.firstWhere(
      (c) => c.characteristicUuid == Guid(characteristicUUID),
    );
    await characteristic.write(data.toList(), withoutResponse: !withResponse);
  }

  @override
  Future<void> setTransportPriority(bool prioritized) async {
    await _device.requestConnectionPriority(
      connectionPriorityRequest:
          prioritized ? ConnectionPriority.high : ConnectionPriority.balanced,
    );
  }
}
