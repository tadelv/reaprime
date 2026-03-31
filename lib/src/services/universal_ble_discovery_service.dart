import 'dart:async';
import 'package:reaprime/src/models/adapter_state.dart';
import 'package:reaprime/src/services/ble/ble_discovery_service.dart';
import 'package:reaprime/src/services/ble/universal_ble_transport.dart';
import 'package:reaprime/src/services/device_matcher.dart';
import 'package:rxdart/rxdart.dart';
import 'package:universal_ble/universal_ble.dart';
import '../models/device/device.dart';
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

  final BehaviorSubject<AdapterState> _adapterStateSubject =
      BehaviorSubject.seeded(AdapterState.unknown);

  @override
  Stream<AdapterState> get adapterStateStream => _adapterStateSubject.stream;

  @override
  Stream<List<Device>> get devices => _deviceStreamController.stream;

  @override
  Future<void> initialize() async {
    UniversalBle.queueType = QueueType.global;

    final initialState = await UniversalBle.getBluetoothAvailabilityState();
    _adapterStateSubject.add(_mapAvailabilityState(initialState));

    UniversalBle.availabilityStream.listen((state) {
      log.info("BLE Adapter state: ${state.name}");
      _adapterStateSubject.add(_mapAvailabilityState(state));
    });

    if (initialState != AvailabilityState.poweredOn) {
      log.warning("Bluetooth not supported on this platform");
      return;
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
      default:
        return AdapterState.unknown;
    }
  }

  bool _isBleDeviceId(String deviceId) {
    final macPattern = RegExp(r'^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$');
    final uuidPattern = RegExp(
      r'^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$',
    );
    return macPattern.hasMatch(deviceId) || uuidPattern.hasMatch(deviceId);
  }

  @override
  void stopScan() {
    UniversalBle.stopScan();
  }

  @override
  Future<void> scanForDevices() async {
    if (_isScanning) {
      log.warning('Scan already in progress, ignoring request');
      return;
    }

    _isScanning = true;

    try {
      log.fine("Clearing stale connections");
      _currentlyScanning.clear();

      var sub = UniversalBle.scanStream.listen((result) async {
        log.fine(
          "Found: ${result.deviceId}: ${result.name}, adv: ${result.services}",
        );
        if (_currentlyScanning.contains(result.deviceId)) {
          return;
        }
        await _deviceScanned(result);
      });

      // Unfiltered scan — empty services list
      final filter = ScanFilter(withServices: []);
      await UniversalBle.startScan(scanFilter: filter);

      final systemDevices = await UniversalBle.getSystemDevices(
        withServices: [],
      );
      for (var d in systemDevices) {
        await _deviceScanned(d);
      }

      await Future.delayed(Duration(seconds: 15), () async {
        await UniversalBle.stopScan();
        await sub.cancel();
        _deviceStreamController.add(_devices.values.toList());
      });
    } finally {
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

        _connections[device.deviceId.toString()] = _devices[device.deviceId
                .toString()]!
            .connectionState
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
}
