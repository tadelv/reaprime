import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/ble_service_identifier.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:rxdart/subjects.dart';

import 'package:reaprime/src/models/device/device.dart';

import '../../scale.dart';

/// Acaia Classic / older model scale implementation (IPS protocol).
///
/// Matches the de1app `acaiascale` implementation for ACAIA/PROCH-named scales.
/// Uses a proprietary protocol with header bytes 0xEF 0xDD, message type,
/// payload, and two checksum bytes over a single BLE characteristic.
class AcaiaScale implements Scale {
  static final BleServiceIdentifier serviceIdentifier =
      BleServiceIdentifier.short('1820');
  static final BleServiceIdentifier characteristic =
      BleServiceIdentifier.short('2a80');

  final Logger _log = Logger('AcaiaScale');
  final String _deviceId;

  final StreamController<ScaleSnapshot> _streamController =
      StreamController.broadcast();

  final BLETransport _transport;

  Timer? _heartbeatTimer;
  Timer? _configTimer;
  int _batteryLevel = 0;
  List<int> _commandBuffer = [];
  bool _receivingNotifications = false;

  AcaiaScale({required BLETransport transport})
    : _transport = transport,
      _deviceId = transport.id;

  @override
  Stream<ScaleSnapshot> get currentSnapshot => _streamController.stream;

  @override
  String get deviceId => _deviceId;

  @override
  String get name =>
      _transport.name.isNotEmpty ? _transport.name : 'Acaia Scale';

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

      // Subscribe to disconnect AFTER connect succeeds.
      // The transport's BehaviorSubject now holds `true`, so the
      // .where(!state) filter won't fire until a real disconnect.
      disconnectSub = _transport.connectionState
          .where((state) => !state)
          .listen((_) {
        _log.info('Transport disconnected');
        _connectionStateController.add(ConnectionState.disconnected);
        disconnectSub?.cancel();
        _heartbeatTimer?.cancel();
        _heartbeatTimer = null;
        _configTimer?.cancel();
        _configTimer = null;
      });

