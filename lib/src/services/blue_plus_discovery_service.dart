import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/models/adapter_state.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/services/ble/android_blue_plus_transport.dart';
import 'package:reaprime/src/services/ble/ble_discovery_service.dart';
import 'package:reaprime/src/services/ble/blue_plus_transport.dart';
import 'package:reaprime/src/services/device_matcher.dart';

class BluePlusDiscoveryService extends BleDiscoveryService {
  final Logger _log = Logger("BluePlusDiscoveryService");
  final List<Device> _devices = [];
  final StreamController<List<Device>> _deviceStreamController =
      StreamController.broadcast();
  final Set<String> _devicesBeingCreated = {};
  bool _isScanning = false;

  // Cancellable 15s scan-duration wait. External stopScan() cancels
  // the timer and completes the completer so scanForDevices returns
  // promptly instead of being pinned for 15s (comms-harden #11).
  Timer? _scanDurationTimer;
  Completer<void>? _scanDurationCompleter;

  // On Linux, queue discovered devices and process after scan stops
  // to avoid BlueZ le-connection-abort-by-local errors
  final List<_PendingDevice> _pendingDevices = [];

  StreamSubscription<String>? _logSubscription;

  BluePlusDiscoveryService();

  @override
  Stream<AdapterState> get adapterStateStream =>
      FlutterBluePlus.adapterState.map(_mapAdapterState);

  static AdapterState _mapAdapterState(BluetoothAdapterState state) {
    switch (state) {
      case BluetoothAdapterState.on:
        return AdapterState.poweredOn;
      case BluetoothAdapterState.off:
        return AdapterState.poweredOff;
      case BluetoothAdapterState.unavailable:
        return AdapterState.unavailable;
      default:
        return AdapterState.unknown;
    }
  }

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
  void stopScan() {
    _cancelScanDurationWait();
    FlutterBluePlus.stopScan();
  }

  /// Cancel the scheduled 15s stopScan and unblock the awaiter in
  /// scanForDevices so it can proceed to post-scan processing /
  /// clean up `_isScanning`. Called from the public stopScan() and
  /// from the timer's own fire path.
  void _cancelScanDurationWait() {
    _scanDurationTimer?.cancel();
    _scanDurationTimer = null;
    final c = _scanDurationCompleter;
    if (c != null && !c.isCompleted) {
      c.complete();
    }
    _scanDurationCompleter = null;
  }

  /// Wait up to [duration] for the scan to finish, or return early if
  /// `stopScan()` is called. The BLE scan is stopped in either case
  /// before this returns.
  Future<void> _waitForScanDuration(Duration duration) async {
    final completer = Completer<void>();
    _scanDurationCompleter = completer;
    _scanDurationTimer = Timer(duration, () async {
      try {
        await FlutterBluePlus.stopScan();
      } catch (e, st) {
        _log.warning('Scheduled stopScan failed', e, st);
      }
      _cancelScanDurationWait();
    });
    await completer.future;
  }

  @override
  Future<void> scanForDevices() async {
    if (_isScanning) {
      _log.warning('Scan already in progress, ignoring request');
      return;
    }

    _isScanning = true;

    // Remove disconnected devices so re-discovered ones get fresh
    // objects. Run the per-device `connectionState.first` checks in
    // parallel so pre-scan latency is capped at 2s regardless of how
    // many devices are cached (comms-harden #23).
    final staleFlags = await Future.wait(
      _devices.map((d) async {
        final state = await d.connectionState.first.timeout(
          const Duration(seconds: 2),
          onTimeout: () => ConnectionState.disconnected,
        );
        return state != ConnectionState.connected;
      }),
    );
    final toRemove = <Device>[
      for (var i = 0; i < _devices.length; i++)
        if (staleFlags[i]) _devices[i],
    ];
    for (final device in toRemove) {
      _devices.remove(device);
      _devicesBeingCreated.remove(device.deviceId);
    }

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
      _log.info("Waiting for adapter state...");
      try {
        await FlutterBluePlus.adapterState
            .where((val) => val == BluetoothAdapterState.on)
            .first
            .timeout(const Duration(seconds: 5));
      } on TimeoutException {
        _log.warning("Adapter state timeout — Bluetooth may be off or unavailable");
        return;
      }
      _log.info("Adapter ready, starting scan...");

      // Unfiltered scan — no withServices parameter
      await FlutterBluePlus.startScan(oneByOne: true);

      // Scan for up to 15s. External stopScan() cancels the timer and
      // completes the completer early so the scanner can free
      // `_isScanning` without waiting out the full duration
      // (comms-harden #11).
      await _waitForScanDuration(const Duration(seconds: 15));

      if (Platform.isLinux && _pendingDevices.isNotEmpty) {
        // On Linux/BlueZ, we must stop scanning before connecting to
        // devices. The 15s (or shorter, on early-stop) scan above has
        // collected devices into _pendingDevices; now process them.
        _log.info("Processing ${_pendingDevices.length} queued BLE devices");
        await Future.delayed(Duration(milliseconds: 200));
        for (final pending in _pendingDevices) {
          await _createDeviceFromName(pending.deviceId, pending.name);
        }
        _pendingDevices.clear();
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
