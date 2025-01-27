import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/machine.dart';

class DeviceController extends ChangeNotifier {
  final List<DeviceDiscoveryService> _services;

  late Map<DeviceDiscoveryService, List<Device>> _devices;

  final StreamController<List<Device>> _deviceStream = StreamController.broadcast();

  Stream<List<Device>> get deviceStream => _deviceStream.stream;

  List<Device> get devices =>
      _devices.values.fold(List<Device>.empty(growable: true), (res, el) {
        res.addAll(el);
        return res;
      }).toList();

  DeviceController(this._services) {
    _devices = {};
  }

  Future<void> initialize() async {
    for (var service in _services) {
      await service.initialize();
      service.devices.listen((devices) => _serviceUpdate(service, devices));
      await service.scanForDevices();
    }
  }

  _serviceUpdate(DeviceDiscoveryService service, List<Device> devices) {
    _devices[service] = devices;
    _deviceStream.add(this.devices);
    notifyListeners();
  }

  Future<Machine> connectMachine(Device device) async {
    DeviceDiscoveryService? service;
    _devices.forEach((s, v) {
      if (v.contains(device)) {
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
