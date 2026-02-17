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
/// 2. **`startScan(timeout:)` returns immediately on Linux.** The timeout
///    parameter does not reliably block for the full scan duration on BlueZ.
///    We start without a timeout and manage the duration ourselves.
///
/// 3. **Scan results arrive asynchronously.** Results can arrive after the
///    scan is reported as stopped. We keep our listener active and wait for
///    results to flush before processing.
///
/// 4. **After a failed connection, devices disappear from the plugin cache.**
///    `flutter_blue_plus_linux` uses `singleWhere` to look up devices
///    internally. After disconnect, the device may be gone, causing
///    "Bad state: No element" on retry. We re-scan before each retry.
///
/// 5. **Adapter availability.** The Bluetooth adapter may not be immediately
///    available (e.g., rfkill, adapter not present). We check and wait for
///    the adapter before proceeding.
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
  static const Duration _scanDuration = Duration(seconds: 12);

  /// How long to wait after stopping scan for in-flight results to arrive
  /// and for BlueZ to fully exit scanning mode before connection attempts.
  static const Duration _postScanSettleDelay = Duration(seconds: 3);

  /// Delay between sequential device connection attempts.
  static const Duration _interDeviceDelay = Duration(milliseconds: 800);

  /// Maximum number of connection retries per device.
  static const int _maxRetries = 2;

  /// Base delay for retry backoff.
  static const Duration _retryBaseDelay = Duration(seconds: 3);

  /// Brief scan duration used before retries to refresh BlueZ device cache.
  static const Duration _refreshScanDuration = Duration(seconds: 4);

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
    assert(
        Platform.isLinux, 'LinuxBleDiscoveryService should only be used on Linux');

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

  /// Ensures any previous scan is fully stopped with settle time.
  Future<void> _ensureScanStopped() async {
    try {
      if (FlutterBluePlus.isScanningNow) {
        _log.info("Stopping previous scan before starting new one");
        await FlutterBluePlus.stopScan();
      }
      // Always give BlueZ a moment even if scan wasn't running,
      // in case it just stopped
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      _log.warning("Error stopping previous scan: $e");
    }
  }

  /// Runs a scan for [duration], collecting results into [_pendingDevices].
  /// Manages the scan lifecycle manually instead of using the timeout
  /// parameter, which doesn't block reliably on Linux.
  Future<void> _runScan(Duration duration) async {
    _pendingDevices.clear();

    // Set up scan listener BEFORE starting scan
    final subscription = FlutterBluePlus.onScanResults.listen((results) {
      if (results.isEmpty) return;

      ScanResult r = results.last;
      final deviceId = r.device.remoteId.str;

      // Skip if device already exists or is being created
      if (_devices.firstWhereOrNull(
                (element) => element.deviceId == deviceId) !=
            null ||
          _devicesBeingCreated.contains(deviceId)) {
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
      if (_pendingDevices.any((p) => p.deviceId == deviceId)) return;

      _log.info("Queued $deviceId for post-scan processing "
          "(service: ${matchedService.str})");
      _pendingDevices.add(_PendingDevice(deviceId, deviceFactory));
    }, onError: (e) => _log.warning("Scan result error: $e"));

    // Start scan WITHOUT timeout - we manage timing ourselves
    _log.info(
      "Starting BLE scan (duration: ${duration.inSeconds}s, "
      "services: ${deviceMappings.keys.length})",
    );
    try {
      await FlutterBluePlus.startScan(
        withServices: deviceMappings.keys.map((e) => Guid(e)).toList(),
        oneByOne: true,
        // No timeout - we manage it ourselves
      );
    } catch (e) {
      _log.severe("Failed to start scan: $e");
      subscription.cancel();
      return;
    }

    // Wait for the full scan duration
    await Future.delayed(duration);

    // Explicitly stop scan
    _log.info("Stopping scan...");
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      _log.warning("Error stopping scan: $e");
    }

    // Wait for in-flight scan results to flush through the stream.
    // BlueZ delivers results asynchronously via D-Bus; results can arrive
    // after the scan is reported as stopped.
    _log.fine(
      "Waiting ${_postScanSettleDelay.inSeconds}s for results to flush "
      "and BlueZ to settle",
    );
    await Future.delayed(_postScanSettleDelay);

    // NOW cancel the subscription - after results have flushed
    subscription.cancel();

    _log.info(
        "Scan complete. Found ${_pendingDevices.length} device(s) to process");
  }

  bool _isBleDeviceId(String deviceId) {
    final macPattern = RegExp(r'^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$');
    final uuidPattern = RegExp(
      r'^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$',
    );
    return macPattern.hasMatch(deviceId) || uuidPattern.hasMatch(deviceId);
  }

  @override
  Future<void> scanForSpecificDevice(String deviceId) async {
    if (!_isBleDeviceId(deviceId)) {
      _log.fine('scanForSpecificDevice: "$deviceId" is not a BLE ID, skipping');
      return;
    }
    if (!_adapterReady) {
      _log.warning('BLE adapter not ready, cannot do targeted scan');
      return;
    }

    _log.info('Linux targeted BLE scan for $deviceId');

    var sub = FlutterBluePlus.onScanResults.listen((results) {
      if (results.isEmpty) return;
      final r = results.last;
      final foundId = r.device.remoteId.str;
      if (_devicesBeingCreated.contains(foundId)) return;
      if (_devices.firstWhereOrNull((d) => d.deviceId == foundId) != null) return;

      final s = r.advertisementData.serviceUuids.firstWhereOrNull(
        (adv) => deviceMappings.keys.map((e) => Guid(e)).toList().contains(adv),
      );
      if (s == null) return;
      final factory = deviceMappings[s.str];
      if (factory == null) return;

      _devicesBeingCreated.add(foundId);
      _pendingDevices.add(_PendingDevice(foundId, factory));
    }, onError: (e) => _log.warning('Targeted scan error: $e'));

    FlutterBluePlus.cancelWhenScanComplete(sub);

    await FlutterBluePlus.startScan(
      withRemoteIds: [deviceId],
      withServices: deviceMappings.keys.map((e) => Guid(e)).toList(),
      oneByOne: true,
    );

    // Linux: scan for up to 15s then stop and process
    await Future.delayed(const Duration(seconds: 15), () async {
      await FlutterBluePlus.stopScan();
    });

    await Future.delayed(_postScanSettleDelay);

    if (_pendingDevices.isNotEmpty) {
      for (final pending in List.of(_pendingDevices)) {
        await _createDevice(pending.deviceId, pending.factory);
      }
      _pendingDevices.clear();
    }

    _deviceStreamController.add(_devices.toList());
  }

  @override
  Future<void> scanForDevices() async {
    final adapterAvailable = await _waitForAdapter();
    if (!adapterAvailable) {
      _log.severe("Cannot scan: Bluetooth adapter not available");
      _deviceStreamController.add(_devices.toList());
      return;
    }

    await _ensureScanStopped();

    // Run the main scan
    await _runScan(_scanDuration);

    // Process queued devices sequentially
    if (_pendingDevices.isNotEmpty) {
      // On BlueZ, the first connect after a long scan consistently fails
      // with le-connection-abort-by-local. Running a brief "prep scan"
      // resets BlueZ's internal state and makes the connect succeed on the
      // first attempt, avoiding a costly retry cycle (~15s saved).
      _log.info("Running connection prep scan before device processing");
      await _ensureScanStopped();
      await _runRefreshScan();

      _log.info(
        "Processing ${_pendingDevices.length} queued BLE device(s) "
        "sequentially",
      );

      // Take a snapshot so we can clear the list
      final toProcess = List<_PendingDevice>.from(_pendingDevices);
      _pendingDevices.clear();

      for (int i = 0; i < toProcess.length; i++) {
        final pending = toProcess[i];

        if (i > 0) {
          _log.fine(
            "Waiting ${_interDeviceDelay.inMilliseconds}ms before "
            "next device",
          );
          await Future.delayed(_interDeviceDelay);
        }

        await _createDeviceWithRetry(pending.deviceId, pending.factory);
      }
    }

    _deviceStreamController.add(_devices.toList());
  }

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

          // Re-scan briefly to refresh BlueZ's device cache.
          // After a failed connection + disconnect, flutter_blue_plus_linux
          // loses the device from its internal list, causing "Bad state:
          // No element" on subsequent connect attempts.
          _log.info("Running refresh scan to restore device in BlueZ cache");
          await _ensureScanStopped();
          await _runRefreshScan();
        }

        await _createDevice(deviceId, deviceFactory);
        return;
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

  /// Brief scan to refresh BlueZ's internal device cache before a retry.
  Future<void> _runRefreshScan() async {
    _log.fine(
        "Refresh scan for ${_refreshScanDuration.inSeconds}s");
    try {
      await FlutterBluePlus.startScan(
        withServices: deviceMappings.keys.map((e) => Guid(e)).toList(),
        oneByOne: true,
      );
      await Future.delayed(_refreshScanDuration);
      await FlutterBluePlus.stopScan();
      // Settle after refresh scan — must wait long enough for BlueZ to
      // fully exit scanning mode, otherwise connect hits
      // le-connection-abort-by-local.
      await Future.delayed(const Duration(seconds: 2));
    } catch (e) {
      _log.warning("Refresh scan failed: $e");
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
    }
  }

  Future<void> _createDevice(
    String deviceId,
    Future<Device> Function(BLETransport) deviceFactory,
  ) async {
    try {
      final transport = LinuxBluePlusTransport(remoteId: deviceId);
      final device = await deviceFactory(transport);

      if (_devices.firstWhereOrNull((d) => d.deviceId == deviceId) != null) {
        _log.fine("Device $deviceId already added, skipping duplicate");
        _devicesBeingCreated.remove(deviceId);
        return;
      }

      _devices.add(device);
      _deviceStreamController.add(_devices);
      _log.info("Device $deviceId added successfully");

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
      rethrow;
    }
  }

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
