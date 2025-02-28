import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:collection/collection.dart';
import 'package:logging/logging.dart' as logging;
import 'package:rxdart/subjects.dart';

import 'package:reaprime/src/models/device/device.dart';

import '../../scale.dart';

class BookooScale implements Scale {
  static String serviceUUID = '00000ffe-0000-1000-8000-00805f9b34fb';
  static String dataUUID = '0000ff11-0000-1000-8000-00805f9b34fb';
  static String cmdUUID = '0000ff12-0000-1000-8000-00805f9b34fb';

  final String _deviceId;

  final StreamController<ScaleSnapshot> _streamController =
      StreamController.broadcast();

  StreamSubscription<BluetoothConnectionState>? _connection;
  StreamSubscription<List<int>>? _notifications;

  BookooScale({required String deviceId}) : _deviceId = deviceId;

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
    if (_connection != null) {
      return;
    }
    _device = BluetoothDevice.fromId(_deviceId);

    var subscription =
        _device.connectionState.listen((BluetoothConnectionState state) async {
      switch (state) {
        case BluetoothConnectionState.connected:
          _connectionStateController.add(ConnectionState.connected);
          _services = await _device.discoverServices();
          _service =
              _services.firstWhere((e) => e.serviceUuid == Guid(serviceUUID));

          _registerNotifications();
        case BluetoothConnectionState.disconnected:
          _connectionStateController.add(ConnectionState.disconnected);
        default:
          break;
      }
    });

    _device.cancelWhenDisconnected(subscription, delayed: true, next: true);
    await _device.connect();
  }

  @override
  disconnect() {
    _notifications?.cancel();
    _connection?.cancel();
    _connectionStateController.add(ConnectionState.disconnected);
  }

  @override
  DeviceType get type => DeviceType.scale;

  @override
  Future<void> tare() async {
    _service.characteristics
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
