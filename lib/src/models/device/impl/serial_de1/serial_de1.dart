import 'dart:async';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/de1_rawmessage.dart';
import 'package:reaprime/src/models/device/serial_port.dart';

import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.utils.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:rxdart/subjects.dart';

part 'serial_de1.parsing.dart';
part 'serial_de1.mmr.dart';

class SerialDe1 implements De1Interface {
  late Logger _log;
  final SerialTransport _transport;

  SerialDe1({required SerialTransport transport}) : _transport = transport {
    _log = Logger("Serial De1/${_transport.name}");
  }

  @override
  Stream<ConnectionState> get connectionState =>
      BehaviorSubject.seeded(ConnectionState.connected);

  MachineSnapshot _currentSnapshot = MachineSnapshot(
    flow: 0,
    state: MachineStateSnapshot(
      state: MachineState.booting,
      substate: MachineSubstate.idle,
    ),
    steamTemperature: 0,
    profileFrame: 0,
    targetFlow: 0,
    targetPressure: 0,
    targetMixTemperature: 0,
    targetGroupTemperature: 0,
    timestamp: DateTime.now(),
    groupTemperature: 0,
    mixTemperature: 0,
    pressure: 0,
  );
  BehaviorSubject<MachineSnapshot> _snapshotSubject = BehaviorSubject();
  @override
  // TODO: implement currentSnapshot
  Stream<MachineSnapshot> get currentSnapshot => _snapshotSubject.stream;

  @override
  // TODO: implement deviceId
  String get deviceId => _transport.name;

  @override
  disconnect() {
    _transportSubscription.cancel();
    _transport.close();
  }

  @override
  String get name => _transport.name;

  late StreamSubscription<String> _transportSubscription;
  StreamController<List<int>> _mmrController = StreamController();

  @override
  Future<void> onConnect() async {
    _log.fine("connecting to device");
    try {
      await _transport.open();
    } catch (e, st) {
      _log.severe("failed to open transport", e, st);
      return;
    }

    _transportSubscription = _transport.readStream.listen(_processSerialInput);

    _log.fine("port opened");
    await _transport.writeCommand("<+N>");
    await _transport.writeCommand("<+M>");
    await _transport.writeCommand("<+Q>");
    await _transport.writeCommand("<+K>");
    await _transport.writeCommand("<+E>");
    _snapshotSubject.add(_currentSnapshot);
  }

  String _currentBuffer = "";
  void _processSerialInput(String input) {
    _currentBuffer += input;

    // Split by newlines — preserves partials if any
    final lines = _currentBuffer.split('\n');

    // All complete lines except the last (which may be incomplete)
    for (int i = 0; i < lines.length - 1; i++) {
      final line = lines[i].trim();
      if (line.isNotEmpty && line.startsWith('[')) {
        _log.fine("received complete response: $line");
        _processDe1Response(line);
      } else {
        _log.warning("Ignored invalid or incomplete line: '$line'");
      }
    }

    // Save the last (possibly incomplete) line back into the buffer
    _currentBuffer = lines.last;
  }

  _processDe1Response(String input) {
    _log.info("processing input: $input");
    final Uint8List payload = hexToBytes(input.substring(3));
    final ByteData data = ByteData.sublistView(payload);
    switch (input.substring(0, 3)) {
      case "[M]":
        _parseShotSample(data);
      case "[N]":
        _parseState(data);
      case "[Q]":
        _parseWaterLevels(data);
      case "[K]":
        _parseShotSettings(data);
				case "[E]":
				_mmrNotification(data);
      default:
        _log.warning("unhandled de1 message: $input");
        break;
    }
    _snapshotSubject.add(_currentSnapshot);
  }

  /// Converts an even‑length hex string to the corresponding bytes.
  ///
  /// Throws a [FormatException] if the string length is odd or contains non‑hex digits.
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

  @override
  Future<void> requestState(MachineState newState) async {
    final String value = De1StateEnum.fromMachineState(newState)
        .hexValue
        .toRadixString(16)
        .padLeft(2, "0");
    final String command = "<B>$value";
    await _transport.writeCommand(command);
  }

  @override
  DeviceType get type => DeviceType.machine;

  @override
  Future<int> getFanThreshhold() {
    // TODO: implement getFanThreshhold
    throw UnimplementedError();
  }

  @override
  Future<double> getFlushFlow() {
    // TODO: implement getFlushFlow
    throw UnimplementedError();
  }

  @override
  Future<double> getFlushTemperature() {
    // TODO: implement getFlushTemperature
    throw UnimplementedError();
  }

