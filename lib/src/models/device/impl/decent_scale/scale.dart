import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:reaprime/src/services/serial/serial_service_desktop.dart';
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

  final BLETransport _device;

  final logging.Logger _log = logging.Logger("Decent scale");

  Timer? _heartbeatTimer;

  DecentScale({required BLETransport transport})
    : _deviceId = transport.id,
      _device = transport;

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
    if (await _device.connectionState.first == true) {
      return;
    }
    _connectionStateController.add(ConnectionState.connecting);
    subscription = _device.connectionState.listen((bool state) async {
      _log.info("state: $state");
      switch (state) {
        case true:
          _connectionStateController.add(ConnectionState.connected);
          await _device.discoverServices();

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
          _sendOledOn();
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
  disconnect() async {
    await _sendPowerOff();
    subscription?.cancel();
    _connectionStateController.add(ConnectionState.disconnected);
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    final connected = await _device.connectionState.first;
    if (!connected) return;
    await _device.disconnect();
  }

  @override
  Future<void> tare() async {
    List<int> payload = [0x03, 0x0F, 0x01, 0x00, 0x00, 0x01, 0x0C];
    await _device.write(serviceUUID, writeUUID, Uint8List.fromList(payload));
  }

  Future<void> _sendHeartBeat() async {
    _log.finest("send hb");
    // List<int> payload = [0x03, 0x0A, 0x03, 0xFF, 0xFF, 0x00, 0x0A];
    // Send OLed off command (will return battery %)
    List<int> payload = [0x03, 0x0A, 0x00, 0x00, 0x00, 0x07];
    if (!_isSleeping) {
      // Send OLed on command (will return battery %)
      payload = [0x03, 0x0A, 0x01, 0x00, 0x00, 0x01, 0x08];
    }
    await _device.write(serviceUUID, writeUUID, Uint8List.fromList(payload));
  }

  void _registerNotifications() async {
    await _device.subscribe(serviceUUID, dataUUID, _parseNotification);
  }

  void _parseNotification(List<int> data) {
    if (data.length < 4) return;
    _log.finest("$hashCode recv: ${data[1].toHex()}");
    switch (data[1]) {
      case 0xCE:
      case 0xCA:
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

  Future<void> _sendOledOn() async {
    List<int> payload = [];
    payload = [0x03, 0x0A, 0x01, 0x00, 0x00, 0x01, 0x08];
    await _device.write(serviceUUID, writeUUID, Uint8List.fromList(payload));
    payload = [0x03, 0x0A, 0x04, 0x00, 0x00, 0x01, 0x08];
    await _device.write(serviceUUID, writeUUID, Uint8List.fromList(payload));
  }

  Future<void> _sendOledOff() async {
    List<int> payload = [];
    payload = [0x03, 0x0A, 0x04, 0x01, 0x00, 0x01, 0x09];
    await _device.write(serviceUUID, writeUUID, Uint8List.fromList(payload));
    payload = [0x03, 0x0A, 0x00, 0x01, 0x00, 0x01, 0x09];
    await _device.write(serviceUUID, writeUUID, Uint8List.fromList(payload));
  }

  bool _isSleeping = false;

  @override
  Future<void> sleepDisplay() async {
    _isSleeping = true;
    _log.info('Putting Decent Scale display to sleep');
    await _sendOledOff();
  }

  Future<void> _sendPowerOff() async {
    _log.info("sending power off");
    List<int> payload = [0x03, 0x0A, 0x02, 0x00, 0x00, 0x00, 0x00];
    await _device.write(serviceUUID, writeUUID, Uint8List.fromList(payload));
  }

  @override
  Future<void> wakeDisplay() async {
    _isSleeping = false;
    _log.info('Waking Decent Scale display');
    await _sendOledOn();
  }
}
