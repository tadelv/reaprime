import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:reaprime/src/models/device/transport/data_transport.dart';
import 'package:reaprime/src/models/device/transport/serial_port.dart';
import 'package:rxdart/rxdart.dart';

enum TransportType { ble, serial, unknown }

class UnifiedDe1Transport {
  final DataTransport _transport;
  final TransportType _transportType;
  final Logger _log;

  late StreamSubscription<String> _transportSubscription;

  Stream<bool> get connectionState => _transport.connectionState;

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
      _transportType =
          transport is BLETransport
              ? TransportType.ble
              : transport is SerialTransport
              ? TransportType.serial
              : TransportType.unknown,
      _log = Logger("UnifiedDe1Transport-${transport.id}");
  Future<void> connect() async {
    await _transport.connect();

    switch (_transportType) {
      case TransportType.ble:
        await _bleConnect();
        break;
      case TransportType.serial:
        await _serialConnect();
        break;
      default:
        throw StateError('Unknown transport type: $_transportType');
    }
  }

  Future<void> _bleConnect() async {
    if (_transport is! BLETransport) {
      throw "wrong transport type";
    }
    await _transport.discoverServices();

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
    switch (_transportType) {
      case TransportType.serial:
        if (_transport is! SerialTransport) {
          throw "Wrong transport type";
        }
        _transportSubscription.cancel();
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
        throw StateError('Unknown transport type: $_transportType');
    }

    await _transport.disconnect();
  }

  void _processSerialInput(String input) {
    _currentBuffer += input;

    // Split by newlines — preserves partials if any
    final lines = _currentBuffer.split('\n');

    // All complete lines except the last (which may be incomplete)
    for (int i = 0; i < lines.length - 1; i++) {
      final line = lines[i].trim();
      if (line.isNotEmpty && line.startsWith('[')) {
        _log.finest("received complete response: $line");
        _processDe1Response(line);
      } else {
        _log.finest("Ignored invalid or incomplete line: '$line'");
      }
    }

    // Save the last (possibly incomplete) line back into the buffer
    _currentBuffer = lines.last;
  }

  void _processDe1Response(String input) {
    _log.finest("processing input: $input");
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

  void _shotSampleNotification(ByteData d) {
    _shotSampleSubject.add(d);
  }

  void _stateNotification(ByteData d) {
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

  Future<ByteData> read(Endpoint e) async {
    if (await _transport.connectionState.first != true) {
      throw ("de1 not connected");
    }

    switch (_transportType) {
      case TransportType.ble:
        return _bleRead(e);
      case TransportType.serial:
        return _serialRead(e);
      default:
        throw ("Unknown transport type: $_transportType");
    }
  }

  Future<ByteData> _bleRead(Endpoint e) async {
    if (_transport is! BLETransport) {
      throw "Invalid transport type, expected BLE";
    }
    var data = await _transport.read(de1ServiceUUID, e.uuid);
    ByteData response = ByteData.sublistView(Uint8List.fromList(data));
    return response;
  }

  Future<ByteData> _serialRead(Endpoint e) async {
    if (_transportType != TransportType.serial) {
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

  Future<void> write(Endpoint e, Uint8List data) async {
    if (await _transport.connectionState.first != true) {
      throw ("de1 not connected");
    }
    try {
      _log.fine('about to write to ${e.name}');
      _log.fine(
        'payload: ${data.map((el) => el.toRadixString(16).padLeft(2, '0')).join(' ')}',
      );

      switch (_transportType) {
        case TransportType.ble:
          await _bleWrite(e, data, false);
          break;
        case TransportType.serial:
          await _serialWrite(e, data);
          break;
        default:
          throw ("Unknown transport type: $_transportType");
      }
    } catch (e, st) {
      _log.severe("failed to write", e, st);
      rethrow;
    }
  }

  Future<void> writeWithResponse(Endpoint e, Uint8List data) async {
    if (await _transport.connectionState.first != true) {
      throw ("de1 not connected");
    }
    try {
      _log.fine('about to write to ${e.name}');
      _log.fine(
        'payload: ${data.map((el) => el.toRadixString(16).padLeft(2, '0')).join(' ')}',
      );
      switch (_transportType) {
        case TransportType.ble:
          await _bleWrite(e, data, true);
          break;
        case TransportType.serial:
          await _serialWrite(e, data);
          break;
        default:
          throw ("Unknown transport type: $_transportType");
      }
    } catch (e, st) {
      _log.severe("failed to write", e, st);
      rethrow;
    }
  }

  Future<void> _serialWrite(Endpoint e, Uint8List data) async {
    if (_transport is! SerialTransport) {
      throw "Invalid transport type, expected Serial";
    }
    final payload = data
        .map((e) => e.toRadixString(16).padLeft(2, '0'))
        .join('');
    await _transport.writeCommand('<${e.representation}>$payload');
  }

  Future<void> _bleWrite(Endpoint e, Uint8List data, bool withResponse) async {
    if (_transport is! BLETransport) {
      throw "Invalid transport type, expected BLE";
    }

    await _transport.write(
      de1ServiceUUID,
      e.uuid,
      data,
      withResponse: withResponse,
    );
  }
}
