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

    StreamSubscription<bool>? disconnectSub;

    try {
      await _transport.connect();

      disconnectSub = _transport.connectionState
          .where((state) => !state)
          .listen((_) {
        _connectionStateController.add(ConnectionState.disconnected);
        disconnectSub?.cancel();
        _notificationsSubscription?.cancel();
      });

      await _transport.discoverServices();
      _registerNotifications();
      _connectionStateController.add(ConnectionState.connected);
    } catch (e) {
      disconnectSub?.cancel();
      _connectionStateController.add(ConnectionState.disconnected);
      try {
        await _transport.disconnect();
      } catch (_) {}
    }
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

  @override
  Future<void> sleepDisplay() async {
    // Felicita Arc doesn't have documented display sleep commands
    // Fallback to disconnect as per scale interface contract
    await disconnect();
  }

  @override
  Future<void> wakeDisplay() async {
    // Felicita Arc doesn't have documented wake display commands
    // The scale wakes on weight change or button press
    // This is a no-op
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

  @override
  Future<void> startTimer() async {}

  @override
  Future<void> stopTimer() async {}

  @override
  Future<void> resetTimer() async {}
}
