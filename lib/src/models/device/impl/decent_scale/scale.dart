import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:reaprime/src/services/serial/serial_service_desktop.dart';
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

  Timer? _heartbeatTimer;

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

  StreamSubscription<bool>? subscription;
  @override
  Future<void> onConnect() async {
    _log.info("on connect");
    _log.info(await _device.isConnected);
    if (await _device.isConnected == true) {
      return;
    }
    subscription = _device.connectionStream.listen((bool state) async {
      _log.info("state: $state");
      switch (state) {
        case true:
          _connectionStateController.add(ConnectionState.connected);
          _services = await _device.discoverServices();
          _service = _services.firstWhere(
            (BleService e) => e.uuid == serviceUUID,
          );

          _registerNotifications();
          _heartbeatTimer?.cancel();
          _heartbeatTimer = Timer.periodic(Duration(seconds: 4), (timer) async {
            if (await _connectionStateController.stream.first !=
                ConnectionState.connected) {
              timer.cancel();
              disconnect();
              return;
            }
            await _sendHeartBeat();
          });
          _sendHeartBeat();
        case false:
          if (await _connectionStateController.stream.first !=
              ConnectionState.connecting) {
            disconnect();
          }
      }
    });
    await _device.connect();
  }

  @override
  disconnect() {
    subscription?.cancel();
    _connectionStateController.add(ConnectionState.disconnected);
    _notificationsSubscription?.cancel();
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _device.isConnected.then((connected) {
      if (!connected) return;
      _device.disconnect();
    });
  }

  @override
  Future<void> tare() async {
    List<int> payload = [0x03, 0x0F, 0x01, 0x00, 0x00, 0x01, 0x0C];
    await _service.characteristics
        .firstWhere((c) => c.uuid == writeUUID)
        .write(payload);
  }

  Future<void> _sendHeartBeat() async {
    _log.finest("send hb");
    // List<int> payload = [0x03, 0x0A, 0x03, 0xFF, 0xFF, 0x00, 0x0A];
    List<int> payload = [0x03, 0x0A, 0x01];
    await _service.characteristics
        .firstWhere((c) => c.uuid == writeUUID)
        .write(payload);
  }

  late StreamSubscription<Uint8List>? _notificationsSubscription;

  void _registerNotifications() async {
    final characteristic = _service.characteristics.firstWhere(
      (c) => c.uuid == dataUUID,
    );
    _notificationsSubscription = characteristic.onValueReceived.listen(
      _parseNotification,
    );
    await characteristic.notifications.subscribe();
    _log.finest("subscribe");
  }

  void _parseNotification(List<int> data) {
    if (data.length < 4) return;
    _log.finest("${this.hashCode} recv: ${data[1].toHex()}");
    switch (data[1]) {
      case 0xCE:
        // weight
        _parseWeight(data);
      case 0x0A:
        // battery
        _parseHeartbeat(data);
    }
  }

  void _parseWeight(List<int> data) {
    var d = ByteData(2);
    d.setInt8(0, data[2]);
    d.setInt8(1, data[3]);
    var weight = d.getInt16(0) / 10;
    _streamController.add(
      ScaleSnapshot(
        timestamp: DateTime.now(),
        weight: weight,
        batteryLevel: _batteryLevel.toInt(),
      ),
    );
  }

  int _batteryLevel = 100;
  void _parseHeartbeat(List<int> data) {
    final level = data[4];
    _log.fine("heartbeat: ${data.map((e) => e.toRadixString(16))}");
    _batteryLevel = min(level, 100);
  }
}
