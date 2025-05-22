import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/serial_de1/serial_de1.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:reaprime/src/models/device/serial_port.dart';
import 'package:rxdart/subjects.dart';

import 'package:usb_serial/usb_serial.dart';

class SerialServiceAndroid implements DeviceDiscoveryService {
  final _log = Logger("Android Serial service");

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

  List<SerialDe1> _devices = [];
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
    List<UsbDevice> devices = await UsbSerial.listDevices();
    _log.shout("found ${devices}");
  }

  @override
  Future<void> scanForDevices() async {
    _devices.clear();
    final devices = await UsbSerial.listDevices();
    for (UsbDevice d in devices) {
      try {
        final port = await d.create();
        if (port != null) {
          final transport = AndroidSerialPort(device: d, port: port);
          _devices.add(SerialDe1(transport: transport));
        }
      } catch (e) {
        _log.warning("failed to add $d", e);
      }
    }
    _machineSubject.add(_devices);
  }
}

class AndroidSerialPort implements SerialTransport {
  final UsbDevice _device;
  final UsbPort _port;
  late Logger _log;
  bool _isReady = false;

  AndroidSerialPort({required UsbDevice device, required UsbPort port})
      : _device = device,
        _port = port {
    _log = Logger("Serial:${_device.deviceName}");
  }
  @override
  Future<void> close() async {
    _portSubscription?.cancel();
    await _port.close();
  }

  @override
  bool get isReady => _isReady;

  @override
  // TODO: implement name
  String get name => "${_device.deviceName}";

  StreamSubscription<Uint8List>? _portSubscription;
  @override
  Future<void> open() async {
    if (await _port.open() == false) {
      throw "Failed to open port";
    }

    await _port.setDTR(false);
    await _port.setRTS(false);

    _port.setPortParameters(
        115200, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);

    _portSubscription = _port.inputStream?.listen((Uint8List event) {
      final input = utf8.decode(event);
      _log.fine("received serial input: $input");
      _outputController.add(input);
    });
  }

  StreamController<String> _outputController = StreamController.broadcast();

  @override
  // TODO: implement readStream
  Stream<String> get readStream => _outputController.stream;

  @override
  Future<void> writeCommand(String command) async {
    await _port.write(utf8.encode('$command\n'));
    _log.fine("wrote request: $command");
  }
}
