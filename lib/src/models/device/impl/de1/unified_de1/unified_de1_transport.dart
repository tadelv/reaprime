import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/device.dart' as device;
import 'package:reaprime/src/models/device/ble_service_identifier.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';
import 'package:reaprime/src/models/device/transport/ble_timeout_exception.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:reaprime/src/models/device/transport/data_transport.dart';
import 'package:reaprime/src/models/device/transport/logical_endpoint.dart';
import 'package:reaprime/src/models/device/transport/serial_port.dart';
import 'package:rxdart/rxdart.dart';

enum TransportType { ble, serial, unknown }

class UnifiedDe1Transport {
  final DataTransport _transport;
  final TransportType transportType;
  final Logger _log;

  // Only assigned on the serial transport path (`_serialConnect`).
  // Nullable so `disconnect()` can be called safely if connect failed
  // before the subscription was wired, or on BLE transports where the
  // serial branch never runs.
  StreamSubscription<String>? _transportSubscription;

  Stream<device.ConnectionState> get connectionState => _transport.connectionState;

  String get id => _transport.id;

  final BehaviorSubject<ByteData> _stateSubject = BehaviorSubject.seeded(
    ByteData(4),
  );
  final BehaviorSubject<ByteData> _shotSampleSubject = BehaviorSubject.seeded(
    ByteData(19),
  );
  // TODO: change this to expose a different subject if needed
  final BehaviorSubject<ByteData> shotSettingsSubject = BehaviorSubject.seeded(
    ByteData(9),
  );
  final BehaviorSubject<ByteData> _waterLevelsSubject = BehaviorSubject.seeded(
    ByteData(4),
  );
  final BehaviorSubject<ByteData> _mmrSubject = BehaviorSubject.seeded(
    ByteData(20),
  );
  final BehaviorSubject<ByteData> _fwMapRequestSubject = BehaviorSubject.seeded(
    ByteData(7),
  );

  Stream<ByteData> get state => _stateSubject.asBroadcastStream();
  Stream<ByteData> get shotSample => _shotSampleSubject.asBroadcastStream();
  Stream<ByteData> get shotSettings => shotSettingsSubject.asBroadcastStream();
  Stream<ByteData> get waterLevels => _waterLevelsSubject.asBroadcastStream();
  Stream<ByteData> get mmr => _mmrSubject.asBroadcastStream();
  Stream<ByteData> get fwMapRequest => _fwMapRequestSubject.asBroadcastStream();

  // Serial only
  String _currentBuffer = "";

  UnifiedDe1Transport({required DataTransport transport})
    : _transport = transport,
      transportType =
          transport is BLETransport
              ? TransportType.ble
              : transport is SerialTransport
              ? TransportType.serial
              : TransportType.unknown,
      _log = Logger("UnifiedDe1Transport-${transport.id}");
  Future<void> connect() async {
    await _transport.connect();

    switch (transportType) {
      case TransportType.ble:
        await _bleConnect();
        break;
      case TransportType.serial:
        await _serialConnect();
        break;
      default:
        throw StateError('Unknown transport type: $transportType');
    }
  }

