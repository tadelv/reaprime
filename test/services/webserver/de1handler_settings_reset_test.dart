import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/impl/mock_de1/mock_de1.dart';
import 'package:reaprime/src/models/errors.dart';
import 'package:reaprime/src/services/webserver_service.dart';
import 'package:shelf_plus/shelf_plus.dart';

import '../../helpers/mock_device_discovery_service.dart';

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

  Future<void> wireWith(De1Interface? device) async {
    final deviceController =
        DeviceController([MockDeviceDiscoveryService()]);
    await deviceController.initialize();
    controller =
        _FixedDe1Controller(controller: deviceController, device: device);
    final de1Handler = De1Handler(controller: controller);
    final app = Router().plus;
    de1Handler.addRoutes(app);
    handler = app.call;
  }

  Future<Response> get(String path) async =>
      await handler(Request('GET', Uri.parse('http://localhost$path')));

  Future<Response> post(String path, Object body) async =>
      await handler(Request(
        'POST',
        Uri.parse('http://localhost$path'),
        body: jsonEncode(body),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      ));

  Future<Response> delete(String path) async =>
      await handler(Request('DELETE', Uri.parse('http://localhost$path')));

  group('GET /api/v1/machine/settings/advanced', () {
    test('returns heaterVoltage and refillKitSetting on MockDe1', () async {
      await wireWith(MockDe1());
      final res = await get('/api/v1/machine/settings/advanced');
      expect(res.statusCode, 200);
      final body = jsonDecode(await res.readAsString());
      expect(body['heaterVoltage'], isA<int>());
      expect(body['refillKitSetting'], isA<String>());
    });

    test('returns 500 when no DE1 connected', () async {
      await wireWith(null);
      final res = await get('/api/v1/machine/settings/advanced');
      expect(res.statusCode, 500);
    });
  });

  group('POST /api/v1/machine/settings/advanced', () {
    test('writes and reads back heaterVoltage', () async {
      final de1 = MockDe1();
      await wireWith(de1);

      final res = await post('/api/v1/machine/settings/advanced', {
        'heaterVoltage': 230,
      });
      expect(res.statusCode, 202);

      final read = await de1.getHeaterVoltage();
      expect(read, De1HeaterVoltage.v220);
    });

    test('writes and reads back refillKitSetting by name', () async {
      final de1 = MockDe1();
      await wireWith(de1);

      final res = await post('/api/v1/machine/settings/advanced', {
        'refillKitSetting': 'forceOn',
      });
      expect(res.statusCode, 202);

      final read = await de1.getRefillKitSettings();
      expect(read, De1RefillKitSettings.forceOn);
    });

    test('round-trips through GET after write', () async {
      final de1 = MockDe1();
      await wireWith(de1);

      await post('/api/v1/machine/settings/advanced', {
        'heaterVoltage': 230,
        'refillKitSetting': 'forceOff',
      });

      final res = await get('/api/v1/machine/settings/advanced');
      expect(res.statusCode, 200);
      final body = jsonDecode(await res.readAsString());
      expect(body['heaterVoltage'], 230);
      expect(body['refillKitSetting'], 'forceOff');
    });

    test('returns 500 when no DE1 connected', () async {
      await wireWith(null);
      final res = await post('/api/v1/machine/settings/advanced', {
        'heaterVoltage': 120,
      });
      expect(res.statusCode, 500);
    });
  });

  group('DELETE /api/v1/machine/settings/reset', () {
    test('returns 202 on MockDe1', () async {
      await wireWith(MockDe1());
      final res = await delete('/api/v1/machine/settings/reset');
      expect(res.statusCode, 202);
    });

    test('returns 500 when no DE1 connected', () async {
      await wireWith(null);
      final res = await delete('/api/v1/machine/settings/reset');
      expect(res.statusCode, 500);
    });
  });
}
