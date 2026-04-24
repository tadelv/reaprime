import 'dart:io';

import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/services/serial/serial_service_android.dart';
import 'package:reaprime/src/services/serial/serial_service_desktop.dart';
import 'package:rxdart/subjects.dart';

/// Returns the correct serial discovery service for the current platform.
///
/// iOS has no viable USB-serial path: the only FFI-backed driver we ship
/// (`libserialport`) can't `dlopen` under iOS's hardened runtime, and the
/// failure fires at launch inside `SerialServiceDesktop.initialize()` /
/// `_performScan()` when they call `SerialPort.availablePorts`. That
/// surfaces as three Crashlytics FATALs (`9d5fc4e9`, `0f9ece6d`,
/// `39f895bc`) with SIGNAL_EARLY — 81% of events fire in the first
/// second of a session. Returning a no-op service on iOS avoids the
/// dlopen entirely.
DeviceDiscoveryService createSerialService() {
  if (Platform.isIOS) {
    return NoOpSerialService();
  }
  if (Platform.isAndroid) {
    return SerialServiceAndroid();
  }
  return SerialServiceDesktop();
}

/// Stand-in for platforms where USB serial isn't supported. Emits an
/// empty device list once and treats all scan calls as no-ops so the
/// `DeviceController` service loop remains uniform across platforms.
class NoOpSerialService implements DeviceDiscoveryService {
  final _devices = BehaviorSubject<List<Device>>.seeded(const <Device>[]);

  @override
  Stream<List<Device>> get devices => _devices.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> scanForDevices() async {}

  @override
  void stopScan() {}
}
