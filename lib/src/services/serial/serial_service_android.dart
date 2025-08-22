import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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

  List<Device> _devices = [];
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
    _log.info("found ${devices}");

    UsbSerial.usbEventStream?.listen((data) {
      switch (data.event) {
        case UsbEvent.ACTION_USB_DETACHED:
          // we lost connectivity, disconnect all devices.
          for (Device d in _devices) {
            d.disconnect();
          }
          _devices.clear();
          _machineSubject.add(_devices);
          break;
        default:
          // require user initiated scan for now
          break;
      }
    });
  }

  @override
  Future<void> scanForDevices() async {
    _devices.clear();
    final devices = await UsbSerial.listDevices();
    final results = await Future.wait(devices.map((d) async {
      try {
        final device = await _detectDevice(d);
        _log.info("Port $d -> ${device ?? 'no device'}");
        return device;
      } catch (e, st) {
        _log.warning("Error detecting device on $d", e, st);
        return null;
      }
    }));
    _devices = results.whereType<Device>().toList();
    _machineSubject.add(_devices);
  }

  Future<Device?> _detectDevice(UsbDevice device) async {
    final port = await device.create(UsbSerial.CH34x);
    if (port == null) {
      _log.warning("failed to add $device, port is null");
      return null;
    }
    final transport = AndroidSerialPort(device: device, port: port);
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
        // FIXME: connect in controller
        final basket = SensorBasket(transport: transport);
        await basket.onConnect();
        return basket;
        // return SensorBasketSerial(transport: transport);
      } else if (isDE1(dataString, combined)) {
        _log.info("Detected: DE1 Machine");
        return SerialDe1(transport: transport);
      }

      _log.warning("Unknown device on port $device");
      await transport.close();
      return null;
    } catch (e, st) {
      _log.warning("Port $device is probably not a device we want", e, st);
      await transport.close();
      return null;
    }
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
      115200,
      UsbPort.DATABITS_8,
      UsbPort.STOPBITS_1,
      UsbPort.PARITY_NONE,
    );

    // TODO: onError close stream
    _portSubscription = _port.inputStream?.listen((Uint8List event) {
      _rawController.add(event);
      try {
        final input = utf8.decode(event);
        _log.finest("received serial input: $input");
        _outputController.add(input);
      } catch (e) {
        _log.fine("unable to parse to string", e);
      }
    });
  }

  final StreamController<Uint8List> _rawController =
      StreamController<Uint8List>.broadcast();

  @override
  Stream<Uint8List> get rawStream => _rawController.stream;

  final StreamController<String> _outputController =
      StreamController<String>.broadcast();

  @override
  Stream<String> get readStream => _outputController.stream;

  @override
  Future<void> writeCommand(String command) async {
    await _port.write(utf8.encode('$command\n'));
    _log.fine("wrote request: $command");
  }

  @override
  Future<void> writeHexCommand(Uint8List command) async {
    await _port.write(command);
    _log.fine("wrote request: ${command.map((e) => e.toRadixString(16))}");
  }
}
