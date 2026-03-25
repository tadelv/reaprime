import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/ble_service_identifier.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:rxdart/subjects.dart';

import 'package:reaprime/src/models/device/device.dart';

import '../../scale.dart';

/// Detected Acaia BLE protocol variant.
enum AcaiaProtocol { ips, pyxis }

/// Unified Acaia scale implementation supporting both IPS (older ACAIA/PROCH
/// models) and Pyxis (newer LUNAR/PEARL/PYXIS models) protocols.
///
/// Protocol is auto-detected at connection time based on discovered BLE
/// services, matching the Decenza approach.
///
/// Reference: de1app bluetooth.tcl (acaia_parse_response, acaia_encode)
class AcaiaScale implements Scale {
  // IPS protocol identifiers
  static final _ipsService = BleServiceIdentifier.short('1820');
  static final _ipsCharacteristic = BleServiceIdentifier.short('2a80');

  // Pyxis protocol identifiers
  static final _pyxisService =
      BleServiceIdentifier.long('49535343-fe7d-4ae5-8fa9-9fafd205e455');
  static final _pyxisStatusChar =
      BleServiceIdentifier.long('49535343-1e4d-4bd9-ba61-23c647249616');
  static final _pyxisCmdChar =
      BleServiceIdentifier.long('49535343-8841-43f4-a8d4-ecbe34729bb3');

  static const int _maxInitRetries = 10;

  final Logger _log = Logger('AcaiaScale');
  final String _deviceId;

  final StreamController<ScaleSnapshot> _streamController =
      StreamController.broadcast();

  final BLETransport _transport;

  AcaiaProtocol? _protocol;
  Timer? _heartbeatTimer;
  Timer? _configTimer;
  Timer? _watchdogTimer;
  int _batteryLevel = 0;
  List<int> _commandBuffer = [];
  DateTime _lastResponse = DateTime.now();
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
      BehaviorSubject.seeded(ConnectionState.discovered);

  @override
  Stream<ConnectionState> get connectionState =>
      _connectionStateController.stream;

  // --- Protocol-dependent helpers ---

  String get _serviceUuid =>
      _protocol == AcaiaProtocol.pyxis ? _pyxisService.long : _ipsService.long;

  String get _notifyCharUuid => _protocol == AcaiaProtocol.pyxis
      ? _pyxisStatusChar.long
      : _ipsCharacteristic.long;

  String get _writeCharUuid => _protocol == AcaiaProtocol.pyxis
      ? _pyxisCmdChar.long
      : _ipsCharacteristic.long;

