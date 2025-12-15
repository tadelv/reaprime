import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:reaprime/src/services/ble/blue_plus_transport.dart';

class BluePlusDiscoveryService implements DeviceDiscoveryService {
  final Logger _log = Logger("BluePlusDiscoveryService");
  Map<String, Future<Device> Function(BLETransport)> deviceMappings;
  final List<Device> _devices = [];
  final StreamController<List<Device>> _deviceStreamController =
      StreamController.broadcast();

  BluePlusDiscoveryService({
    required Map<String, Future<Device> Function(BLETransport)> mappings,
  }) : deviceMappings = mappings.map((k, v) {
         return MapEntry(Guid(k).str, v);
       });

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

  @override
  // TODO: implement devices
  Stream<List<Device>> get devices => _deviceStreamController.stream;

  @override
  Future<void> disconnect(Device device) {
    // TODO: implement disconnect
    throw UnimplementedError();
  }

  @override
  Future<void> initialize() async {
    await FlutterBluePlus.setOptions(showPowerAlert: true);
    _log.info("initialized");
  }

  @override
  Future<void> scanForDevices() async {
    // listen to scan results
    // Note: `onScanResults` clears the results between scans. You should use
    //  `scanResults` if you want the current scan results *or* the results from the previous scan.
    var subscription = FlutterBluePlus.onScanResults.listen((results) async {
      if (results.isNotEmpty) {
        ScanResult r = results.last; // the most recently found device
        _log.fine(
          '${r.device.remoteId}: "${r.advertisementData.advName}" found!',
        );
        final s = r.advertisementData.serviceUuids.firstWhereOrNull(
          (adv) =>
              deviceMappings.keys.map((e) => Guid(e)).toList().contains(adv),
        );
        if (s == null) {
          return;
        }
        final device = deviceMappings[s.str];
        if (device == null) {
          return;
        }
        final transport = BluePlusTransport(remoteId: r.device.remoteId.str);
        final d = await device(transport);
        r.device.connectionState.listen((event) {
          if (event != BluetoothConnectionState.disconnected) {
            _devices.removeWhere((d) => d.deviceId == r.device.remoteId.str);
            _deviceStreamController.add(_devices);
          }
        });
        _devices.add(d);
        _deviceStreamController.add(_devices);
      }
    }, onError: (e) => _log.warning(e));

    // cleanup: cancel subscription when scanning stops
    FlutterBluePlus.cancelWhenScanComplete(subscription);

    // Wait for Bluetooth enabled & permission granted
    // In your real app you should use `FlutterBluePlus.adapterState.listen` to handle all states
    await FlutterBluePlus.adapterState
        .where((val) => val == BluetoothAdapterState.on)
        .first;

    // Start scanning w/ timeout
    // Optional: use `stopScan()` as an alternative to timeout
    await FlutterBluePlus.startScan(
      withServices:
          deviceMappings.keys
              .map((e) => Guid(e))
              .toList(), // match any of the specified services
    );

    await Future.delayed(Duration(seconds: 15), () async {
      await FlutterBluePlus.stopScan();
      _deviceStreamController.add(_devices.toList());
    });

  }
}
