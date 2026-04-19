import 'dart:async';

import 'package:reaprime/src/models/adapter_state.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/device_scanner.dart';
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

  /// When set, [scanForDevices] will emit `scanning: true` then wait for
  /// this completer before emitting `scanning: false`. This lets tests
  /// add devices mid-scan and verify early-stop behavior.
  Completer<void>? scanCompleter;

  /// When set, the next [scanForDevices] call throws this object instead of
  /// running a scan. Consumed after one throw. Tests use this to exercise
  /// scan-start failure classification in [ConnectionManager].
  Object? failNextScanWith;

  @override
  Stream<List<Device>> get deviceStream => _deviceSubject.stream;

  @override
  Stream<bool> get scanningStream => _scanningSubject.stream;

  @override
  Stream<AdapterState> get adapterStateStream =>
      _adapterStateSubject.stream;

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

  /// Complete the scan. Only needed when [scanCompleter] is set.
  void completeScan() {
    scanCompleter?.complete();
    scanCompleter = null;
    _scanningSubject.add(false);
  }

  @override
  Future<void> scanForDevices() async {
    if (failNextScanWith != null) {
      final e = failNextScanWith;
      failNextScanWith = null;
      throw e!;
    }
    _scanningSubject.add(true);
    // Re-emit current devices to simulate scan rediscovery.
    // This ensures listeners that skip(1) the BehaviorSubject replay
    // still see the devices.
    _deviceSubject.add(List.from(_devices));
    if (scanCompleter != null) {
      await scanCompleter!.future;
    } else {
      await Future.delayed(Duration.zero);
      _scanningSubject.add(false);
    }
  }

  @override
  void stopScan() {
    stopScanCallCount++;
  }

  void dispose() {
    _deviceSubject.close();
    _scanningSubject.close();
    _adapterStateSubject.close();
  }
}
