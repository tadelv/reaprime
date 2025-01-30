import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/scale.dart';

class DecentScale implements Scale {
  static String serviceUUID = '0000fff0-0000-1000-8000-00805f9b34fb';
  static String dataUUID = '0000fff4-0000-1000-8000-00805f9b34fb';
  static String writeUUID = '000036f5-0000-1000-8000-00805f9b34fb';

  final String _deviceId;

  final StreamController<ScaleSnapshot> _streamController =
      StreamController.broadcast();

  final _ble = FlutterReactiveBle();
  late StreamSubscription<ConnectionStateUpdate> _connection;
  late StreamSubscription<List<int>> _notifications;

  DecentScale({required String deviceId}) : _deviceId = deviceId;

  @override
  Stream<ScaleSnapshot> get currentSnapshot => _streamController.stream;

  @override
  String get deviceId => _deviceId;

  @override
  disconnect() {
    _notifications.cancel();
    _connection.cancel();
  }

  @override
  String get name => "Decent Scale";

  @override
  Future<void> onConnect() async {
    _connection = _ble.connectToDevice(id: _deviceId).listen((connectionState) {
      if (connectionState.connectionState == DeviceConnectionState.connected) {
        // register for notifications
        _registerNotifications();
      }
    });
  }

  @override
  DeviceType get type => DeviceType.scale;

  @override
  Future<void> tare() async {
    List<int> payload = [0x03, 0x0F, 0xFD];
    var characteristic = QualifiedCharacteristic(
      characteristicId: Uuid.parse(DecentScale.writeUUID),
      serviceId: Uuid.parse(DecentScale.serviceUUID),
      deviceId: _deviceId,
    );

    await _ble.writeCharacteristicWithResponse(
      characteristic,
      value: Uint8List.fromList(payload),
    );
  }

  _registerNotifications() async {
    var characteristic = QualifiedCharacteristic(
      characteristicId: Uuid.parse(dataUUID),
      serviceId: Uuid.parse(serviceUUID),
      deviceId: _deviceId,
    );
    _notifications = _ble
        .subscribeToCharacteristic(characteristic)
        .listen(_parseNotification);
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
