import 'dart:async';
import 'dart:typed_data';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:rxdart/subjects.dart';

import 'package:reaprime/src/models/device/device.dart';

import '../../scale.dart';

class EurekaScale implements Scale {
  static String serviceUUID = 'fff0';
  static String dataUUID = 'fff1';
  static String commandUUID = 'fff2';
  static String batteryServiceUUID = '180f';
  static String batteryCharUUID = '2a19';

  final String _deviceId;

  final StreamController<ScaleSnapshot> _streamController =
      StreamController.broadcast();

  final BLETransport _transport;

  int _batteryLevel = 0;

  EurekaScale({required BLETransport transport})
    : _transport = transport,
      _deviceId = transport.id;

  @override
  Stream<ScaleSnapshot> get currentSnapshot => _streamController.stream;

  @override
  String get deviceId => _deviceId;

  @override
  String get name => "Eureka Precisa";

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
      _readBattery();
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
    final writeData = Uint8List.fromList([0xAA, 0x02, 0x31, 0x31]);
    await _transport.write(
      serviceUUID,
      commandUUID,
      writeData,
      withResponse: false,
    );
  }

  /// Start the scale timer
  @override
  Future<void> startTimer() async {
    final writeData = Uint8List.fromList([0xAA, 0x02, 0x33, 0x33]);
    await _transport.write(
      serviceUUID,
      commandUUID,
      writeData,
      withResponse: false,
    );
  }

  /// Stop the scale timer
  @override
  Future<void> stopTimer() async {
    final writeData = Uint8List.fromList([0xAA, 0x02, 0x34, 0x34]);
    await _transport.write(
      serviceUUID,
      commandUUID,
      writeData,
      withResponse: false,
    );
  }

  /// Reset the scale timer
  @override
  Future<void> resetTimer() async {
    final writeData = Uint8List.fromList([0xAA, 0x02, 0x35, 0x35]);
    await _transport.write(
      serviceUUID,
      commandUUID,
      writeData,
      withResponse: false,
    );
  }

  @override
  Future<void> sleepDisplay() async {
    // Eureka Precisa doesn't have documented display sleep commands
    // Fallback to disconnect as per scale interface contract
    await disconnect();
  }

  @override
  Future<void> wakeDisplay() async {
    // Eureka Precisa doesn't have documented wake display commands
    // This is a no-op
  }

  void _registerNotifications() async {
    await _transport.subscribe(serviceUUID, dataUUID, _parseNotification);
  }

  void _readBattery() async {
    try {
      final data = await _transport.read(batteryServiceUUID, batteryCharUUID);
      if (data.isNotEmpty) {
        _batteryLevel = data[0];
      }
    } catch (_) {
      // Battery read may fail on some devices; ignore
    }
  }

  void _parseNotification(List<int> data) {
    if (data.length < 9) return;

    bool isNeg = data[6] != 0;
    int weight = data[7] + (data[8] << 8);
    if (isNeg) {
      weight = weight * -1;
    }

    _streamController.add(
      ScaleSnapshot(
        timestamp: DateTime.now(),
        weight: weight / 10.0,
        batteryLevel: _batteryLevel,
      ),
    );
  }
}
