import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:reaprime/src/services/ble/linux_blue_plus_transport.dart';

/// Linux-specific BLE discovery service that handles BlueZ quirks.
///
/// BlueZ (the Linux Bluetooth stack) has several behaviors that differ from
/// Android/iOS BLE stacks:
///
/// 1. **Scanning vs connecting is mutually exclusive.** Attempting to connect
///    to a device while a scan is active causes `le-connection-abort-by-local`
///    errors. This service queues discovered devices and processes them only
///    after the scan has fully stopped.
///
/// 2. **Adapter state transitions need settling time.** After stopping a scan,
///    BlueZ needs a brief pause before the adapter is ready for connections.
///
/// 3. **Connection attempts are less reliable.** BlueZ connections can fail
///    transiently, so we implement retry logic with increasing delays.
///
/// 4. **Service UUID scan filtering can be unreliable.** On some BlueZ
///    versions, filtering by service UUIDs during scan does not work
///    correctly. We scan without filters and match services manually from
///    advertisement data.
///
/// 5. **Adapter availability.** The Bluetooth adapter may not be immediately
///    available (e.g., rfkill, adapter not present). We check and wait for
///    the adapter before proceeding.
///
/// 6. **Sequential device processing.** Connecting to multiple devices
///    concurrently on BlueZ is unreliable. We process discovered devices
///    one at a time with delays between each.
class LinuxBleDiscoveryService implements DeviceDiscoveryService {
  final Logger _log = Logger("LinuxBleDiscoveryService");
  Map<String, Future<Device> Function(BLETransport)> deviceMappings;
  final List<Device> _devices = [];
  final StreamController<List<Device>> _deviceStreamController =
      StreamController.broadcast();
  final Set<String> _devicesBeingCreated = {};

  /// Queue of devices discovered during scan, processed after scan stops.
  final List<_PendingDevice> _pendingDevices = [];

  StreamSubscription<String>? _logSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterSubscription;

  /// Whether the BLE adapter is currently available and powered on.
  bool _adapterReady = false;

  /// How long to scan before stopping and processing results.
  /// BlueZ needs a longer scan window because:
  /// - BLE advertising intervals can be up to 10.24s
  /// - BlueZ may miss initial advertisements while the adapter settles
  /// - We want to catch devices with slow advertising intervals
  static const Duration _scanDuration = Duration(seconds: 12);

  /// Delay after stopping scan before processing devices.
  /// BlueZ needs this to fully release the scanning state internally.
  static const Duration _postScanSettleDelay = Duration(milliseconds: 500);

  /// Delay between sequential device connection attempts.
  /// Prevents BlueZ from becoming overwhelmed with concurrent operations.
  static const Duration _interDeviceDelay = Duration(milliseconds: 800);

  /// Maximum number of connection retries per device.
  static const int _maxRetries = 2;

  /// Base delay for retry backoff.
  static const Duration _retryBaseDelay = Duration(seconds: 2);

  /// Timeout for waiting for the adapter to become available.
  static const Duration _adapterTimeout = Duration(seconds: 10);

  LinuxBleDiscoveryService({
    required Map<String, Future<Device> Function(BLETransport)> mappings,
  }) : deviceMappings = mappings.map((k, v) {
         return MapEntry(Guid(k).str, v);
       });

  @override
  Stream<List<Device>> get devices => _deviceStreamController.stream;

  @override
  Future<void> initialize() async {
    assert(Platform.isLinux, 'LinuxBleDiscoveryService should only be used on Linux');

    await FlutterBluePlus.setLogLevel(LogLevel.warning);
    _logSubscription = FlutterBluePlus.logs.listen((logMessage) {
      _log.fine("FBP Native: $logMessage");
    });

    // Monitor adapter state changes
    _adapterSubscription = FlutterBluePlus.adapterState.listen((state) {
      final wasReady = _adapterReady;
      _adapterReady = state == BluetoothAdapterState.on;

      if (_adapterReady && !wasReady) {
        _log.info("Bluetooth adapter is now ON");
      } else if (!_adapterReady && wasReady) {
        _log.warning("Bluetooth adapter state changed to: $state");
      }
    });

    // Check initial adapter state
    _adapterReady = await _checkAdapterState();
    if (!_adapterReady) {
      _log.warning(
        "Bluetooth adapter not ready at init time. "
        "Will wait for adapter during scan.",
      );
    }

    _log.info("initialized (Linux-specific BLE service)");
  }

