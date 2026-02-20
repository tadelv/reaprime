import 'package:reaprime/src/models/device/device.dart';
import 'package:rxdart/rxdart.dart';

/// A controllable DeviceDiscoveryService for widget tests.
///
/// Unlike SimulatedDeviceService (fixed device set, no timing control),
/// this lets tests add/remove specific devices at specific times.
class MockDeviceDiscoveryService implements DeviceDiscoveryService {
  final _controller = BehaviorSubject<List<Device>>.seeded([]);
  final List<Device> _devices = [];

  @override
  Stream<List<Device>> get devices => _controller.stream;

  /// Add a device and notify listeners immediately.
  void addDevice(Device device) {
    _devices.add(device);
    _controller.add(List.from(_devices));
  }

  /// Remove a device by ID and notify listeners.
  void removeDevice(String deviceId) {
    _devices.removeWhere((d) => d.deviceId == deviceId);
    _controller.add(List.from(_devices));
  }

  /// Remove all devices.
  void clear() {
    _devices.clear();
    _controller.add([]);
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> scanForDevices() async {}

  @override
  Future<void> scanForSpecificDevices(List<String> deviceIds) async {}

  void dispose() {
    _controller.close();
  }
}
