import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/ble_service_identifier.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/device_implementation.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:reaprime/src/models/device/transport/data_transport.dart';
import 'package:reaprime/src/models/errors.dart';
import 'package:rxdart/subjects.dart';

enum AcaiaProtocol { ips, pyxis }

class AcaiaScale implements Scale {
  static final _ipsService = BleServiceIdentifier.short('1820');
  static final _ipsCharacteristic = BleServiceIdentifier.short('2a80');
  static final _pyxisService = BleServiceIdentifier.long(
    '49535343-fe7d-4ae5-8fa9-9fafd205e455',
  );
  static final _pyxisStatusChar = BleServiceIdentifier.long(
    '49535343-1e4d-4bd9-ba61-23c647249616',
  );
  static final _pyxisCmdChar = BleServiceIdentifier.long(
    '49535343-8841-43f4-a8d4-ecbe34729bb3',
  );

  static const advertisedServiceUuids = [
    '49535343-fe7d-4ae5-8fa9-9fafd205e455',
    '49535343-1e4d-4bd9-ba61-23c647249616',
    '49535343-8841-43f4-a8d4-ecbe34729bb3',
  ];

  static const _maxInitRetries = 10;
  static const _header1 = 0xEF;
  static const _header2 = 0xDD;
  static const _metadataLength = 5;
  static const _maxPayloadLength = 64;
  static const _identPayload = [
    0x30,
    0x31,
    0x32,
    0x33,
    0x34,
    0x35,
    0x36,
    0x37,
    0x38,
    0x39,
    0x30,
    0x31,
    0x32,
    0x33,
    0x34,
  ];
  static const _configPayload = [
    0x09,
    0x00,
    0x01,
    0x01,
    0x02,
    0x02,
    0x01,
    0x03,
    0x04,
  ];
  static const _heartbeatPayload = [0x02, 0x00];

  final Logger _log = Logger('AcaiaScale');
  final BLETransport _transport;
  final String _deviceId;
  final StreamController<ScaleSnapshot> _streamController =
      StreamController.broadcast();
  final BehaviorSubject<ConnectionState> _connectionStateController =
      BehaviorSubject.seeded(ConnectionState.discovered);

  AcaiaProtocol? _protocol;
  StreamSubscription<ConnectionState>? _disconnectSubscription;
  Timer? _maintenanceTimer;
  Timer? _watchdogTimer;
  List<int> _buffer = [];
  DateTime _lastValidFrame = DateTime.now();
  int _batteryLevel = 0;
  int _generation = 0;
  bool _hasValidWeight = false;
  bool _badBatteryLogged = false;

  AcaiaScale({required BLETransport transport})
    : _transport = transport,
      _deviceId = transport.id;

  @override
  Stream<ScaleSnapshot> get currentSnapshot => _streamController.stream;

  @override
  String get deviceId => _deviceId;

  @override
  DeviceImplementation get implementation => DeviceImplementation.acaiaScale;

  @override
  TransportType get transportType => _transport.transportType;

  @override
  String get name =>
      _transport.name.isNotEmpty ? _transport.name : 'Acaia Scale';

  @override
  Stream<ConnectionState> get connectionState =>
      _connectionStateController.stream;

  @override
  DeviceType get type => DeviceType.scale;

  String get _serviceUuid =>
      _protocol == AcaiaProtocol.pyxis ? _pyxisService.long : _ipsService.long;

  String get _notifyCharacteristic => _protocol == AcaiaProtocol.pyxis
      ? _pyxisStatusChar.long
      : _ipsCharacteristic.long;

  String get _writeCharacteristic => _protocol == AcaiaProtocol.pyxis
      ? _pyxisCmdChar.long
      : _ipsCharacteristic.long;

  bool get _withResponse => _protocol == AcaiaProtocol.pyxis;

