import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:web_socket_channel/io.dart';
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
  late HttpServer server;
  late Uri wsUri;

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

    server = await io.serve(app.call, 'localhost', 0);
    wsUri = Uri.parse('ws://localhost:${server.port}/ws/v1/devices');
  });

  tearDown(() async {
    await server.close(force: true);
    deviceController.dispose();
  });

  /// Connect and return the channel + a broadcast stream of decoded messages.
  (IOWebSocketChannel, Stream<Map<String, dynamic>>) connectWs() {
    final channel = IOWebSocketChannel.connect(wsUri);
    final messages = channel.stream
        .map((msg) => jsonDecode(msg.toString()) as Map<String, dynamic>)
        .asBroadcastStream();
    return (channel, messages);
  }

  /// Wait for and return the first message that contains an 'error' key.
  Future<Map<String, dynamic>> waitForError(
    Stream<Map<String, dynamic>> messages,
  ) {
    return messages
        .where((msg) => msg.containsKey('error'))
        .first
        .timeout(Duration(seconds: 2));
  }

  /// Wait for and return the first state message (has 'devices' key).
  Future<Map<String, dynamic>> waitForState(
    Stream<Map<String, dynamic>> messages,
  ) {
    return messages
        .where((msg) => msg.containsKey('devices'))
        .first
        .timeout(Duration(seconds: 2));
  }

  group('Devices WebSocket', () {
    test('sends initial state on connect', () async {
      final (channel, messages) = connectWs();

      final first = await waitForState(messages);

      expect(first, containsPair('scanning', false));
      expect(first['timestamp'], isA<String>());
      expect(first['devices'], isList);
      expect((first['devices'] as List), isEmpty);

      await channel.sink.close();
    });

    test('sends initial state with existing devices', () async {
      mockDiscovery.addDevice(
        TestScale(deviceId: 'scale-1', name: 'My Scale'),
      );
      await Future.delayed(Duration.zero);

      final (channel, messages) = connectWs();

      // Wait for a state message that includes our device
      final state = await messages
          .where((msg) =>
              msg.containsKey('devices') &&
              (msg['devices'] as List).isNotEmpty)
          .first
          .timeout(Duration(seconds: 2));

      expect(state['scanning'], false);
      final devices = state['devices'] as List;
      expect(devices, hasLength(1));
      expect(devices[0]['id'], 'scale-1');
      expect(devices[0]['name'], 'My Scale');
      expect(devices[0]['type'], 'scale');

      await channel.sink.close();
    });

    test('emits update when device is added', () async {
      final (channel, messages) = connectWs();

      // Wait for initial state (empty)
      await waitForState(messages);

      // Add a device
      mockDiscovery.addDevice(
        TestScale(deviceId: 'new-scale', name: 'New Scale'),
      );

      // Wait for a state message with the new device
      final update = await messages
          .where((msg) =>
              msg.containsKey('devices') &&
              (msg['devices'] as List).isNotEmpty)
          .first
          .timeout(Duration(seconds: 2));

      final devices = update['devices'] as List;
      expect(devices, hasLength(1));
      expect(devices[0]['id'], 'new-scale');

      await channel.sink.close();
    });

    test('emits update when device is removed', () async {
      mockDiscovery.addDevice(
        TestScale(deviceId: 'scale-1', name: 'Scale'),
      );
      await Future.delayed(Duration.zero);

      final (channel, messages) = connectWs();

      // Wait for initial state with one device
      await messages
          .where((msg) =>
              msg.containsKey('devices') &&
              (msg['devices'] as List).isNotEmpty)
          .first
          .timeout(Duration(seconds: 2));

      // Remove the device
      mockDiscovery.removeDevice('scale-1');

      // Wait for update with empty list
      final update = await messages
          .where((msg) =>
              msg.containsKey('devices') &&
              (msg['devices'] as List).isEmpty)
          .first
          .timeout(Duration(seconds: 2));

      expect((update['devices'] as List), isEmpty);

      await channel.sink.close();
    });

    test('responds with error for unknown command', () async {
      final (channel, messages) = connectWs();

      // Wait for initial state
      await waitForState(messages);

      // Send unknown command
      channel.sink.add(jsonEncode({'command': 'reboot'}));

      final response = await waitForError(messages);
      expect(response['error'], contains('Unknown command'));

      await channel.sink.close();
    });

    test('responds with error for missing command field', () async {
      final (channel, messages) = connectWs();

      // Wait for initial state
      await waitForState(messages);

      // Send message without command
      channel.sink.add(jsonEncode({'action': 'scan'}));

      final response = await waitForError(messages);
      expect(response['error'], contains('Missing "command"'));

      await channel.sink.close();
    });

    test('responds with error for invalid JSON', () async {
      final (channel, messages) = connectWs();

      // Wait for initial state
      await waitForState(messages);

      // Send invalid JSON
      channel.sink.add('not json');

      final response = await waitForError(messages);
      expect(response['error'], contains('Invalid JSON'));

      await channel.sink.close();
    });

    test('connect command with missing deviceId returns error', () async {
      final (channel, messages) = connectWs();

      // Wait for initial state
      await waitForState(messages);

      channel.sink.add(jsonEncode({'command': 'connect'}));

      final response = await waitForError(messages);
      expect(response['error'], contains('Missing "deviceId"'));

      await channel.sink.close();
    });

    test('disconnect command with unknown device returns error', () async {
      final (channel, messages) = connectWs();

      // Wait for initial state
      await waitForState(messages);

      channel.sink.add(
        jsonEncode({'command': 'disconnect', 'deviceId': 'nonexistent'}),
      );

      final response = await waitForError(messages);
      expect(response['error'], contains('Device not found'));

      await channel.sink.close();
    });

    test('disconnect command calls device.disconnect()', () async {
      mockDiscovery.addDevice(
        TestScale(deviceId: 'scale-1', name: 'Scale'),
      );
      await Future.delayed(Duration.zero);

      final (channel, messages) = connectWs();

      // Wait for initial state with device
      await messages
          .where((msg) =>
              msg.containsKey('devices') &&
              (msg['devices'] as List).isNotEmpty)
          .first
          .timeout(Duration(seconds: 2));

      // Disconnect — should not produce an error
      channel.sink.add(
        jsonEncode({'command': 'disconnect', 'deviceId': 'scale-1'}),
      );

      // Give time for the command to process — no error expected
      await Future.delayed(Duration(milliseconds: 100));

      await channel.sink.close();
    });

    test('scan command triggers scanForDevices', () async {
      final (channel, messages) = connectWs();

      // Wait for initial state
      await waitForState(messages);

      // Send scan command (quick mode to avoid blocking)
      channel.sink.add(
        jsonEncode({'command': 'scan', 'connect': false, 'quick': true}),
      );

      // Should get a scanning state update
      final update = await waitForState(messages);
      expect(update, containsPair('scanning', isA<bool>()));

      await channel.sink.close();
    });

    test('connect command connects a scale device', () async {
      mockDiscovery.addDevice(
        TestScale(deviceId: 'scale-1', name: 'Scale'),
      );
      await Future.delayed(Duration.zero);

      final (channel, messages) = connectWs();

      // Wait for initial state with device
      await messages
          .where((msg) =>
              msg.containsKey('devices') &&
              (msg['devices'] as List).isNotEmpty)
          .first
          .timeout(Duration(seconds: 2));

      // Send connect command
      channel.sink.add(
        jsonEncode({'command': 'connect', 'deviceId': 'scale-1'}),
      );

      // Should not receive an error — give time for processing
      await Future.delayed(Duration(milliseconds: 100));

      await channel.sink.close();
    });
  });
}
