import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/services/telemetry/telemetry_service.dart';
import 'package:rxdart/rxdart.dart';

class DeviceController {
  final List<DeviceDiscoveryService> _services;

  late Map<DeviceDiscoveryService, List<Device>> _devices;

  final _log = Logger("Device Controller");
  final BehaviorSubject<List<Device>> _deviceStream = BehaviorSubject.seeded(
    [],
  );

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
      } catch (e) {
        _log.warning("Service $service failed to init:", e);
      }
    }
    // Note: we no longer auto-scan here. The UI layer decides whether to run
    // a targeted scan (preferred device) or a full scan (no preference).
    // This avoids competing BLE scans that interfere with each other.
  }

  bool _autoConnect = true;
  bool get shouldAutoConnect => _autoConnect;

  Future<void> scanForDevices({required bool autoConnect}) async {
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
    final completer = Completer();
    try {
      completer.complete(
        Future.wait(
          _services.map((service) async {
            try {
              _log.fine("starting scan for $service");
              await service.scanForDevices();
              // _deviceStream.add(_devices.values.expand((e) => e).toList());
            } catch (e, st) {
              _log.warning("Service $service failed to scan:", e, st);
            }
          }),
        ),
      );
    } finally {
      completer.future.then((_) async {
        await Future.delayed(Duration(milliseconds: 200), () {
          _autoConnect = tmpAutoConnect;
          _log.info("_autoConnect restored to $tmpAutoConnect");
          _log.info("current devices: $devices");
        });
      });
    }
  }

  /// Scan all services for a specific device by ID.
  ///
  /// Returns true if the device appears in [deviceStream] within the timeout,
  /// false otherwise. Callers should fall back to [scanForDevices] on false.
  Future<bool> scanForSpecificDevice(String deviceId) {
    return scanForSpecificDevices([deviceId], awaitDeviceId: deviceId);
  }

  /// Scan all services for multiple specific devices in a single scan pass.
  ///
  /// [deviceIds] — all device IDs to include in the scan filter.
  /// [awaitDeviceId] — the device to wait for; returns true when it appears.
  ///   Other IDs will still be discovered (and trigger auto-connect via
  ///   controllers listening to [deviceStream]) but are not awaited.
  ///
  /// Returns true if [awaitDeviceId] appears within the timeout, false otherwise.
  Future<bool> scanForSpecificDevices(
    List<String> deviceIds, {
    required String awaitDeviceId,
  }) async {
    // BLE scan can take a few seconds, plus device creation (connect +
    // service discovery + inspection) adds ~3-5s on top. Use a generous
    // timeout to avoid false negatives.
    final timeout = Duration(seconds: Platform.isLinux ? 25 : 15);

    // Start targeted scan on all services in parallel (each service
    // self-validates whether the IDs belong to its transport)
    for (final service in _services) {
      service.scanForSpecificDevices(deviceIds).catchError((e) {
        _log.warning("Service $service scanForSpecificDevices failed: $e");
      });
    }

    // Wait until the primary device appears in the stream or we time out
    try {
      await _deviceStream
          .expand((devices) => devices)
          .where((device) => device.deviceId == awaitDeviceId)
          .first
          .timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    }
  }

  void _serviceUpdate(DeviceDiscoveryService service, List<Device> devices) {
    _log.fine("$service update: $devices");
    _devices[service] = devices;

    // Get current device names
    final currentDeviceNames = this.devices.map((d) => d.name).toSet();

    // Detect disconnections: devices that were in previous update but not in current
    final disconnectedDevices = _previousDeviceNames.difference(currentDeviceNames);
    for (var deviceName in disconnectedDevices) {
      _disconnectedAt[deviceName] = DateTime.now();
      _log.info("Device $deviceName disconnected");
    }

    // Detect reconnections: devices in current update that have disconnection timestamps
    for (var deviceName in currentDeviceNames) {
      if (_disconnectedAt.containsKey(deviceName)) {
        final disconnectedTime = _disconnectedAt[deviceName]!;
        final duration = DateTime.now().difference(disconnectedTime);
        _log.info("Device $deviceName reconnected after ${duration.inSeconds}s");

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
  }
}
