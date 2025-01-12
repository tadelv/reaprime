import 'dart:async';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import '../models/device/device.dart';
import '../models/device/machine.dart';
import '../models/device/scale.dart';
import 'package:logging/logging.dart' as logging;

class BleDeviceService extends DeviceService {
  BleDeviceService(this.deviceMappings);

  Map<Uuid, Device Function(String)> deviceMappings;

  final Map<String, Device> _devices = {};

  late FlutterReactiveBle _ble;
  final log = logging.Logger("BleDeviceService");

  @override
  Map<String, Device> get devices => _devices;

  StreamSubscription<DiscoveredDevice>? _subscription;

  @override
  Future<void> initialize() async {
    _ble = FlutterReactiveBle();
    log.info("inting: ${_ble.status}");
    _ble.statusStream.listen((status) {
      log.fine("status change: ${status}");
      if (status == BleStatus.ready) {
        //scanForDevices();
      }
    });
  }

  @override
  Future<void> scanForDevices() async {
    _subscription = _ble
        .scanForDevices(
          withServices: deviceMappings.keys.toList(),
          scanMode: ScanMode.lowLatency,
          //requireLocationServicesEnabled: false,
        )
        .listen(
          (d) => _deviceScanned(d),
          onError: (e) {
            log.warning("failed: $e");
          },
        );

    Future.delayed(Duration(seconds: 30), () {
      _subscription?.cancel();
			log.info("stopping scan");
    });
  }

  // return machine with specific id
  @override
  Future<Machine> connectToMachine({String? deviceId}) async {
    throw "Not implemented yet";
  }

  // return scale with specific id
  @override
  Future<Scale> connectToScale({String? deviceId}) async {
    throw "Not implemented yet";
  }

  // disconnect (and dispose of?) device
  @override
  Future<void> disconnect(Device device) async {}

  _deviceScanned(DiscoveredDevice device) {
    for (Uuid uid in device.serviceUuids) {
      var initializer = deviceMappings[uid];
      if (initializer != null) {
        _devices[device.id] = initializer(device.id);
      }
    }
    log.fine("found new device: ${device.name}");
		log.fine("devices: ${_devices.toString()}");
    notifyListeners();
  }
}
