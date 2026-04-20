import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/scan_result.dart';
import 'package:reaprime/src/models/errors.dart';
import 'package:rxdart/rxdart.dart';

/// A DeviceDiscoveryService that always throws from `scanForDevices`.
class _FailingDiscoveryService implements DeviceDiscoveryService {
  final _controller = BehaviorSubject<List<Device>>.seeded(const []);
  final Object error;

  _FailingDiscoveryService(this.error);

  @override
  Stream<List<Device>> get devices => _controller.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> scanForDevices() async {
    throw error;
  }

  @override
  void stopScan() {}
}

/// A DeviceDiscoveryService that succeeds and reports one device.
class _QuietDiscoveryService implements DeviceDiscoveryService {
  final _controller = BehaviorSubject<List<Device>>.seeded(const []);
  final Device device;

  _QuietDiscoveryService(this.device);

  @override
  Stream<List<Device>> get devices => _controller.stream;

  @override
  Future<void> initialize() async {
    _controller.add([device]);
  }

  @override
  Future<void> scanForDevices() async {
    // Re-emit on scan so the DeviceController populates its aggregated view.
    _controller.add([device]);
  }

  @override
  void stopScan() {}
}

/// Minimal `Device` stub.
class _FakeDevice implements Device {
  @override
  final String deviceId;

  @override
  final String name;

  @override
  final DeviceType type;

  _FakeDevice({required this.deviceId, required this.name, required this.type});

  @override
  Stream<ConnectionState> get connectionState =>
      Stream.value(ConnectionState.disconnected);

  @override
  Future<void> onConnect() async {}

  @override
  Future<void> disconnect() async {}
}

void main() {
  group('DeviceController.scanForDevices partial failures (comms-harden #22)',
      () {
    test(
      'one service throwing does not torpedo the scan — '
      'devices from succeeding services are still returned',
      () async {
        final failing =
            _FailingDiscoveryService(const PermissionDeniedException('denied'));
        final succeeding = _QuietDiscoveryService(
          _FakeDevice(
            deviceId: 'D9:11:0B:E6:9F:86',
            name: 'DE1',
            type: DeviceType.machine,
          ),
        );

        final controller = DeviceController([failing, succeeding]);
        await controller.initialize();

        final result = await controller.scanForDevices();

        expect(result.matchedDevices, hasLength(1),
            reason: 'succeeding service must still yield its device');
        expect(result.matchedDevices.first.deviceId, 'D9:11:0B:E6:9F:86');
        expect(result.failedServices, hasLength(1),
            reason: 'failing service must be surfaced in failedServices');
        expect(result.failedServices.first.error,
            isA<PermissionDeniedException>());
        expect(result.failedServices.first.serviceName,
            contains('FailingDiscoveryService'));
        expect(result.terminationReason, ScanTerminationReason.completed);
      },
    );

    test(
      'all services failing yields a ScanResult with empty matched + '
      'populated failedServices (no top-level throw)',
      () async {
        final a = _FailingDiscoveryService(Exception('adapter-off'));
        final b = _FailingDiscoveryService(const PermissionDeniedException());

        final controller = DeviceController([a, b]);
        await controller.initialize();

        final result = await controller.scanForDevices();

        expect(result.matchedDevices, isEmpty);
        expect(result.failedServices, hasLength(2));
      },
    );

    test(
      'concurrent scanForDevices calls share one in-flight scan',
      () async {
        final service = _QuietDiscoveryService(
          _FakeDevice(
            deviceId: 'id-1',
            name: 'D1',
            type: DeviceType.machine,
          ),
        );
        final controller = DeviceController([service]);
        await controller.initialize();

        final first = controller.scanForDevices();
        final second = controller.scanForDevices();

        expect(identical(first, second), isTrue,
            reason: 'second concurrent call must share the in-flight Future');
        await first;
      },
    );
  });

  // Gap F — regression coverage for comms-harden #20 (disconnect detection
  // keyed on device.name instead of deviceId). Kept as a skipped
  // placeholder; activate when the Phase 6 key-migration lands. See
  // doc/plans/comms-harden.md #20.
  group('disconnect tracking keys (comms-harden #20)', () {
    test(
      'two devices with same name but different IDs do not collide',
      () async {
        fail('pending Phase 6 fix for #20');
      },
      skip:
          'pending fix for comms-harden #20 — see doc/plans/comms-harden.md',
    );
  });
}
