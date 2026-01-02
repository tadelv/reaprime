import 'dart:async';
import 'dart:typed_data';
import 'package:collection/collection.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:rxdart/subjects.dart';

import 'package:reaprime/src/models/device/device.dart';

import '../../scale.dart';

class FelicitaArc implements Scale {
  static String serviceUUID = 'ffe0';
  static String dataUUID = 'ffe1';

  final String _deviceId;

  final StreamController<ScaleSnapshot> _streamController =
      StreamController.broadcast();

  final BLETransport _transport;

  FelicitaArc({required BLETransport transport})
    : _transport = transport,
      _deviceId = transport.id;

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
    if (await _transport.connectionState.first == true) {
      return;
    }
    _connectionStateController.add(ConnectionState.connecting);
    StreamSubscription<bool>? subscription;
    subscription = _transport.connectionState.listen((bool state) async {
      switch (state) {
        case true:
          _connectionStateController.add(ConnectionState.connected);
          await _transport.discoverServices();

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
    await _transport.connect();
  }

  @override
  disconnect() async {
    await _transport.disconnect();
  }

  @override
  DeviceType get type => DeviceType.scale;

  @override
  Future<void> tare() async {
    final writeData = Uint8List(1);
    writeData[0] = 0x54;
    await _transport.write(
      serviceUUID,
      dataUUID,
      writeData
    );
  }

  late StreamSubscription<Uint8List>? _notificationsSubscription;

  void _registerNotifications() async {
    await _transport.subscribe(serviceUUID, dataUUID, _parseNotification);
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