  @override
  Future<void> onConnect() async {
    if (_connectionStateController.value == ConnectionState.connected &&
        await _transport.getConnectionState() == ConnectionState.connected) {
      return;
    }
    _invalidateConnection();
    final generation = _generation;
    _connectionStateController.add(ConnectionState.connecting);

    try {
      await _disconnectSubscription?.cancel();
      _disconnectSubscription = null;
      if (generation != _generation) {
        throw const DeviceNotConnectedException.scale();
      }
      await _transport.connect();
      await _ensureCurrentConnection(generation);
      _disconnectSubscription = _transport.connectionState
          .where((state) => state == ConnectionState.disconnected)
          .listen((_) {
            if (generation != _generation) return;
            _invalidateConnection();
            _connectionStateController.add(ConnectionState.disconnected);
          });

      final services = await _transport.discoverServices();
      await _ensureCurrentConnection(generation);
      if (_pyxisService.matchesAny(services)) {
        _protocol = AcaiaProtocol.pyxis;
      } else if (_ipsService.matchesAny(services)) {
        _protocol = AcaiaProtocol.ips;
      } else {
        throw StateError('No supported Acaia service found');
      }

      await _initialize(generation);
      await _ensureCurrentConnection(generation);
      _connectionStateController.add(ConnectionState.connected);
      _startMaintenance(generation);
    } catch (error, stackTrace) {
      if (generation != _generation) return;
      _log.warning('Failed to initialize scale', error, stackTrace);
      _invalidateConnection();
      _connectionStateController.add(ConnectionState.disconnected);
      final cancellation = _disconnectSubscription?.cancel();
      _disconnectSubscription = null;
      try {
        await _transport.disconnect();
      } catch (_) {}
      await cancellation;
    }
  }

  Future<void> _initialize(int generation) async {
    _hasValidWeight = false;
    _badBatteryLogged = false;
    _buffer = [];
    await _transport.subscribe(
      _serviceUuid,
      _notifyCharacteristic,
      _parseNotification,
    );
    await _ensureCurrentConnection(generation);
    await Future<void>.delayed(
      Duration(milliseconds: _protocol == AcaiaProtocol.pyxis ? 500 : 100),
    );
    await _ensureCurrentConnection(generation);

    for (
      var attempt = 0;
      attempt < _maxInitRetries && !_hasValidWeight;
      attempt++
    ) {
      if (!await _write(_encode(0x0B, _identPayload))) {
        throw StateError('Acaia ident write failed');
      }
      await _ensureCurrentConnection(generation);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await _ensureCurrentConnection(generation);
      if (!await _write(_encode(0x0C, _configPayload))) {
        throw StateError('Acaia config write failed');
      }
      await _ensureCurrentConnection(generation);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await _ensureCurrentConnection(generation);
    }

    if (!_hasValidWeight) {
      throw StateError('Acaia scale produced no valid weight');
    }
  }

  Future<void> _ensureCurrentConnection(int generation) async {
    if (generation != _generation ||
        await _transport.getConnectionState() != ConnectionState.connected ||
        generation != _generation) {
      throw const DeviceNotConnectedException.scale();
    }
  }

  static Uint8List _encode(int messageType, List<int> payload) {
    var evenChecksum = 0;
    var oddChecksum = 0;
    for (var i = 0; i < payload.length; i++) {
      if (i.isEven) {
        evenChecksum = (evenChecksum + payload[i]) & 0xFF;
      } else {
        oddChecksum = (oddChecksum + payload[i]) & 0xFF;
      }
    }
    return Uint8List.fromList([
      _header1,
      _header2,
      messageType,
      ...payload,
      evenChecksum,
      oddChecksum,
    ]);
  }

  Future<bool> _write(Uint8List data) async {
    try {
      await _transport.write(
        _serviceUuid,
        _writeCharacteristic,
        data,
        withResponse: _withResponse,
      );
      return true;
    } on DeviceNotConnectedException {
      _log.fine('Acaia write skipped because the device disconnected');
      return false;
    }
  }

  void _startMaintenance(int generation) {
    _lastValidFrame = DateTime.now();
    _scheduleMaintenance(generation);
    if (_protocol == AcaiaProtocol.pyxis) _scheduleWatchdog(generation);
  }

  void _scheduleMaintenance(int generation) {
    _maintenanceTimer?.cancel();
    _maintenanceTimer = Timer(const Duration(seconds: 3), () {
      unawaited(_runMaintenance(generation));
    });
  }

  Future<void> _runMaintenance(int generation) async {
    if (!_isCurrent(generation)) return;
    try {
      await _write(_encode(0x00, _heartbeatPayload));
    } on TimeoutException catch (error) {
      _log.warning('Acaia heartbeat timed out: $error');
    } catch (error, stackTrace) {
      _log.warning('Acaia heartbeat failed', error, stackTrace);
    } finally {
      if (_isCurrent(generation)) _scheduleMaintenance(generation);
    }
  }

  void _scheduleWatchdog(int generation) {
    _watchdogTimer?.cancel();
    final elapsed = DateTime.now().difference(_lastValidFrame);
    final remaining = const Duration(seconds: 5) - elapsed;
    _watchdogTimer = Timer(
      remaining.isNegative ? Duration.zero : remaining,
      () {
        unawaited(_runWatchdog(generation));
      },
    );
  }

