import 'dart:async';

import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:rxdart/rxdart.dart';

class DeviceController {
  final List<DeviceDiscoveryService> _services;

  late Map<DeviceDiscoveryService, List<Device>> _devices;

  final BehaviorSubject<List<Device>> _deviceStream =
      BehaviorSubject.seeded([]);

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
      try {
        await service.initialize();
        service.devices.listen((devices) => _serviceUpdate(service, devices));
      } catch (e) {
        Logger("DeviceController")
            .warning("Service ${service} failed to init:", e);
      }
    }
    await scanForDevices();
  }

  Future<void> scanForDevices() async {
    // throw out all disconnected devices
    _devices.forEach((_, devices) async {
      for (var device in devices) {
        var state = await device.connectionState.first;
        if (state != ConnectionState.connected) {
          devices.remove(device);
        }
      }
    });
    _deviceStream.add(devices);
    for (var service in _services) {
      try {
        await service.scanForDevices();
      } catch (e) {
        Logger("DeviceController")
            .warning("Service ${service} failed to scan:", e);
      }
    }
  }

  _serviceUpdate(DeviceDiscoveryService service, List<Device> devices) {
    _devices[service] = devices;
    _deviceStream.add(this.devices);
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
