import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/connection_manager.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/device.dart';

import '../helpers/mock_de1_controller.dart';
import '../helpers/mock_device_discovery_service.dart';
import '../helpers/mock_scale_controller.dart';
import '../helpers/test_scale.dart';

/// Minimal De1Interface stub for smoke-testing MockDe1Controller.
/// Uses noSuchMethod so we don't need to implement every member.
class _FakeDe1 implements De1Interface {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('ConnectionStatus', () {
    test('defaults to idle with empty lists', () {
      const status = ConnectionStatus();
      expect(status.phase, ConnectionPhase.idle);
      expect(status.foundMachines, isEmpty);
      expect(status.foundScales, isEmpty);
      expect(status.pendingAmbiguity, isNull);
      expect(status.error, isNull);
    });

    test('copyWith preserves fields not overridden', () {
      const status = ConnectionStatus(phase: ConnectionPhase.scanning);
      final updated = status.copyWith(phase: ConnectionPhase.ready);
      expect(updated.phase, ConnectionPhase.ready);
      expect(updated.foundMachines, isEmpty);
    });

    test('copyWith can null out optional fields', () {
      const status = ConnectionStatus(
        pendingAmbiguity: AmbiguityReason.machinePicker,
        error: 'something',
      );
      final cleared = status.copyWith(
        pendingAmbiguity: () => null,
        error: () => null,
      );
      expect(cleared.pendingAmbiguity, isNull);
      expect(cleared.error, isNull);
    });
  });

  group('MockDe1Controller', () {
    late MockDeviceDiscoveryService discoveryService;
    late DeviceController deviceController;
    late MockDe1Controller mockDe1Controller;

    setUp(() {
      discoveryService = MockDeviceDiscoveryService();
      deviceController = DeviceController([discoveryService]);
      mockDe1Controller = MockDe1Controller(controller: deviceController);
    });

    test('records connectToDe1 calls', () async {
      final fakeDe1 = _FakeDe1();
      await mockDe1Controller.connectToDe1(fakeDe1);

      expect(mockDe1Controller.connectCalls, hasLength(1));
      expect(mockDe1Controller.connectCalls.first, same(fakeDe1));
    });

    test('emits de1 on stream after successful connect', () async {
      final fakeDe1 = _FakeDe1();
      await mockDe1Controller.connectToDe1(fakeDe1);

      expect(mockDe1Controller.de1Subject.value, same(fakeDe1));
    });

    test('throws when shouldFailConnect is true', () async {
      mockDe1Controller.shouldFailConnect = true;
      final fakeDe1 = _FakeDe1();

      expect(
        () => mockDe1Controller.connectToDe1(fakeDe1),
        throwsA(isA<Exception>()),
      );
      // Call was still recorded
      expect(mockDe1Controller.connectCalls, hasLength(1));
    });

    test('de1 stream starts with null', () {
      expect(mockDe1Controller.de1Subject.value, isNull);
    });
  });

  group('MockScaleController', () {
    late MockDeviceDiscoveryService discoveryService;
    late DeviceController deviceController;
    late MockScaleController mockScaleController;

    setUp(() {
      discoveryService = MockDeviceDiscoveryService();
      deviceController = DeviceController([discoveryService]);
      mockScaleController = MockScaleController(controller: deviceController);
    });

    test('records connectToScale calls', () async {
      final testScale = TestScale();
      await mockScaleController.connectToScale(testScale);

      expect(mockScaleController.connectCalls, hasLength(1));
      expect(mockScaleController.connectCalls.first, same(testScale));
    });

    test('emits connected state after successful connect', () async {
      final testScale = TestScale();
      await mockScaleController.connectToScale(testScale);

      expect(
        mockScaleController.connectionStateSubject.value,
        ConnectionState.connected,
      );
    });

    test('throws when shouldFailConnect is true', () async {
      mockScaleController.shouldFailConnect = true;
      final testScale = TestScale();

      expect(
        () => mockScaleController.connectToScale(testScale),
        throwsA(isA<Exception>()),
      );
      // Call was still recorded
      expect(mockScaleController.connectCalls, hasLength(1));
    });

    test('connectionState starts with discovered', () {
      expect(
        mockScaleController.connectionStateSubject.value,
        ConnectionState.discovered,
      );
    });

    test('does not auto-connect when devices appear', () async {
      // Add a scale to discovery — the mock should NOT auto-connect
      final testScale = TestScale(deviceId: 'auto-scale');
      discoveryService.addDevice(testScale);

      // Give the stream time to propagate
      await Future.delayed(Duration.zero);

      expect(mockScaleController.connectCalls, isEmpty);
    });
  });
}
