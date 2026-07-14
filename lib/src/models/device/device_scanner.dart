import 'package:reaprime/src/models/adapter_state.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/device_attach_notifier.dart';
import 'package:reaprime/src/models/device/remembered_device.dart';
import 'package:reaprime/src/models/device/scan_filter.dart';
import 'package:reaprime/src/models/device/scan_result.dart';
import 'package:reaprime/src/models/device/watch_filter.dart';

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
  Future<ScanResult> scanForDevices({ScanFilter? filter});

  void stopScan();

  /// Out-of-band "a device just arrived on the bus" edges, merged across every
  /// registered [DeviceAttachNotifier] service (today: Android USB serial).
  /// Consumers treat this as "scan now"; it says nothing about *which* device
  /// arrived being usable or preferred. Never emits for transports that can
  /// only discover by scanning.
  Stream<DeviceAttachedEvent> get deviceAttached;

  /// Aggregated Bluetooth adapter state across any BLE-capable discovery
  /// services. Non-BLE transports (serial, simulated) contribute nothing;
  /// if no BLE service is registered the stream emits [AdapterState.unknown].
  Stream<AdapterState> get adapterStateStream;

  /// Synchronous snapshot of the most recently emitted adapter state.
  /// Used by the scan orchestrator to populate `ScanReport` without
  /// awaiting a stream value (comms-harden #27).
  AdapterState get currentAdapterState;

  /// Attempt a direct connection to a remembered device without scanning.
  /// Iterates the registered discovery services, returning the first
  /// connected device or null if all services return null.
  Future<Device?> tryQuickConnect(RememberedDevice remembered);

  /// Whether any registered discovery service supports a persistent
  /// background device watch. Drives ConnectionManager's choice between
  /// the watch and the legacy backoff-burst scale reconnect loop.
  bool get supportsBackgroundWatch;

  /// Start a persistent low-duty-cycle scale watch on every supporting
  /// discovery service. Discoveries arrive through [deviceStream]; the
  /// watch does NOT flip [scanningStream] (no UI scanning indicator).
  Future<void> startScaleWatch(DeviceWatchFilter filter);

  /// Stop a watch started with [startScaleWatch]. Idempotent.
  Future<void> stopScaleWatch();

  /// Emits when a running scale watch dies and cannot be restarted.
  /// Consumers (ScaleWatch) must fall back to the legacy reconnect loop.
  Stream<void> get scaleWatchFailures;
}
