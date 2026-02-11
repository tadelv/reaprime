import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:reaprime/src/services/ble/blue_plus_transport.dart';

class BluePlusDiscoveryService implements DeviceDiscoveryService {
  final Logger _log = Logger("BluePlusDiscoveryService");
  Map<String, Future<Device> Function(BLETransport)> deviceMappings;
  final List<Device> _devices = [];
  final StreamController<List<Device>> _deviceStreamController =
      StreamController.broadcast();
  final Set<String> _devicesBeingCreated = {};

  // On Linux, queue discovered devices and process after scan stops
  // to avoid BlueZ le-connection-abort-by-local errors
  final List<_PendingDevice> _pendingDevices = [];

  StreamSubscription<String>? _logSubscription;

  BluePlusDiscoveryService({
    required Map<String, Future<Device> Function(BLETransport)> mappings,
  }) : deviceMappings = mappings.map((k, v) {
         return MapEntry(Guid(k).str, v);
       });

  @override
  Stream<List<Device>> get devices => _deviceStreamController.stream;

  Future<void> _createDevice(
    String deviceId,
    Future<Device> Function(BLETransport) deviceFactory,
  ) async {
    try {
      final transport = BluePlusTransport(remoteId: deviceId);
      final device = await deviceFactory(transport);

      // Double-check device wasn't added while we were creating it
      if (_devices.firstWhereOrNull((d) => d.deviceId == deviceId) != null) {
        _log.fine("Device $deviceId already added, skipping duplicate");
        return;
      }

      // Add device to list
      _devices.add(device);
      _deviceStreamController.add(_devices);
      _log.info("Device $deviceId added successfully");

      // Set up cleanup listener for when device disconnects.
      // We use skip(1) to ignore the current connection state that was set during
      // device creation/inspection (e.g., MachineParser connecting and inspecting).
      // This way we only react to FUTURE disconnection events, not the state that
      // existed when the device was first created.
      StreamSubscription? sub;
      sub = device.connectionState.skip(1).listen((event) {
        if (event == ConnectionState.disconnected) {
          _log.info(
            "Device $deviceId disconnected, removing from discovery list",
          );
          _devices.removeWhere((d) => d.deviceId == deviceId);
          _deviceStreamController.add(_devices);
          sub?.cancel();
        }
      });
    } catch (e) {
      _log.severe("Error creating device $deviceId: $e");
      // Don't add device to list if creation failed
    } finally {
      _devicesBeingCreated.remove(deviceId);
    }
  }

  @override
  Future<void> initialize() async {
    await FlutterBluePlus.setLogLevel(LogLevel.warning);
    _logSubscription = FlutterBluePlus.logs.listen((logMessage) {
      _log.fine("BP Native: $logMessage");
    });
    await FlutterBluePlus.setOptions(showPowerAlert: true);
    _log.info("initialized");
  }

  @override
  Future<void> scanForDevices() async {
    // listen to scan results
    // Note: `onScanResults` clears the results between scans. You should use
    //  `scanResults` if you want the current scan results *or* the results from the previous scan.
    var subscription = FlutterBluePlus.onScanResults.listen((results) {
      if (results.isEmpty) {
        return;
      }
      ScanResult r = results.last; // the most recently found device
      final deviceId = r.device.remoteId.str;

      // Check if device already exists or is being created
      if (_devices.firstWhereOrNull(
            (element) => element.deviceId == deviceId,
          ) !=
          null) {
        _log.fine(
          "duplicate device scanned ${r.device.remoteId}, ${r.advertisementData.advName}",
        );
        return;
      }

      if (_devicesBeingCreated.contains(deviceId)) {
        _log.fine(
          "device already being created ${r.device.remoteId}, ${r.advertisementData.advName}",
        );
        return;
      }

      _log.fine(
        '${r.device.remoteId}: "${r.advertisementData.advName}" found!',
      );

      final s = r.advertisementData.serviceUuids.firstWhereOrNull(
        (adv) => deviceMappings.keys.map((e) => Guid(e)).toList().contains(adv),
      );
      if (s == null) {
        return;
      }

      final deviceFactory = deviceMappings[s.str];
      if (deviceFactory == null) {
        return;
      }

      // Mark device as being created to prevent duplicates
      _devicesBeingCreated.add(deviceId);

      if (Platform.isLinux) {
        // On Linux/BlueZ, queue device for processing after scan stops
        // to avoid le-connection-abort-by-local errors
        _pendingDevices.add(_PendingDevice(deviceId, deviceFactory));
        _log.info("Queued $deviceId for post-scan processing");
      } else {
        // On other platforms, create device immediately
        _createDevice(deviceId, deviceFactory);
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
      oneByOne: true,
    );

    if (Platform.isLinux) {
      // On Linux/BlueZ, we must stop scanning before connecting to devices.
      // Scan for 15s to ensure we catch devices with slow advertising intervals,
      // then process all queued devices after the scan stops.
      await Future.delayed(Duration(seconds: 15), () async {
        await FlutterBluePlus.stopScan();
      });

      if (_pendingDevices.isNotEmpty) {
        _log.info("Processing ${_pendingDevices.length} queued BLE devices");
        // Brief delay for BlueZ to settle after scan stop
        await Future.delayed(Duration(milliseconds: 200));
        for (final pending in _pendingDevices) {
          await _createDevice(pending.deviceId, pending.factory);
        }
        _pendingDevices.clear();
      }
    } else {
      await Future.delayed(Duration(seconds: 15), () async {
        await FlutterBluePlus.stopScan();
      });
    }

    _deviceStreamController.add(_devices.toList());
  }
}

class _PendingDevice {
  final String deviceId;
  final Future<Device> Function(BLETransport) factory;
  _PendingDevice(this.deviceId, this.factory);
}
