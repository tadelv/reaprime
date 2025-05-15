import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/de1_rawmessage.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.utils.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:rxdart/subjects.dart';

import 'package:libserialport/libserialport.dart';

DeviceDiscoveryService createSerialService() => SerialServiceAndroid();

class SerialServiceAndroid implements DeviceDiscoveryService {
  final _log = Logger("Serial service");

  // StreamSubscription<UsbEvent>? _usbSerialSubscription;
  List<_SerialDE1> _devices = [];
  Machine? _connectedMachine;

  @override
  Future<Machine> connectToMachine({String? deviceId}) {
    // TODO: implement connectToMachine
    throw UnimplementedError();
  }

  @override
  Future<Scale> connectToScale({String? deviceId}) {
    // TODO: implement connectToScale
    throw UnimplementedError();
  }

  final BehaviorSubject<List<Device>> _machineSubject =
      BehaviorSubject.seeded(<Device>[]);
  @override
  Stream<List<Device>> get devices => _machineSubject.stream;

  @override
  Future<void> disconnect(Device device) {
    // TODO: implement disconnect
    throw UnimplementedError();
  }

  @override
  Future<void> initialize() async {
    final list = await SerialPort.availablePorts;
    _log.shout("found devices: $list");
  }

  @override
  Future<void> scanForDevices() async {
    final list = await SerialPort.availablePorts;
    _devices = list.map((id) {
      final port = SerialPort(id);
      return _SerialDE1(port: port);
    }).toList();
    _machineSubject.add(_devices);
  }

  Future<void> _processDevices() async {
    // if (_devices.isEmpty) {
    //   _connectedMachine = null;
    //   _machineSubject.add([]);
    //   return;
    // }
    // if (_connectedMachine != null) {
    //   return;
    // }
    // UsbDevice? de1 = _devices.firstWhereOrNull((e) => e.deviceName == "DE1");
    // if (de1 == null) {
    //   return;
    // }
    // UsbPort? port = await de1.create();
    // if (port == null) {
    //   return;
    // }
    // if (await port.open() == false) {
    //   return;
    // }
    // _connectedMachine = _SerialDE1(port: port);
  }
}

class _SerialDE1 implements De1Interface {
  late Logger _log;
  SerialPort _port;

  StreamSubscription<Uint8List>? _portSubscription;

  _SerialDE1({required SerialPort port}) : _port = port {
    _log = Logger("Serial: ${port.name}");
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
  String get deviceId => '${_port.name ?? "unknown port" }';

  @override
  disconnect() {
    // TODO: implement disconnect
    throw UnimplementedError();
  }

  @override
  // TODO: implement name
  String get name => _port.description ?? "Serial de1";

  @override
  Future<void> onConnect() async {
    _log.fine("connecting to device");
    await Future.microtask(() async {
      // _port.openRead();
      // _port.openWrite();
      if (await _port.open(mode: 3) == false) {
        _log.warning("could not open port");
        return;
      }
      final SerialPortConfig cfg = SerialPortConfig();
      cfg.baudRate = 115200;
      cfg.bits = 8;
      cfg.parity = 0;
      cfg.stopBits = 1;
      cfg.rts = 0;
      cfg.cts = 0;
      cfg.dtr = 0;
      cfg.dsr = 0;
      cfg.xonXoff = 0;
      cfg.setFlowControl(0);
			await _port.setConfig(cfg);
      // _port.config = cfg;
      _log.info("current config: ${_port.config.bits}");
      _log.info("current config: ${_port.config.parity}");
      _log.info("current config: ${_port.config.stopBits}");
      _log.info("current config: ${_port.config.baudRate}");

      _log.fine("port opened");
      // await _writeToPort("(D)ISCONNECTED");
      // await _writeToPort("(C)ONNECTED");
      // await _writeToPort("{F}00000001");
      // await _writeToPort("{C}00000001");
      // await _writeToPort("DE BLE Module");
      // await _writeToPort("<N>");
      await _writeToPort("<+N>");
      await _writeToPort("<+M>");
      // await _writeToPort("<+Q>");
      // _port.flush();
      _portSubscription = SerialPortReader(_port).stream.listen((data) {
        final input = utf8.decode(data);
        _log.fine("received serial input: $input");
        _log.fine("contains: ${input.contains('\n')}");
        _processSerialInput(input);
      });
      _log.fine("port subscribed: ${_portSubscription}");
      _log.fine("err: ${SerialPort.lastError}");
      // _readySubject.add(true);
      _snapshotSubject.add(_currentSnapshot);
    });
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
        final groupPressure = data.getUint16(2) / (1 << 12);
        final groupFlow = data.getUint16(4) / (1 << 12);
        final mixTemp = data.getUint16(6) / (1 << 8);
        final headTemp = ((data.getUint8(8) << 16) +
                (data.getUint8(9) << 8) +
                (data.getUint8(10))) /
            (1 << 16);
        final setMixTemp = data.getUint16(11) / (1 << 8);
        final setHeadTemp = data.getUint16(13) / (1 << 8);
        final setGroupPressure = data.getUint8(15) / (1 << 4);
        final setGroupFlow = data.getUint8(16) / (1 << 4);
        final frameNumber = data.getUint8(17);
        final steamTemp = data.getUint8(18);

        _currentSnapshot = _currentSnapshot.copyWith(
          timestamp: DateTime.now(),
          pressure: groupPressure,
          flow: groupFlow,
          mixTemperature: mixTemp,
          groupTemperature: headTemp,
          targetMixTemperature: setMixTemp,
          targetGroupTemperature: setHeadTemp,
          targetPressure: setGroupPressure,
          targetFlow: setGroupFlow,
          profileFrame: frameNumber,
          steamTemperature: steamTemp,
        );
      case "[N]":
        var state = De1StateEnum.fromHexValue(payload[0]);
        var subState =
            De1SubState.fromHexValue(payload[1]) ?? De1SubState.noState;
        _currentSnapshot = _currentSnapshot.copyWith(
          state: MachineStateSnapshot(
            state: mapDe1ToMachineState(state),
            substate: mapDe1SubToMachineSubstate(subState),
          ),
        );
      case "[Q]":
        _parseWaterLevels(data);
      default:
        break;
    }
    _snapshotSubject.add(_currentSnapshot);
  }

  _parseWaterLevels(ByteData data) {
    try {
      // notifyFrom(Endpoint.waterLevels, data.buffer.asUint8List());
      var waterlevel = data.getUint16(0, Endian.big);
      var waterThreshold = data.getUint16(2, Endian.big);

      De1WaterLevelData wlData = De1WaterLevelData(
        currentLevel: waterlevel,
        currentLimit: waterThreshold,
      );
      _waterSubject.add(
        De1WaterLevels(
          currentPercentage: wlData.getLevelPercent(),
          warningThresholdPercentage: 0,
        ),
      );
    } catch (e) {
      _log.severe("waternotify", e);
    }
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

  Future<void> _writeToPort(String command) async {
    // await Future.microtask(() {
    await _port.write(utf8.encode(command + '\n'), timeout: 250);
      // _port.write(utf8.encode('\n'), timeout: 100);
      // _port.drain();
      _log.fine("wrote request: $command");
    // });
  }

  @override
  Future<void> requestState(MachineState newState) async {
    final String value = De1StateEnum.fromMachineState(newState)
        .hexValue
        .toRadixString(16)
        .padLeft(2, "0");
    final String command = "<B>$value";
    return await _writeToPort(command);
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

  @override
  // TODO: implement shotSettings
  Stream<De1ShotSettings> get shotSettings => throw UnimplementedError();

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