  @override
  Future<double> getFlushTimeout() {
    // TODO: implement getFlushTimeout
    throw UnimplementedError();
  }

  @override
  Future<double> getHeaterIdleTemp() {
    // TODO: implement getHeaterIdleTemp
    throw UnimplementedError();
  }

  @override
  Future<double> getHeaterPhase1Flow() {
    // TODO: implement getHeaterPhase1Flow
    throw UnimplementedError();
  }

  @override
  Future<double> getHeaterPhase2Flow() {
    // TODO: implement getHeaterPhase2Flow
    throw UnimplementedError();
  }

  @override
  Future<double> getHeaterPhase2Timeout() {
    // TODO: implement getHeaterPhase2Timeout
    throw UnimplementedError();
  }

  @override
  Future<double> getHotWaterFlow() {
    // TODO: implement getHotWaterFlow
    throw UnimplementedError();
  }

  @override
  Future<double> getSteamFlow() {
    // TODO: implement getSteamFlow
    throw UnimplementedError();
  }

  @override
  Future<int> getTankTempThreshold() {
    // TODO: implement getTankTempThreshold
    throw UnimplementedError();
  }

  @override
  Future<bool> getUsbChargerMode() {
    // TODO: implement getUsbChargerMode
    throw UnimplementedError();
  }

  @override
  // TODO: implement rawOutStream
  Stream<De1RawMessage> get rawOutStream => throw UnimplementedError();

  BehaviorSubject<bool> _readySubject = BehaviorSubject.seeded(false);
  @override
  // TODO: implement ready
  Stream<bool> get ready => _readySubject.stream;

  @override
  void sendRawMessage(De1RawMessage message) {
    // TODO: implement sendRawMessage
  }

  @override
  Future<void> setFanThreshhold(int temp) {
    // TODO: implement setFanThreshhold
    throw UnimplementedError();
  }

  @override
  Future<void> setFlushFlow(double newFlow) {
    // TODO: implement setFlushFlow
    throw UnimplementedError();
  }

  @override
  Future<void> setFlushTemperature(double newTemp) {
    // TODO: implement setFlushTemperature
    throw UnimplementedError();
  }

  @override
  Future<void> setFlushTimeout(double newTimeout) {
    // TODO: implement setFlushTimeout
    throw UnimplementedError();
  }

  @override
  Future<void> setHeaterIdleTemp(double val) {
    // TODO: implement setHeaterIdleTemp
    throw UnimplementedError();
  }

  @override
  Future<void> setHeaterPhase1Flow(double val) {
    // TODO: implement setHeaterPhase1Flow
    throw UnimplementedError();
  }

  @override
  Future<void> setHeaterPhase2Flow(double val) {
    // TODO: implement setHeaterPhase2Flow
    throw UnimplementedError();
  }

  @override
  Future<void> setHeaterPhase2Timeout(double val) {
    // TODO: implement setHeaterPhase2Timeout
    throw UnimplementedError();
  }

  @override
  Future<void> setHotWaterFlow(double newFlow) {
    // TODO: implement setHotWaterFlow
    throw UnimplementedError();
  }

  @override
  Future<void> setProfile(Profile profile) {
    // TODO: implement setProfile
    throw UnimplementedError();
  }

  @override
  Future<void> setSteamFlow(double newFlow) {
    // TODO: implement setSteamFlow
    throw UnimplementedError();
  }

  @override
  Future<void> setTankTempThreshold(int temp) {
    // TODO: implement setTankTempThreshold
    throw UnimplementedError();
  }

  @override
  Future<void> setUsbChargerMode(bool t) {
    // TODO: implement setUsbChargerMode
    throw UnimplementedError();
  }

  @override
  Future<void> setWaterLevelWarning(int newThresholdPercentage) {
    // TODO: implement setWaterLevelWarning
    throw UnimplementedError();
  }

  final BehaviorSubject<De1ShotSettings> _shotSettingsController =
      BehaviorSubject();
  @override
  Stream<De1ShotSettings> get shotSettings =>
      _shotSettingsController.asBroadcastStream();

  @override
  Future<void> updateShotSettings(De1ShotSettings newSettings) {
    // TODO: implement updateShotSettings
    throw UnimplementedError();
  }

  BehaviorSubject<De1WaterLevels> _waterSubject = BehaviorSubject();
  @override
  // TODO: implement waterLevels
  Stream<De1WaterLevels> get waterLevels => _waterSubject.stream;
}
