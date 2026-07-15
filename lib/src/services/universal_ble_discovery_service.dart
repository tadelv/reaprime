import 'dart:async';
import 'dart:io' show Platform;
import 'package:reaprime/src/models/adapter_state.dart';
import 'package:reaprime/src/models/device/device_implementation.dart';
import 'package:reaprime/src/models/device/remembered_device.dart';
import 'package:reaprime/src/models/device/transport/ble_connect_exception.dart';
import 'package:reaprime/src/models/device/transport/data_transport.dart';
import 'package:reaprime/src/models/device/scan_filter.dart' as domain;
import 'package:reaprime/src/services/ble/ble_discovery_service.dart';
import 'package:reaprime/src/services/ble/universal_ble_transport.dart';
import 'package:reaprime/src/services/device_factory.dart';
import 'package:reaprime/src/services/device_matcher.dart';
import 'package:rxdart/rxdart.dart';
import 'package:universal_ble/universal_ble.dart';
import '../models/device/device.dart';
import '../models/device/machine.dart';
import '../models/device/impl/de1/de1.models.dart';
import 'package:logging/logging.dart' as logging;

class UniversalBleDiscoveryService extends BleDiscoveryService {
  UniversalBleDiscoveryService();

  final Map<String, Device> _devices = {};

  final log = logging.Logger("UniversalBleDeviceService");

  final StreamController<List<Device>> _deviceStreamController =
      StreamController.broadcast();

  final Map<String, StreamSubscription<ConnectionState>> _connections = {};

  final List<String> _currentlyScanning = [];

  bool _isScanning = false;

  // Cancellable 15s scan-duration wait. External stopScan() cancels the
  // timer and completes the completer so scanForDevices returns promptly
  // instead of being pinned for 15s with _isScanning stuck true
  // (parity with BluePlusDiscoveryService, comms-harden #11).
  Timer? _scanDurationTimer;
  Completer<void>? _scanDurationCompleter;

  final BehaviorSubject<AdapterState> _adapterStateSubject =
      BehaviorSubject.seeded(AdapterState.unknown);

  @override
  Stream<AdapterState> get adapterStateStream => _adapterStateSubject.stream;

  @override
  Stream<List<Device>> get devices => _deviceStreamController.stream;

  @override
  Future<void> initialize() async {
    // perDevice: each BLE peripheral gets its own command queue, so
    // DE1 GATT operations never block scale heartbeat writes and vice
    // versa. Mirrors flutter_blue_plus' per-connection serialization.
    UniversalBle.queueType = QueueType.perDevice;

    var initialState = await UniversalBle.getBluetoothAvailabilityState();

    // iOS with bluetooth-central background mode: universal_ble returns
    // `unknown` without creating CBCentralManager when permission is
    // .notDetermined, to avoid triggering the permission prompt during
    // background state-restoration launches. Force-create the manager
    // here so the system permission dialog appears on first foreground
    // launch and the availability stream resolves to the real state.
    if (Platform.isIOS && initialState == AvailabilityState.unknown) {
      log.info('iOS adapter state is unknown; requesting BLE permissions');
      await UniversalBle.requestPermissions();
      initialState = await UniversalBle.getBluetoothAvailabilityState();
    }

    _adapterStateSubject.add(_mapAvailabilityState(initialState));

    UniversalBle.availabilityStream.listen((state) {
      log.info("BLE Adapter state: ${state.name}");
      _adapterStateSubject.add(_mapAvailabilityState(state));
    });

    if (initialState != AvailabilityState.poweredOn) {
      log.warning("Bluetooth not supported on this platform, state: ${initialState.name}");
    }
  }

  static AdapterState _mapAvailabilityState(AvailabilityState state) {
    switch (state) {
      case AvailabilityState.poweredOn:
        return AdapterState.poweredOn;
      case AvailabilityState.poweredOff:
        return AdapterState.poweredOff;
      case AvailabilityState.unsupported:
        return AdapterState.unavailable;
      case AvailabilityState.unauthorized:
        return AdapterState.unauthorized;
      default:
        return AdapterState.unknown;
    }
  }

  @override
  void stopScan() {
    _cancelScanDurationWait();
    UniversalBle.stopScan();
  }

  /// Cancel the scheduled 15s stopScan and unblock the awaiter in
  /// scanForDevices so it can proceed to cleanup / free `_isScanning`.
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
  /// `stopScan()` is called. The BLE scan is stopped in either case.
  Future<void> _waitForScanDuration(Duration duration) async {
    final completer = Completer<void>();
    _scanDurationCompleter = completer;
    _scanDurationTimer = Timer(duration, () async {
      try {
        await UniversalBle.stopScan();
      } catch (e, st) {
        log.warning('Scheduled stopScan failed', e, st);
      }
      _cancelScanDurationWait();
    });
    await completer.future;
  }

