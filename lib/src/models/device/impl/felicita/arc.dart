import 'dart:async';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:collection/collection.dart';

import 'package:reaprime/src/models/device/device.dart';

import '../../scale.dart';

class FelicitaArc implements Scale {
  static String serviceUUID = '0000ffe0-0000-1000-8000-00805f9b34fb';
  static String dataUUID = '0000ffe1-0000-1000-8000-00805f9b34fb';

  final String _deviceId;

  final StreamController<ScaleSnapshot> _streamController =
      StreamController.broadcast();

  final _ble = FlutterReactiveBle();
  late StreamSubscription<ConnectionStateUpdate> _connection;
  late StreamSubscription<List<int>> _notifications;

  FelicitaArc({required String deviceId}) : _deviceId = deviceId;

  @override
  Stream<ScaleSnapshot> get currentSnapshot => _streamController.stream;

  @override
  String get deviceId => _deviceId;

  @override
  String get name => "Felicita Arc";

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

  static const int minBattLevel = 129;
  static const int maxBattLevel = 158;

  _parseNotification(List<int> data) {
    if (data.length != 18) {
      return;
    }
    var weight = int.parse(
      data.slice(3, 9).map((value) => value - 48).join(''),
    );
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