  Future<void> _bleConnect() async {
    if (_transport is! BLETransport) {
      throw "wrong transport type";
    }
    final services = await _transport.discoverServices();
    final de1Service = BleServiceIdentifier.parse(de1ServiceUUID);
    if (!de1Service.matchesAny(services)) {
      throw Exception(
        'Expected DE1 service ${de1Service.long} not found. '
        'Discovered services: $services',
      );
    }

    _stateNotification(
      ByteData.sublistView(
        await _transport.read(de1ServiceUUID, Endpoint.stateInfo.uuid),
      ),
    );

    _shotSettingsNotification(
      ByteData.sublistView(
        await _transport.read(de1ServiceUUID, Endpoint.shotSettings.uuid),
      ),
    );

    await _transport.subscribe(de1ServiceUUID, Endpoint.stateInfo.uuid, (d) {
      _stateNotification(ByteData.sublistView(Uint8List.fromList(d)));
    });
    await _transport.subscribe(de1ServiceUUID, Endpoint.shotSample.uuid, (d) {
      _shotSampleNotification(ByteData.sublistView(Uint8List.fromList(d)));
    });
    await _transport.subscribe(de1ServiceUUID, Endpoint.waterLevels.uuid, (d) {
      _waterLevelsNotification(ByteData.sublistView(Uint8List.fromList(d)));
    });
    await _transport.subscribe(de1ServiceUUID, Endpoint.shotSettings.uuid, (d) {
      _shotSettingsNotification(ByteData.sublistView(Uint8List.fromList(d)));
    });
    await _transport.subscribe(de1ServiceUUID, Endpoint.readFromMMR.uuid, (d) {
      _mmrNotification(ByteData.sublistView(Uint8List.fromList(d)));
    });
    await _transport.subscribe(de1ServiceUUID, Endpoint.fwMapRequest.uuid, (d) {
      _fwMapNotification(ByteData.sublistView(Uint8List.fromList(d)));
    });

    if (Platform.isAndroid) {
      _log.info("requesting priority for $this");
      await _transport.setTransportPriority(true);
    }
  }

  Future<void> _serialConnect() async {
    if (_transport is! SerialTransport) {
      throw "Wrong transport type";
    }
    // Start notifications - regular setup
    // await _transport.writeCommand("<-N>");
    // await _transport.writeCommand("<-M>");
    // await _transport.writeCommand("<-Q>");
    // await _transport.writeCommand("<-K>");
    // await _transport.writeCommand("<-E>");

    _transportSubscription = _transport.readStream.listen(_processSerialInput);

    await _transport.writeCommand("<+${Endpoint.stateInfo.representation}>");
    await _transport.writeCommand("<+${Endpoint.shotSample.representation}>");
    await _transport.writeCommand("<+${Endpoint.waterLevels.representation}>");
    await _transport.writeCommand("<+${Endpoint.shotSettings.representation}>");
    await _transport.writeCommand("<+${Endpoint.readFromMMR.representation}>");
    await _transport.writeCommand("<+${Endpoint.fwMapRequest.representation}>");

    // needed to know which state we're at - request idle state
    await _transport.writeCommand("<B>02");
  }

  Future<void> disconnect() async {
    _log.warning(
      'disconnect() called by app code',
      null,
      StackTrace.current,
    );
    switch (transportType) {
      case TransportType.serial:
        if (_transport is! SerialTransport) {
          throw "Wrong transport type";
        }
        await _transportSubscription?.cancel();
        _transportSubscription = null;
        // Start notifications - regular setup
        await _transport.writeCommand(
          "<-${Endpoint.stateInfo.representation}>",
        );
        await _transport.writeCommand(
          "<-${Endpoint.shotSample.representation}>",
        );
        await _transport.writeCommand(
          "<-${Endpoint.waterLevels.representation}>",
        );
        await _transport.writeCommand(
          "<-${Endpoint.shotSettings.representation}>",
        );
        await _transport.writeCommand(
          "<-${Endpoint.readFromMMR.representation}>",
        );
        await _transport.writeCommand(
          "<-${Endpoint.fwMapRequest.representation}>",
        );
        break;
      case TransportType.ble:
        // BLE doesn't need special disconnect handling
        break;
      case TransportType.unknown:
        throw StateError('Unknown transport type: $transportType');
    }

    await _transport.disconnect();
  }

  // Matches a complete message: [X] prefix + hex payload, terminated by
  // another '[' (next message) or newline.
  // Group 1 = the message content (e.g., "[M]0A0B0C").
  static final _messagePattern =
      RegExp(r'(\[[A-Z]\][0-9A-Fa-f\s]*?)(?=\[|\n)');

