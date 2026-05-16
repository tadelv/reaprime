import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/impl/bengle/mock_bengle.dart';
import 'package:reaprime/src/models/device/impl/mock_de1/mock_de1.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/errors.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:reaprime/src/services/webserver_service.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:rxdart/rxdart.dart';

import '../../helpers/mock_device_discovery_service.dart';
import '../../helpers/mock_settings_service.dart';
import '../../helpers/test_scale.dart';

/// ScaleController subclass with controllable connection state and weight
/// emission.
class _TestScaleController extends ScaleController {
  final TestScale testScale;
  final BehaviorSubject<ConnectionState> _connectionState;
  final BehaviorSubject<WeightSnapshot> _weight = BehaviorSubject();

  _TestScaleController(this.testScale)
      : _connectionState = BehaviorSubject.seeded(ConnectionState.connected);

  @override
  Stream<ConnectionState> get connectionState => _connectionState.stream;

  @override
  ConnectionState get currentConnectionState => _connectionState.value;

  @override
  Stream<WeightSnapshot> get weightSnapshot => _weight.stream;

  @override
  Scale connectedScale() {
    if (_connectionState.value != ConnectionState.connected) {
      throw 'No scale connected';
    }
    return testScale;
  }

  void emitWeight(double weight, {double weightFlow = 0.0}) {
    _weight.add(WeightSnapshot(
      timestamp: DateTime(2026, 1, 15, 8, 0),
      weight: weight,
      weightFlow: weightFlow,
    ));
  }

  void simulateDisconnect() {
    _connectionState.add(ConnectionState.disconnected);
  }

  @override
  void dispose() {
    _connectionState.close();
    _weight.close();
    super.dispose();
  }
}

class _FixedDe1Controller extends De1Controller {
  _FixedDe1Controller({required super.controller, this.device});

  De1Interface? device;

  @override
  De1Interface connectedDe1() {
    final d = device;
    if (d == null) throw const DeviceNotConnectedException.machine();
    return d;
  }
}

void main() {
  late Handler handler;
  late _FixedDe1Controller controller;
  late SettingsController settingsController;
  late ScaleController scaleController;

  Future<void> wireWith(De1Interface? device) async {
    final deviceController =
        DeviceController([MockDeviceDiscoveryService()]);
    await deviceController.initialize();
    controller =
        _FixedDe1Controller(controller: deviceController, device: device);
    
    final mockSettings = MockSettingsService();
    settingsController = SettingsController(mockSettings);
    await settingsController.loadSettings();

    final testScale = TestScale();
    scaleController = _TestScaleController(testScale);
    final de1Handler = De1Handler(controller: controller, settingsController: settingsController, scaleController: scaleController);
    final app = Router().plus;
    de1Handler.addRoutes(app);
    handler = app.call;
  }

  Future<Response> get(String path) async =>
      await handler(Request('GET', Uri.parse('http://localhost$path')));

  Future<Response> put(String path, Object body) async =>
      await handler(Request(
        'PUT',
        Uri.parse('http://localhost$path'),
        body: jsonEncode(body),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      ));

  group('GET /api/v1/machine/capabilities', () {
    test('returns cupWarmer when a Bengle is connected', () async {
      await wireWith(MockBengle());
      final res = await get('/api/v1/machine/capabilities');
      expect(res.statusCode, 200);
      final body = jsonDecode(await res.readAsString());
      expect(body['capabilities'], contains('cupWarmer'));
    });

    test('returns empty list for a plain DE1', () async {
      await wireWith(MockDe1());
      final res = await get('/api/v1/machine/capabilities');
      expect(res.statusCode, 200);
      final body = jsonDecode(await res.readAsString());
      expect(body['capabilities'], isEmpty);
    });

    test('returns integratedScale when a Bengle is connected', () async {
      await wireWith(MockBengle());
      final res = await get('/api/v1/machine/capabilities');
      final body = jsonDecode(await res.readAsString());
      expect(body['capabilities'], contains('integratedScale'));
    });

    test('does not return integratedScale on plain DE1', () async {
      await wireWith(MockDe1());
      final res = await get('/api/v1/machine/capabilities');
      final body = jsonDecode(await res.readAsString());
      expect(body['capabilities'], isNot(contains('integratedScale')));
    });
  });

  group('GET /api/v1/machine/cupWarmer', () {
    test('200 + initial setpoint 0.0 on MockBengle', () async {
      await wireWith(MockBengle());
      final res = await get('/api/v1/machine/cupWarmer');
      expect(res.statusCode, 200);
      final body = jsonDecode(await res.readAsString());
      expect(body['temperature'], 0.0);
    });

    test('404 on plain DE1 (machine connected but capability absent)',
        () async {
      await wireWith(MockDe1());
      final res = await get('/api/v1/machine/cupWarmer');
      expect(res.statusCode, 404);
    });
  });

  group('PUT /api/v1/machine/cupWarmer', () {
    test('200 + writes setpoint into MockBengle', () async {
      final bengle = MockBengle();
      await wireWith(bengle);

      final res = await put('/api/v1/machine/cupWarmer', {'temperature': 60});
      expect(res.statusCode, 200);
      expect(await bengle.getCupWarmerTemperature(), 60.0);
    });

    test('400 on out-of-range temperature', () async {
      await wireWith(MockBengle());
      final res = await put('/api/v1/machine/cupWarmer', {'temperature': 100});
      expect(res.statusCode, 400);
    });

    test('400 on negative temperature', () async {
      await wireWith(MockBengle());
      final res = await put('/api/v1/machine/cupWarmer', {'temperature': -5});
      expect(res.statusCode, 400);
    });

    test('400 when temperature key is missing', () async {
      await wireWith(MockBengle());
      final res = await put('/api/v1/machine/cupWarmer', {});
      expect(res.statusCode, 400);
    });

    test('404 on plain DE1', () async {
      await wireWith(MockDe1());
      final res = await put('/api/v1/machine/cupWarmer', {'temperature': 60});
      expect(res.statusCode, 404);
    });
  });
}
