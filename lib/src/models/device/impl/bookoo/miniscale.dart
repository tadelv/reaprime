import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:rxdart/subjects.dart';

import 'package:reaprime/src/models/device/device.dart';

import '../../scale.dart';

class BookooScale implements Scale {
  static String serviceUUID = '0ffe';
  static String dataUUID = 'ff11';
  static String cmdUUID = 'ff12';

  final String _deviceId;

  final StreamController<ScaleSnapshot> _streamController =
      StreamController.broadcast();

  BookooScale({required String deviceId}) : _deviceId = deviceId {
    _device = BluetoothDevice.fromId(_deviceId);
  }

  @override
  Stream<ScaleSnapshot> get currentSnapshot => _streamController.stream;

  @override
  String get deviceId => _deviceId;

  @override
  String get name => "Bookoo Mini Scale";

  final StreamController<ConnectionState> _connectionStateController =
      BehaviorSubject.seeded(ConnectionState.connecting);

  late BluetoothDevice _device;
  late List<BluetoothService> _services;
  late BluetoothService _service;

  @override
  Stream<ConnectionState> get connectionState =>
      _connectionStateController.stream;

  @override
  Future<void> onConnect() async {
    if (await _device.connectionState.first ==
        BluetoothConnectionState.connected) {
      return;
    }

    final subscription =
        _device.connectionState.listen((BluetoothConnectionState state) async {
      switch (state) {
        case BluetoothConnectionState.connected:
          _connectionStateController.add(ConnectionState.connected);
          _services = await _device.discoverServices();
          _service =
              _services.firstWhere((e) => e.serviceUuid == Guid(serviceUUID));

          _registerNotifications();
        case BluetoothConnectionState.disconnected:
          if (await _connectionStateController.stream.first !=
              ConnectionState.connecting) {
            _connectionStateController.add(ConnectionState.disconnected);
          }
        default:
          break;
      }
    });

    _device.cancelWhenDisconnected(subscription, delayed: true, next: true);
    await _device.connect();
  }

  @override
  disconnect() {
    _device.disconnect();
  }

  @override
  DeviceType get type => DeviceType.scale;

  @override
  Future<void> tare() async {
    await _service.characteristics
        .firstWhere((c) => c.characteristicUuid == Guid(cmdUUID))
        .write([0x03, 0x0A, 0x01, 0x00, 0x00, 0x08]);
  }

  _registerNotifications() async {
    final characteristic = _service.characteristics
        .firstWhere((c) => c.characteristicUuid == Guid(dataUUID));
    final subscription =
        characteristic.onValueReceived.listen(_parseNotification);
    _device.cancelWhenDisconnected(subscription);
    await characteristic.setNotifyValue(true);
  }

  _parseNotification(List<int> data) {
    int weight = 0;
    if (data.length == 20) {
      weight = (data[7] << 16) + (data[8] << 8) + data[9];
      if (data[6] == 45) {
        weight = weight * -1;
      }
    }
    var battery = data[13];
    _streamController.add(
      ScaleSnapshot(
        timestamp: DateTime.now(),
        weight: weight / 100,
        batteryLevel: battery,
      ),
    );
  }
}
