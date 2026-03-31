import 'package:reaprime/src/models/adapter_state.dart';
import 'package:reaprime/src/models/device/device.dart';

/// BLE-transport-specific extension of DeviceDiscoveryService.
/// Adds Bluetooth adapter state monitoring.
/// Only BLE discovery services extend this — serial/simulated services do not.
abstract class BleDiscoveryService extends DeviceDiscoveryService {
  /// Stream of Bluetooth adapter state changes.
  /// Should replay current state on subscription (BehaviorSubject semantics).
  Stream<AdapterState> get adapterStateStream;
}
