import 'dart:async';

import 'package:reaprime/src/models/adapter_state.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/device_scanner.dart';
import 'package:reaprime/src/models/device/remembered_device.dart';
import 'package:reaprime/src/models/device/scan_filter.dart';
import 'package:reaprime/src/models/device/watch_filter.dart';
import 'package:rxdart/rxdart.dart';

/// A controllable [DeviceScanner] for testing [ConnectionManager].
///
/// Provides fine-grained control over device emissions and scan lifecycle.
/// Records [stopScan] calls for verification.
///
/// By default, [scanForDevices] completes immediately. Set [scanCompleter]
/// before calling to hold the scan open until you complete it manually —
/// useful for testing early-stop behavior.
class MockDeviceScanner implements DeviceScanner {
  final _deviceSubject = BehaviorSubject<List<Device>>.seeded([]);
  final _scanningSubject = BehaviorSubject<bool>.seeded(false);
  final _adapterStateSubject =
      BehaviorSubject<AdapterState>.seeded(AdapterState.unknown);
  final List<Device> _devices = [];

  /// Number of times [stopScan] has been called.
  int stopScanCallCount = 0;

  /// Number of times [scanForDevices] has been called (successful starts
  /// only — a [failNextScanWith] throw does not count).
  int scanCallCount = 0;

  /// When set, [scanForDevices] will emit `scanning: true` then wait for
  /// this completer before emitting `scanning: false`. This lets tests
  /// add devices mid-scan and verify early-stop behavior.
  Completer<void>? scanCompleter;
  final List<Completer<void>> queuedScanCompleters = [];
  final List<List<Device>> queuedScanResults = [];

  /// When set, the next [scanForDevices] call throws this object instead of
  /// running a scan. Consumed after one throw. Tests use this to exercise
  /// scan-start failure classification in [ConnectionManager].
  Object? failNextScanWith;

  /// Watch capability flag. Defaults to false so existing tests exercise
  /// the legacy backoff-reconnect path unchanged; background-scale-watch
  /// tests flip it on.
  bool supportsWatch = false;

  /// Filter passed to the most recent [startScaleWatch] call.
  DeviceWatchFilter? lastWatchFilter;

  /// Number of times [startScaleWatch] has been called.
  int startWatchCallCount = 0;

  /// Number of times [stopScaleWatch] has been called.
  int stopWatchCallCount = 0;

  /// True while a watch is running (started and not yet stopped).
  bool watchActive = false;

  /// When set, the next [startScaleWatch] call throws this object.
  /// Consumed after one throw. Tests use this to exercise the
  /// fall-back-to-legacy-backoff path in [ConnectionManager].
  Object? failNextWatchWith;

  final _watchFailuresSubject = PublishSubject<void>();

  /// Simulate a running watch dying without a possible restart (failed
  /// refresh / resume / adapter recovery in the real service).
  void emitWatchFailure() {
    watchActive = false;
    _watchFailuresSubject.add(null);
  }

  @override
  Stream<List<Device>> get deviceStream => _deviceSubject.stream;

  @override
  Stream<bool> get scanningStream => _scanningSubject.stream;

  @override
  Stream<AdapterState> get adapterStateStream =>
      _adapterStateSubject.stream;

  @override
  AdapterState get currentAdapterState => _adapterStateSubject.value;

  @override
  List<Device> get devices => List.from(_devices);

  /// Push an adapter state onto the stream for tests that drive environmental
  /// recovery paths in [ConnectionManager].
  void mockAdapterState(AdapterState state) {
    _adapterStateSubject.add(state);
  }

  /// Add a device and emit on the device stream.
  void addDevice(Device device) {
    _devices.add(device);
    _deviceSubject.add(List.from(_devices));
  }

  /// Remove a device by ID and emit.
  void removeDevice(String deviceId) {
    _devices.removeWhere((d) => d.deviceId == deviceId);
    _deviceSubject.add(List.from(_devices));
  }

  /// Reset all state for a fresh test.
  void reset() {
    _devices.clear();
    _deviceSubject.add([]);
    stopScanCallCount = 0;
    scanCallCount = 0;
    scanCompleter = null;
    queuedScanCompleters.clear();
    queuedScanResults.clear();
    failNextScanWith = null;
    quickConnectResult = null;
    quickConnectCallCount = 0;
  }

  /// Complete the scan. Only needed when [scanCompleter] is set.
  void completeScan() {
    scanCompleter?.complete();
    scanCompleter = null;
    _scanningSubject.add(false);
  }

  @override
  Future<ScanResult> scanForDevices({ScanFilter? filter}) async {
    if (failNextScanWith != null) {
      final e = failNextScanWith;
      failNextScanWith = null;
      throw e!;
    }
    scanCallCount++;
    final start = DateTime.now();
    final scanDevices =
        queuedScanResults.isNotEmpty ? queuedScanResults.removeAt(0) : _devices;
    _scanningSubject.add(true);
    _deviceSubject.add(List.from(scanDevices));
    final completer = queuedScanCompleters.isNotEmpty
        ? queuedScanCompleters.removeAt(0)
        : scanCompleter;
    if (completer != null) {
      await completer.future;
    } else {
      await Future.delayed(Duration.zero);
      _scanningSubject.add(false);
    }
    return ScanResult(
      matchedDevices: List.unmodifiable(scanDevices),
      failedServices: const [],
      terminationReason: ScanTerminationReason.completed,
      duration: DateTime.now().difference(start),
    );
  }

  @override
  void stopScan() {
    stopScanCallCount++;
  }

  /// When set, [tryQuickConnect] returns this device. When null (default),
  /// returns null to force the scan fallback path.
  Device? quickConnectResult;

  /// Number of times [tryQuickConnect] has been called.
  int quickConnectCallCount = 0;

  @override
  Future<Device?> tryQuickConnect(RememberedDevice remembered) async {
    quickConnectCallCount++;
    return quickConnectResult;
  }

  @override
  bool get supportsBackgroundWatch => supportsWatch;

  @override
  Future<void> startScaleWatch(DeviceWatchFilter filter) async {
    if (failNextWatchWith != null) {
      final e = failNextWatchWith;
      failNextWatchWith = null;
      throw e!;
    }
    startWatchCallCount++;
    lastWatchFilter = filter;
    watchActive = true;
  }

  @override
  Future<void> stopScaleWatch() async {
    stopWatchCallCount++;
    watchActive = false;
  }

  @override
  Stream<void> get scaleWatchFailures => _watchFailuresSubject.stream;

  void dispose() {
    _watchFailuresSubject.close();
    _deviceSubject.close();
    _scanningSubject.close();
    _adapterStateSubject.close();
  }
}
