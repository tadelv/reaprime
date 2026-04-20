import 'package:reaprime/src/models/adapter_state.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/scan_result.dart';

export 'package:reaprime/src/models/device/scan_result.dart';

/// Abstraction of what [ConnectionManager] needs from [DeviceController].
///
/// Enables testing ConnectionManager with a lightweight mock instead of
/// wiring up a full DeviceController with discovery services.
abstract class DeviceScanner {
  Stream<List<Device>> get deviceStream;
  Stream<bool> get scanningStream;
  List<Device> get devices;

  /// Runs one scan cycle across every discovery service and completes
  /// with the aggregated [ScanResult] when all services have finished
  /// (success or failure). Concurrent callers share the in-flight
  /// Future rather than triggering a second scan.
  ///
  /// Per-service failures are reported via [ScanResult.failedServices];
  /// the Future rejects only on catastrophic, scan-wide errors (the
  /// scan could not even be attempted).
  Future<ScanResult> scanForDevices();

  void stopScan();

  /// Aggregated Bluetooth adapter state across any BLE-capable discovery
  /// services. Non-BLE transports (serial, simulated) contribute nothing;
  /// if no BLE service is registered the stream emits [AdapterState.unknown].
  Stream<AdapterState> get adapterStateStream;
}
