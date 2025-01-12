import 'package:flutter/material.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/scale.dart';

enum DeviceType { machine, scale }

abstract class Device {
  String get deviceId;
  String get name;
  DeviceType get type;

  // discover and subscribe to services/characteristics
  Future<void> onConnect();
}

abstract class DeviceService extends ChangeNotifier {
  Map<String, Device> get devices;

  Future<void> initialize() async {
    throw "Not implemented yet";
  }

  Future<void> scanForDevices() async {
    throw "Not implemented yet";
  }

  // return machine with specific id
  Future<Machine> connectToMachine({String? deviceId}) async {
    throw "Not implemented yet";
  }

  // return scale with specific id
  Future<Scale> connectToScale({String? deviceId}) async {
    throw "Not implemented yet";
  }

  // disconnect (and dispose of?) device
  Future<void> disconnect(Device device) async {
    throw "Not implemented yet";
  }
}

// TODO: device - connection map somehow
// service needs to know, which device is which implementation
