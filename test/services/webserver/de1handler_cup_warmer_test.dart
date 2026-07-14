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

    test('returns stopAtWeight when a Bengle is connected', () async {
      await wireWith(MockBengle());
      final res = await get('/api/v1/machine/capabilities');
      final body = jsonDecode(await res.readAsString());
      expect(body['capabilities'], contains('stopAtWeight'));
    });

    test('does not return stopAtWeight on plain DE1', () async {
      await wireWith(MockDe1());
      final res = await get('/api/v1/machine/capabilities');
      final body = jsonDecode(await res.readAsString());
      expect(body['capabilities'], isNot(contains('stopAtWeight')));
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

    test('currentTemperature is null when the firmware has no reading',
        () async {
      await wireWith(MockBengle());
      final res = await get('/api/v1/machine/cupWarmer');
      expect(res.statusCode, 200);
      final body = jsonDecode(await res.readAsString()) as Map;
      expect(body.containsKey('currentTemperature'), isTrue,
          reason: 'the key is always present on a Bengle — null means '
              'no valid reading, clients render a placeholder');
      expect(body['currentTemperature'], isNull);
    });

    test('200 + live mat temperature when the firmware reports one',
        () async {
      final bengle = MockBengle();
      bengle.setMatCurrentTemperature(42.5);
      await wireWith(bengle);
      final res = await get('/api/v1/machine/cupWarmer');
      expect(res.statusCode, 200);
      final body = jsonDecode(await res.readAsString());
      expect(body['currentTemperature'], 42.5);
    });

    test('404 on plain DE1 (machine connected but capability absent)',
        () async {
      await wireWith(MockDe1());
      final res = await get('/api/v1/machine/cupWarmer');
      expect(res.statusCode, 404);
    });

    // --- scheduled pre-warm (MMR rows 59-61) ---

    test('prewarm fields report the firmware defaults on a fresh Bengle',
        () async {
      await wireWith(MockBengle());
      final res = await get('/api/v1/machine/cupWarmer');
      expect(res.statusCode, 200);
      final body = jsonDecode(await res.readAsString()) as Map;
      expect(body['prewarmEnabled'], isFalse);
      expect(body['prewarmLeadMinutes'], 30, reason: 'firmware default');
      expect(body['prewarmActive'], isFalse);
    });

    test('prewarmActive is true while the SCHEDULE is driving the mat',
        () async {
      final bengle = MockBengle();
      bengle.setCupWarmerPrewarmActive(true);
      await wireWith(bengle);
      final res = await get('/api/v1/machine/cupWarmer');
      final body = jsonDecode(await res.readAsString());
      expect(body['prewarmActive'], isTrue,
          reason: 'this is how a UI explains a cup warmer that came on by '
              'itself at 06:30');
    });

    test('all three prewarm fields are null on firmware without the registers',
        () async {
      // Older firmware older firmware: rows 59-61 do not exist; the reads fail.
      final bengle = MockBengle()..setPrewarmSupported(false);
      await wireWith(bengle);
      final res = await get('/api/v1/machine/cupWarmer');
      expect(res.statusCode, 200, reason: 'degrade, never crash the endpoint');
      final body = jsonDecode(await res.readAsString()) as Map;
      for (final key in const [
        'prewarmEnabled',
        'prewarmLeadMinutes',
        'prewarmActive',
      ]) {
        expect(body.containsKey(key), isTrue,
            reason: 'the key is always present on a Bengle');
        expect(body[key], isNull,
            reason: '$key must be "unavailable", never invented data');
      }
      // The rest of the payload still works.
      expect(body['temperature'], 0.0);
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

    // --- scheduled pre-warm (MMR rows 59-61) ---

    test('200 + writes the pre-warm pair into MockBengle', () async {
      final bengle = MockBengle();
      await wireWith(bengle);

      final res = await put('/api/v1/machine/cupWarmer', {
        'prewarmEnabled': true,
        'prewarmLeadMinutes': 45,
      });
      expect(res.statusCode, 200);
      expect(bengle.prewarmEnabled, isTrue);
      expect(bengle.prewarmLeadMinutes, 45);

      // The response echoes what the machine reports back — never an
      // unverified success.
      final body = jsonDecode(await res.readAsString());
      expect(body['prewarmEnabled'], isTrue);
      expect(body['prewarmLeadMinutes'], 45);
    });

    test('GET after PUT round-trips the pre-warm settings', () async {
      final bengle = MockBengle();
      await wireWith(bengle);
      await put('/api/v1/machine/cupWarmer', {
        'prewarmEnabled': true,
        'prewarmLeadMinutes': 15,
      });
      final body = jsonDecode(await (await get(
        '/api/v1/machine/cupWarmer',
      )).readAsString());
      expect(body['prewarmEnabled'], isTrue);
      expect(body['prewarmLeadMinutes'], 15);
    });

    test('a temperature-only PUT leaves the pre-warm settings alone', () async {
      final bengle = MockBengle();
      await wireWith(bengle);
      await put('/api/v1/machine/cupWarmer', {
        'prewarmEnabled': true,
        'prewarmLeadMinutes': 20,
      });
      final res = await put('/api/v1/machine/cupWarmer', {'temperature': 55});
      expect(res.statusCode, 200);
      expect(bengle.prewarmEnabled, isTrue);
      expect(bengle.prewarmLeadMinutes, 20);
    });

    test('a partial pre-warm PUT keeps the machine value for the other half',
        () async {
      final bengle = MockBengle();
      await wireWith(bengle);
      await put('/api/v1/machine/cupWarmer', {
        'prewarmEnabled': true,
        'prewarmLeadMinutes': 20,
      });
      // Toggle off without restating the lead — the pair is written together,
      // so the lead must survive.
      final res = await put('/api/v1/machine/cupWarmer', {
        'prewarmEnabled': false,
      });
      expect(res.statusCode, 200);
      expect(bengle.prewarmEnabled, isFalse);
      expect(bengle.prewarmLeadMinutes, 20);
    });

    test('prewarmActive is read-only: a PUT carrying it writes nothing',
        () async {
      final bengle = MockBengle();
      await wireWith(bengle);
      final res = await put('/api/v1/machine/cupWarmer', {
        'temperature': 60,
        'prewarmActive': true,
      });
      expect(res.statusCode, 200);
      expect(await bengle.getCupWarmerPrewarmActive(), isFalse,
          reason: 'prewarmActive is firmware status (MatPreheatActive, R) — a '
              'client must not be able to set it');
      expect(bengle.prewarmEnabled, isFalse,
          reason: 'and it must not be mistaken for prewarmEnabled');
    });

    test('400 on prewarmLeadMinutes above 120', () async {
      await wireWith(MockBengle());
      final res = await put('/api/v1/machine/cupWarmer', {
        'prewarmEnabled': true,
        'prewarmLeadMinutes': 999,
      });
      expect(res.statusCode, 400);
    });

    test('400 on a negative prewarmLeadMinutes', () async {
      await wireWith(MockBengle());
      final res = await put('/api/v1/machine/cupWarmer', {
        'prewarmLeadMinutes': -5,
      });
      expect(res.statusCode, 400);
    });

    test('400 when prewarmEnabled is not a boolean', () async {
      await wireWith(MockBengle());
      final res = await put('/api/v1/machine/cupWarmer', {
        'prewarmEnabled': 'yes',
      });
      expect(res.statusCode, 400);
    });

    test('a pre-warm PUT on firmware without the registers echoes null',
        () async {
      final bengle = MockBengle()..setPrewarmSupported(false);
      await wireWith(bengle);
      final res = await put('/api/v1/machine/cupWarmer', {
        'prewarmEnabled': true,
        'prewarmLeadMinutes': 30,
      });
      expect(res.statusCode, 200, reason: 'inert, not an error');
      final body = jsonDecode(await res.readAsString()) as Map;
      expect(body['prewarmEnabled'], isNull,
          reason: 'the write landed in unmapped space — never claim a success '
              'we cannot read back');
      expect(body['prewarmLeadMinutes'], isNull);
      expect(bengle.prewarmEnabled, isFalse);
    });

    test('404 on plain DE1 for a pre-warm PUT (no write reaches the machine)',
        () async {
      await wireWith(MockDe1());
      final res = await put('/api/v1/machine/cupWarmer', {
        'prewarmEnabled': true,
        'prewarmLeadMinutes': 30,
      });
      expect(res.statusCode, 404);
    });
  });
}
