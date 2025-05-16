import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/serial_de1/serial_de1.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:reaprime/src/models/device/serial_port.dart';

import 'package:rxdart/subjects.dart';

import 'package:libserialport/libserialport.dart';

DeviceDiscoveryService createSerialService() => SerialServiceAndroid();

class SerialServiceAndroid implements DeviceDiscoveryService {
  final _log = Logger("Serial service");

  // StreamSubscription<UsbEvent>? _usbSerialSubscription;
  List<SerialDe1> _devices = [];

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
    _log.info("found devices: $list");
  }

  @override
  Future<void> scanForDevices() async {
    final list = SerialPort.availablePorts;
    _devices = list.map((id) {
      final port = SerialPort(id);
			final transport = _DesktopSerialPort(port: port);
      return SerialDe1(transport: transport);
    }).toList();
    _machineSubject.add(_devices);
  }

}

class _DesktopSerialPort implements SerialTransport {
  SerialPort _port;
  late Logger _log;

  _DesktopSerialPort({required SerialPort port}) : _port = port {
    _log = Logger("SerialPort:${port.name}");
  }

  @override
  Future<void> close() async {
    _portSubscription?.cancel();
    _port.close();
    _port.dispose();
  }

  @override
  bool get isReady => _port.isOpen;

  @override
  String get name => _port.name ?? "Unknown port";

  StreamSubscription<Uint8List>? _portSubscription;

  @override
  Future<void> open() async {
    await Future.microtask(() {
      if (_port.open(mode: 3) == false) {
        _log.warning("could not open port");
        throw "failed to open port: ${SerialPort.lastError}";
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
      _port.config = cfg;
      // _port.config = cfg;
      _log.fine("current config: ${_port.config.bits}");
      _log.fine("current config: ${_port.config.parity}");
      _log.fine("current config: ${_port.config.stopBits}");
      _log.fine("current config: ${_port.config.baudRate}");

      _log.fine("port opened");
      _portSubscription = SerialPortReader(_port).stream.listen((data) {
        final input = utf8.decode(data);
        _log.fine("received serial input: $input");
        _readController.add(input);
      });
      _log.fine("port subscribed: ${_portSubscription}");
    });
  }

  final StreamController<String> _readController =
      StreamController<String>.broadcast();
  @override
  Stream<String> get readStream => _readController.stream;

  @override
  Future<void> writeCommand(String command) async {
    await Future.microtask(() {
      _port.write(utf8.encode("$command\n"));
    });
  }
}
