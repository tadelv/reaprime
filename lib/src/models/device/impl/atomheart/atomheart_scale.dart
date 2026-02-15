import 'dart:async';
import 'dart:typed_data';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:rxdart/subjects.dart';

import 'package:reaprime/src/models/device/device.dart';

import '../../scale.dart';

/// Atomheart Eclair scale implementation.
///
/// BLE Protocol:
/// - Notifications contain 10-byte frames: header('W') + int32_le weight_mg + uint32_le timer + xor_byte
/// - Weight is in milligrams (signed), divided by 1000 for grams
/// - XOR validation on payload bytes (bytes 1..end-1) must match last byte
class AtomheartScale implements Scale {
  static String serviceUUID = 'b905eaea-6c7e-4f73-b43d-2cdfcab29570';
  static String dataUUID = 'b905eaeb-6c7e-4f73-b43d-2cdfcab29570';
  static String commandUUID = 'b905eaec-6c7e-4f73-b43d-2cdfcab29570';

  final String _deviceId;

  final StreamController<ScaleSnapshot> _streamController =
      StreamController.broadcast();

  final BLETransport _transport;

  AtomheartScale({required BLETransport transport})
      : _transport = transport,
        _deviceId = transport.id;

  @override
  Stream<ScaleSnapshot> get currentSnapshot => _streamController.stream;

  @override
  String get deviceId => _deviceId;

  @override
  String get name => "Atomheart Eclair";

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
    await _transport.write(
      serviceUUID,
      commandUUID,
      Uint8List.fromList([0x54, 0x01, 0x01]),
      withResponse: false,
    );
  }

  @override
  Future<void> sleepDisplay() async {
    await disconnect();
  }

  @override
  Future<void> wakeDisplay() async {
    // Atomheart Eclair doesn't support display wake via BLE
  }

  void _registerNotifications() async {
    await _transport.subscribe(serviceUUID, dataUUID, _parseNotification);
  }

  bool _validateXor(List<int> data) {
    if (data.length < 3) return false;
    var xorResult = 0;
    for (var i = 1; i < data.length - 1; i++) {
      xorResult ^= data[i];
    }
    return (xorResult & 0xFF) == (data.last & 0xFF);
  }

  void _parseNotification(List<int> data) {
    if (data.length < 9) return;

    // Header must be 'W' (0x57)
    if (data[0] != 0x57) return;

    // Validate XOR checksum
    if (!_validateXor(data)) return;

    // Extract weight as signed int32 little-endian from bytes 1-4
    final byteData = ByteData(4);
    byteData.setUint8(0, data[1]);
    byteData.setUint8(1, data[2]);
    byteData.setUint8(2, data[3]);
    byteData.setUint8(3, data[4]);
    final weightMg = byteData.getInt32(0, Endian.little);

    final weight = weightMg / 1000.0;

    _streamController.add(
      ScaleSnapshot(
        timestamp: DateTime.now(),
        weight: weight,
        batteryLevel: 0,
      ),
    );
  }
}
