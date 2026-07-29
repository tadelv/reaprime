import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/bengle_probe_bridge.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/sensor_controller.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/bengle/mock_bengle.dart';
import 'package:reaprime/src/models/device/scan_filter.dart';
import 'package:reaprime/src/models/device/impl/mock_de1/mock_de1.dart';
import 'package:rxdart/rxdart.dart';

class _EmptyDiscovery extends DeviceDiscoveryService {
  @override
  Stream<List<Device>> get devices => const Stream.empty();
  @override
  Future<void> initialize() async {}
  @override
  Future<void> scanForDevices({ScanFilter? filter}) async {}
}

class _StubDe1Controller extends De1Controller {
  _StubDe1Controller()
    : _subj = BehaviorSubject.seeded(null),
      super(controller: DeviceController([_EmptyDiscovery()]));

  final BehaviorSubject<De1Interface?> _subj;

  @override
  Stream<De1Interface?> get de1 => _subj.stream;

  void emit(De1Interface? device) => _subj.add(device);
}

void main() {
  group('BengleProbeBridge', () {
    late SensorController sensors;
    late _StubDe1Controller de1;
    late BengleProbeBridge bridge;

    setUp(() async {
      final deviceController = DeviceController([_EmptyDiscovery()]);
      await deviceController.initialize();
      sensors = SensorController(controller: deviceController);
      de1 = _StubDe1Controller();
      bridge = BengleProbeBridge(de1Controller: de1, sensorController: sensors);
    });

    tearDown(() async {
      await bridge.dispose();
      sensors.dispose();
    });

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test(
      'registers a probe when Bengle connects with probe attached',
      () async {
        final bengle = MockBengle();
        await bengle.onConnect();
        de1.emit(bengle);
        await settle();
        expect(sensors.sensors.keys, contains('${bengle.deviceId}-milkprobe'));
        await bengle.onDisconnect();
      },
    );

    test('does not register when probe is not attached', () async {
      final bengle = MockBengle(probeAttached: false);
      await bengle.onConnect();
      de1.emit(bengle);
      await settle();
      expect(sensors.sensors, isEmpty);
      await bengle.onDisconnect();
    });

    test('unregisters when probe detaches mid-session', () async {
      final bengle = MockBengle();
      await bengle.onConnect();
      de1.emit(bengle);
      await settle();
      expect(sensors.sensors, isNotEmpty);

      bengle.setProbeAttached(false);
      await settle();
      expect(sensors.sensors, isEmpty);
      await bengle.onDisconnect();
    });

    test('unregisters on machine disconnect', () async {
      final bengle = MockBengle();
      await bengle.onConnect();
      de1.emit(bengle);
      await settle();
      expect(sensors.sensors, isNotEmpty);

      de1.emit(null);
      await settle();
      expect(sensors.sensors, isEmpty);
      await bengle.onDisconnect();
    });

    test('does not register for non-Bengle machines', () async {
      final mockDe1 = MockDe1();
      await mockDe1.onConnect();
      de1.emit(mockDe1);
      await settle();
      expect(sensors.sensors, isEmpty);
      await mockDe1.onDisconnect();
    });
  });
}