  /// Checks if the Bluetooth adapter is powered on and available.
  Future<bool> _checkAdapterState() async {
    try {
      final state = await FlutterBluePlus.adapterState.first.timeout(
        const Duration(seconds: 3),
      );
      return state == BluetoothAdapterState.on;
    } on TimeoutException {
      _log.warning("Timed out checking adapter state");
      return false;
    }
  }

  /// Waits for the Bluetooth adapter to become available.
  /// Returns true if the adapter is ready, false if we timed out.
  Future<bool> _waitForAdapter() async {
    if (_adapterReady) return true;

    _log.info("Waiting for Bluetooth adapter to become available...");
    try {
      await FlutterBluePlus.adapterState
          .where((val) => val == BluetoothAdapterState.on)
          .first
          .timeout(_adapterTimeout);
      _adapterReady = true;
      _log.info("Bluetooth adapter is ready");
      return true;
    } on TimeoutException {
      _log.severe(
        "Bluetooth adapter did not become available within "
        "${_adapterTimeout.inSeconds}s. "
        "Check that Bluetooth is enabled (bluetoothctl power on) "
        "and not blocked (rfkill unblock bluetooth).",
      );
      return false;
    }
  }

  /// Ensures any previous scan is stopped before starting a new one.
  Future<void> _ensureScanStopped() async {
    try {
      if (FlutterBluePlus.isScanningNow) {
        _log.info("Stopping previous scan before starting new one");
        await FlutterBluePlus.stopScan();
        // Give BlueZ time to fully stop the previous scan
        await Future.delayed(const Duration(milliseconds: 300));
      }
    } catch (e) {
      _log.warning("Error stopping previous scan: $e");
    }
  }

  @override
  Future<void> scanForDevices() async {
    // Step 1: Ensure adapter is available
    final adapterAvailable = await _waitForAdapter();
    if (!adapterAvailable) {
      _log.severe("Cannot scan: Bluetooth adapter not available");
      _deviceStreamController.add(_devices.toList());
      return;
    }

    // Step 2: Stop any ongoing scan
    await _ensureScanStopped();

    // Step 3: Clear pending devices from any previous scan
    _pendingDevices.clear();

    // Step 4: Set up scan listener
    // On Linux/BlueZ, we must NOT connect to devices while scanning.
    // All discovered devices are queued and processed after the scan stops.
    var subscription = FlutterBluePlus.onScanResults.listen((results) {
      if (results.isEmpty) return;

      ScanResult r = results.last;
      final deviceId = r.device.remoteId.str;

      // Skip if device already exists or is being created
      if (_devices.firstWhereOrNull(
            (element) => element.deviceId == deviceId,
          ) !=
          null) {
        _log.fine(
          "Duplicate device scanned $deviceId, "
          "${r.advertisementData.advName}",
        );
        return;
      }

      if (_devicesBeingCreated.contains(deviceId)) {
        _log.fine(
          "Device already being created $deviceId, "
          "${r.advertisementData.advName}",
        );
        return;
      }

      _log.fine(
        '$deviceId: "${r.advertisementData.advName}" found! '
        'services: ${r.advertisementData.serviceUuids}',
      );

      // Match against known service UUIDs
      final matchedService =
          r.advertisementData.serviceUuids.firstWhereOrNull(
        (adv) =>
            deviceMappings.keys.map((e) => Guid(e)).toList().contains(adv),
      );
      if (matchedService == null) return;

      final deviceFactory = deviceMappings[matchedService.str];
      if (deviceFactory == null) return;

      // Check if already pending
      if (_pendingDevices.any((p) => p.deviceId == deviceId)) {
        _log.fine("Device $deviceId already in pending queue");
        return;
      }

      _log.info("Queued $deviceId for post-scan processing "
          "(service: ${matchedService.str})");
      _pendingDevices.add(_PendingDevice(deviceId, deviceFactory));
    }, onError: (e) => _log.warning("Scan result error: $e"));

    // Step 5: Auto-cancel subscription when scan completes
    FlutterBluePlus.cancelWhenScanComplete(subscription);

    // Step 6: Start scanning
    // On BlueZ, scan with service filters when possible. However, some BlueZ
    // versions have issues with service UUID filtering. If scanning with
    // filters returns no results, a retry without filters could be considered.
    _log.info(
      "Starting BLE scan (duration: ${_scanDuration.inSeconds}s, "
      "services: ${deviceMappings.keys.length})",
    );
    try {
      await FlutterBluePlus.startScan(
        withServices:
            deviceMappings.keys.map((e) => Guid(e)).toList(),
        oneByOne: true,
        timeout: _scanDuration,
      );
    } catch (e) {
      _log.severe("Failed to start scan: $e");
      // If scan failed, try to stop it cleanly
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
      _deviceStreamController.add(_devices.toList());
      return;
    }

    // Step 7: Wait for scan to complete
    // The scan will stop automatically after _scanDuration due to the timeout
    // parameter above. We wait here for it to complete.
    _log.info("Scan completed. Found ${_pendingDevices.length} device(s)");

    // Step 8: Post-scan settle delay
    // Critical for BlueZ: the adapter needs time to transition from scanning
    // mode back to idle before we can initiate connections.
    _log.fine(
      "Waiting ${_postScanSettleDelay.inMilliseconds}ms for BlueZ to settle",
    );
    await Future.delayed(_postScanSettleDelay);

    // Step 9: Process queued devices sequentially
    if (_pendingDevices.isNotEmpty) {
      _log.info(
        "Processing ${_pendingDevices.length} queued BLE device(s) "
        "sequentially",
      );

      for (int i = 0; i < _pendingDevices.length; i++) {
        final pending = _pendingDevices[i];

        // Add inter-device delay (except for the first device)
        if (i > 0) {
          _log.fine(
            "Waiting ${_interDeviceDelay.inMilliseconds}ms before "
            "next device",
          );
          await Future.delayed(_interDeviceDelay);
        }

        await _createDeviceWithRetry(pending.deviceId, pending.factory);
      }
      _pendingDevices.clear();
    }

    // Step 10: Emit final device list
    _deviceStreamController.add(_devices.toList());
  }

