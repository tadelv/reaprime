import 'dart:async';
import 'dart:math';
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
import 'package:reaprime/src/models/device/de1_firmwaremodel.dart';
import 'package:rxdart/streams.dart';
import 'package:rxdart/subjects.dart';

part 'serial_de1.parsing.dart';
part 'serial_de1.mmr.dart';
part 'serial_de1.profile.dart';
part 'serial_de1.firmware.dart';

class SerialDe1 implements De1Interface {
  late Logger _log;
  final SerialTransport _transport;

  SerialDe1({required SerialTransport transport}) : _transport = transport {
    _log = Logger("Serial De1/${_transport.name}");
  }

  final BehaviorSubject<ConnectionState> _connectionStateSubject =
      BehaviorSubject.seeded(ConnectionState.connecting);

  @override
  Stream<ConnectionState> get connectionState => _connectionStateSubject.stream;

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
  Stream<MachineSnapshot> get currentSnapshot => _snapshotSubject.stream;

  @override
  String get deviceId => _transport.name;

  @override
  disconnect() {
    _connectionStateSubject.add(ConnectionState.disconnecting);
    try {
      _transportSubscription.cancel();
      _transport.close();
    } catch (e, st) {
      _log.warning("failed to close transport:", e, st);
    }
    _connectionStateSubject.add(ConnectionState.disconnected);
  }

  @override
  String get name => _transport.name;

  late StreamSubscription<String> _transportSubscription;
  StreamController<List<int>> _mmrController = StreamController.broadcast();

  @override
  Future<void> onConnect() async {
    _log.fine("connecting to device");
    try {
      await _transport.open();
    } catch (e, st) {
      _log.severe("failed to open transport", e, st);
      disconnect();
      return;
    }

    _transportSubscription = _transport.readStream.listen(_processSerialInput);

    _log.fine("port opened");
    _connectionStateSubject.add(ConnectionState.connected);

    // stop all previous notifies (if any) - just in case.

    await _sendCommand("<-N>");
    await _sendCommand("<-M>");
    await _sendCommand("<-Q>");
    await _sendCommand("<-K>");
    await _sendCommand("<-E>");

    // TODO: needed to know which state we're at?
    await requestState(MachineState.sleeping);

    await _sendCommand("<+N>");
    await _sendCommand("<+M>");
    await _sendCommand("<+Q>");
    await _sendCommand("<+K>");
    await _sendCommand("<+E>");
    updateShotSettings(De1ShotSettings(
        steamSetting: 0,
        targetSteamTemp: 150,
        targetSteamDuration: 60,
        targetHotWaterTemp: 70,
        targetHotWaterVolume: 50,
        targetHotWaterDuration: 30,
        targetShotVolume: 0,
        groupTemp: 90.0));
    _snapshotSubject.add(_currentSnapshot);
    _readySubject.add(true);
  }

