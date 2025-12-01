import 'dart:async';
import 'dart:typed_data';
import 'package:universal_ble/universal_ble.dart';
import 'package:rxdart/subjects.dart';

import 'package:reaprime/src/models/device/device.dart';

import '../../hardware_scale.dart';

class BookooScale implements HardwareScale {
  static String serviceUUID = BleUuidParser.string('0ffe');
  static String dataUUID = BleUuidParser.string('ff11');
  static String cmdUUID = BleUuidParser.string('ff12');

  final String _deviceId;

  final StreamController<ScaleSnapshot> _streamController =
      StreamController.broadcast();

  BookooScale({required String deviceId}) : _deviceId = deviceId {
    _device = BleDevice(deviceId: deviceId, name: "BookooScale $deviceId");
  }

  @override
  Stream<ScaleSnapshot> get currentSnapshot => _streamController.stream;

  @override
  String get deviceId => _deviceId;

  @override
  String get name => "Bookoo Mini Scale";

  final StreamController<ConnectionState> _connectionStateController =
      BehaviorSubject.seeded(ConnectionState.connecting);

  late BleDevice _device;
  late List<BleService> _services;
  late BleService _service;

  @override
  Stream<ConnectionState> get connectionState =>
      _connectionStateController.stream;

  @override
  Future<void> onConnect() async {
    if (await _device.connectionStream.first == true) {
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
        .firstWhere((c) => c.uuid == cmdUUID)
        .write([0x03, 0x0A, 0x01, 0x00, 0x00, 0x08]);
  }

  late StreamSubscription<Uint8List>? _notificationsSubscription;

  void _registerNotifications() async {
    final characteristic =
        _service.characteristics.firstWhere((c) => c.uuid == dataUUID);
    _notificationsSubscription =
        characteristic.onValueReceived.listen(_parseNotification);
    await characteristic.notifications.subscribe();
    // characteristic.onValueReceived.listen(_parseNotification);
    // _device.cancelWhenDisconnected(subscription);
    // await characteristic.;
    // await UniversalBle.subscribeNotifications(_deviceId, serviceUUID, dataUUID);
  }

  void _parseNotification(List<int> data) {
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
