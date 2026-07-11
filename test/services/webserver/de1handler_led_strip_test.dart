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
import 'package:reaprime/src/models/device/led_strip.dart';
import 'package:reaprime/src/models/errors.dart';
import 'package:reaprime/src/services/webserver_service.dart';
import 'package:shelf_plus/shelf_plus.dart';

import 'package:reaprime/src/models/device/impl/bengle/bengle.dart';

import '../../helpers/fake_ble_transport.dart';
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
    final deviceController =
        DeviceController([MockDeviceDiscoveryService()]);
    await deviceController.initialize();
    controller =
        _FixedDe1Controller(controller: deviceController, device: device);

    final mockSettings = MockSettingsService();
    settingsController = SettingsController(mockSettings);
    await settingsController.loadSettings();

    final testScale = TestScale();
    scaleController = TestScaleController(testScale);

    final de1Handler = De1Handler(controller: controller, settingsController: settingsController, scaleController: scaleController, workflowController: WorkflowController());
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

  Future<Response> post(String path, [Object body = const {}]) async =>
      await handler(Request(
        'POST',
        Uri.parse('http://localhost$path'),
        body: jsonEncode(body),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      ));

  group('GET /api/v1/machine/capabilities — ledStrip', () {
    test('returns ledStrip when a Bengle is connected', () async {
      await wireWith(MockBengle());
      final res = await get('/api/v1/machine/capabilities');
      final body = jsonDecode(await res.readAsString());
      expect(body['capabilities'], contains('ledStrip'));
    });

    test('does not return ledStrip on plain DE1', () async {
      await wireWith(MockDe1());
      final res = await get('/api/v1/machine/capabilities');
      final body = jsonDecode(await res.readAsString());
      expect(body['capabilities'], isNot(contains('ledStrip')));
    });
  });

  group('GET /api/v1/machine/ledStrip', () {
    test('200 + initial all-off on MockBengle', () async {
      await wireWith(MockBengle());
      final res = await get('/api/v1/machine/ledStrip');
      expect(res.statusCode, 200);
      final body = jsonDecode(await res.readAsString());
      expect(body['frontStrip']['sleeping'], '000000000000');
      expect(body['frontStrip']['awake'], '000000000000');
      expect(body['backStrip']['sleeping'], '000000000000');
      expect(body['backStrip']['awake'], '000000000000');
      expect(body['frontSwitch']['sleeping'], '000000000000');
      expect(body['frontSwitch']['awake'], '000000000000');
    });

    test('404 on plain DE1', () async {
      await wireWith(MockDe1());
      final res = await get('/api/v1/machine/ledStrip');
      expect(res.statusCode, 404);
    });

    test('200 + serves the machine-stored palette after connect-time '
        'hydration (real Bengle over fake transport)', () async {
      // The user-facing fix: after an app restart the first GET must show
      // the colours stored on the machine, not all-off — no PUT/reset (and
      // no skin change) needed first.
      final transport = FakeBleTransport();
      final bengle = Bengle(transport: transport);
      transport.queueOnConnectResponses(
        v13Model: 128, // Bengle marker
        ledFrontAwake: 0x385A92,
        ledFrontSleep: 0x112233,
        ledRearAwake: 0xFF7A00,
        ledRearSleep: 0x0000FF,
      );
      await bengle.onConnect();
      addTearDown(transport.dispose);
      await wireWith(bengle);

      final res = await get('/api/v1/machine/ledStrip');
      expect(res.statusCode, 200);
      final body = jsonDecode(await res.readAsString());
      expect(body['frontStrip']['awake'], '38385A5A9292');
      expect(body['frontStrip']['sleeping'], '111122223333');
      expect(body['backStrip']['awake'], 'FFFF7A7A0000');
      expect(body['backStrip']['sleeping'], '00000000FFFF');
      // Switch mirrors the front strip on read.
      expect(body['frontSwitch']['awake'], '38385A5A9292');
      expect(body['frontSwitch']['sleeping'], '111122223333');
    });
  });

  group('PUT /api/v1/machine/ledStrip', () {
    test('200 + writes state into MockBengle', () async {
      final bengle = MockBengle();
      await wireWith(bengle);

      final res = await put('/api/v1/machine/ledStrip', {
        'frontStrip': {'sleeping': 'FFFF80000000', 'awake': '000000000000'},
        'backStrip': {'sleeping': '000000000000', 'awake': 'FFFFFFFFFFFF'},
        'frontSwitch': {'sleeping': '000000000000', 'awake': '000000000000'},
      });
      expect(res.statusCode, 200);

      final state = await bengle.getLedStripState();
      expect(state.frontStrip.sleeping,
          const Color16(65535, 32768, 0));
      expect(state.frontStrip.awake, Color16.off);
      expect(state.backStrip.awake,
          const Color16(65535, 65535, 65535));
    });

    test('400 on non-map body', () async {
      await wireWith(MockBengle());
      final res = await put('/api/v1/machine/ledStrip', [1, 2, 3]);
      expect(res.statusCode, 400);
    });

    test('malformed hex defaults to zero', () async {
      final bengle = MockBengle();
      await wireWith(bengle);

      final res = await put('/api/v1/machine/ledStrip', {
        'frontStrip': {'sleeping': 'XXYY', 'awake': '000000000000'},
        'backStrip': {'sleeping': '000000000000', 'awake': '000000000000'},
        'frontSwitch': {'sleeping': '000000000000', 'awake': '000000000000'},
      });
      expect(res.statusCode, 200);

      final state = await bengle.getLedStripState();
      expect(state.frontStrip.sleeping, Color16.off);
    });

    test('404 on plain DE1', () async {
      await wireWith(MockDe1());
      final res = await put('/api/v1/machine/ledStrip', {
        'frontStrip': {'sleeping': 'FFFF80000000', 'awake': '000000000000'},
        'backStrip': {'sleeping': '000000000000', 'awake': '000000000000'},
        'frontSwitch': {'sleeping': '000000000000', 'awake': '000000000000'},
      });
      expect(res.statusCode, 404);
    });
  });

  group('POST /api/v1/machine/ledStrip/commit', () {
    test('202 on Bengle', () async {
      await wireWith(MockBengle());
      final res = await post('/api/v1/machine/ledStrip/commit');
      expect(res.statusCode, 202);
    });

    test('404 on plain DE1', () async {
      await wireWith(MockDe1());
      final res = await post('/api/v1/machine/ledStrip/commit');
      expect(res.statusCode, 404);
    });
  });

  group('POST /api/v1/machine/ledStrip/reset', () {
    test('200 + returns state on Bengle', () async {
      final bengle = MockBengle();
      await wireWith(bengle);

      // Write a config, commit it, overwrite cache, then reset.
      final written = LedStripState(
        frontStrip: ZoneLedState(
            sleeping: const Color16(65535, 0, 0),
            awake: Color16.off),
      );
      await bengle.setLedStrip(written);
      await bengle.commitLedStrip();
      // Overwrite with something else.
      await bengle.setLedStrip(const LedStripState());

      final res = await post('/api/v1/machine/ledStrip/reset');
      expect(res.statusCode, 200);
      final body = jsonDecode(await res.readAsString());
      // After reset, cache is back to what was committed.
      expect(body['frontStrip']['sleeping'], 'FFFF00000000');
    });

    test('404 on plain DE1', () async {
      await wireWith(MockDe1());
      final res = await post('/api/v1/machine/ledStrip/reset');
      expect(res.statusCode, 404);
    });
  });

  group('POST /api/v1/machine/ledStrip/preview', () {
    test('202 on Bengle', () async {
      await wireWith(MockBengle());
      final res = await post('/api/v1/machine/ledStrip/preview', {
        'front': 'FFFF00000000',
        'back': '00000000FFFF',
      });
      expect(res.statusCode, 202);
    });

    test('202 + preview does not touch the stored config', () async {
      final bengle = MockBengle();
      await wireWith(bengle);

      final res = await post('/api/v1/machine/ledStrip/preview', {
        'front': 'FFFF00000000',
        'back': '00000000FFFF',
      });
      expect(res.statusCode, 202);

      // GET still serves the (all-off) stored config — preview bypasses it.
      final got = await get('/api/v1/machine/ledStrip');
      final body = jsonDecode(await got.readAsString());
      expect(body['frontStrip']['awake'], '000000000000');
    });

    test('202 on empty body — missing keys preview as black', () async {
      // Color16.fromJson is defensive-black: `{}` is accepted and blacks
      // both strips (locked model semantics, not an error).
      await wireWith(MockBengle());
      final res = await post('/api/v1/machine/ledStrip/preview');
      expect(res.statusCode, 202);
    });

    test('400 on non-map body', () async {
      await wireWith(MockBengle());
      final res = await post('/api/v1/machine/ledStrip/preview', [1, 2, 3]);
      expect(res.statusCode, 400);
    });

    test('404 on plain DE1', () async {
      await wireWith(MockDe1());
      final res = await post('/api/v1/machine/ledStrip/preview', {
        'front': 'FFFF00000000',
        'back': '00000000FFFF',
      });
      expect(res.statusCode, 404);
    });
  });

  group('POST /api/v1/machine/ledStrip/preview/clear', () {
    test('202 on Bengle', () async {
      await wireWith(MockBengle());
      final res = await post('/api/v1/machine/ledStrip/preview/clear');
      expect(res.statusCode, 202);
    });

    test('404 on plain DE1', () async {
      await wireWith(MockDe1());
      final res = await post('/api/v1/machine/ledStrip/preview/clear');
      expect(res.statusCode, 404);
    });
  });
}
