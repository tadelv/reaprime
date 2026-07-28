import 'dart:async';
import 'dart:typed_data';
import 'package:reaprime/src/models/device/ble_service_identifier.dart';
import 'package:reaprime/src/models/device/device_implementation.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:reaprime/src/models/device/transport/data_transport.dart';
import 'package:reaprime/src/models/errors.dart';
import 'package:rxdart/subjects.dart';

import 'package:reaprime/src/models/device/device.dart';

import '../../scale.dart';

class BookooScale implements Scale {
  static final BleServiceIdentifier serviceIdentifier =
      BleServiceIdentifier.short('0ffe');
  static final BleServiceIdentifier dataCharacteristic =
      BleServiceIdentifier.short('ff11');
  static final BleServiceIdentifier commandCharacteristic =
      BleServiceIdentifier.short('ff12');

  final BLETransport _transport;

  final StreamController<ScaleSnapshot> _streamController =
      StreamController.broadcast();
  int _batteryLevel = 0;

  BookooScale({required BLETransport transport}) : _transport = transport;
  @override
  Stream<ScaleSnapshot> get currentSnapshot => _streamController.stream;

  @override
  String get deviceId => _transport.id;

  @override
  DeviceImplementation get implementation => DeviceImplementation.bookooScale;

  @override
  TransportType get transportType => _transport.transportType;

  @override
  String get name => "Bookoo Mini Scale";

  final StreamController<ConnectionState> _connectionStateController =
      BehaviorSubject.seeded(ConnectionState.discovered);

  @override
  Stream<ConnectionState> get connectionState =>
      _connectionStateController.stream;

  @override
  Future<void> onConnect() async {
    if (await _transport.connectionState.first == ConnectionState.connected) {
      return;
    }
    _connectionStateController.add(ConnectionState.connecting);

    StreamSubscription<ConnectionState>? disconnectSub;

    try {
      await _transport.connect();

      disconnectSub = _transport.connectionState
          .where((state) => state == ConnectionState.disconnected)
          .listen((_) {
            _connectionStateController.add(ConnectionState.disconnected);
            disconnectSub?.cancel();
          });

      final services = await _transport.discoverServices();
      if (!serviceIdentifier.matchesAny(services)) {
        throw Exception(
          'Expected service ${serviceIdentifier.long} not found. '
          'Discovered services: $services',
        );
      }
      await _registerNotifications();
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
    await _write([0x03, 0x0A, 0x01, 0x00, 0x00, 0x08]);
  }

  @override
  Future<void> sleepDisplay() async {
    // Bookoo scale doesn't have documented display sleep commands
    // Fallback to disconnect as per scale interface contract
    await disconnect();
  }

  @override
  Future<void> wakeDisplay() async {
    // Bookoo scale doesn't have documented wake display commands
    // This is a no-op
  }

  Future<void> _registerNotifications() async {
    await _transport.subscribe(
      serviceIdentifier.long,
      dataCharacteristic.long,
      _parseNotification,
    );
  }

  void _parseNotification(List<int> data) {
    if (data.length < 10 || data[0] != 0x03 || data[1] != 0x0B) return;
    var weight = (data[7] << 16) | (data[8] << 8) | data[9];
    if (data[6] == 0x2D) weight *= -1;
    if (data.length >= 14 && data[13] <= 100) {
      _batteryLevel = data[13];
    }
    _streamController.add(
      ScaleSnapshot(
        timestamp: DateTime.now(),
        weight: weight / 100,
        batteryLevel: _batteryLevel,
      ),
    );
  }

  Future<void> _write(List<int> command) async {
    try {
      await _transport.write(
        serviceIdentifier.long,
        commandCharacteristic.long,
        Uint8List.fromList(command),
      );
    } on DeviceNotConnectedException {
      return;
    }
  }

  @override
  Future<void> startTimer() async {
    await _write([0x03, 0x0A, 0x04, 0x00, 0x00, 0x0A]);
  }

  @override
  Future<void> stopTimer() async {
    await _write([0x03, 0x0A, 0x05, 0x00, 0x00, 0x0D]);
  }

  @override
  Future<void> resetTimer() async {
    await _write([0x03, 0x0A, 0x06, 0x00, 0x00, 0x0C]);
  }
}
