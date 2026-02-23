import 'dart:async';
import 'dart:io';

import 'package:reaprime/src/services/ble/universal_ble_transport.dart';
import 'package:reaprime/src/services/device_matcher.dart';
import 'package:universal_ble/universal_ble.dart';
import '../models/device/device.dart';
import '../models/device/machine.dart';
import '../models/device/scale.dart';
import 'package:logging/logging.dart' as logging;

class UniversalBleDiscoveryService extends DeviceDiscoveryService {
  UniversalBleDiscoveryService();

  final Map<String, Device> _devices = {};

  final log = logging.Logger("UniversalBleDeviceService");

  final StreamController<List<Device>> _deviceStreamController =
      StreamController.broadcast();

  final Map<String, StreamSubscription<ConnectionState>> _connections = {};

  final List<String> _currentlyScanning = [];

  bool _isScanning = false;

  @override
  Stream<List<Device>> get devices => _deviceStreamController.stream;

  @override
  Future<void> initialize() async {
    UniversalBle.queueType = QueueType.global;
    if (await UniversalBle.getBluetoothAvailabilityState() !=
        AvailabilityState.poweredOn) {
      log.warning("Bluetooth not supported on this platform");
      return;
    }
    UniversalBle.availabilityStream.listen((state) {
      log.info("BLE Adapter state: ${state.name}");
    });
  }

  bool _isBleDeviceId(String deviceId) {
    final macPattern = RegExp(r'^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$');
    final uuidPattern = RegExp(
      r'^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$',
    );
    return macPattern.hasMatch(deviceId) || uuidPattern.hasMatch(deviceId);
  }

  @override
  Future<void> scanForSpecificDevices(List<String> deviceIds) async {
    final bleIds = deviceIds.where(_isBleDeviceId).toList();
    if (bleIds.isEmpty) {
      log.fine('scanForSpecificDevices: no BLE IDs in $deviceIds, skipping');
      return;
    }
    // universal_ble does not support withRemoteIds filtering — fall back to full scan
    log.info('universal_ble: falling back to full scan for $bleIds');
    await scanForDevices();
  }

  @override
  Future<void> scanForDevices() async {
    if (_isScanning) {
      log.warning('Scan already in progress, ignoring request');
      return;
    }

    _isScanning = true;

    try {
      log.fine("Clearing stale connections");
      _currentlyScanning.clear();

      var sub = UniversalBle.scanStream.listen((result) async {
        log.fine(
          "Found: ${result.deviceId}: ${result.name}, adv: ${result.services}",
        );
        if (_currentlyScanning.contains(result.deviceId)) {
          return;
        }
        await _deviceScanned(result);
      });

      // Unfiltered scan — empty services list
      final filter = ScanFilter(withServices: []);
      await UniversalBle.startScan(scanFilter: filter);

      final systemDevices = await UniversalBle.getSystemDevices(
        withServices: [],
      );
      for (var d in systemDevices) {
        await _deviceScanned(d);
      }

      await Future.delayed(Duration(seconds: 15), () async {
        await UniversalBle.stopScan();
        await sub.cancel();
        _deviceStreamController.add(_devices.values.toList());
      });
    } finally {
      _isScanning = false;
    }
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

  Future<void> _deviceScanned(BleDevice device) async {
    _currentlyScanning.add(device.deviceId);

    try {
      final name = device.name ?? '';
      if (name.isEmpty) return;

      if (_devices.containsKey(device.deviceId.toString())) return;

      final matchedDevice = await DeviceMatcher.match(
        transport: UniversalBleTransport(device: device),
        advertisedName: name,
      );

      if (matchedDevice != null) {
        _devices[device.deviceId.toString()] = matchedDevice;
        _deviceStreamController.add(_devices.values.toList());
        log.fine("found new device: ${device.name}");

        _connections[device.deviceId.toString()] = _devices[device.deviceId
                .toString()]!
            .connectionState
            .listen((connectionState) {
          if (connectionState == ConnectionState.disconnected) {
            _devices.remove(device.deviceId.toString());
            _deviceStreamController.add(_devices.values.toList());
          }
        });
      }
    } finally {
      _currentlyScanning.remove(device.deviceId);
    }
  }
}
