import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
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

  final StreamController<ScaleSnapshot> _streamController = StreamController.broadcast();

  final _ble = FlutterReactiveBle();
  StreamSubscription<ConnectionStateUpdate>? _connection;
  StreamSubscription<List<int>>? _notifications;

  BookooScale({required String deviceId}) : _deviceId = deviceId;

  @override
  Stream<ScaleSnapshot> get currentSnapshot => _streamController.stream;

  @override
  String get deviceId => _deviceId;

  @override
  String get name => "Bookoo Mini Scale";

  final StreamController<ConnectionState> _connectionStateController = BehaviorSubject.seeded(ConnectionState.connecting);

  @override
  Stream<ConnectionState> get connectionState => _connectionStateController.stream;

  @override
  Future<void> onConnect() async {
    if (_connection != null) {
      return;
    }
    _connection = _ble.connectToDevice(id: _deviceId).listen(
      (data) {
        switch (data.connectionState) {
          case DeviceConnectionState.connecting:
            _connectionStateController.add(ConnectionState.connecting);
          case DeviceConnectionState.connected:
            _connectionStateController.add(ConnectionState.connected);
            _registerNotifications();
          case DeviceConnectionState.disconnecting:
            _connectionStateController.add(ConnectionState.disconnecting);
          case DeviceConnectionState.disconnected:
            _connectionStateController.add(ConnectionState.disconnected);
            _notifications?.cancel();
            _connection?.cancel();
        }
      },
      onError: (e) {
        logging.Logger("Bookoo").warning("failed to connect:", e);
      },
    );
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
    var characteristic = QualifiedCharacteristic(
      characteristicId: Uuid.parse(cmdUUID),
      serviceId: Uuid.parse(serviceUUID),
      deviceId: _deviceId,
    );
    await _ble.writeCharacteristicWithResponse(
      characteristic,
      value: Uint8List.fromList([0x03, 0x0A, 0x01, 0x00, 0x00, 0x08]),
    );
  }

  _registerNotifications() async {
    var characteristic = QualifiedCharacteristic(
      characteristicId: Uuid.parse(dataUUID),
      serviceId: Uuid.parse(serviceUUID),
      deviceId: _deviceId,
    );
    _notifications = _ble.subscribeToCharacteristic(characteristic).listen(_parseNotification);
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
