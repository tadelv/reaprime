import 'dart:async';
import 'dart:typed_data';

import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:rxdart/subjects.dart';

import 'package:reaprime/src/models/device/device.dart';

import '../../scale.dart';

/// Atomax Skale2 scale implementation.
///
/// Uses a simple single-byte command protocol for tare, display, and timer
/// controls. Weight is reported as a little-endian int32 divided by 2560.
/// Battery level is read from the standard BLE Battery Service (0x180F).
class Skale2Scale implements Scale {
  static String serviceUUID = 'ff08';
  static String weightCharacteristicUUID = 'ef81';
  static String commandCharacteristicUUID = 'ef80';
  static String buttonCharacteristicUUID = 'ef82';
  static String batteryServiceUUID = '180f';
  static String batteryCharacteristicUUID = '2a19';

  final String _deviceId;

  final StreamController<ScaleSnapshot> _streamController =
      StreamController.broadcast();

  final BLETransport _transport;

  int _batteryLevel = 0;

  Skale2Scale({required BLETransport transport})
    : _transport = transport,
      _deviceId = transport.id;

  @override
  Stream<ScaleSnapshot> get currentSnapshot => _streamController.stream;

  @override
  String get deviceId => _deviceId;

  @override
  String get name => "Skale2";

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
      await _initScale();
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

  // --- Initialization ---

  Future<void> _initScale() async {
    // Subscribe to weight notifications
    await _transport.subscribe(
      serviceUUID,
      weightCharacteristicUUID,
      _parseWeightNotification,
    );

    // Subscribe to button notifications (optional, best-effort)
    try {
      await _transport.subscribe(
        serviceUUID,
        buttonCharacteristicUUID,
        _parseButtonNotification,
      );
    } catch (_) {
      // Button characteristic may not be available on all devices
    }

    // Read battery level from standard BLE battery service
    try {
      final batteryData = await _transport.read(
        batteryServiceUUID,
        batteryCharacteristicUUID,
      );
      if (batteryData.isNotEmpty) {
        _batteryLevel = batteryData[0];
      }
    } catch (_) {
      // Battery service may not be available
    }

    // Turn on display and set to weight mode
    await _sendDisplayOn();
    await _sendDisplayWeight();

    // Set scale to grams
    await _transport.write(
      serviceUUID,
      commandCharacteristicUUID,
      Uint8List.fromList([0x03]),
      withResponse: false,
    );
  }

  // --- Commands ---

  Future<void> _sendDisplayOn() async {
    await _transport.write(
      serviceUUID,
      commandCharacteristicUUID,
      Uint8List.fromList([0xED]),
      withResponse: false,
    );
  }

  Future<void> _sendDisplayWeight() async {
    await _transport.write(
      serviceUUID,
      commandCharacteristicUUID,
      Uint8List.fromList([0xEC]),
      withResponse: false,
    );
  }

  Future<void> _sendDisplayOff() async {
    await _transport.write(
      serviceUUID,
      commandCharacteristicUUID,
      Uint8List.fromList([0xEE]),
      withResponse: false,
    );
  }

  // --- Tare ---

  @override
  Future<void> tare() async {
    await _transport.write(
      serviceUUID,
      commandCharacteristicUUID,
      Uint8List.fromList([0x10]),
      withResponse: false,
    );
  }

  // --- Display control ---

  @override
  Future<void> sleepDisplay() async {
    await _sendDisplayOff();
  }

  @override
  Future<void> wakeDisplay() async {
    await _sendDisplayOn();
    await _sendDisplayWeight();
  }

  // --- Notification parsing ---

  void _parseWeightNotification(List<int> data) {
    if (data.length < 4) return;

    // Read 4 bytes as little-endian signed int32
    final byteData = ByteData(4);
    byteData.setUint8(0, data[0] & 0xFF);
    byteData.setUint8(1, data[1] & 0xFF);
    byteData.setUint8(2, data[2] & 0xFF);
    byteData.setUint8(3, data[3] & 0xFF);
    final rawValue = byteData.getInt32(0, Endian.little);

    // Divide by 10*256 = 2560 to get weight in grams
    final weight = rawValue / 2560.0;

    _streamController.add(
      ScaleSnapshot(
        timestamp: DateTime.now(),
        weight: weight,
        batteryLevel: _batteryLevel,
      ),
    );
  }

  void _parseButtonNotification(List<int> data) {
    // Button press notifications - currently informational only.
    // Could be used to trigger tare or other actions in the future.
  }

  @override
  Future<void> startTimer() async {
    await _transport.write(
      serviceUUID,
      commandCharacteristicUUID,
      Uint8List.fromList([0xDD]),
      withResponse: false,
    );
  }

  @override
  Future<void> stopTimer() async {
    await _transport.write(
      serviceUUID,
      commandCharacteristicUUID,
      Uint8List.fromList([0xD1]),
      withResponse: false,
    );
  }

  @override
  Future<void> resetTimer() async {
    await _transport.write(
      serviceUUID,
      commandCharacteristicUUID,
      Uint8List.fromList([0xD0]),
      withResponse: false,
    );
  }
}
