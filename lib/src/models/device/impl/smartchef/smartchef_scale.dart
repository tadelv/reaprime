import 'dart:async';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:rxdart/subjects.dart';

import 'package:reaprime/src/models/device/device.dart';

import '../../scale.dart';

class SmartChefScale implements Scale {
  static String serviceUUID = 'fff0';
  static String dataUUID = 'fff1';

  final String _deviceId;

  final StreamController<ScaleSnapshot> _streamController =
      StreamController.broadcast();

  final BLETransport _transport;

  double _weightAtTare = 0.0;

  SmartChefScale({required BLETransport transport})
    : _transport = transport,
      _deviceId = transport.id;

  @override
  Stream<ScaleSnapshot> get currentSnapshot => _streamController.stream;

  @override
  String get deviceId => _deviceId;

  @override
  String get name => "SmartChef Scale";

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
    // SmartChef doesn't support BLE tare command
    // Implement software tare by recording current weight offset
    _weightAtTare = _lastRawWeight;
  }

  @override
  Future<void> sleepDisplay() async {
    // SmartChef scale doesn't have documented display sleep commands
    // Fallback to disconnect as per scale interface contract
    await disconnect();
  }

  @override
  Future<void> wakeDisplay() async {
    // SmartChef scale doesn't have documented wake display commands
    // This is a no-op
  }

  void _registerNotifications() async {
    await _transport.subscribe(serviceUUID, dataUUID, _parseNotification);
  }

  double _lastRawWeight = 0.0;

  void _parseNotification(List<int> data) {
    if (data.length < 7) return;

    double weight = ((data[5] << 8) + data[6]) / 10.0;

    if (data[3] > 10) {
      weight *= -1;
    }

    _lastRawWeight = weight;

    _streamController.add(
      ScaleSnapshot(
        timestamp: DateTime.now(),
        weight: weight - _weightAtTare,
        batteryLevel: 0,
      ),
    );
  }
}