  /// Creates a device with retry logic for Linux/BlueZ connection failures.
  ///
  /// BlueZ connections can fail transiently due to timing issues, adapter
  /// state, or interference. We retry with increasing delays.
  Future<void> _createDeviceWithRetry(
    String deviceId,
    Future<Device> Function(BLETransport) deviceFactory,
  ) async {
    _devicesBeingCreated.add(deviceId);

    for (int attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        if (attempt > 0) {
          final delay = _retryBaseDelay * attempt;
          _log.info(
            "Retry $attempt/$_maxRetries for device $deviceId "
            "(waiting ${delay.inMilliseconds}ms)",
          );
          await Future.delayed(delay);
        }

        await _createDevice(deviceId, deviceFactory);
        return; // Success, exit retry loop
      } catch (e) {
        _log.warning(
          "Attempt ${attempt + 1}/${_maxRetries + 1} failed for "
          "device $deviceId: $e",
        );

        if (attempt == _maxRetries) {
          _log.severe(
            "All ${_maxRetries + 1} attempts failed for device $deviceId. "
            "Giving up.",
          );
        }
      }
    }

    _devicesBeingCreated.remove(deviceId);
  }

  /// Creates a device from a discovered BLE peripheral.
  Future<void> _createDevice(
    String deviceId,
    Future<Device> Function(BLETransport) deviceFactory,
  ) async {
    try {
      final transport = LinuxBluePlusTransport(remoteId: deviceId);
      final device = await deviceFactory(transport);

      // Double-check device was not added while we were creating it
      if (_devices.firstWhereOrNull((d) => d.deviceId == deviceId) != null) {
        _log.fine("Device $deviceId already added, skipping duplicate");
        _devicesBeingCreated.remove(deviceId);
        return;
      }

      // Add device to list
      _devices.add(device);
      _deviceStreamController.add(_devices);
      _log.info("Device $deviceId added successfully");

      // Set up cleanup listener for when device disconnects.
      // We use skip(1) to ignore the current connection state that was set
      // during device creation/inspection (e.g., MachineParser connecting
      // and inspecting). This way we only react to FUTURE disconnection
      // events, not the state that existed when the device was first created.
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

      _devicesBeingCreated.remove(deviceId);
    } catch (e) {
      _log.severe("Error creating device $deviceId: $e");
      _devicesBeingCreated.remove(deviceId);
      rethrow; // Rethrow so retry logic can catch it
    }
  }

  /// Clean up subscriptions and resources.
  void dispose() {
    _logSubscription?.cancel();
    _adapterSubscription?.cancel();
    _deviceStreamController.close();
  }
}

class _PendingDevice {
  final String deviceId;
  final Future<Device> Function(BLETransport) factory;
  _PendingDevice(this.deviceId, this.factory);
}