  Future<void> _sendCommand(String command) async {
    try {
      await _transport.writeCommand(command);
    } catch (e, st) {
      _log.severe("failed to write to transport", e, st);
      // TODO: disconnect here?
    }
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
        _log.finest("received complete response: $line");
        _processDe1Response(line);
      } else {
        _log.warning("Ignored invalid or incomplete line: '$line'");
      }
    }

    // Save the last (possibly incomplete) line back into the buffer
    _currentBuffer = lines.last;
  }

  // TODO: allow code to register own processors per "Endpoint"
  void _processDe1Response(String input) {
    _log.fine("processing input: $input");
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
      case "[I]":
        _parseFWMapRequest(data);
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
    await _sendCommand(command);
  }

  @override
  DeviceType get type => DeviceType.machine;

  @override
  // TODO: implement rawOutStream
  Stream<De1RawMessage> get rawOutStream => throw UnimplementedError();

  BehaviorSubject<bool> _readySubject = BehaviorSubject.seeded(false);
  @override
  Stream<bool> get ready => _readySubject.stream;

  @override
  void sendRawMessage(De1RawMessage message) {
    _sendCommand(message.payload);
  }

  @override
  Future<void> setWaterLevelWarning(int newThresholdPercentage) {
    ByteData value = ByteData(4);
    try {
      // 00 00 0c 00
      // 00 00 00 07
      value.setInt16(0, 0, Endian.big);
      value.setInt16(2, newThresholdPercentage * 256, Endian.big);

      return _sendCommand(
          "<Q>${value.buffer.asUint8List().map((e) => e.toRadixString(16).padLeft(2, '0')).join()}");
    } catch (e) {
      _log.severe("failed to set water warning", e);
      rethrow;
    }
  }

  final BehaviorSubject<De1ShotSettings> _shotSettingsController =
      BehaviorSubject();
  @override
  Stream<De1ShotSettings> get shotSettings =>
      _shotSettingsController.asBroadcastStream();

  @override
  Future<void> updateShotSettings(De1ShotSettings newSettings) async {
    Uint8List data = Uint8List(9);

    int index = 0;
    data[index] = newSettings.steamSetting;
    index++;
    data[index] = newSettings.targetSteamTemp;
    index++;
    data[index] = newSettings.targetSteamDuration;
    index++;
    data[index] = newSettings.targetHotWaterTemp;
    index++;
    data[index] = newSettings.targetHotWaterVolume;
    index++;
    data[index] = newSettings.targetHotWaterDuration;
    index++;
    data[index] = newSettings.targetShotVolume;
    index++;

    data[index] = newSettings.groupTemp.toInt();
    index++;
    data[index] =
        ((newSettings.groupTemp - newSettings.groupTemp.floor()) * 256.0)
            .toInt();
    index++;

    await _sendCommand(
        "<K>${data.map((e) => e.toRadixString(16).padLeft(2, '0')).toList()}");
    // await _parseShotSettings(await _read(Endpoint.shotSettings));
    _parseShotSettings(ByteData.sublistView(data));
  }

  BehaviorSubject<De1WaterLevels> _waterSubject = BehaviorSubject();
  @override
  Stream<De1WaterLevels> get waterLevels => _waterSubject.stream;

  @override
  Future<void> setProfile(Profile profile) async {
    await _sendProfile(profile);
  }

  // MMR

  @override
  Future<bool> getUsbChargerMode() async {
    var result = await _mmrRead(MMRItem.allowUSBCharging);
    return _unpackMMRInt(result) == 1;
  }

  @override
  Future<void> setUsbChargerMode(bool t) async {
    await _mmrWrite(MMRItem.allowUSBCharging, _packMMRInt(t ? 1 : 0));
  }

  @override
  Future<int> getFanThreshhold() async {
    var result = await _mmrRead(MMRItem.fanThreshold);
    return _unpackMMRInt(result);
  }

  @override
  Future<void> setFanThreshhold(int temp) async {
    await _mmrWrite(MMRItem.fanThreshold, _packMMRInt(min(50, temp)));
  }

  @override
  Future<double> getSteamFlow() async {
    var result = await _mmrRead(MMRItem.targetSteamFlow);
    return _unpackMMRInt(result).toDouble() / 100;
  }

  @override
  Future<void> setSteamFlow(double newFlow) async {
    var value = _packMMRInt((newFlow * 100).toInt());
    await _mmrWrite(MMRItem.targetSteamFlow, value);
  }

  @override
  Future<double> getHotWaterFlow() async {
    var result = await _mmrRead(MMRItem.hotWaterFlowRate);
    return _unpackMMRInt(result).toDouble() / 10;
  }

  @override
  Future<void> setHotWaterFlow(double newFlow) async {
    var value = _packMMRInt((newFlow * 10).toInt());
    await _mmrWrite(MMRItem.hotWaterFlowRate, value);
  }

  @override
  Future<double> getFlushFlow() async {
    var result = await _mmrRead(MMRItem.flushFlowRate);
    return _unpackMMRInt(result).toDouble() / 10;
  }

  @override
  Future<void> setFlushFlow(double newFlow) async {
    var value = _packMMRInt((newFlow * 10).toInt());
    await _mmrWrite(MMRItem.flushFlowRate, value);
  }

  @override
  Future<double> getFlushTimeout() async {
    var result = await _mmrRead(MMRItem.flushTimeout);
    return _unpackMMRInt(result).toDouble() / 10;
  }

  @override
  Future<void> setFlushTimeout(double newTimeout) async {
    var value = _packMMRInt((newTimeout * 10).toInt());
    await _mmrWrite(MMRItem.flushTimeout, value);
  }

  @override
  Future<double> getFlushTemperature() async {
    var result = await _mmrRead(MMRItem.flushTemp);
    return _unpackMMRInt(result).toDouble() / 10;
  }

  @override
  Future<void> setFlushTemperature(double newTemp) async {
    var value = _packMMRInt((newTemp * 10).toInt());
    await _mmrWrite(MMRItem.flushTemp, value);
  }

  @override
  Future<int> getTankTempThreshold() async {
    var result = await _mmrRead(MMRItem.tankTemp);
    return _unpackMMRInt(result);
  }

  @override
  Future<void> setTankTempThreshold(int temp) async {
    var value = _packMMRInt(temp);
    await _mmrWrite(MMRItem.tankTemp, value);
  }

  @override
  Future<double> getHeaterIdleTemp() async {
    var result = await _mmrRead(MMRItem.waterHeaterIdleTemp);
    return _unpackMMRInt(result).toDouble() / 10;
  }

  @override
  Future<double> getHeaterPhase1Flow() async {
    var result = await _mmrRead(MMRItem.heaterUp1Flow);
    return _unpackMMRInt(result).toDouble() / 10;
  }

  @override
  Future<double> getHeaterPhase2Flow() async {
    var result = await _mmrRead(MMRItem.heaterUp2Flow);
    return _unpackMMRInt(result).toDouble() / 10;
  }

  @override
  Future<double> getHeaterPhase2Timeout() async {
    var result = await _mmrRead(MMRItem.heaterUp2Timeout);
    return _unpackMMRInt(result).toDouble() / 10;
  }

  @override
  Future<void> setHeaterIdleTemp(double val) async {
    var value = _packMMRInt((val * 10).toInt());
    await _mmrWrite(MMRItem.waterHeaterIdleTemp, value);
  }

  @override
  Future<void> setHeaterPhase1Flow(double val) async {
    var value = _packMMRInt((val * 10).toInt());
    await _mmrWrite(MMRItem.heaterUp1Flow, value);
  }

  @override
  Future<void> setHeaterPhase2Flow(double val) async {
    var value = _packMMRInt((val * 10).toInt());
    await _mmrWrite(MMRItem.heaterUp2Flow, value);
  }

  @override
  Future<void> setHeaterPhase2Timeout(double val) async {
    var value = _packMMRInt((val * 10).toInt());
    await _mmrWrite(MMRItem.heaterUp2Timeout, value);
  }

  @override
  Future<void> updateFirmware(Uint8List fwImage,
      {required void Function(double) onProgress}) async {
    await _updateFirmware(fwImage, onProgress);
  }
}
