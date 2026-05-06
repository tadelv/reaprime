import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/impl/bengle/mock_bengle.dart';
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
      expect(body['front'], '000000');
      expect(body['back'], '000000');
    });

    test('404 on plain DE1', () async {
      await wireWith(MockDe1());
      final res = await get('/api/v1/machine/ledStrip');
      expect(res.statusCode, 404);
    });
  });

  group('POST /api/v1/machine/ledStrip', () {
    test('202 + writes hex state into MockBengle', () async {
      final bengle = MockBengle();
      await wireWith(bengle);

      final res = await post('/api/v1/machine/ledStrip', {
        'front': 'FF8000',
        'back': '0A141E',
      });
      expect(res.statusCode, 202);

      final state = await bengle.getLedStripState();
      expect(state.frontRed, 255);
      expect(state.frontGreen, 128);
      expect(state.frontBlue, 0);
      expect(state.backRed, 10);
      expect(state.backGreen, 20);
      expect(state.backBlue, 30);
    });

    test('202 with partial body (front only, back defaults to 000000)', () async {
      final bengle = MockBengle();
      await wireWith(bengle);

      final res = await post('/api/v1/machine/ledStrip', {
        'front': '640000',
      });
      expect(res.statusCode, 202);

      final state = await bengle.getLedStripState();
      expect(state.frontRed, 100);
      expect(state.frontGreen, 0);
      expect(state.frontBlue, 0);
      expect(state.backRed, 0);
      expect(state.backGreen, 0);
      expect(state.backBlue, 0);
    });

    test('400 on non-map body', () async {
      await wireWith(MockBengle());
      final res = await post('/api/v1/machine/ledStrip', [1, 2, 3]);
      expect(res.statusCode, 400);
    });

    test('malformed hex string defaults channel to 0', () async {
      final bengle = MockBengle();
      await wireWith(bengle);

      final res = await post('/api/v1/machine/ledStrip', {
        'front': 'XXYYZZ',
      });
      expect(res.statusCode, 202);

      final state = await bengle.getLedStripState();
      expect(state.frontRed, 0);
      expect(state.frontGreen, 0);
      expect(state.frontBlue, 0);
    });

    test('404 on plain DE1', () async {
      await wireWith(MockDe1());
      final res = await post('/api/v1/machine/ledStrip', {
        'front': 'FF0000',
      });
      expect(res.statusCode, 404);
    });
  });
}