      await _transport.discoverServices();
      await _initScale();
      _connectionStateController.add(ConnectionState.connected);
      _log.info('Scale initialized successfully');
    } catch (e) {
      _log.warning('Failed to initialize scale: $e');
      disconnectSub?.cancel();
      _heartbeatTimer?.cancel();
      _heartbeatTimer = null;
      _configTimer?.cancel();
      _configTimer = null;
      _connectionStateController.add(ConnectionState.disconnected);
      try {
        await _transport.disconnect();
      } catch (_) {}
    }
  }

  @override
  disconnect() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _configTimer?.cancel();
    _configTimer = null;
    await _transport.disconnect();
  }

  @override
  DeviceType get type => DeviceType.scale;

  // --- Protocol encoding (matches de1app acaia_encode) ---

  static const int _header1 = 0xEF;
  static const int _header2 = 0xDD;

  static const List<int> _identPayload = [
    0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37,
    0x38, 0x39, 0x30, 0x31, 0x32, 0x33, 0x34,
  ];

  // Config payload matching de1app hex "0900010102020103041106":
  // data [0x09,0x00,0x01,0x01,0x02,0x02,0x01,0x03,0x04] + checksums [0x11,0x06]
  static const List<int> _configPayload = [
    0x09, 0x00, 0x01, 0x01, 0x02, 0x02, 0x01, 0x03, 0x04,
  ];

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

  // --- Initialization sequence (matches de1app timing) ---

  Future<void> _initScale() async {
    _receivingNotifications = false;

    // de1app IPS: t+100ms enable notifications, t+500ms send ident
    await _transport.subscribe(
      serviceIdentifier.long,
      characteristic.long,
      _parseNotification,
    );

    await Future.delayed(const Duration(milliseconds: 400));

    // Send ident (IPS: write without response)
    await _transport.write(
      serviceIdentifier.long,
      characteristic.long,
      _encode(0x0B, _identPayload),
      withResponse: false,
    );
    _log.fine('Sent ident');

    // de1app retries ident every 400ms if no notifications received
    await Future.delayed(const Duration(milliseconds: 400));

    if (!_receivingNotifications) {
      _log.info('No response after ident, retrying...');
      await _transport.write(
        serviceIdentifier.long,
        characteristic.long,
        _encode(0x0B, _identPayload),
        withResponse: false,
      );
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // Send config
    await _transport.write(
      serviceIdentifier.long,
      characteristic.long,
      _encode(0x0C, _configPayload),
      withResponse: false,
    );
    _log.fine('Sent config');

    // Start heartbeat cycle: heartbeat every 2s, config 1s after heartbeat
    // (matches de1app forced heartbeat pattern)
    _heartbeatTimer?.cancel();
    _configTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _sendHeartbeat();
    });
  }

  void _sendHeartbeat() {
    _transport.write(
      serviceIdentifier.long,
      characteristic.long,
      _encode(0x00, _heartbeatPayload),
      withResponse: false,
    );
    // Send config 1s after heartbeat (de1app forced heartbeat pattern)
    _configTimer?.cancel();
    _configTimer = Timer(const Duration(seconds: 1), () {
      _transport.write(
        serviceIdentifier.long,
        characteristic.long,
        _encode(0x0C, _configPayload),
        withResponse: false,
      );
    });
  }

  // --- Tare (matches de1app: 17 zero bytes on wire) ---

  @override
  Future<void> tare() async {
    await _transport.write(
      serviceIdentifier.long,
      characteristic.long,
      _encode(0x04, List.filled(15, 0x00)),
      withResponse: false,
    );
  }

  // --- Display control ---

  @override
  Future<void> sleepDisplay() async {
    await disconnect();
  }

  @override
  Future<void> wakeDisplay() async {}

  // --- Notification parsing (matches de1app acaia_parse_response) ---

  static const int _metadataLen = 5;

  void _parseNotification(List<int> data) {
    _log.fine('Notification received: ${data.length} bytes');
    _commandBuffer.addAll(data);

    while (_commandBuffer.length >= _metadataLen + 1) {
      // Find header
      if (_commandBuffer[0] != _header1 || _commandBuffer[1] != _header2) {
        _commandBuffer.removeAt(0);
        continue;
      }

      int msgType = _commandBuffer[2];
      int length = _commandBuffer[3];
      int eventType = _commandBuffer[4];

      // Total message size: metadata + remaining payload
      int msgLen = _metadataLen + length;

      // Wait for complete message
      if (_commandBuffer.length < msgLen) break;

      // Track that scale is responding (de1app sets flag when msg_type != 7)
      if (msgType != 7) {
        _receivingNotifications = true;
      }

      // Battery message
      if (msgType == 8 && _commandBuffer.length > 4) {
        _batteryLevel = _commandBuffer[4];
      }

      // Weight messages: msg_type 12, event_type 5 or 11, length <= 64
      if (msgType == 12 &&
          (eventType == 5 || eventType == 11) &&
          length <= 64) {
        final payloadOffset =
            eventType == 5 ? _metadataLen : _metadataLen + 3;
        _decodeWeight(_commandBuffer, payloadOffset);
      }

      // Advance past processed message
      if (msgLen <= _commandBuffer.length) {
        _commandBuffer = _commandBuffer.sublist(msgLen);
      } else {
        _commandBuffer.clear();
      }
    }
  }

  /// Decode weight from buffer at offset.
  /// 3-byte (24-bit) little-endian weight matching de1app.
  void _decodeWeight(List<int> buffer, int offset) {
    if (offset + 6 > buffer.length) return;

    int value = ((buffer[offset + 2] & 0xFF) << 16) +
        ((buffer[offset + 1] & 0xFF) << 8) +
        (buffer[offset] & 0xFF);

    int unit = buffer[offset + 4] & 0xFF;
    double weight = value / pow(10, unit);

    // Sign: negative if byte > 1 (de1app convention)
    if ((buffer[offset + 5] & 0xFF) > 1) {
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

  @override
  Future<void> startTimer() async {}

  @override
  Future<void> stopTimer() async {}

  @override
  Future<void> resetTimer() async {}
}
