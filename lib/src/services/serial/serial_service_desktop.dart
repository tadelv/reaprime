import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/decent_scale/scale_serial.dart';
import 'package:reaprime/src/models/device/impl/sensor/sensor_basket.dart';
import 'package:reaprime/src/models/device/impl/serial_de1/serial_de1.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:reaprime/src/models/device/serial_port.dart';
import 'utils.dart';

import 'package:rxdart/subjects.dart';

import 'package:libserialport/libserialport.dart';

class SerialServiceDesktop implements DeviceDiscoveryService {
  final _log = Logger("Serial service");

  // StreamSubscription<UsbEvent>? _usbSerialSubscription;
  List<Device> _devices = [];

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
    final ports = SerialPort.availablePorts;
    _log.info("Found ports: $ports");

    // Check each port individually to avoid failures breaking the loop
    final results = await Future.wait(
      ports.map((portId) async {
        try {
          final device = await _detectDevice(portId);
          _log.info("Port $portId -> ${device ?? 'no device'}");
          return device;
        } catch (e, st) {
          _log.warning("Error detecting device on $portId", e, st);
          return null;
        }
      }),
    );

    // Keep only valid devices
    _devices = results.whereType<Device>().toList();

    // Notify observers
    _machineSubject.add(_devices);
    _log.info("Added devices: $_devices");
  }

  Future<Device?> _detectDevice(String id) async {
    final port = SerialPort(id);
    final transport = _DesktopSerialPort(port: port);
    final List<Uint8List> rawData = [];
    final duration = const Duration(seconds: 3);

    try {
      await transport.open();

      // Start listening to the stream
      final subscription = transport.rawStream.listen(
        (chunk) {
          rawData.add(chunk);
        },
        onError: (err, st) => _log.warning("Serial read error", err, st),
        cancelOnError: false,
      );

      // Collect for the desired duration
      await Future.delayed(duration);
      await subscription.cancel();

      // Combine all chunks into one buffer
      final combined = rawData.expand((e) => e).toList();
      final dataString = String.fromCharCodes(combined);
      final strings = rawData.map((e) => String.fromCharCodes(e)).toList();
      _log.info("Collected serial data: $dataString");

      // Heuristic checks for device type
      if (isDecentScale(strings, rawData)) {
        _log.info("Detected: Decent Scale");
        return HDSSerial(transport: transport);
      } else if (isSensorBasket(strings)) {
        _log.info("Detected: Sensor Basket");
        return SensorBasket(transport: transport);
      } else {
        // try and check if we get some replies when subscribing to state
        final List<String> messages = [];
        final sub = transport.readStream.listen((line) {
          messages.add(line);
        });
        await transport.writeCommand('<+M>');
        await Future.delayed(duration);
        await transport.writeCommand('<-M>');
        sub.cancel();
        final List<String> lines = messages.join().split('\n');
        if (isDE1(lines, combined)) {
          _log.info("Detected: DE1 Machine");
          return SerialDe1(transport: transport);
        }
      }

      _log.warning("Unknown device on port $id");
      await transport.close();
      return null;
    } catch (e, st) {
      _log.warning("Port $id is probably not a device we want", e, st);
      await transport.close();
      return null;
    }
  }
}

class _DesktopSerialPort implements SerialTransport {
  final SerialPort _port;
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
  String get id => "${_port.address}";

  @override
  String get name => _port.name ?? "Unknown port";

  StreamSubscription<Uint8List>? _portSubscription;

  final StreamController<Uint8List> _rawStreamController =
      StreamController<Uint8List>.broadcast();

  @override
  Stream<Uint8List> get rawStream => _rawStreamController.stream;

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
      _log.finest("current config: ${_port.config.bits}");
      _log.finest("current config: ${_port.config.parity}");
      _log.finest("current config: ${_port.config.stopBits}");
      _log.finest("current config: ${_port.config.baudRate}");

      _log.fine("port opened");
      _portSubscription = SerialPortReader(_port).stream.listen((data) {
        _rawStreamController.add(data);
        try {
          final input = utf8.decode(data);
          _log.finest("received serial input: $input");
          _readController.add(input);
        } catch (e) {
          _log.fine("unable to parse serial input to string", e);
        }
      }, onError: (error) {
        _log.severe("port error:", error);
        _readController.addError(error);
        _readController.close();
        close();
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
      _log.fine("wrote: $command");
    });
  }

  @override
  Future<void> writeHexCommand(Uint8List command) async {
    await Future.microtask(() {
      _port.write(command);
      _log.fine("wrote: ${command.map((e) => e.toRadixString(16))}");
    });
  }
}
