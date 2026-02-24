import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/services/ble/android_blue_plus_transport.dart';
import 'package:reaprime/src/services/ble/blue_plus_transport.dart';
import 'package:reaprime/src/services/device_matcher.dart';

class BluePlusDiscoveryService implements DeviceDiscoveryService {
  final Logger _log = Logger("BluePlusDiscoveryService");
  final List<Device> _devices = [];
  final StreamController<List<Device>> _deviceStreamController =
      StreamController.broadcast();
  final Set<String> _devicesBeingCreated = {};
  bool _isScanning = false;

  // On Linux, queue discovered devices and process after scan stops
  // to avoid BlueZ le-connection-abort-by-local errors
  final List<_PendingDevice> _pendingDevices = [];

  StreamSubscription<String>? _logSubscription;

  BluePlusDiscoveryService();

  @override
  Stream<List<Device>> get devices => _deviceStreamController.stream;

  Future<void> _createDeviceFromName(String deviceId, String name) async {
    try {
      final transport =
          Platform.isAndroid
              ? AndroidBluePlusTransport(remoteId: deviceId)
              : BluePlusTransport(remoteId: deviceId);

      final device = await DeviceMatcher.match(
        transport: transport,
        advertisedName: name,
      );

      if (device == null) {
        _log.fine('No device match for name "$name"');
        return;
      }

      // Double-check device wasn't added while we were creating it
      if (_devices.firstWhereOrNull((d) => d.deviceId == deviceId) != null) {
        _log.fine("Device $deviceId already added, skipping duplicate");
        return;
      }

      // Add device to list
      _devices.add(device);
      _deviceStreamController.add(_devices);
      _log.info('Device $deviceId "$name" added successfully');

      // Set up cleanup listener for when device disconnects.
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

  bool _isBleDeviceId(String deviceId) {
    // MAC address format: AA:BB:CC:DD:EE:FF
    final macPattern = RegExp(r'^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$');
    // UUID format: 8-4-4-4-12 hex chars
    final uuidPattern = RegExp(
      r'^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$',
    );
    return macPattern.hasMatch(deviceId) || uuidPattern.hasMatch(deviceId);
  }

  @override
  Future<void> scanForSpecificDevices(List<String> deviceIds) async {
    final bleIds = deviceIds.where(_isBleDeviceId).toList();
    if (bleIds.isEmpty) {
      _log.fine('scanForSpecificDevices: no BLE IDs in $deviceIds, skipping');
      return;
    }

    _log.info('Starting targeted BLE scan for devices $bleIds');

    var subscription = FlutterBluePlus.onScanResults.listen((results) {
      if (results.isEmpty) return;
      final r = results.last;
      final foundId = r.device.remoteId.str;
      final name = r.advertisementData.advName;

      if (deviceIds.contains(foundId) == false) {
        return;
      }

      if (_devices.firstWhereOrNull((d) => d.deviceId == foundId) != null) {
        return;
      }
      if (_devicesBeingCreated.contains(foundId)) return;

      _devicesBeingCreated.add(foundId);
      _createDeviceFromName(foundId, name);
    }, onError: (e) => _log.warning('Targeted scan error: $e'));

    FlutterBluePlus.cancelWhenScanComplete(subscription);

    await FlutterBluePlus.adapterState
        .where((val) => val == BluetoothAdapterState.on)
        .first;

    await FlutterBluePlus.startScan(
      // withRemoteIds: bleIds,
      oneByOne: true,
    );

    // Stop after timeout (device found earlier stops via cancelWhenScanComplete)
    final timeout =
        Platform.isLinux
            ? const Duration(seconds: 20)
            : const Duration(seconds: 8);
    await Future.delayed(timeout, () async {
      await FlutterBluePlus.stopScan();
    });

    _deviceStreamController.add(_devices.toList());
  }

  @override
  Future<void> scanForDevices() async {
    if (_isScanning) {
      _log.warning('Scan already in progress, ignoring request');
      return;
    }

    _isScanning = true;

    try {
      var subscription = FlutterBluePlus.onScanResults.listen((results) {
        if (results.isEmpty) return;

        ScanResult r = results.last;
        final deviceId = r.device.remoteId.str;
        final name = r.advertisementData.advName;

        // Check if device already exists or is being created
        if (_devices.firstWhereOrNull((d) => d.deviceId == deviceId) != null) {
          _log.fine("duplicate device scanned $deviceId, $name");
          return;
        }

        if (_devicesBeingCreated.contains(deviceId)) {
          _log.fine("device already being created $deviceId, $name");
          return;
        }

        // Mark device as being created to prevent duplicates
        _devicesBeingCreated.add(deviceId);

        if (Platform.isLinux) {
          _pendingDevices.add(_PendingDevice(deviceId, name));
          _log.info("Queued $deviceId for post-scan processing");
        } else {
          _createDeviceFromName(deviceId, name);
        }
      }, onError: (e) => _log.warning(e));

      // cleanup: cancel subscription when scanning stops
      FlutterBluePlus.cancelWhenScanComplete(subscription);

      // Wait for Bluetooth enabled & permission granted
      await FlutterBluePlus.adapterState
          .where((val) => val == BluetoothAdapterState.on)
          .first;

      // Unfiltered scan — no withServices parameter
      await FlutterBluePlus.startScan(oneByOne: true);

      if (Platform.isLinux) {
        // On Linux/BlueZ, we must stop scanning before connecting to devices.
        // Scan for 15s to ensure we catch devices with slow advertising intervals,
        // then process all queued devices after the scan stops.
        await Future.delayed(Duration(seconds: 15), () async {
          await FlutterBluePlus.stopScan();
        });

        if (_pendingDevices.isNotEmpty) {
          _log.info("Processing ${_pendingDevices.length} queued BLE devices");
          await Future.delayed(Duration(milliseconds: 200));
          for (final pending in _pendingDevices) {
            await _createDeviceFromName(pending.deviceId, pending.name);
          }
          _pendingDevices.clear();
        }
      } else {
        await Future.delayed(Duration(seconds: 15), () async {
          await FlutterBluePlus.stopScan();
        });
      }

      _deviceStreamController.add(_devices.toList());
    } finally {
      _isScanning = false;
    }
  }
}

class _PendingDevice {
  final String deviceId;
  final String name;
  _PendingDevice(this.deviceId, this.name);
}
