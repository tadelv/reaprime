import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/device.dart';
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
  late DevicesHandler devicesHandler;
  late Handler handler;

  setUp(() async {
    mockDiscovery = MockDeviceDiscoveryService();
    deviceController = DeviceController([mockDiscovery]);
    await deviceController.initialize();

    de1Controller = De1Controller(controller: deviceController);
    scaleController = ScaleController(controller: deviceController);

    devicesHandler = DevicesHandler(
      controller: deviceController,
      de1Controller: de1Controller,
      scaleController: scaleController,
    );

    final app = Router().plus;
    devicesHandler.addRoutes(app);
    handler = app.call;
  });

  tearDown(() {
    devicesHandler.dispose();
    deviceController.dispose();
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

    group('scanning state', () {
      test('isScanning is initially false', () {
        expect(deviceController.isScanning, isFalse);
      });

      test('scanningStream emits true then false during scanForDevices',
          () async {
        final states = <bool>[];
        final sub = deviceController.scanningStream.listen(states.add);

        await deviceController.scanForDevices(autoConnect: false);
        // Wait for the delayed callback to fire
        await Future.delayed(Duration(milliseconds: 300));

        sub.cancel();

        // Should contain: initial false (BehaviorSubject), true, false
        expect(states, contains(true));
        expect(states.last, isFalse);
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

  group('DevicesStateAggregator', () {
    late DeviceController deviceController;
    late MockDeviceDiscoveryService mockDiscovery;
    late DevicesStateAggregator aggregator;

    setUp(() async {
      mockDiscovery = MockDeviceDiscoveryService();
      deviceController = DeviceController([mockDiscovery]);
      await deviceController.initialize();

      aggregator = DevicesStateAggregator(
        controller: deviceController,
      );
    });

    tearDown(() {
      aggregator.dispose();
      deviceController.dispose();
    });

    test('emits initial state with empty device list', () async {
      final state = await aggregator.stateStream.first;

      expect(state['devices'], isList);
      expect((state['devices'] as List), isEmpty);
      expect(state['scanning'], false);
      expect(state['timestamp'], isA<String>());
    });

    test('emits update when device is added', () async {
      // Consume initial state
      await aggregator.stateStream.first;

      mockDiscovery.addDevice(
        TestScale(deviceId: 'scale-1', name: 'Scale 1'),
      );

      // Wait for debounce (100ms) + margin
      final state = await aggregator.stateStream
          .where((s) => (s['devices'] as List).isNotEmpty)
          .first
          .timeout(Duration(seconds: 2));

      final devices = state['devices'] as List;
      expect(devices, hasLength(1));
      expect(devices[0]['id'], 'scale-1');
    });

    test('emits update when device is removed', () async {
      mockDiscovery.addDevice(
        TestScale(deviceId: 'scale-1', name: 'Scale 1'),
      );

      // Wait for state with device
      await aggregator.stateStream
          .where((s) => (s['devices'] as List).isNotEmpty)
          .first
          .timeout(Duration(seconds: 2));

      mockDiscovery.removeDevice('scale-1');

      // Wait for state with empty list
      final state = await aggregator.stateStream
          .where((s) => (s['devices'] as List).isEmpty)
          .first
          .timeout(Duration(seconds: 2));

      expect((state['devices'] as List), isEmpty);
    });

    test('cleans up subscription when device is removed', () async {
      mockDiscovery.addDevice(
        TestScale(deviceId: 'scale-1', name: 'Scale 1'),
      );
      await aggregator.stateStream
          .where((s) => (s['devices'] as List).isNotEmpty)
          .first
          .timeout(Duration(seconds: 2));

      expect(aggregator.activeDeviceSubscriptionCount, 1);

      mockDiscovery.removeDevice('scale-1');
      await aggregator.stateStream
          .where((s) => (s['devices'] as List).isEmpty)
          .first
          .timeout(Duration(seconds: 2));

      expect(aggregator.activeDeviceSubscriptionCount, 0);
    });

    test('emits update when device connection state changes', () async {
      final scale = TestScale(deviceId: 'scale-1', name: 'Scale 1');
      mockDiscovery.addDevice(scale);

      // Wait for state with connected device
      await aggregator.stateStream
          .where((s) =>
              (s['devices'] as List).isNotEmpty &&
              (s['devices'] as List)[0]['state'] == 'connected')
          .first
          .timeout(Duration(seconds: 2));

      // Change connection state
      scale.setConnectionState(ConnectionState.disconnected);

      // Wait for state reflecting the disconnected state
      final state = await aggregator.stateStream
          .where((s) =>
              (s['devices'] as List).isNotEmpty &&
              (s['devices'] as List)[0]['state'] == 'disconnected')
          .first
          .timeout(Duration(seconds: 2));

      expect((state['devices'] as List)[0]['state'], 'disconnected');
    });

    test('resubscribes when device reappears with same ID', () async {
      final scale1 = TestScale(deviceId: 'scale-1', name: 'Scale 1');
      mockDiscovery.addDevice(scale1);

      await aggregator.stateStream
          .where((s) => (s['devices'] as List).isNotEmpty)
          .first
          .timeout(Duration(seconds: 2));

      // Remove and add a NEW object with the same ID
      mockDiscovery.removeDevice('scale-1');
      await aggregator.stateStream
          .where((s) => (s['devices'] as List).isEmpty)
          .first
          .timeout(Duration(seconds: 2));

      final scale2 = TestScale(
        deviceId: 'scale-1',
        name: 'Scale 1',
        initialState: ConnectionState.connecting,
      );
      mockDiscovery.addDevice(scale2);

      // Should see the new device's initial state (connecting)
      final state = await aggregator.stateStream
          .where((s) =>
              (s['devices'] as List).isNotEmpty &&
              (s['devices'] as List)[0]['state'] == 'connecting')
          .first
          .timeout(Duration(seconds: 2));

      expect((state['devices'] as List)[0]['state'], 'connecting');

      // Verify new object's state changes are observed
      scale2.setConnectionState(ConnectionState.connected);

      final updated = await aggregator.stateStream
          .where((s) =>
              (s['devices'] as List).isNotEmpty &&
              (s['devices'] as List)[0]['state'] == 'connected')
          .first
          .timeout(Duration(seconds: 2));

      expect((updated['devices'] as List)[0]['state'], 'connected');
    });

    test('replaces subscription when same-ID different-object appears in-place',
        () async {
      // This tests the case where a device is replaced without being removed
      // first (e.g., discovery service emits a new list with a new object
      // for the same deviceId)
      final scale1 = TestScale(deviceId: 'scale-1', name: 'Scale v1');
      mockDiscovery.addDevice(scale1);

      await aggregator.stateStream
          .where((s) => (s['devices'] as List).isNotEmpty)
          .first
          .timeout(Duration(seconds: 2));

      expect(aggregator.activeDeviceSubscriptionCount, 1);

      // Replace with a new object by clearing and re-adding
      mockDiscovery.clear();
      final scale2 = TestScale(deviceId: 'scale-1', name: 'Scale v2');
      mockDiscovery.addDevice(scale2);

      // Wait for state with the new device
      await aggregator.stateStream
          .where((s) =>
              (s['devices'] as List).isNotEmpty &&
              (s['devices'] as List)[0]['name'] == 'Scale v2')
          .first
          .timeout(Duration(seconds: 2));

      expect(aggregator.activeDeviceSubscriptionCount, 1);

      // Verify old object's state changes are NOT observed
      scale1.setConnectionState(ConnectionState.disconnected);
      // Give time for any stale emission
      await Future.delayed(Duration(milliseconds: 200));

      // Current state should still show connected (from scale2)
      final current = await aggregator.stateStream.first;
      expect((current['devices'] as List)[0]['state'], 'connected');

      // Verify new object's state changes ARE observed
      scale2.setConnectionState(ConnectionState.disconnecting);

      final state = await aggregator.stateStream
          .where((s) =>
              (s['devices'] as List).isNotEmpty &&
              (s['devices'] as List)[0]['state'] == 'disconnecting')
          .first
          .timeout(Duration(seconds: 2));

      expect((state['devices'] as List)[0]['state'], 'disconnecting');
    });

    test('debounces rapid changes into single emission', () async {
      // Consume initial state
      await aggregator.stateStream.first;

      final emissions = <Map<String, dynamic>>[];
      final sub = aggregator.stateStream.listen(emissions.add);

      // Add multiple devices in rapid succession
      mockDiscovery.addDevice(
        TestScale(deviceId: 'scale-1', name: 'Scale 1'),
      );
      mockDiscovery.addDevice(
        TestScale(deviceId: 'scale-2', name: 'Scale 2'),
      );
      mockDiscovery.addDevice(
        TestScale(deviceId: 'scale-3', name: 'Scale 3'),
      );

      // Wait for debounce to settle
      await Future.delayed(Duration(milliseconds: 300));

      sub.cancel();

      // Should have fewer emissions than the 3 additions due to debouncing.
      // The final emission should show all 3 devices.
      final lastDevices = emissions.last['devices'] as List;
      expect(lastDevices, hasLength(3));
      expect(emissions.length, lessThan(3));
    });

    test('no new emissions after dispose', () async {
      // Consume initial state
      await aggregator.stateStream.first;

      aggregator.dispose();

      // Subscribe after dispose — BehaviorSubject replays its last value
      // then closes, so we collect everything and check that no NEW emissions
      // arrive from upstream changes.
      final emissions = <Map<String, dynamic>>[];
      final completer = Completer<void>();
      aggregator.stateStream.listen(
        emissions.add,
        onError: (_) {},
        onDone: () => completer.complete(),
      );

      // Wait for the stream to close (BehaviorSubject emits done on close)
      await completer.future.timeout(Duration(seconds: 1));

      final countAfterClose = emissions.length;

      // Adding a device after dispose should NOT produce new emissions
      mockDiscovery.addDevice(
        TestScale(deviceId: 'scale-1', name: 'Scale 1'),
      );
      await Future.delayed(Duration(milliseconds: 200));

      expect(emissions.length, countAfterClose);
    });
  });
}