  @override
  Future<void> scanForDevices({domain.ScanFilter? filter}) async {
    final state = _adapterStateSubject.value;
    if (state != AdapterState.poweredOn) {
      log.warning("Cannot scan, adapter state is $state");
      _deviceStreamController.add(_devices.values.toList());
      return;
    }
    if (_isScanning) {
      log.warning('Scan already in progress, ignoring request');
      return;
    }

    _isScanning = true;
    StreamSubscription<BleDevice>? sub;

    try {
      log.fine("Clearing stale connections");
      _currentlyScanning.clear();

      sub = UniversalBle.scanStream.listen((result) async {
        log.finest(
          "Found: ${result.deviceId}: ${result.name}, adv: ${result.services}",
        );
        if (_currentlyScanning.contains(result.deviceId)) {
          return;
        }
        await _deviceScanned(result);
      });

      // Unfiltered scan — empty services list (sb-044: name-match is the
      // documented discovery path; service UUIDs are only a scan-filter
      // optimization, not needed on macOS/iOS).
      final scanFilter = ScanFilter(withServices: []);

      // Android: use aggressive scan settings to avoid the chip-side
      // advert de-duplication that throttles results to ~1 per 12 s.
      // matchMode: aggressive disables firmware-layer de-duplication;
      // numOfMatches: max removes the per-device match cap;
      // scanMode: lowLatency prioritises scan duty cycle over power.
      // callbackType omitted: allMatches is the Android default, and
      // matchLost causes IllegalArgumentException on some GSI images.
      final platformConfig = Platform.isAndroid
          ? PlatformConfig(
              android: AndroidOptions(
                scanMode: AndroidScanMode.lowLatency,
                matchMode: AndroidScanMatchMode.aggressive,
                numOfMatches: AndroidScanNumOfMatches.max,
              ),
            )
          : null;
      await UniversalBle.startScan(
        scanFilter: scanFilter,
        platformConfig: platformConfig,
      );

      // CoreBluetooth/BlueZ hide system-connected/bonded BLE devices from
      // scan results; query them explicitly so a DE1 paired via System
      // Settings is still discovered (#126). Optional — must never abort the
      // main scan (parity with BluePlusDiscoveryService's macOS guard), so
      // failures are swallowed.
      try {
        final systemDevices = await UniversalBle.getSystemDevices(
          withServices: [],
        );
        for (var d in systemDevices) {
          await _deviceScanned(d);
        }
      } catch (e, st) {
        log.fine('System device check failed', e, st);
      }

      // Scan for up to 15s; external stopScan() ends the wait early so the
      // scanner frees `_isScanning` without waiting out the full duration.
      await _waitForScanDuration(const Duration(seconds: 15));
    } finally {
      await sub?.cancel();
      _cancelScanDurationWait();
      _deviceStreamController.add(_devices.values.toList());
      _isScanning = false;
    }
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

        _connections[device.deviceId
            .toString()] = _devices[device.deviceId.toString()]!.connectionState
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

  @override
  Future<Device?> tryQuickConnect(RememberedDevice remembered) async {
    final impl = remembered.implementation;
    final tt = remembered.transportType;
    if (impl == null || tt == null || tt != TransportType.ble) {
      return null;
    }

    final deviceId = remembered.id;

    BleDevice? bleDevice;
    if (Platform.isIOS || Platform.isMacOS) {
      bleDevice = await _findSystemDevice(deviceId);
      if (bleDevice == null) {
        log.info('Quick-connect: device $deviceId not in system cache');
        return null;
      }
    } else {
      bleDevice = BleDevice(deviceId: deviceId, name: remembered.name);
    }

    final transport = UniversalBleTransport(device: bleDevice);
    final device = DeviceFactory.createBle(impl, transport);
    if (device == null) {
      log.warning('Quick-connect: DeviceFactory returned null for $impl');
      return null;
    }

    try {
      await _connectWithRetry(device);
      if (device is Machine) {
        final model = device.machineInfo.model;
        final expectedBengle = impl == DeviceImplementation.bengle;
        final actualBengle = model == DecentMachineModel.Bengle.name;
        if (expectedBengle != actualBengle) {
          log.warning(
            'Quick-connect: identity mismatch for $deviceId '
            '(expected ${impl.name}, got model=$model)',
          );
          try { await device.disconnect(); } catch (_) {}
          try { await transport.dispose(); } catch (_) {}
          return null;
        }
      }
      _devices[deviceId] = device;
      _deviceStreamController.add(_devices.values.toList());
      _connections[deviceId] = device.connectionState.listen((state) {
        if (state == ConnectionState.disconnected) {
          _devices.remove(deviceId);
          _deviceStreamController.add(_devices.values.toList());
        }
      });
      log.info('Quick-connect succeeded for $deviceId');
      return device;
    } catch (e, st) {
      log.warning('Quick-connect failed for $deviceId', e, st);
      try {
        await device.disconnect();
      } catch (_) {}
      try {
        await transport.dispose();
      } catch (_) {}
      return null;
    }
  }

  Future<BleDevice?> _findSystemDevice(String deviceId) async {
    try {
      final systemDevices = await UniversalBle.getSystemDevices(
        withServices: [],
      );
      for (final d in systemDevices) {
        if (d.deviceId == deviceId) return d;
      }
    } catch (e, st) {
      log.fine('getSystemDevices failed during quick-connect', e, st);
    }
    return null;
  }

  Future<void> _connectWithRetry(Device device) async {
    const timeout = Duration(seconds: 10);
    try {
      await device.onConnect().timeout(timeout);
    } on BleConnectException catch (e) {
      log.info('Quick-connect GATT error ($e), retrying once after 1s');
      await Future.delayed(const Duration(seconds: 1));
      try {
        await device.disconnect();
      } catch (_) {}
      await device.onConnect().timeout(timeout);
    }
  }
}
