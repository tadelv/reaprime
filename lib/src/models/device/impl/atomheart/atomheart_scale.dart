import 'dart:async';
import 'dart:typed_data';
import 'package:reaprime/src/models/device/ble_service_identifier.dart';
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
  static final BleServiceIdentifier serviceIdentifier =
      BleServiceIdentifier.long('b905eaea-6c7e-4f73-b43d-2cdfcab29570');
  static final BleServiceIdentifier dataCharacteristic =
      BleServiceIdentifier.long('b905eaeb-6c7e-4f73-b43d-2cdfcab29570');
  static final BleServiceIdentifier commandCharacteristic =
      BleServiceIdentifier.long('b905eaec-6c7e-4f73-b43d-2cdfcab29570');

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
      serviceIdentifier.long,
      commandCharacteristic.long,
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

  @override
  Future<void> startTimer() async {
    await _transport.write(
      serviceIdentifier.long,
      commandCharacteristic.long,
      Uint8List.fromList([0x43, 0x01, 0x01]),
      withResponse: false,
    );
  }

  @override
  Future<void> stopTimer() async {
    await _transport.write(
      serviceIdentifier.long,
      commandCharacteristic.long,
      Uint8List.fromList([0x43, 0x00, 0x00]),
      withResponse: false,
    );
  }

  @override
  Future<void> resetTimer() async {
    // Atomheart resets timer via tare command
    await tare();
  }

  void _registerNotifications() async {
    await _transport.subscribe(serviceIdentifier.long, dataCharacteristic.long, _parseNotification);
  }

  /// Parse a BLE notification frame into a ScaleSnapshot.
  /// Returns null if the frame is invalid.
  static ScaleSnapshot? parseFrame(List<int> data) {
    if (data.length < 9) return null;
    if (data[0] != 0x57) return null;

    // Validate XOR checksum
    var xorResult = 0;
    for (var i = 1; i < data.length - 1; i++) {
      xorResult ^= data[i];
    }
    if ((xorResult & 0xFF) != (data.last & 0xFF)) return null;

    // Extract weight as signed int32 little-endian from bytes 1-4
    final byteData = ByteData(4);
    byteData.setUint8(0, data[1]);
    byteData.setUint8(1, data[2]);
    byteData.setUint8(2, data[3]);
    byteData.setUint8(3, data[4]);
    final weightMg = byteData.getInt32(0, Endian.little);

    // Extract timer as uint32 little-endian from bytes 5-8
    final timerData = ByteData(4);
    timerData.setUint8(0, data[5]);
    timerData.setUint8(1, data[6]);
    timerData.setUint8(2, data[7]);
    timerData.setUint8(3, data[8]);
    final timerMs = timerData.getUint32(0, Endian.little);

    return ScaleSnapshot(
      timestamp: DateTime.now(),
      weight: weightMg / 1000.0,
      batteryLevel: 0,
      timerValue: timerMs > 0 ? Duration(milliseconds: timerMs) : null,
    );
  }

  void _parseNotification(List<int> data) {
    final snapshot = parseFrame(data);
    if (snapshot != null) {
      _streamController.add(snapshot);
    }
  }
}