  Future<void> _runWatchdog(int generation) async {
    if (!_isCurrent(generation)) return;
    if (DateTime.now().difference(_lastValidFrame) >=
        const Duration(seconds: 5)) {
      await disconnect();
      return;
    }
    _scheduleWatchdog(generation);
  }

  bool _isCurrent(int generation) =>
      generation == _generation &&
      _connectionStateController.value == ConnectionState.connected;

  void _invalidateConnection() {
    _generation++;
    _maintenanceTimer?.cancel();
    _maintenanceTimer = null;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
  }

  @override
  Future<void> disconnect() async {
    _invalidateConnection();
    await _disconnectSubscription?.cancel();
    _disconnectSubscription = null;
    _connectionStateController.add(ConnectionState.disconnected);
    await _transport.disconnect();
  }

  @override
  Future<void> tare() async {
    final command = _encode(0x04, List<int>.filled(15, 0));
    for (var attempt = 0; attempt < 3; attempt++) {
      if (!await _write(command)) throw StateError('Acaia tare write failed');
      if (attempt < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  }

  @override
  Future<void> sleepDisplay() => disconnect();

  @override
  Future<void> wakeDisplay() async {}

  @override
  Future<void> startTimer() async {}

  @override
  Future<void> stopTimer() async {}

  @override
  Future<void> resetTimer() async {}

  void _parseNotification(List<int> data) {
    _buffer.addAll(data);
    while (true) {
      var headerIndex = -1;
      for (var i = 0; i + 1 < _buffer.length; i++) {
        if (_buffer[i] == _header1 && _buffer[i + 1] == _header2) {
          headerIndex = i;
          break;
        }
      }

      if (headerIndex < 0) {
        _buffer = _buffer.isNotEmpty && _buffer.last == _header1
            ? [_header1]
            : [];
        return;
      }
      if (headerIndex > 0) _buffer = _buffer.sublist(headerIndex);
      if (_buffer.length < _metadataLength) return;

      final payloadLength = _buffer[3];
      if (payloadLength > _maxPayloadLength) {
        _buffer = _buffer.sublist(2);
        continue;
      }
      if (!_hasValidKnownLength(_buffer[2], payloadLength, _buffer[4])) {
        _buffer = _buffer.sublist(2);
        continue;
      }

      final frameLength = _metadataLength + payloadLength;
      if (_buffer.length < frameLength) return;
      final frame = List<int>.unmodifiable(_buffer.sublist(0, frameLength));
      _buffer = _buffer.sublist(frameLength);
      if (_processFrame(frame)) {
        _lastValidFrame = DateTime.now();
        if (_protocol == AcaiaProtocol.pyxis &&
            _connectionStateController.value == ConnectionState.connected) {
          _scheduleWatchdog(_generation);
        }
      }
    }
  }

  bool _hasValidKnownLength(int messageType, int payloadLength, int eventType) {
    if (messageType == 0x08) return payloadLength == 3;
    if (messageType != 0x0C) return true;
    return switch (eventType) {
      5 => payloadLength == 6,
      11 => payloadLength == 9,
      _ => true,
    };
  }

  bool _processFrame(List<int> frame) {
    final messageType = frame[2];
    final eventType = frame[4];

    if (messageType == 0x08) {
      final battery = frame[4] & 0x7F;
      if (battery <= 100) {
        _batteryLevel = battery;
      } else if (!_badBatteryLogged) {
        _badBatteryLogged = true;
        _log.warning('Ignoring out-of-range Acaia battery value $battery');
      }
      return true;
    }
    if (messageType != 0x0C) return false;

    if (eventType == 5) {
      _decodeWeight(frame, _metadataLength);
      return true;
    }
    if (eventType != 11) return false;
    if (frame[7] == 7) return true;
    if (frame[7] != 5) return false;
    _decodeWeight(frame, _metadataLength + 3);
    return true;
  }

  void _decodeWeight(List<int> frame, int offset) {
    final magnitude =
        (frame[offset + 2] << 16) | (frame[offset + 1] << 8) | frame[offset];
    final exponent = frame[offset + 4];
    var weight = magnitude / pow(10, exponent);
    if (frame[offset + 5] > 1) weight *= -1;
    _hasValidWeight = true;
    _streamController.add(
      ScaleSnapshot(
        timestamp: DateTime.now(),
        weight: weight,
        batteryLevel: _batteryLevel,
      ),
    );
  }
}
