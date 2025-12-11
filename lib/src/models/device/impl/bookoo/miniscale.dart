import 'dart:async';
import 'dart:typed_data';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:rxdart/subjects.dart';

import 'package:reaprime/src/models/device/device.dart';

import '../../scale.dart';

class BookooScale implements Scale {
  static String serviceUUID = '0ffe';
  static String dataUUID = 'ff11';
  static String cmdUUID = 'ff12';

  final BLETransport _transport;

  final StreamController<ScaleSnapshot> _streamController =
      StreamController.broadcast();

  BookooScale({required BLETransport transport}) : _transport = transport;
  @override
  Stream<ScaleSnapshot> get currentSnapshot => _streamController.stream;

  @override
  String get deviceId => _transport.id;

  @override
  String get name => "Bookoo Mini Scale";

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
          }
      }
    });

    await _transport.connect();
  }

  @override
  disconnect() {
    _transport.disconnect();
  }

  @override
  DeviceType get type => DeviceType.scale;

  @override
  Future<void> tare() async {
    await _transport.write(
      serviceUUID,
      cmdUUID,
      Uint8List.fromList([0x03, 0x0A, 0x01, 0x00, 0x00, 0x08]),
    );
  }


  void _registerNotifications() async {
    await _transport.subscribe(serviceUUID, dataUUID, _parseNotification);
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
