import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:rxdart/subjects.dart';

import 'package:libserialport/libserialport.dart';

DeviceDiscoveryService createSerialService() => SerialServiceAndroid();

class SerialServiceAndroid implements DeviceDiscoveryService {
  final _log = Logger("Serial service");

  // StreamSubscription<UsbEvent>? _usbSerialSubscription;
  List<SerialDevice> _devices = [];
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
    final list = SerialPort.availablePorts;
    _log.shout("found devices: $list");
  }

  @override
  Future<void> scanForDevices() async {
    final list = SerialPort.availablePorts;
    _devices = list.map((id) => SerialDevice(id: id)).toList();
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

class SerialDevice implements Device {
  final String _id;

  SerialDevice({required String id}) : _id = id;
  @override
  // TODO: implement connectionState
  Stream<ConnectionState> get connectionState =>
      BehaviorSubject.seeded(ConnectionState.connected).stream;

  @override
  // TODO: implement deviceId
  String get deviceId => _id;

  @override
  disconnect() {
    // TODO: implement disconnect
    throw UnimplementedError();
  }

  @override
  // TODO: implement name
  String get name => "Serial device";

  @override
  Future<void> onConnect() {
    // TODO: implement onConnect
    throw UnimplementedError();
  }

  @override
  // TODO: implement type
  DeviceType get type => DeviceType.machine;
}

// TODO: implements De1 (and Scale?)
class _SerialDE1 implements Machine {
  final _log = Logger("Serial device");
  SerialPort _port;

  StreamSubscription<Uint8List>? _portSubscription;

  _SerialDE1({required SerialPort port}) : _port = port {
    _portSubscription = SerialPortReader(_port).stream.listen((data) {
      _log.finest("received serial input:");
      // TODO: process data
    });
  }

  @override
  Stream<ConnectionState> get connectionState =>
      BehaviorSubject.seeded(ConnectionState.connected);

  @override
  // TODO: implement currentSnapshot
  Stream<MachineSnapshot> get currentSnapshot => throw UnimplementedError();

  @override
  // TODO: implement deviceId
  String get deviceId => throw UnimplementedError();

  @override
  disconnect() {
    // TODO: implement disconnect
    throw UnimplementedError();
  }

  @override
  // TODO: implement name
  String get name => throw UnimplementedError();

  @override
  Future<void> onConnect() {
    // TODO: implement onConnect
    throw UnimplementedError();
  }

  @override
  Future<void> requestState(MachineState newState) {
    // TODO: implement requestState
    throw UnimplementedError();
  }

  @override
  // TODO: implement type
  DeviceType get type => throw UnimplementedError();
}
