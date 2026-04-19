import 'package:reaprime/src/models/adapter_state.dart';
import 'package:reaprime/src/models/device/device.dart';

/// Abstraction of what [ConnectionManager] needs from [DeviceController].
///
/// Enables testing ConnectionManager with a lightweight mock instead of
/// wiring up a full DeviceController with discovery services.
abstract class DeviceScanner {
  Stream<List<Device>> get deviceStream;
  Stream<bool> get scanningStream;
  List<Device> get devices;
  Future<void> scanForDevices();
  void stopScan();

  /// Aggregated Bluetooth adapter state across any BLE-capable discovery
  /// services. Non-BLE transports (serial, simulated) contribute nothing;
  /// if no BLE service is registered the stream emits [AdapterState.unknown].
  Stream<AdapterState> get adapterStateStream;
}
