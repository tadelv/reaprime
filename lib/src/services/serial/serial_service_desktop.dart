import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/decent_scale/scale_serial.dart';
import 'package:reaprime/src/models/device/impl/sensor/debug_port.dart';
import 'package:reaprime/src/models/device/impl/sensor/sensor_basket.dart';
import 'package:reaprime/src/models/device/impl/serial_de1/serial_de1.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:reaprime/src/models/device/transport/serial_port.dart';
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

  final BehaviorSubject<List<Device>> _machineSubject = BehaviorSubject.seeded(
    <Device>[],
  );
  @override
  Stream<List<Device>> get devices => _machineSubject.stream;

  @override
  Future<void> disconnect(Device device) {
    // TODO: implement disconnect
    throw UnimplementedError();
  }

  @override
  Future<void> initialize() async {
    final list = SerialPort.availablePorts;
    _log.info("Initializing");
    _log.info("found ports: $list");
  }

  @override
  Future<void> scanForDevices() async {
    final ports = SerialPort.availablePorts;
    _log.info("Found ports: $ports");

    List<Device> connected = [];
    for (var d in _devices) {
      final state = await d.connectionState.first;
      if (state == ConnectionState.connected) {
        connected.add(d);
      }
    }
    final scanPorts = ports.where(
      (p) => connected.map((e) => e.deviceId).contains(p) == false,
    );

    final results = <Device?>[];

    for (final portId in scanPorts) {
      try {
        results.add(await _detectDevice(portId));
      } catch (e, st) {
        _log.warning("Error detecting device on $portId", e, st);
        results.add(null);
      }
    }
    results.addAll(connected);

    _devices = results.whereType<Device>().toList();
    _machineSubject.add(_devices);
    _log.info("Added devices: $_devices");
  }

  Future<Device?> _detectDevice(String id) async {
    final port = SerialPort(id);
    if (port.transport.toTransport() != 'USB') {
      return null;
    }
    final transport = _DesktopSerialPort(port: port);
    final rawData = <Uint8List>[];
    const readDuration = Duration(milliseconds: 800);
    _log.fine("Inspecting: ${port.name}, ${port.productName}");

    // De1 shortcut
    if (port.productName == "DE1") {
      return SerialDe1(transport: transport);
    }

    try {
      await transport.disconnect();

      // Collect data with a timeout rather than a fixed delay
      final subscription = transport.rawStream.listen(rawData.add);

      // Wait for data or timeout
      await subscription.asFuture<void>().timeout(
        readDuration,
        onTimeout: () async {
          await subscription.cancel();
        },
      );

      final combined = rawData.expand((e) => e).toList();
      final strings = rawData.map(utf8.decode).toList().join().split('\n');
      _log.info("Collected serial data: ${utf8.decode(combined)}");
      _log.info("parsed into strings: ${strings}");
      if (combined.isEmpty && strings.isEmpty) {
        throw ('no data collected');
      }
      if (strings.any((s) => s.startsWith('R '))) {
        return DebugPort(transport: transport);
      } else if (isDecentScale(strings, rawData)) {
        _log.info("Detected: Decent Scale");
        return HDSSerial(transport: transport);
      } else if (isSensorBasket(strings)) {
        _log.info("Detected: Sensor Basket");
        return SensorBasket(transport: transport);
      } else {
        // TODO: better DE1 detection
        final messages = <String>[];
        final stateSubscription = transport.readStream.listen(messages.add);

        // Send state commands without a fixed delay, but with timeout
        await transport.writeCommand('<+M>');
        try {
          await stateSubscription.asFuture<void>().timeout(
            readDuration,
            onTimeout: () async {
              await stateSubscription.cancel();
            },
          );
        } finally {
          await transport.writeCommand('<-M>');
        }

        if (isDE1(messages.join().split('\n'), combined)) {
          _log.info("Detected: DE1 Machine");
          return SerialDe1(transport: transport);
        }
      }

      _log.warning("Unknown device on port $id");
      await transport.disconnect();
      return null;
    } catch (e, st) {
      _log.warning("Port $id is probably not a device we want", e, st);
      await transport.disconnect();
      return null;
    }
  }
}

class _DesktopSerialPort implements SerialTransport {
  final SerialPort _port;
  late Logger _log;
  final BehaviorSubject<bool> _open = BehaviorSubject.seeded(false);

  @override
  Stream<bool> get connectionState => _open.asBroadcastStream();

  _DesktopSerialPort({required SerialPort port}) : _port = port {
    _log = Logger("SerialPort:${port.name}");
  }

  @override
  Future<void> disconnect() async {
    _portSubscription?.cancel();
    _port.close();
    _open.add(false);
  }

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
  Future<void> connect() async {
    if (_port.isOpen) {
      _log.warning("already open");
      return;
    }
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
      _portSubscription = SerialPortReader(_port).stream.listen(
        (data) {
          _rawStreamController.add(data);
          try {
            final input = utf8.decode(data);
            _log.finest("received serial input: $input");
            _readController.add(input);
          } catch (e) {
            _log.fine("unable to parse serial input to string", e);
          }
        },
        onError: (error) {
          _log.severe("port error:", error);
          _readController.addError(error);
          _readController.close();
          disconnect();
        },
      );
      _log.fine("port subscribed: ${_portSubscription}");
    });
    _open.add(true);
  }

  final StreamController<String> _readController =
      StreamController<String>.broadcast();
  @override
  Stream<String> get readStream => _readController.stream;

  @override
  Future<void> writeCommand(String command) async {
    await _write(utf8.encode("$command\n"));
    _log.fine("wrote: $command");
  }

  @override
  Future<void> writeHexCommand(Uint8List command) async {
    await _write(command);
  }

  Future<void> _write(Uint8List command) async {
    await Future.microtask(() async {
      _port.write(command);
      _log.fine("wrote: ${command.map((e) => e.toRadixString(16))}");
      if (Platform.isLinux) {
        await Future.delayed(Duration(milliseconds: 20), () {
          _log.finest("delaying next write");
        });
      }
    });
  }
}

extension IntToString on int {
  String toHex() => '0x${toRadixString(16)}';
  String toPadded([int width = 3]) => toString().padLeft(width, '0');
  String toTransport() {
    switch (this) {
      case SerialPortTransport.usb:
        return 'USB';
      case SerialPortTransport.bluetooth:
        return 'Bluetooth';
      case SerialPortTransport.native:
        return 'Native';
      default:
        return 'Unknown';
    }
  }
}
