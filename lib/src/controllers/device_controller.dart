import 'dart:async';

import 'package:logging/logging.dart';
import 'package:reaprime/src/models/adapter_state.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/device_scanner.dart';
import 'package:reaprime/src/services/ble/ble_discovery_service.dart';
import 'package:reaprime/src/services/telemetry/telemetry_service.dart';
import 'package:rxdart/rxdart.dart';

class DeviceController implements DeviceScanner {
  final List<DeviceDiscoveryService> _services;

  late Map<DeviceDiscoveryService, List<Device>> _devices;

  final _log = Logger("Device Controller");
  final BehaviorSubject<List<Device>> _deviceStream = BehaviorSubject.seeded(
    [],
  );

  final BehaviorSubject<bool> _scanningStream = BehaviorSubject.seeded(false);

  Stream<bool> get scanningStream => _scanningStream.stream;
  bool get isScanning => _scanningStream.value;

  /// Aggregated adapter state across BLE discovery services. Replays the
  /// most recent state to new subscribers.
  final BehaviorSubject<AdapterState> _adapterStateStream =
      BehaviorSubject.seeded(AdapterState.unknown);

  @override
  Stream<AdapterState> get adapterStateStream =>
      _adapterStateStream.stream;

  final List<StreamSubscription> _serviceSubscriptions = [];

  // Telemetry service for reporting device state changes
  TelemetryService? _telemetryService;

  // Track when devices were last seen disconnecting
  final Map<String, DateTime> _disconnectedAt = {};

  // Track previously seen device names for disconnection detection
  final Set<String> _previousDeviceNames = {};

  /// Set the telemetry service for tracking device state changes
  ///
  /// Should be called before initialize() to ensure device state is tracked
  /// from the start. Follows setter injection pattern used in SettingsController.
  set telemetryService(TelemetryService service) {
    _telemetryService = service;
  }

  Stream<List<Device>> get deviceStream => _deviceStream.asBroadcastStream();

  List<Device> get devices =>
      _devices.values.fold(List<Device>.empty(growable: true), (res, el) {
        res.addAll(el);
        return res;
      }).toList();

