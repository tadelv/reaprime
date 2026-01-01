import 'dart:async';

import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:rxdart/rxdart.dart';

class DeviceController {
  final List<DeviceDiscoveryService> _services;

  late Map<DeviceDiscoveryService, List<Device>> _devices;

  final _log = Logger("Device Controller");
  final BehaviorSubject<List<Device>> _deviceStream = BehaviorSubject.seeded(
    [],
  );
  
  final List<StreamSubscription> _serviceSubscriptions = [];

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
        final subscription = service.devices.listen((devices) => _serviceUpdate(service, devices));
        _serviceSubscriptions.add(subscription);
      } catch (e) {
        _log.warning("Service ${service} failed to init:", e);
      }
    }
    await scanForDevices(autoConnect: false);
  }

  bool _autoConnect = true;
  bool get shouldAutoConnect => _autoConnect;

  Future<void> scanForDevices({required bool autoConnect }) async {
    // throw out all disconnected devices
    _devices.forEach((_, devices) async {
      List<Device> devicesToRemove = [];
      for (var device in devices) {
        var state = await device.connectionState.first;
        if (state != ConnectionState.connected) {
          // devices.remove(device);
          devicesToRemove.add(device);
        }
      }
      for (var device in devicesToRemove) {
        devices.remove(device);
      }
    });
    final tmpAutoConnect = _autoConnect;
    _autoConnect = autoConnect;
    _deviceStream.add(devices);
    // Scan all services in parallel
    try {
      await Future.wait(
        _services.map((service) async {
          try {
            await service.scanForDevices();
            _log.info("Service $service scan completed");
            _deviceStream.add(_devices.values.expand((e) => e).toList());
          } catch (e, st) {
            _log.warning("Service $service failed to scan:", e, st);
          }
        }),
      );
    } finally {
      await Future.delayed(Duration(milliseconds: 200), () {
        _autoConnect = tmpAutoConnect;
        _log.info("_autoConnect restored to $tmpAutoConnect");
        _log.info("current devices: ${this.devices}");
      });
    }
  }

  _serviceUpdate(DeviceDiscoveryService service, List<Device> devices) {
    _devices[service] = devices;
    _deviceStream.add(this.devices);
  }

  void dispose() {
    for (var subscription in _serviceSubscriptions) {
      subscription.cancel();
    }
    _serviceSubscriptions.clear();
    _deviceStream.close();
  }
}