  bool get _useWriteResponse => _protocol == AcaiaProtocol.pyxis;

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
        _log.info('Transport disconnected');
        _connectionStateController.add(ConnectionState.disconnected);
        disconnectSub?.cancel();
        _cancelTimers();
      });

      final services = await _transport.discoverServices();

      // Auto-detect protocol from discovered services
      if (_pyxisService.matchesAny(services)) {
        _protocol = AcaiaProtocol.pyxis;
        _log.info('Detected Pyxis protocol');
      } else if (_ipsService.matchesAny(services)) {
        _protocol = AcaiaProtocol.ips;
        _log.info('Detected IPS protocol');
      } else {
        throw Exception(
          'No Acaia service found. Expected ${_pyxisService.long} or '
          '${_ipsService.long}. Discovered: $services',
        );
      }

      await _initScale();
      _connectionStateController.add(ConnectionState.connected);
      _log.info('Scale initialized successfully (protocol: $_protocol)');
    } catch (e) {
      _log.warning('Failed to initialize scale: $e');
      disconnectSub?.cancel();
      _cancelTimers();
      _connectionStateController.add(ConnectionState.disconnected);
      try {
        await _transport.disconnect();
      } catch (_) {}
    }
  }

  @override
  disconnect() async {
    _cancelTimers();
    await _transport.disconnect();
  }

  void _cancelTimers() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _configTimer?.cancel();
    _configTimer = null;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
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

  static const List<int> _configPayload = [
    0x09, 0x00, 0x01, 0x01, 0x02, 0x02, 0x01, 0x03, 0x04,
  ];

  static const List<int> _heartbeatPayload = [0x02, 0x00];

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

  // --- Initialization with retry loop (matches de1app/Decenza) ---

  Future<void> _initScale() async {
    _receivingNotifications = false;

    // Notification enable delay: IPS=100ms, Pyxis=500ms
    final notifyDelay = _protocol == AcaiaProtocol.pyxis ? 500 : 100;

    await _transport.subscribe(
        _serviceUuid, _notifyCharUuid, _parseNotification);
    await Future.delayed(Duration(milliseconds: notifyDelay));

    // Retry ident+config up to _maxInitRetries times until scale responds
    for (int attempt = 1; attempt <= _maxInitRetries; attempt++) {
      if (_receivingNotifications) break;

      _log.fine('Init attempt $attempt/$_maxInitRetries');

      // Send ident
      await _transport.write(
        _serviceUuid,
        _writeCharUuid,
        _encode(0x0B, _identPayload),
        withResponse: _useWriteResponse,
      );

      await Future.delayed(const Duration(milliseconds: 200));

      // Send config
      await _transport.write(
        _serviceUuid,
        _writeCharUuid,
        _encode(0x0C, _configPayload),
        withResponse: _useWriteResponse,
      );

      await Future.delayed(const Duration(milliseconds: 500));
    }

    if (!_receivingNotifications) {
      _log.warning(
          'Scale did not respond after $_maxInitRetries init attempts');
    }

    // Start heartbeat (3s interval, matching Decenza)
    _lastResponse = DateTime.now();
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _sendHeartbeat();
    });

    // Watchdog for Pyxis only (5s timeout)
    if (_protocol == AcaiaProtocol.pyxis) {
      _watchdogTimer?.cancel();
      _watchdogTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _checkWatchdog();
      });
    }
  }

  void _sendHeartbeat() {
    _transport.write(
      _serviceUuid,
      _writeCharUuid,
      _encode(0x00, _heartbeatPayload),
      withResponse: _useWriteResponse,
    );
    _configTimer?.cancel();
    _configTimer = Timer(const Duration(seconds: 1), () {
      _transport.write(
        _serviceUuid,
        _writeCharUuid,
        _encode(0x0C, _configPayload),
        withResponse: _useWriteResponse,
      );
    });
  }

  void _checkWatchdog() {
    final elapsed = DateTime.now().difference(_lastResponse).inMilliseconds;
    if (elapsed > 5000) {
      _log.warning('Watchdog timeout: no response for ${elapsed}ms');
      disconnect();
    }
  }

  // --- Tare: 3x with 100ms spacing (de1app/Decenza workaround) ---

  @override
  Future<void> tare() async {
    final cmd = _encode(0x04, List.filled(15, 0x00));
    await _transport.write(
      _serviceUuid,
      _writeCharUuid,
      cmd,
      withResponse: _useWriteResponse,
    );
    await Future.delayed(const Duration(milliseconds: 100));
    await _transport.write(
      _serviceUuid,
      _writeCharUuid,
      cmd,
      withResponse: _useWriteResponse,
    );
    await Future.delayed(const Duration(milliseconds: 100));
    await _transport.write(
      _serviceUuid,
      _writeCharUuid,
      cmd,
      withResponse: _useWriteResponse,
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
    _lastResponse = DateTime.now();
    _commandBuffer.addAll(data);

    while (_commandBuffer.length >= _metadataLen + 1) {
      if (_commandBuffer[0] != _header1 || _commandBuffer[1] != _header2) {
        _commandBuffer.removeAt(0);
        continue;
      }

      int msgType = _commandBuffer[2];
      int length = _commandBuffer[3];
      int eventType = _commandBuffer[4];

      int msgLen = _metadataLen + length;

      if (_commandBuffer.length < msgLen) break;

      if (msgType != 7) {
        _receivingNotifications = true;
      }

      if (msgType == 8 && _commandBuffer.length > 4) {
        _batteryLevel = _commandBuffer[4];
      }

      if (msgType == 12 &&
          (eventType == 5 || eventType == 11) &&
          length <= 64) {
        final payloadOffset =
            eventType == 5 ? _metadataLen : _metadataLen + 3;
        _decodeWeight(_commandBuffer, payloadOffset);
      }

      if (msgLen <= _commandBuffer.length) {
        _commandBuffer = _commandBuffer.sublist(msgLen);
      } else {
        _commandBuffer.clear();
      }
    }
  }

  void _decodeWeight(List<int> buffer, int offset) {
    if (offset + 6 > buffer.length) return;

    int value = ((buffer[offset + 2] & 0xFF) << 16) +
        ((buffer[offset + 1] & 0xFF) << 8) +
        (buffer[offset] & 0xFF);

    int unit = buffer[offset + 4] & 0xFF;
    double weight = value / pow(10, unit);

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
