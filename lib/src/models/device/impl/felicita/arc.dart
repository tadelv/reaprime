import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:collection/collection.dart';
import 'package:rxdart/subjects.dart';

import 'package:reaprime/src/models/device/device.dart';

import '../../scale.dart';

class FelicitaArc implements Scale {
  static String serviceUUID = 'ffe0';
  static String dataUUID = 'ffe1';

  final String _deviceId;

  final StreamController<ScaleSnapshot> _streamController =
      StreamController.broadcast();

  final BluetoothDevice _device;
  late List<BluetoothService> _services;
  late BluetoothService _service;

  FelicitaArc({required String deviceId})
      : _deviceId = deviceId,
        _device = BluetoothDevice.fromId(deviceId);

  @override
  Stream<ScaleSnapshot> get currentSnapshot => _streamController.stream;

  @override
  String get deviceId => _deviceId;

  @override
  String get name => "Felicita Arc";

  final StreamController<ConnectionState> _connectionStateController =
      BehaviorSubject.seeded(ConnectionState.connecting);

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
        .firstWhere((c) => c.characteristicUuid == Guid(dataUUID))
        .write([0x54]);
  }

  _registerNotifications() async {
    final characteristic = _service.characteristics
        .firstWhere((c) => c.characteristicUuid == Guid(dataUUID));
    final subscription =
        characteristic.onValueReceived.listen(_parseNotification);
    _device.cancelWhenDisconnected(subscription);
    await characteristic.setNotifyValue(true);
  }

  static const int minBattLevel = 129;
  static const int maxBattLevel = 158;

  _parseNotification(List<int> data) {
    if (data.length != 18) {
      return;
    }
    var negative = data.slice(2).first - 45 == 0;
    var weight = int.parse(
      data.slice(3, 9).map((value) => value - 48).join(''),
    );
    if (negative) {
      weight *= -1;
    }
    var battery =
        ((data[15] - minBattLevel) / (maxBattLevel - minBattLevel) * 100)
            .round();
    _streamController.add(
      ScaleSnapshot(
        timestamp: DateTime.now(),
        weight: weight / 100,
        batteryLevel: battery,
      ),
    );
  }
}
