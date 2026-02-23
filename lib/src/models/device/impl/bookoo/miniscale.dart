import 'dart:async';
import 'dart:typed_data';
import 'package:reaprime/src/models/device/ble_service_identifier.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
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

      final services = await _transport.discoverServices();
      if (!serviceIdentifier.matchesAny(services)) {
        throw Exception(
          'Expected service ${serviceIdentifier.long} not found. '
          'Discovered services: $services',
        );
      }
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
    await _transport.write(
      serviceIdentifier.long,
      commandCharacteristic.long,
      Uint8List.fromList([0x03, 0x0A, 0x01, 0x00, 0x00, 0x08]),
    );
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

  void _registerNotifications() async {
    await _transport.subscribe(serviceIdentifier.long, dataCharacteristic.long, _parseNotification);
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

  @override
  Future<void> startTimer() async {
    await _transport.write(
      serviceIdentifier.long,
      commandCharacteristic.long,
      Uint8List.fromList([0x03, 0x0A, 0x04, 0x00, 0x00, 0x0A]),
    );
  }

  @override
  Future<void> stopTimer() async {
    await _transport.write(
      serviceIdentifier.long,
      commandCharacteristic.long,
      Uint8List.fromList([0x03, 0x0A, 0x05, 0x00, 0x00, 0x0D]),
    );
  }

  @override
  Future<void> resetTimer() async {
    await _transport.write(
      serviceIdentifier.long,
      commandCharacteristic.long,
      Uint8List.fromList([0x03, 0x0A, 0x06, 0x00, 0x00, 0x0C]),
    );
  }
}
