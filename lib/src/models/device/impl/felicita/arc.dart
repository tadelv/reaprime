import 'dart:async';
import 'dart:typed_data';
import 'package:universal_ble/universal_ble.dart';
import 'package:collection/collection.dart';
import 'package:rxdart/subjects.dart';

import 'package:reaprime/src/models/device/device.dart';

import '../../scale.dart';

class FelicitaArc implements Scale {
  static String serviceUUID = BleUuidParser.string('ffe0');
  static String dataUUID = BleUuidParser.string('ffe1');

  final String _deviceId;

  final StreamController<ScaleSnapshot> _streamController =
      StreamController.broadcast();

  final BleDevice _device;
  late List<BleService> _services;
  late BleService _service;

  FelicitaArc({required String deviceId})
      : _deviceId = deviceId,
        _device = BleDevice(deviceId: deviceId, name: "Felicita $deviceId");

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
    if (await _device.isConnected == true) {
      return;
    }
    StreamSubscription<bool>? subscription;
    subscription = _device.connectionStream.listen((bool state) async {
      switch (state) {
        case true:
          _connectionStateController.add(ConnectionState.connected);
          _services = await _device.discoverServices();
          _service =
              _services.firstWhere((BleService e) => e.uuid == serviceUUID);

          _registerNotifications();
        case false:
          if (await _connectionStateController.stream.first !=
              ConnectionState.connecting) {
            _connectionStateController.add(ConnectionState.disconnected);
            subscription?.cancel();
            _notificationsSubscription?.cancel();
          }
      }
    });
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
        .firstWhere((c) => c.uuid == dataUUID)
        .write([0x54]);
  }

  late StreamSubscription<Uint8List>? _notificationsSubscription;

  void _registerNotifications() async {
    final characteristic =
        _service.characteristics.firstWhere((c) => c.uuid == dataUUID);
    _notificationsSubscription =
        characteristic.onValueReceived.listen(_parseNotification);

    await characteristic.notifications.subscribe();
  }

  static const int minBattLevel = 129;
  static const int maxBattLevel = 158;

  void _parseNotification(List<int> data) {
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
