import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:logging/logging.dart' as logging;
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:rxdart/subjects.dart';

class DecentScale implements Scale {
  static String serviceUUID = '0000fff0-0000-1000-8000-00805f9b34fb';
  static String dataUUID = '0000fff4-0000-1000-8000-00805f9b34fb';
  static String writeUUID = '000036f5-0000-1000-8000-00805f9b34fb';

  final String _deviceId;

  final StreamController<ScaleSnapshot> _streamController =
      StreamController.broadcast();

  final _ble = FlutterReactiveBle();
  StreamSubscription<ConnectionStateUpdate>? _connection;
  StreamSubscription<List<int>>? _notifications;

  final logging.Logger _log = logging.Logger("Decent scale");

  DecentScale({required String deviceId}) : _deviceId = deviceId;

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
        _log.warning("failed to connect:", e);
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
