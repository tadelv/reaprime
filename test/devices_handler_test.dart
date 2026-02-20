import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/services/webserver_service.dart';

import 'helpers/mock_device_discovery_service.dart';
import 'helpers/test_scale.dart';

void main() {
  late DeviceController deviceController;
  late De1Controller de1Controller;
  late ScaleController scaleController;
  late MockDeviceDiscoveryService mockDiscovery;
  late Handler handler;

  setUp(() async {
    mockDiscovery = MockDeviceDiscoveryService();
    deviceController = DeviceController([mockDiscovery]);
    await deviceController.initialize();

    de1Controller = De1Controller(controller: deviceController);
    scaleController = ScaleController(controller: deviceController);

    final devicesHandler = DevicesHandler(
      controller: deviceController,
      de1Controller: de1Controller,
      scaleController: scaleController,
    );

    final app = Router().plus;
    devicesHandler.addRoutes(app);
    handler = app.call;
  });

  Future<Response> sendPut(String path, {String? body}) async {
    return await handler(
      Request(
        'PUT',
        Uri.parse('http://localhost$path'),
        body: body,
        headers: body != null ? {'content-type': 'application/json'} : null,
      ),
    );
  }

  Future<Response> sendGet(String path) async {
    return await handler(Request('GET', Uri.parse('http://localhost$path')));
  }

  group('DevicesHandler', () {
    group('_extractDeviceId', () {
      test('reads deviceId from JSON body', () async {
        final response = await sendPut(
          '/api/v1/devices/connect',
          body: jsonEncode({'deviceId': 'AA:BB:CC:DD:EE:FF'}),
        );
        // Device not found (not in controller), but proves body was parsed
        expect(response.statusCode, 404);
      });

      test('reads deviceId from query parameter', () async {
        final response = await sendPut(
          '/api/v1/devices/connect?deviceId=some-device',
        );
        expect(response.statusCode, 404);
      });

      test('returns 400 when deviceId is missing entirely', () async {
        final response = await sendPut('/api/v1/devices/connect');
        expect(response.statusCode, 400);
        final body = jsonDecode(await response.readAsString());
        expect(body['error'], 'Missing deviceId');
      });

      test('returns 400 when body is empty JSON object', () async {
        final response = await sendPut(
          '/api/v1/devices/connect',
          body: jsonEncode({}),
        );
        expect(response.statusCode, 400);
      });

      test('falls back to query param when body has no deviceId', () async {
        final response = await sendPut(
          '/api/v1/devices/connect?deviceId=fallback-id',
          body: jsonEncode({'other': 'field'}),
        );
        // 404 = deviceId was extracted (fallback-id) but device not found
        expect(response.statusCode, 404);
      });

      test('body takes precedence over query param', () async {
        mockDiscovery.addDevice(
          TestScale(deviceId: 'body-id', name: 'Body Scale'),
        );
        // Wait for stream to propagate
        await Future.delayed(Duration.zero);

        final response = await sendPut(
          '/api/v1/devices/connect?deviceId=query-id',
          body: jsonEncode({'deviceId': 'body-id'}),
        );
        // body-id exists, so connect succeeds
        expect(response.statusCode, 200);
      });

      test('falls back to query param when body is invalid JSON', () async {
        final response = await handler(
          Request(
            'PUT',
            Uri.parse(
              'http://localhost/api/v1/devices/connect?deviceId=fallback',
            ),
            body: 'not json at all',
          ),
        );
        // 404 = deviceId was extracted from query but device not found
        expect(response.statusCode, 404);
      });
    });

    group('BLE and USB device IDs', () {
      test('handles BLE MAC address with colons via body', () async {
        const macAddress = 'AA:BB:CC:DD:EE:FF';
        mockDiscovery.addDevice(
          TestScale(deviceId: macAddress, name: 'BLE Scale'),
        );
        await Future.delayed(Duration.zero);

        final response = await sendPut(
          '/api/v1/devices/connect',
          body: jsonEncode({'deviceId': macAddress}),
        );
        expect(response.statusCode, 200);
      });

      test('handles BLE UUID with hyphens via body', () async {
        const uuid = '550e8400-e29b-41d4-a716-446655440000';
        mockDiscovery.addDevice(
          TestScale(deviceId: uuid, name: 'iOS Scale'),
        );
        await Future.delayed(Duration.zero);

        final response = await sendPut(
          '/api/v1/devices/connect',
          body: jsonEncode({'deviceId': uuid}),
        );
        expect(response.statusCode, 200);
      });

      test('handles USB serial port path with slashes via body', () async {
        const serialPath = '/dev/ttyUSB0';
        mockDiscovery.addDevice(
          TestScale(deviceId: serialPath, name: 'USB Scale'),
        );
        await Future.delayed(Duration.zero);

        final response = await sendPut(
          '/api/v1/devices/connect',
          body: jsonEncode({'deviceId': serialPath}),
        );
        expect(response.statusCode, 200);
      });

      test('handles MAC address via query parameter', () async {
        const macAddress = 'AA:BB:CC:DD:EE:FF';
        mockDiscovery.addDevice(
          TestScale(deviceId: macAddress, name: 'BLE Scale'),
        );
        await Future.delayed(Duration.zero);

        final response = await sendPut(
          '/api/v1/devices/connect?deviceId=$macAddress',
        );
        expect(response.statusCode, 200);
      });
    });

    group('disconnect', () {
      test('reads deviceId from JSON body', () async {
        mockDiscovery.addDevice(
          TestScale(deviceId: 'scale-1', name: 'My Scale'),
        );
        await Future.delayed(Duration.zero);

        final response = await sendPut(
          '/api/v1/devices/disconnect',
          body: jsonEncode({'deviceId': 'scale-1'}),
        );
        expect(response.statusCode, 200);
      });

      test('returns 400 when deviceId is missing', () async {
        final response = await sendPut('/api/v1/devices/disconnect');
        expect(response.statusCode, 400);
        final body = jsonDecode(await response.readAsString());
        expect(body['error'], 'Missing deviceId');
      });

      test('returns 404 when device not found', () async {
        final response = await sendPut(
          '/api/v1/devices/disconnect',
          body: jsonEncode({'deviceId': 'nonexistent'}),
        );
        expect(response.statusCode, 404);
      });
    });

    group('device list', () {
      test('returns empty list when no devices', () async {
        final response = await sendGet('/api/v1/devices');
        expect(response.statusCode, 200);
        final body = jsonDecode(await response.readAsString());
        expect(body, isEmpty);
      });

      test('returns discovered devices with id field', () async {
        mockDiscovery.addDevice(
          TestScale(deviceId: 'AA:BB:CC:DD:EE:FF', name: 'Test Scale'),
        );
        await Future.delayed(Duration.zero);

        final response = await sendGet('/api/v1/devices');
        expect(response.statusCode, 200);
        final body = jsonDecode(await response.readAsString()) as List;
        expect(body, hasLength(1));
        expect(body[0]['id'], 'AA:BB:CC:DD:EE:FF');
        expect(body[0]['name'], 'Test Scale');
        expect(body[0]['type'], 'scale');
      });
    });
  });
}
