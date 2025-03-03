import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart' as logging;
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:rxdart/subjects.dart';

class DecentScale implements Scale {
  static String serviceUUID = 'fff0';
  static String dataUUID = 'fff4';
  static String writeUUID = '36f5';

  final String _deviceId;

  final StreamController<ScaleSnapshot> _streamController =
      StreamController.broadcast();

  final BluetoothDevice _device;
  late List<BluetoothService> _services;
  late BluetoothService _service;

  final logging.Logger _log = logging.Logger("Decent scale");

  DecentScale({required String deviceId})
      : _deviceId = deviceId,
        _device = BluetoothDevice.fromId(deviceId);

  @override
  Stream<ScaleSnapshot> get currentSnapshot => _streamController.stream;

  @override
  String get deviceId => _deviceId;

  @override
  DeviceType get type => DeviceType.scale;

  @override
  String get name => "Decent Scale";

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
  Future<void> tare() async {
    List<int> payload = [0x03, 0x0F, 0xFD];
    await _service.characteristics
        .firstWhere((c) => c.characteristicUuid == Guid(writeUUID))
        .write(payload);
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
    if (data.length < 4) return;
    var d = ByteData(2);
    d.setInt8(0, data[2]);
    d.setInt8(1, data[3]);
    var weight = d.getInt16(0) / 10;
    _streamController.add(
      ScaleSnapshot(
        timestamp: DateTime.now(),
        weight: weight,
        batteryLevel: 100,
      ),
    );
  }
}
