import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/scan_result.dart';
import 'package:reaprime/src/models/errors.dart';
import 'package:reaprime/src/services/telemetry/telemetry_service.dart';
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

/// Manual discovery service — tests push emissions by calling `emit`.
class _ManualDiscoveryService implements DeviceDiscoveryService {
  final _controller = BehaviorSubject<List<Device>>.seeded(const []);

  @override
  Stream<List<Device>> get devices => _controller.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> scanForDevices() async {}

  @override
  void stopScan() {}

  void emit(List<Device> devices) => _controller.add(devices);
}

class _RecordingTelemetry implements TelemetryService {
  final Map<String, Object> customKeys = {};

  @override
  Future<void> initialize() async {}

  @override
  Future<void> recordError(Object error, StackTrace? stackTrace,
      {bool fatal = false}) async {}

  @override
  Future<void> log(String message) async {}

  @override
  Future<void> setCustomKey(String key, Object value) async {
    customKeys[key] = value;
  }

  @override
  Future<void> setConsentEnabled(bool enabled) async {}

  @override
  String getLogBuffer() => '';
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

  group('devices getter caching (comms-harden #28)', () {
    test(
      'repeat getter calls return the same list instance until a mutation',
      () async {
        final service = _ManualDiscoveryService();
        final controller = DeviceController([service]);
        await controller.initialize();

        service.emit([
          _FakeDevice(
            deviceId: 'AA:11:11:11:11:11',
            name: 'DE1',
            type: DeviceType.machine,
          ),
        ]);
        await Future<void>.delayed(Duration.zero);

        final first = controller.devices;
        final second = controller.devices;
        expect(identical(first, second), isTrue,
            reason: 'cache should return the same instance on a hot call');

        service.emit(const []);
        await Future<void>.delayed(Duration.zero);

        final afterMutation = controller.devices;
        expect(identical(first, afterMutation), isFalse,
            reason: 'cache must rebuild after a device-list mutation');
      },
    );
  });

  group('disconnect tracking keys (comms-harden #20)', () {
    test(
      'two devices with same name but different IDs do not collide on disconnect',
      () async {
        final service = _ManualDiscoveryService();
        final telemetry = _RecordingTelemetry();
        final controller = DeviceController([service])
          ..telemetryService = telemetry;
        await controller.initialize();

        final a = _FakeDevice(
          deviceId: 'AA:11:11:11:11:11',
          name: 'DE1',
          type: DeviceType.machine,
        );
        final b = _FakeDevice(
          deviceId: 'BB:22:22:22:22:22',
          name: 'DE1',
          type: DeviceType.machine,
        );

        // Baseline: both present.
        service.emit([a, b]);
        await Future<void>.delayed(Duration.zero);

        // Drop b only.
        service.emit([a]);
        await Future<void>.delayed(Duration.zero);

        // Bring b back. Only b's reconnection_duration_* should land,
        // not a's (would happen with name-based keying since both named
        // 'DE1').
        service.emit([a, b]);
        await Future<void>.delayed(Duration.zero);

        expect(telemetry.customKeys,
            contains('reconnection_duration_${b.deviceId}'));
        expect(telemetry.customKeys,
            isNot(contains('reconnection_duration_${a.deviceId}')));
      },
    );

    test(
      'device returning with a different advertised name is still matched by id',
      () async {
        final service = _ManualDiscoveryService();
        final telemetry = _RecordingTelemetry();
        final controller = DeviceController([service])
          ..telemetryService = telemetry;
        await controller.initialize();

        final before = _FakeDevice(
          deviceId: 'CC:33:33:33:33:33',
          name: 'DE1',
          type: DeviceType.machine,
        );
        final afterFirmware = _FakeDevice(
          deviceId: 'CC:33:33:33:33:33',
          name: 'DE1Pro', // firmware update renamed advertised name
          type: DeviceType.machine,
        );

        service.emit([before]);
        await Future<void>.delayed(Duration.zero);
        service.emit(const []);
        await Future<void>.delayed(Duration.zero);
        service.emit([afterFirmware]);
        await Future<void>.delayed(Duration.zero);

        expect(telemetry.customKeys,
            contains('reconnection_duration_${before.deviceId}'));
      },
    );

    test(
      'telemetry device_<id>_type key uses deviceId, not name',
      () async {
        final service = _ManualDiscoveryService();
        final telemetry = _RecordingTelemetry();
        final controller = DeviceController([service])
          ..telemetryService = telemetry;
        await controller.initialize();

        final a = _FakeDevice(
          deviceId: 'AA:11:11:11:11:11',
          name: 'DE1',
          type: DeviceType.machine,
        );
        final b = _FakeDevice(
          deviceId: 'BB:22:22:22:22:22',
          name: 'DE1',
          type: DeviceType.scale,
        );

        service.emit([a, b]);
        await Future<void>.delayed(Duration.zero);

        expect(telemetry.customKeys, contains('device_${a.deviceId}_type'));
        expect(telemetry.customKeys, contains('device_${b.deviceId}_type'));
        expect(telemetry.customKeys['device_${a.deviceId}_type'], 'machine');
        expect(telemetry.customKeys['device_${b.deviceId}_type'], 'scale');
      },
    );
  });
}
