import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/impl/bengle/mock_bengle.dart';
import 'package:reaprime/src/models/device/impl/mock_de1/mock_de1.dart';
import 'package:reaprime/src/models/errors.dart';
import 'package:reaprime/src/services/webserver_service.dart';
import 'package:shelf_plus/shelf_plus.dart';

import '../../helpers/mock_device_discovery_service.dart';
import '../../helpers/mock_settings_service.dart';
import '../../helpers/test_scale.dart';
import '../../helpers/test_scale_controller.dart';

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
  late TestScaleController scaleController;

  Future<void> wireWith(De1Interface? device) async {
    final deviceController = DeviceController([MockDeviceDiscoveryService()]);
    await deviceController.initialize();
    controller = _FixedDe1Controller(
      controller: deviceController,
      device: device,
    );

    final mockSettings = MockSettingsService();
    settingsController = SettingsController(mockSettings);
    await settingsController.loadSettings();

    final testScale = TestScale();
    scaleController = TestScaleController(testScale);
    final de1Handler = De1Handler(
      controller: controller,
      settingsController: settingsController,
      scaleController: scaleController,
      workflowController: WorkflowController(),
    );
    final app = Router().plus;
    de1Handler.addRoutes(app);
    handler = app.call;
  }

  Future<Response> get(String path) async =>
      await handler(Request('GET', Uri.parse('http://localhost$path')));

  Future<Response> post(String path, Object body) async => await handler(
    Request(
      'POST',
      Uri.parse('http://localhost$path'),
      body: jsonEncode(body),
      headers: {HttpHeaders.contentTypeHeader: 'application/json'},
    ),
  );

  group('GET /api/v1/machine/capabilities — scaleCalibration', () {
    test('returns scaleCalibration when a Bengle is connected', () async {
      await wireWith(MockBengle());
      final res = await get('/api/v1/machine/capabilities');
      expect(res.statusCode, 200);
      final body = jsonDecode(await res.readAsString());
      expect(body['capabilities'], contains('scaleCalibration'));
    });

    test('does not return scaleCalibration on plain DE1', () async {
      await wireWith(MockDe1());
      final res = await get('/api/v1/machine/capabilities');
      final body = jsonDecode(await res.readAsString());
      expect(body['capabilities'], isNot(contains('scaleCalibration')));
    });
  });

  group('POST /api/v1/machine/scale/calibrate', () {
    test('200 + zero result on MockBengle', () async {
      await wireWith(MockBengle());
      final res = await post('/api/v1/machine/scale/calibrate', {
        'command': 'zero',
      });
      expect(res.statusCode, 200);
      final body = jsonDecode(await res.readAsString());
      expect(body['success'], isTrue);
      expect(body['finalStep'], 'complete');
      expect(body['pointStatus'], 'none');
    });

    test('200 + left latch reports pointStatus incomplete', () async {
      await wireWith(MockBengle());
      final res = await post('/api/v1/machine/scale/calibrate', {
        'command': 'left',
        'grams': 500,
      });
      expect(res.statusCode, 200);
      final body = jsonDecode(await res.readAsString());
      expect(body['success'], isTrue);
      expect(body['pointStatus'], 'incomplete');
    });

    test('200 + right latch reports pointStatus ok (solved)', () async {
      await wireWith(MockBengle());
      final res = await post('/api/v1/machine/scale/calibrate', {
        'command': 'right',
        'grams': 500,
      });
      expect(res.statusCode, 200);
      final body = jsonDecode(await res.readAsString());
      expect(body['success'], isTrue);
      expect(body['pointStatus'], 'ok');
    });

    test('202 on abort', () async {
      await wireWith(MockBengle());
      final res = await post('/api/v1/machine/scale/calibrate', {
        'command': 'abort',
      });
      expect(res.statusCode, 202);
    });

    test('400 when left is missing grams', () async {
      await wireWith(MockBengle());
      final res = await post('/api/v1/machine/scale/calibrate', {
        'command': 'left',
      });
      expect(res.statusCode, 400);
      final body = jsonDecode(await res.readAsString());
      expect(body['error'], contains('grams'));
    });

    test('400 when right is missing grams', () async {
      await wireWith(MockBengle());
      final res = await post('/api/v1/machine/scale/calibrate', {
        'command': 'right',
      });
      expect(res.statusCode, 400);
    });

    test('400 on an unknown command', () async {
      await wireWith(MockBengle());
      final res = await post('/api/v1/machine/scale/calibrate', {
        'command': 'wiggle',
      });
      expect(res.statusCode, 400);
      final body = jsonDecode(await res.readAsString());
      expect(body['error'], contains('wiggle'));
    });

    test('400 on a non-object JSON body', () async {
      await wireWith(MockBengle());
      // A bare JSON string is valid JSON but not an object — previously an
      // undocumented 500 (thrown inside the handler) instead of a 400.
      final res = await post('/api/v1/machine/scale/calibrate', 'zero');
      expect(res.statusCode, 400);
      final body = jsonDecode(await res.readAsString());
      expect(body['error'], contains('JSON object'));
    });

    test(
      '404 on plain DE1 (machine connected but capability absent)',
      () async {
        await wireWith(MockDe1());
        final res = await post('/api/v1/machine/scale/calibrate', {
          'command': 'zero',
        });
        expect(res.statusCode, 404);
      },
    );

    test('500 when no machine is connected', () async {
      await wireWith(null);
      final res = await post('/api/v1/machine/scale/calibrate', {
        'command': 'zero',
      });
      expect(res.statusCode, 500);
    });
  });
}
