import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:rxdart/subjects.dart';

import 'package:reaprime/src/models/device/device.dart';

import '../../scale.dart';

/// Acaia Pyxis / Lunar 2021 / Pearl (newer models) scale implementation.
///
/// Uses the same Acaia protocol encoding as [AcaiaScale] but communicates
/// over separate command (write) and status (notify) characteristics with
/// long-form UUIDs. Includes a watchdog to detect stale connections.
class AcaiaPyxisScale implements Scale {
  static String serviceUUID = '49535343-fe7d-4ae5-8fa9-9fafd205e455';
  static String commandCharacteristicUUID =
      '49535343-8841-43f4-a8d4-ecbe34729bb3';
  static String statusCharacteristicUUID =
      '49535343-1e4d-4bd9-ba61-23c647249616';

  final String _deviceId;

  final StreamController<ScaleSnapshot> _streamController =
      StreamController.broadcast();

  final BLETransport _transport;

  Timer? _heartbeatTimer;
  Timer? _watchdogTimer;
  int _batteryLevel = 0;
  List<int> _commandBuffer = [];
  DateTime _lastResponse = DateTime.now();

  AcaiaPyxisScale({required BLETransport transport})
    : _transport = transport,
      _deviceId = transport.id;

  @override
  Stream<ScaleSnapshot> get currentSnapshot => _streamController.stream;

  @override
  String get deviceId => _deviceId;

  @override
  String get name => "Acaia Pyxis";

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
    StreamSubscription<bool>? subscription;
    subscription = _transport.connectionState.listen((bool state) async {
      switch (state) {
        case true:
          _connectionStateController.add(ConnectionState.connected);
          await _transport.discoverServices();
          await _initScale();
        case false:
          if (await _connectionStateController.stream.first !=
              ConnectionState.connecting) {
            _connectionStateController.add(ConnectionState.disconnected);
            subscription?.cancel();
            _heartbeatTimer?.cancel();
            _heartbeatTimer = null;
            _watchdogTimer?.cancel();
            _watchdogTimer = null;
          }
      }
    });
    await _transport.connect();
  }

  @override
  disconnect() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    await _transport.disconnect();
  }

  @override
  DeviceType get type => DeviceType.scale;

  // --- Protocol encoding ---

  static const int _header1 = 0xEF;
  static const int _header2 = 0xDD;

  static const List<int> _identPayload = [
    0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37,
    0x38, 0x39, 0x30, 0x31, 0x32, 0x33, 0x34,
  ];

  static const List<int> _configPayload = [9, 0, 1, 1, 2, 2, 5, 3, 4];

  static const List<int> _heartbeatPayload = [0x02, 0x00];

  /// Encode a message with the Acaia protocol:
  /// [header1, header2, msgType, ...payload, cksum1, cksum2]
  static Uint8List _encode(int msgType, List<int> payload) {
    int cksum1 = 0;
    int cksum2 = 0;
    for (int i = 0; i < payload.length; i++) {
      if (i % 2 == 0) {
        cksum1 = (cksum1 + payload[i]) & 0xFF;
      } else {
        cksum2 = (cksum2 + payload[i]) & 0xFF;
      }
    }
    return Uint8List.fromList([
      _header1,
      _header2,
      msgType,
      ...payload,
      cksum1,
      cksum2,
    ]);
  }

  // --- Initialization sequence ---

  Future<void> _initScale() async {
    // Send ident
    await _transport.write(
      serviceUUID,
      commandCharacteristicUUID,
      _encode(0x0B, _identPayload),
    );

    // Send config
    await _transport.write(
      serviceUUID,
      commandCharacteristicUUID,
      _encode(0x0C, _configPayload),
    );

    // Register notifications on status characteristic
    await _transport.subscribe(
      serviceUUID,
      statusCharacteristicUUID,
      _parseNotification,
    );

    // Start heartbeat timer after 3 second delay
    _lastResponse = DateTime.now();
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer(const Duration(seconds: 3), () {
      _sendHeartbeat();
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        _sendHeartbeat();
      });
    });

    // Start watchdog timer to detect stale connections
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _checkWatchdog();
    });
  }

  Future<void> _sendHeartbeat() async {
    await _transport.write(
      serviceUUID,
      commandCharacteristicUUID,
      _encode(0x00, _heartbeatPayload),
      withResponse: true,
    );
    // Also send config as acknowledgement
    await _transport.write(
      serviceUUID,
      commandCharacteristicUUID,
      _encode(0x0C, _configPayload),
    );
  }

  void _checkWatchdog() {
    final elapsed = DateTime.now().difference(_lastResponse).inMilliseconds;
    if (elapsed > 3400) {
      disconnect();
    }
  }

  // --- Tare ---

  @override
  Future<void> tare() async {
    await _transport.write(
      serviceUUID,
      commandCharacteristicUUID,
      _encode(0x04, [0x00, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
      withResponse: false,
    );
    // Send config as acknowledgement after tare
    await _transport.write(
      serviceUUID,
      commandCharacteristicUUID,
      _encode(0x0C, _configPayload),
    );
  }

  // --- Display control ---

  @override
  Future<void> sleepDisplay() async {
    // Acaia Pyxis doesn't support display control
    // Fallback to disconnect as per scale interface contract
    await disconnect();
  }

  @override
  Future<void> wakeDisplay() async {
    // Acaia Pyxis doesn't support display control
    // This is a no-op
  }

  // --- Notification parsing ---

  void _parseNotification(List<int> data) {
    _lastResponse = DateTime.now();
    _commandBuffer.addAll(data);

    // Look for valid message starting with header bytes
    while (_commandBuffer.length > 4) {
      // Find header
      if (_commandBuffer[0] != _header1 || _commandBuffer[1] != _header2) {
        _commandBuffer.removeAt(0);
        continue;
      }

      int msgType = _commandBuffer[2];

      // We need at least bytes up to the payload start to parse
      if (_commandBuffer.length < 5) break;

      List<int> payload = _commandBuffer.sublist(4);

      switch (msgType) {
        case 12:
          _parseType12(payload);
          _commandBuffer.clear();
          return;
        case 8:
          _batteryLevel = _commandBuffer[4];
          _commandBuffer.clear();
          return;
        default:
          // Unknown type, discard this message
          _commandBuffer.clear();
          return;
      }
    }
  }

  void _parseType12(List<int> payload) {
    if (payload.isEmpty) return;
    int subType = payload[0];

    switch (subType) {
      case 5:
        // Weight data
        _decodeWeight(payload);
      case 8:
        // Tare done - no action needed
        break;
      case 11:
        // Heartbeat response
        if (payload.length > 3 && payload[3] == 5) {
          _decodeWeight(payload.sublist(3));
        }
      case 12:
        // Weight data (Pyxis-specific)
        _decodeWeight(payload);
    }
  }

  void _decodeWeight(List<int> payload) {
    if (payload.length < 7) return;

    int temp = ((payload[4] & 0xFF) << 24) +
        ((payload[3] & 0xFF) << 16) +
        ((payload[2] & 0xFF) << 8) +
        (payload[1] & 0xFF);

    int unit = payload[5] & 0xFF;
    double weight = temp / pow(10, unit);

    if ((payload[6] & 0x02) != 0) {
      weight *= -1;
    }

    _streamController.add(
      ScaleSnapshot(
        timestamp: DateTime.now(),
        weight: weight,
        batteryLevel: _batteryLevel,
      ),
    );
  }
}