  DeviceController(this._services) {
    _devices = {};
  }

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      _log.fine("Already initialized, skipping");
      return;
    }
    _initialized = true;

    for (var service in _services) {
      try {
        await service.initialize();
        final subscription = service.devices.listen(
          (devices) => _serviceUpdate(service, devices),
        );
        _serviceSubscriptions.add(subscription);
        if (service is BleDiscoveryService) {
          final adapterSub = service.adapterStateStream.listen((state) {
            if (!_adapterStateStream.isClosed) {
              _adapterStateStream.add(state);
            }
          });
          _serviceSubscriptions.add(adapterSub);
        }
      } catch (e) {
        _log.warning("Service $service failed to init:", e);
      }
    }
    // Note: we no longer auto-scan here. The UI layer decides whether to run
    // a targeted scan (preferred device) or a full scan (no preference).
    // This avoids competing BLE scans that interfere with each other.
  }

  Future<void> scanForDevices() async {
    _scanningStream.add(true);
    // throw out disconnected/discovered devices (keep connected and connecting)
    for (final entry in _devices.entries) {
      final devices = entry.value;
      final toRemove = <Device>[];
      for (final device in devices) {
        final state = await device.connectionState.first
            .timeout(const Duration(seconds: 2),
                onTimeout: () => ConnectionState.disconnected);
        if (state != ConnectionState.connected &&
            state != ConnectionState.connecting) {
          toRemove.add(device);
        }
      }
      for (final device in toRemove) {
        devices.remove(device);
      }
    }
    // Sync the disconnect-detection baseline with the cleaned list so that
    // service emissions arriving during the scan don't see false diffs.
    _previousDeviceNames.clear();
    _previousDeviceNames.addAll(devices.map((d) => d.name));
    _deviceStream.add(devices);
    // Scan all services in parallel
    final completer = Completer();
    try {
      completer.complete(
        Future.wait(
          _services.map((service) async {
            try {
              _log.fine("starting scan for $service");
              await service.scanForDevices();
            } catch (e, st) {
              _log.warning("Service $service failed to scan:", e, st);
            }
          }),
        ),
      );
    } finally {
      completer.future
          .timeout(Duration(seconds: 30))
          .then((_) {}, onError: (e) {
        _log.warning("scan timed out or failed: $e");
      }).whenComplete(() async {
        await Future.delayed(Duration(milliseconds: 200), () {
          if (!_scanningStream.isClosed) _scanningStream.add(false);
          _log.info("current devices: $devices");
        });
      });
    }
  }

  /// Stop all in-progress scans across all discovery services.
  void stopScan() {
    for (final service in _services) {
      service.stopScan();
    }
  }

  void _serviceUpdate(DeviceDiscoveryService service, List<Device> devices) {
    _log.fine("$service update: $devices");
    _devices[service] = devices;

    // Get current device names
    final currentDeviceNames = this.devices.map((d) => d.name).toSet();

    // Skip disconnect/reconnect detection during active scans — the device
    // list is in flux and intermediate states are transient noise. The scan
    // will produce the authoritative list when it completes.
    if (!isScanning) {
      // Detect disconnections: devices that were in previous update but not in current
      final disconnectedDevices =
          _previousDeviceNames.difference(currentDeviceNames);
      for (var deviceName in disconnectedDevices) {
        _disconnectedAt[deviceName] = DateTime.now();
        _log.info("Device $deviceName disconnected");
      }

      // Detect reconnections: devices in current update that have disconnection timestamps
      for (var deviceName in currentDeviceNames) {
        if (_disconnectedAt.containsKey(deviceName)) {
          final disconnectedTime = _disconnectedAt[deviceName]!;
          final duration = DateTime.now().difference(disconnectedTime);
          _log.info(
              "Device $deviceName reconnected after ${duration.inSeconds}s");

          // Set telemetry custom key with reconnection duration
          _telemetryService?.setCustomKey(
            'reconnection_duration_$deviceName',
            duration.inSeconds,
          );

          // Remove from disconnected tracking
          _disconnectedAt.remove(deviceName);
        }
      }

      // Clean up stale disconnection entries (older than 24 hours)
      final now = DateTime.now();
      _disconnectedAt.removeWhere((deviceName, timestamp) {
        return now.difference(timestamp).inHours > 24;
      });
    }

    // Update previous device names for next comparison
    _previousDeviceNames.clear();
    _previousDeviceNames.addAll(currentDeviceNames);

    _deviceStream.add(this.devices);
    _updateDeviceCustomKeys();
  }

  /// Update telemetry custom keys with current device state
  ///
  /// Called on every device list change to keep telemetry context up-to-date.
  /// Sets individual device keys (device_{name}_type) and summary counts by type.
  void _updateDeviceCustomKeys() {
    if (_telemetryService == null) return;

    int machineCount = 0;
    int scaleCount = 0;
    int sensorCount = 0;

    for (var device in devices) {
      // Set individual device type key
      _telemetryService!.setCustomKey(
        'device_${device.name}_type',
        device.type.name,
      );

      // Count by type (devices in the map are considered connected)
      switch (device.type) {
        case DeviceType.machine:
          machineCount++;
          break;
        case DeviceType.scale:
          scaleCount++;
          break;
        case DeviceType.sensor:
          sensorCount++;
          break;
      }
    }

    // Set summary counts
    _telemetryService!.setCustomKey('connected_machines', machineCount);
    _telemetryService!.setCustomKey('connected_scales', scaleCount);
    _telemetryService!.setCustomKey('connected_sensors', sensorCount);
  }

  void dispose() {
    for (var subscription in _serviceSubscriptions) {
      subscription.cancel();
    }
    _serviceSubscriptions.clear();
    _deviceStream.close();
    _scanningStream.close();
    _adapterStateStream.close();
  }
}
