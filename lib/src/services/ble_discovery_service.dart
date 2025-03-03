import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/device/device.dart';
import '../models/device/machine.dart';
import '../models/device/scale.dart';
import 'package:logging/logging.dart' as logging;

class BleDiscoveryService extends DeviceDiscoveryService {
  BleDiscoveryService(this.deviceMappings);

  Map<String, Device Function(String)> deviceMappings;

  final Map<String, Device> _devices = {};

  final log = logging.Logger("BleDeviceService");

  final StreamController<List<Device>> _deviceStreamController =
      StreamController.broadcast();

  final Map<String, StreamSubscription<ConnectionState>> _connections = {};

  @override
  Stream<List<Device>> get devices => _deviceStreamController.stream;

  @override
  Future<void> initialize() async {
    if (await FlutterBluePlus.isSupported == false) {
      log.warning("Bluetooth not supported on this platform");
      return;
    }
    FlutterBluePlus.adapterState.listen((BluetoothAdapterState state) {
      log.info("BLE Adapter state: ${state.name}");
    });
  }

  @override
  Future<void> scanForDevices() async {
    var sub = FlutterBluePlus.onScanResults.listen((results) {
      if (results.isNotEmpty) {
        ScanResult r = results.last;
        log.info("Found: ${r.device.remoteId}: ${r.advertisementData.advName}");
        _deviceScanned(r);
      }
    });

    FlutterBluePlus.cancelWhenScanComplete(sub);

    await FlutterBluePlus.startScan(
        withServices: deviceMappings.keys.map((k) => Guid(k)).toList(),
        timeout: Duration(seconds: 30));
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
  Future<void> disconnect(Device device) async {
    device.disconnect();
    _devices.remove(device.deviceId);
    _deviceStreamController.add(_devices.values.toList());
  }

  _deviceScanned(ScanResult device) {
    for (Guid uid in device.advertisementData.serviceUuids) {
      var initializer = deviceMappings[uid.toString().toUpperCase()];
      if (initializer != null &&
          _devices.containsKey(device.device.remoteId.toString()) == false) {
        _devices[device.device.remoteId.toString()] =
            initializer(device.device.remoteId.toString());
        _deviceStreamController.add(_devices.values.toList());
        log.fine("found new device: ${device.advertisementData.advName}");
        log.fine("devices: ${_devices.toString()}");
        _connections[device.device.remoteId.toString()] =
            _devices[device.device.remoteId.toString()]!
                .connectionState
                .listen((connectionState) {
          if (connectionState == ConnectionState.disconnected) {
            _devices.remove(device.device.remoteId.toString());
            _deviceStreamController.add(_devices.values.toList());
          }
        });
      }
    }
  }
}
