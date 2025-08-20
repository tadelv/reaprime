import 'dart:async';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';
import 'package:logging/logging.dart' as logging;
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:rxdart/subjects.dart';

class DecentScale implements Scale {
  static String serviceUUID = BleUuidParser.string('fff0');
  static String dataUUID = BleUuidParser.string('fff4');
  static String writeUUID = BleUuidParser.string('36f5');

  final String _deviceId;

  final StreamController<ScaleSnapshot> _streamController =
      StreamController.broadcast();

  final BleDevice _device;
  late List<BleService> _services;
  late BleService _service;

  final logging.Logger _log = logging.Logger("Decent scale");

  DecentScale({required String deviceId})
      : _deviceId = deviceId,
        _device = BleDevice(deviceId: deviceId, name: "Decent Scale $deviceId");

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
    _log.info("on connect");
    _log.info(await _device.isConnected);
    if (await _device.isConnected == true) {
      return;
    }
    StreamSubscription<bool>? subscription;
    subscription = _device.connectionStream.listen((bool state) async {
      _log.info("state: $state");
      switch (state) {
        case true:
          _connectionStateController.add(ConnectionState.connected);
          _services = await _device.discoverServices();
          _service =
              _services.firstWhere((BleService e) => e.uuid == serviceUUID);

          _registerNotifications();
          // TODO: heartbeat support?
          tare();
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
  Future<void> tare() async {
    List<int> payload = [0x03, 0x0F, 0xFD];
    await _service.characteristics
        .firstWhere((c) => c.uuid == writeUUID)
        .write(payload);
  }

  late StreamSubscription<Uint8List>? _notificationsSubscription;

  void _registerNotifications() async {
    final characteristic =
        _service.characteristics.firstWhere((c) => c.uuid == dataUUID);
    _notificationsSubscription =
        characteristic.onValueReceived.listen(_parseNotification);
    await characteristic.notifications.subscribe();
    _log.finest("subscribe");
  }

  void _parseNotification(List<int> data) {
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