  // Render the first `max` characters of a buffer for a log line. Replaces
  // non-printable and whitespace chars with their escape form so the sample
  // stays on a single line and reveals whether the content is e.g. sensor
  // basket text, binary noise, or something else.
  static String _sampleForLog(String s, int max) {
    final head = s.length <= max ? s : '${s.substring(0, max)}…';
    final escaped = head
        .replaceAll('\\', r'\\')
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\r')
        .replaceAll('\t', r'\t')
        .replaceAllMapped(
          RegExp(r'[^\x20-\x7e]'),
          (m) => '\\x${m[0]!.codeUnitAt(0).toRadixString(16).padLeft(2, '0')}',
        );
    return '"$escaped"';
  }

  void _processSerialInput(String input) {
    _currentBuffer += input;

    // Discard any leading junk before the first '['
    final firstBracket = _currentBuffer.indexOf('[');
    if (firstBracket < 0) {
      // No message start in buffer at all
      _currentBuffer = '';
      return;
    }
    if (firstBracket > 0) {
      _log.finest(
          "Discarding non-message data: '${_currentBuffer.substring(0, firstBracket)}'");
      _currentBuffer = _currentBuffer.substring(firstBracket);
    }

    // Extract all complete messages. A message is "complete" when followed by
    // another '[' (next message start) or a newline. Incomplete messages at
    // the end of the buffer won't match the lookahead and stay buffered.
    final matches = _messagePattern.allMatches(_currentBuffer).toList();

    if (matches.isEmpty) {
      // Guard against unbounded buffer growth from corrupted serial streams
      if (_currentBuffer.length > 4096) {
        _log.warning(
            'Serial buffer overflow (${_currentBuffer.length} bytes), discarding. '
            'Head sample: ${_sampleForLog(_currentBuffer, 200)}');
        _currentBuffer = '';
      }
      return;
    }

    final completeCount = matches.length;

    for (int i = 0; i < completeCount; i++) {
      final message = matches[i].group(1)!.trim();
      if (message.isNotEmpty) {
        _log.finest("received complete response: $message");
        _processDe1Response(message);
      }
    }

    // Keep unprocessed portion in the buffer
    if (completeCount > 0) {
      _currentBuffer = _currentBuffer.substring(matches[completeCount - 1].end);
      // Strip consumed newlines
      _currentBuffer = _currentBuffer.replaceAll(RegExp(r'^\n+'), '');
    }
  }

  void _processDe1Response(String input) {
    _log.finest("processing input: $input");
    try {
      final Uint8List payload = hexToBytes(input.substring(3));
      final ByteData data = ByteData.sublistView(payload);
      switch (input.substring(0, 3)) {
        case "[M]":
          _shotSampleNotification(data);
        case "[N]":
          _stateNotification(data);
        case "[Q]":
          _waterLevelsNotification(data);
        case "[K]":
          _shotSettingsNotification(data);
        case "[E]":
          _mmrNotification(data);
        case "[I]":
          _fwMapNotification(data);
        default:
          _log.warning("unhandled de1 message: $input");
          break;
      }
    } on FormatException catch (e) {
      _log.warning("malformed serial message, skipping: '$input' ($e)");
    }
  }

