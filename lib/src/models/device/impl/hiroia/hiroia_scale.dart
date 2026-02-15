import 'dart:async';
import 'dart:typed_data';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:rxdart/subjects.dart';

import 'package:reaprime/src/models/device/device.dart';

import '../../scale.dart';

class HiroiaScale implements Scale {
  static String serviceUUID = '06c31822-8682-4744-9211-febc93e3bece';
  static String dataUUID = '06c31824-8682-4744-9211-febc93e3bece';
  static String writeUUID = '06c31823-8682-4744-9211-febc93e3bece';

  final String _deviceId;

  final StreamController<ScaleSnapshot> _streamController =
      StreamController.broadcast();

  final BLETransport _transport;

  HiroiaScale({required BLETransport transport})
    : _transport = transport,
      _deviceId = transport.id;

  @override
  Stream<ScaleSnapshot> get currentSnapshot => _streamController.stream;

  @override
  String get deviceId => _deviceId;

  @override
  String get name => "Hiroia Jimmy";

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
    final writeData = Uint8List.fromList([0x07, 0x00]);
    await _transport.write(
      serviceUUID,
      writeUUID,
      writeData,
      withResponse: false,
    );
  }

  @override
  Future<void> sleepDisplay() async {
    // Hiroia Jimmy doesn't have documented display sleep commands
    // Fallback to disconnect as per scale interface contract
    await disconnect();
  }

  @override
  Future<void> wakeDisplay() async {
    // Hiroia Jimmy doesn't have documented wake display commands
    // This is a no-op
  }

  void _registerNotifications() async {
    await _transport.subscribe(serviceUUID, dataUUID, _parseNotification);
  }

  /// Send toggle unit command to switch the scale back to grams
  Future<void> _sendToggleUnit() async {
    final writeData = Uint8List.fromList([0x0b, 0x00]);
    await _transport.write(
      serviceUUID,
      writeUUID,
      writeData,
      withResponse: false,
    );
  }

  void _parseNotification(List<int> data) {
    if (data.length < 7) return;

    int mode = data[0];

    // If mode > 0x08, the scale is not in grams mode; toggle back to grams
    if (mode > 0x08) {
      _sendToggleUnit();
      return;
    }

    int sign = data[6];
    int msw = data[5];
    int lsw = data[4];
    int weight = 256 * msw + lsw;

    if (sign == 255) {
      weight = (65536 - weight) * -1;
    }

    _streamController.add(
      ScaleSnapshot(
        timestamp: DateTime.now(),
        weight: weight / 10.0,
        batteryLevel: 0,
      ),
    );
  }
}
