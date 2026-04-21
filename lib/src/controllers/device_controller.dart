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

  // Track when devices were last seen disconnecting, keyed by deviceId.
  // Keying by id (not name) avoids cross-attribution when two devices
  // advertise the same name, and survives firmware-update name changes
  // (comms-harden #20).
  final Map<String, DateTime> _disconnectedAt = {};

  // Track previously seen device ids for disconnection detection.
  final Set<String> _previousDeviceIds = {};

  // Map of deviceId → display name for the most recent observation.
  // Used only to render human-readable log messages; correlation is by id.
  final Map<String, String> _deviceNamesById = {};

  /// Set the telemetry service for tracking device state changes
  ///
  /// Should be called before initialize() to ensure device state is tracked
  /// from the start. Follows setter injection pattern used in SettingsController.
  set telemetryService(TelemetryService service) {
    _telemetryService = service;
  }

  // Expose the BehaviorSubject's own stream directly — it is already
  // broadcast-compatible and supports multiple listeners with replay.
  // Avoids the previous `asBroadcastStream()` wrapping, which created
  // a new broadcast wrapper on every getter call and accumulated
  // underlying subscriptions (comms-harden #14).
  @override
  Stream<List<Device>> get deviceStream => _deviceStream.stream;

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

  /// In-flight scan Future so concurrent callers share a single scan
  /// cycle instead of kicking off parallel scans that would interfere
  /// with each other at the BLE layer.
  Future<ScanResult>? _inFlightScan;

  @override
  Future<ScanResult> scanForDevices() {
    return _inFlightScan ??= _runScan().whenComplete(() {
      _inFlightScan = null;
    });
  }

  Future<ScanResult> _runScan() async {
    _scanningStream.add(true);
    final start = DateTime.now();
    try {
      // Throw out disconnected/discovered devices (keep connected and
      // connecting). Run the per-device `connectionState.first` checks
      // across every service in parallel so pre-scan latency is
      // capped at 2s total regardless of how many services or
      // devices are cached (comms-harden #23).
      final pairs = <({DeviceDiscoveryService service, Device device})>[];
      for (final entry in _devices.entries) {
        for (final device in entry.value) {
          pairs.add((service: entry.key, device: device));
        }
      }
      final staleFlags = await Future.wait(
        pairs.map((p) async {
          final state = await p.device.connectionState.first.timeout(
            const Duration(seconds: 2),
            onTimeout: () => ConnectionState.disconnected,
          );
          return state != ConnectionState.connected &&
              state != ConnectionState.connecting;
        }),
      );
      for (var i = 0; i < pairs.length; i++) {
        if (staleFlags[i]) {
          _devices[pairs[i].service]?.remove(pairs[i].device);
        }
      }
      // Sync the disconnect-detection baseline with the cleaned list so
      // that service emissions arriving during the scan don't see false
      // diffs.
      _previousDeviceIds.clear();
      _previousDeviceIds.addAll(devices.map((d) => d.deviceId));
      _deviceNamesById
        ..clear()
        ..addEntries(devices.map((d) => MapEntry(d.deviceId, d.name)));
      _deviceStream.add(devices);

      // Run every service's scan in parallel and capture per-service
      // failures in the result rather than torpedoing the whole scan.
      // A user with BLE permission denied but a USB DE1 connected still
      // gets their machine back from the serial service.
      final failures = <ServiceScanFailure>[];
      await Future.wait(
        _services.map((service) async {
          try {
            _log.fine("starting scan for $service");
            await service.scanForDevices();
          } catch (e, st) {
            _log.warning("Service $service failed to scan:", e, st);
            failures.add(
              ServiceScanFailure(
                serviceName: service.runtimeType.toString(),
                error: e,
                stackTrace: st,
              ),
            );
          }
        }),
      );

      _log.info("current devices: $devices");
      // Settle delay before flipping scanningStream so downstream UI
      // observers see a stable "scanning" period rather than a
      // zero-duration flicker when services resolve synchronously.
      // Preserved from the pre-PR-A implementation to keep widget-test
      // timing assumptions intact; revisit in PR B when status
      // derivation is in place.
      await Future.delayed(const Duration(milliseconds: 200));
      return ScanResult(
        matchedDevices: List.unmodifiable(devices),
        failedServices: List.unmodifiable(failures),
        terminationReason: ScanTerminationReason.completed,
        duration: DateTime.now().difference(start),
      );
    } finally {
      if (!_scanningStream.isClosed) _scanningStream.add(false);
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

    // Snapshot current device ids + id→name map. Correlation keys are
    // always deviceId; name is kept only for human-readable log output
    // (comms-harden #20).
    final currentDevices = this.devices;
    final currentDeviceIds = currentDevices.map((d) => d.deviceId).toSet();
    for (final d in currentDevices) {
      _deviceNamesById[d.deviceId] = d.name;
    }

    // Skip disconnect/reconnect detection during active scans — the device
    // list is in flux and intermediate states are transient noise. The scan
    // will produce the authoritative list when it completes.
    if (!isScanning) {
      // Detect disconnections: devices that were in previous update but not in current
      final disconnectedIds =
          _previousDeviceIds.difference(currentDeviceIds);
      for (var deviceId in disconnectedIds) {
        _disconnectedAt[deviceId] = DateTime.now();
        final name = _deviceNamesById[deviceId] ?? deviceId;
        _log.info("Device $name ($deviceId) disconnected");
      }

      // Detect reconnections: devices in current update that have disconnection timestamps
      for (var deviceId in currentDeviceIds) {
        if (_disconnectedAt.containsKey(deviceId)) {
          final disconnectedTime = _disconnectedAt[deviceId]!;
          final duration = DateTime.now().difference(disconnectedTime);
          final name = _deviceNamesById[deviceId] ?? deviceId;
          _log.info(
              "Device $name ($deviceId) reconnected after ${duration.inSeconds}s");

          // Set telemetry custom key with reconnection duration
          _telemetryService?.setCustomKey(
            'reconnection_duration_$deviceId',
            duration.inSeconds,
          );

          // Remove from disconnected tracking
          _disconnectedAt.remove(deviceId);
        }
      }

      // Clean up stale disconnection entries (older than 24 hours)
      final now = DateTime.now();
      _disconnectedAt.removeWhere((_, timestamp) {
        return now.difference(timestamp).inHours > 24;
      });
    }

    // Update previous device ids for next comparison
    _previousDeviceIds.clear();
    _previousDeviceIds.addAll(currentDeviceIds);

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
      // Set individual device type key, keyed by deviceId so same-named
      // devices don't clobber each other (comms-harden #20).
      _telemetryService!.setCustomKey(
        'device_${device.deviceId}_type',
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