  Uint8List hexToBytes(String hex) {
    hex = hex.replaceAll(RegExp(r'\s+'), ''); // strip whitespace
    if (hex.length.isOdd) {
      throw FormatException('Invalid input length, must be even', hex);
    }
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      final byteStr = hex.substring(i, i + 2);
      result[i ~/ 2] = int.parse(byteStr, radix: 16);
    }
    return result;
  }

  // Minimum lengths required by `_parseStateAndShotSample` in
  // `unified_de1.parsing.dart`. Shorter frames (observed in the wild on
  // Galaxy Tab A9+ 0.5.13) cause a `RangeError` deep in rxdart and land
  // in Crashlytics as fatal. Drop them here with a warning instead.
  static const _minShotSampleBytes = 19;
  static const _minStateBytes = 2;

  void _shotSampleNotification(ByteData d) {
    if (d.lengthInBytes < _minShotSampleBytes) {
      _log.warning(
        'Dropping short shotSample frame '
        '(${d.lengthInBytes} < $_minShotSampleBytes bytes)',
      );
      return;
    }
    _shotSampleSubject.add(d);
  }

  void _stateNotification(ByteData d) {
    if (d.lengthInBytes < _minStateBytes) {
      _log.warning(
        'Dropping short state frame '
        '(${d.lengthInBytes} < $_minStateBytes bytes)',
      );
      return;
    }
    _stateSubject.add(d);
  }

  void _waterLevelsNotification(ByteData d) {
    _waterLevelsSubject.add(d);
  }

  void _shotSettingsNotification(ByteData d) {
    shotSettingsSubject.add(d);
  }

  void _fwMapNotification(ByteData d) {
    _fwMapRequestSubject.add(d);
  }

  void _mmrNotification(ByteData d) {
    _mmrSubject.add(d);
  }

  Future<ByteData> read(LogicalEndpoint endpoint) async {
    if (await _transport.connectionState.first != device.ConnectionState.connected) {
      throw ("de1 not connected");
    }

    try {
      switch (transportType) {
        case TransportType.ble:
          if (endpoint.uuid == null) {
            throw StateError(
                'Endpoint ${endpoint.name} has no BLE wire support');
          }
          return await _bleRead(endpoint);
        case TransportType.serial:
          if (endpoint.representation == null) {
            throw StateError(
                'Endpoint ${endpoint.name} has no serial wire support');
          }
          if (endpoint is! Endpoint) {
            throw StateError(
                'Serial read requires DE1 Endpoint, got ${endpoint.name}');
          }
          return await _serialRead(endpoint);
        default:
          throw ("Unknown transport type: $transportType");
      }
    } catch (e, st) {
      if (_isBleTimeout(e)) {
        if (await _handleBleTimeout(e, st)) {
          _log.info('Retrying read of ${endpoint.name} after reconnect');
          return read(endpoint);
        }
      }
      _log.severe("failed to read", e, st);
      rethrow;
    }
  }

  Future<ByteData> _bleRead(LogicalEndpoint e) async {
    if (_transport is! BLETransport) {
      throw "Invalid transport type, expected BLE";
    }
    var data = await _transport.read(de1ServiceUUID, e.uuid!);
    ByteData response = ByteData.sublistView(Uint8List.fromList(data));
    return response;
  }

  Future<ByteData> _serialRead(Endpoint e) async {
    if (transportType != TransportType.serial) {
      throw "Invalid transport type, expected Serial";
    }

    switch (e) {
      case Endpoint.versions:
        throw UnimplementedError();
      case Endpoint.requestedState:
        return _stateSubject.first;
      case Endpoint.setTime:
        throw UnimplementedError();
      case Endpoint.shotDirectory:
        throw UnimplementedError();
      case Endpoint.readFromMMR:
        return _mmrSubject.first;
      case Endpoint.writeToMMR:
        throw UnimplementedError();
      case Endpoint.shotMapRequest:
        throw UnimplementedError();
      case Endpoint.deleteShotRange:
        throw UnimplementedError();
      case Endpoint.fwMapRequest:
        return _fwMapRequestSubject.first;
      case Endpoint.temperatures:
        throw UnimplementedError();
      case Endpoint.shotSettings:
        return shotSettingsSubject.first;
      case Endpoint.deprecatedShotDesc:
        throw UnimplementedError();
      case Endpoint.shotSample:
        return _shotSampleSubject.first;
      case Endpoint.stateInfo:
        return _stateSubject.first;
      case Endpoint.headerWrite:
        throw UnimplementedError();
      case Endpoint.frameWrite:
        throw UnimplementedError();
      case Endpoint.waterLevels:
        return _waterLevelsSubject.first;
      case Endpoint.calibration:
        // TODO: Handle this case.
        throw UnimplementedError();
    }
  }

  Future<void> write(LogicalEndpoint endpoint, Uint8List data) async {
    if (await _transport.connectionState.first != device.ConnectionState.connected) {
      throw ("de1 not connected");
    }
    try {
      _log.fine('about to write to ${endpoint.name}');
      _log.fine(
        'payload: ${data.map((el) => el.toRadixString(16).padLeft(2, '0')).join(' ')}',
      );

      switch (transportType) {
        case TransportType.ble:
          if (endpoint.uuid == null) {
            throw StateError(
                'Endpoint ${endpoint.name} has no BLE wire support');
          }
          await _bleWrite(endpoint, data, false);
          break;
        case TransportType.serial:
          if (endpoint.representation == null) {
            throw StateError(
                'Endpoint ${endpoint.name} has no serial wire support');
          }
          await _serialWrite(endpoint, data);
          break;
        default:
          throw ("Unknown transport type: $transportType");
      }
    } catch (e, st) {
      if (_isBleTimeout(e)) {
        if (await _handleBleTimeout(e, st)) {
          _log.info('Retrying write to ${endpoint.name} after reconnect');
          return write(endpoint, data);
        }
      }
      _log.severe("failed to write", e, st);
      rethrow;
    }
  }

  Future<void> writeWithResponse(LogicalEndpoint endpoint, Uint8List data) async {
    if (await _transport.connectionState.first != device.ConnectionState.connected) {
      throw ("de1 not connected");
    }
    try {
      _log.fine('about to write to ${endpoint.name}');
      _log.fine(
        'payload: ${data.map((el) => el.toRadixString(16).padLeft(2, '0')).join(' ')}',
      );
      switch (transportType) {
        case TransportType.ble:
          if (endpoint.uuid == null) {
            throw StateError(
                'Endpoint ${endpoint.name} has no BLE wire support');
          }
          await _bleWrite(endpoint, data, true);
          break;
        case TransportType.serial:
          if (endpoint.representation == null) {
            throw StateError(
                'Endpoint ${endpoint.name} has no serial wire support');
          }
          await _serialWrite(endpoint, data);
          break;
        default:
          throw ("Unknown transport type: $transportType");
      }
    } catch (e, st) {
      if (_isBleTimeout(e)) {
        if (await _handleBleTimeout(e, st)) {
          _log.info('Retrying write to ${endpoint.name} after reconnect');
          return writeWithResponse(endpoint, data);
        }
      }
      _log.severe("failed to write", e, st);
      rethrow;
    }
  }

  bool _isBleTimeout(Object error) {
    return transportType == TransportType.ble &&
        error is BleTimeoutException;
  }

  /// Attempts to recover from a BLE timeout by reconnecting.
  /// Returns true if reconnect succeeded, false if it failed.
  Future<bool> _handleBleTimeout(Object error, StackTrace st) async {
    _log.warning('BLE write timed out, attempting reconnect');
    try {
      await _transport.disconnect();
      await _transport.connect();
      await _bleConnect();
      _log.info('BLE reconnect successful after timeout');
      return true;
    } catch (reconnectError) {
      _log.severe(
        'BLE reconnect failed, disconnecting',
        reconnectError,
      );
      try {
        // Don't await — BLE stack may be unresponsive
        _transport.disconnect();
      } catch (e, st) {
        _log.fine('transport.disconnect() during BLE recovery failed', e, st);
      }
      return false;
    }
  }

  Future<void> _serialWrite(LogicalEndpoint e, Uint8List data) async {
    if (_transport is! SerialTransport) {
      throw "Invalid transport type, expected Serial";
    }
    final payload = data
        .map((e) => e.toRadixString(16).padLeft(2, '0'))
        .join('');
    await _transport.writeCommand('<${e.representation!}>$payload');
  }

  Future<void> _bleWrite(LogicalEndpoint e, Uint8List data, bool withResponse) async {
    if (_transport is! BLETransport) {
      throw "Invalid transport type, expected BLE";
    }

    await _transport.write(
      de1ServiceUUID,
      e.uuid!,
      data,
      withResponse: withResponse,
    );
  }
}
