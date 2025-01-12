import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/machine.dart';

class DeviceController extends ChangeNotifier {
  final List<DeviceService> _services;

  late Map<DeviceService, Map<String, Device>> _devices;

  final StreamController<List<Device>> _deviceStream = StreamController();

  Stream<List<Device>> get deviceStream => _deviceStream.stream;

  List<Device> get devices =>
      _devices.values.fold(List<Device>.empty(growable: true), (res, el) {
        res.addAll(el.values);
        return res;
      }).toList();

  DeviceController(this._services) {
    _devices = {};
  }

  Future<void> initialize() async {
    for (var service in _services) {
      await service.initialize();
      service.addListener(() => _serviceUpdate(service, service.devices));
      await service.scanForDevices();
    }
  }

  _serviceUpdate(DeviceService service, Map<String, Device> devices) {
    _devices[service] = devices;
    _deviceStream.add(this.devices);
    notifyListeners();
  }

  Future<Machine> connectMachine(Device device) async {
    DeviceService? service;
    _devices.forEach((s, v) {
      if (v.containsKey(device.deviceId)) {
        service = s;
        return;
      }
    });

    if (service != null) {
      return service!.connectToMachine(deviceId: device.deviceId);
    }
    throw "Cant find service to use for device connection";
  }
}
