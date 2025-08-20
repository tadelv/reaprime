import 'dart:async';
import 'dart:io';

import 'package:universal_ble/universal_ble.dart';
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
    UniversalBle.queueType = QueueType.perDevice;
    if (await UniversalBle.getBluetoothAvailabilityState() !=
        AvailabilityState.poweredOn) {
      log.warning("Bluetooth not supported on this platform");
      return;
    }
    UniversalBle.availabilityStream.listen((state) {
      log.info("BLE Adapter state: ${state.name}");
    });
  }

  @override
  Future<void> scanForDevices() async {
    log.info("mappings: ${deviceMappings}");
    var sub = UniversalBle.scanStream.listen((result) {
      log.info("Found: ${result.deviceId}: ${result.name}, adv: ${result.services}");
      _deviceScanned(result);
    });

    // FIXME: determine correct way to specify services for linux
    final List<String> services = Platform.isLinux ? [] : deviceMappings.keys.toList();

    final filter = ScanFilter(withServices: services);

    await UniversalBle.startScan(scanFilter: filter);

    // TODO: configurable delay?
    await Future.delayed(Duration(seconds: 15), () async {
      await UniversalBle.stopScan();
      await sub.cancel();
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
  Future<void> disconnect(Device device) async {
    device.disconnect();
    _devices.remove(device.deviceId);
    _deviceStreamController.add(_devices.values.toList());
  }

  void _deviceScanned(BleDevice device) {
    for (String uid in device.services) {
      var initializer = deviceMappings[uid.toString().toUpperCase()];
      if (initializer != null &&
          _devices.containsKey(device.deviceId.toString()) == false) {
        _devices[device.deviceId.toString()] =
            initializer(device.deviceId.toString());
        _deviceStreamController.add(_devices.values.toList());
        log.fine("found new device: ${device.name}");
        log.fine("devices: ${_devices.toString()}");
        _connections[device.deviceId.toString()] =
            _devices[device.deviceId.toString()]!
                .connectionState
                .listen((connectionState) {
          if (connectionState == ConnectionState.disconnected) {
            _devices.remove(device.deviceId.toString());
            _deviceStreamController.add(_devices.values.toList());
          }
        });
      }
    }
  }
}
