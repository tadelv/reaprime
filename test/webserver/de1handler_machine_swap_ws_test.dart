import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:web_socket_channel/io.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/device.dart' show ConnectionState;
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:reaprime/src/services/webserver_service.dart';

import '../helpers/mock_device_discovery_service.dart';
import '../helpers/mock_settings_service.dart';
import '../helpers/test_de1.dart';

/// Bench bug i14 — "the app never reconnects after a power-cycle".
///
/// A machine power-cycle drops the De1 object and builds a NEW one under the
/// SAME device id (the USB stable id is derived from the SAMD21 factory
/// serial, so it is byte-identical across a power-cycle). The machine sockets
/// used to bind to one De1 *instance* at open and never re-bind, so a client
/// that connected before the power-cycle sat on an open-but-silent socket
/// forever.
///
/// These lock the server-side contract: a client that connected BEFORE the
/// swap receives frames from the NEW machine after it, with no client-side
/// action — and exactly one copy of each frame.
void main() {
  late De1Controller de1Controller;
  late HttpServer server;

  setUp(() async {
    final deviceController = DeviceController([MockDeviceDiscoveryService()]);
    await deviceController.initialize();

    de1Controller = De1Controller(controller: deviceController);

    final settingsController = SettingsController(MockSettingsService());
    await settingsController.loadSettings();

    final de1Handler = De1Handler(
      controller: de1Controller,
      settingsController: settingsController,
      scaleController: ScaleController(),
      workflowController: WorkflowController(),
    );

    final app = Router().plus;
    de1Handler.addRoutes(app);

    server = await io.serve(app.call, 'localhost', 0);
  });

  tearDown(() async {
    await server.close(force: true);
  });

  Uri wsUri(String path) => Uri.parse('ws://localhost:${server.port}$path');

  (IOWebSocketChannel, Stream<Map<String, dynamic>>) connectWs(String path) {
    final channel = IOWebSocketChannel.connect(wsUri(path));
    final messages = channel.stream
        .map((msg) => jsonDecode(msg.toString()) as Map<String, dynamic>)
        .asBroadcastStream();
    // Drain into a broadcast stream eagerly so frames sent before a
    // `.first`/`.take()` is awaited are not dropped.
    messages.listen((_) {});
    return (channel, messages);
  }

  /// Let the WebSocket + rx plumbing settle.
  Future<void> settle([int turns = 6]) async {
    for (var i = 0; i < turns; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  /// The power-cycle, exactly as De1Controller sees it on the bench: the
  /// transport reports `disconnected` (→ `_onDisconnect()` nulls the de1),
  /// then the next scan builds a brand-new instance under the same id.
  Future<TestDe1> powerCycle(TestDe1 old) async {
    old.setConnectionState(ConnectionState.disconnected);
    await settle();
    final fresh = TestDe1(deviceId: old.deviceId, name: old.name);
    await de1Controller.connectToDe1(fresh);
    await settle();
    return fresh;
  }

  MachineSnapshot snapshotAt(double groupTemperature) => MachineSnapshot(
        timestamp: DateTime(2026, 7, 14, 15, 53),
        state: const MachineStateSnapshot(
          state: MachineState.idle,
          substate: MachineSubstate.idle,
        ),
        flow: 0,
        pressure: 0,
        targetFlow: 0,
        targetPressure: 0,
        mixTemperature: 90,
        groupTemperature: groupTemperature,
        targetMixTemperature: 93,
        targetGroupTemperature: 93,
        profileFrame: 0,
        steamTemperature: 0,
      );

  group('machine snapshot socket survives a machine swap', () {
    test(
        'a client bound before a power-cycle receives frames from the NEW '
        'machine after it', () async {
      final first = TestDe1(deviceId: 'usb-2e8a-a-8549628789ABCDEF');
      await de1Controller.connectToDe1(first);

      final (channel, messages) = connectWs('/ws/v1/machine/snapshot');
      final received = <Map<String, dynamic>>[];
      messages.listen(received.add);
      await settle();
      expect(received, isNotEmpty, reason: 'the old machine streams');

      // The machine is power-cycled: same device id, brand-new De1 object.
      final second = await powerCycle(first);
      expect(identical(first, second), isFalse);

      received.clear();
      second.emitSnapshot(snapshotAt(83.09));
      await settle();

      expect(
        received.map((f) => f['groupTemperature']),
        contains(83.09),
        reason: 'the pre-existing socket must re-bind to the new machine',
      );

      await channel.sink.close();
    });

    test('the swapped-in socket is not duplicated (one frame per emit)',
        () async {
      final first = TestDe1(deviceId: 'usb-2e8a-a-8549628789ABCDEF');
      await de1Controller.connectToDe1(first);

      final (channel, messages) = connectWs('/ws/v1/machine/snapshot');
      final received = <Map<String, dynamic>>[];
      messages.listen(received.add);
      await settle();

      final second = await powerCycle(first);
      // A second power-cycle: three instances have now passed under one socket.
      final third = await powerCycle(second);

      received.clear();
      third.emitSnapshot(snapshotAt(91.5));
      await settle();

      expect(
        received.where((f) => f['groupTemperature'] == 91.5).length,
        1,
        reason: 'a leaked subscription per swap would multiply the frame rate',
      );

      // The dead instances must have no listener left on them.
      expect(first.snapshotSubject.hasListener, isFalse);
      expect(second.snapshotSubject.hasListener, isFalse);

      await channel.sink.close();
    });

    test('frames from the OLD machine are ignored after the swap', () async {
      final first = TestDe1(deviceId: 'usb-2e8a-a-8549628789ABCDEF');
      await de1Controller.connectToDe1(first);

      final (channel, messages) = connectWs('/ws/v1/machine/snapshot');
      final received = <Map<String, dynamic>>[];
      messages.listen(received.add);
      await settle();

      await powerCycle(first);

      received.clear();
      first.emitSnapshot(snapshotAt(11.1)); // zombie instance still alive
      await settle();

      expect(received, isEmpty);

      await channel.sink.close();
    });

    test('closing the socket cancels the machine subscription (no leak)',
        () async {
      final machine = TestDe1(deviceId: 'usb-2e8a-a-8549628789ABCDEF');
      await de1Controller.connectToDe1(machine);

      final (channel, _) = connectWs('/ws/v1/machine/snapshot');
      await settle();
      expect(machine.snapshotSubject.hasListener, isTrue);

      await channel.sink.close();
      await settle();

      expect(machine.snapshotSubject.hasListener, isFalse);
    });

    test('with no machine connected the socket still errors and closes',
        () async {
      final (channel, messages) = connectWs('/ws/v1/machine/snapshot');

      final first = await messages.first.timeout(const Duration(seconds: 2));
      expect(first['error'], 'No machine connected');

      // Contract relied on by every ReconnectingWebSocket client: the socket
      // is CLOSED, so the client retries until a machine appears.
      await expectLater(
        messages.drain<void>().timeout(const Duration(seconds: 2)),
        completes,
      );
      await channel.sink.close();
    });
  });

  group('sibling machine sockets survive a machine swap', () {
    test('shotSettings re-binds to the new machine', () async {
      final first = TestDe1(deviceId: 'usb-2e8a-a-8549628789ABCDEF');
      await de1Controller.connectToDe1(first);

      final (channel, messages) = connectWs('/ws/v1/machine/shotSettings');
      final received = <Map<String, dynamic>>[];
      messages.listen(received.add);
      await settle();

      final second = await powerCycle(first);

      received.clear();
      second.emitShotSettings(De1ShotSettings(
        steamSetting: 0,
        targetSteamTemp: 150,
        targetSteamDuration: 30,
        targetHotWaterTemp: 90,
        targetHotWaterVolume: 200,
        targetHotWaterDuration: 30,
        targetShotVolume: 36,
        groupTemp: 92.5,
      ));
      await settle();

      expect(received.map((f) => f['targetSteamTemp']), contains(150));
      await channel.sink.close();
    });

    test('waterLevels re-binds to the new machine', () async {
      final first = TestDe1(deviceId: 'usb-2e8a-a-8549628789ABCDEF');
      await de1Controller.connectToDe1(first);

      final (channel, messages) = connectWs('/ws/v1/machine/waterLevels');
      final received = <Map<String, dynamic>>[];
      messages.listen(received.add);
      await settle();

      final second = await powerCycle(first);

      received.clear();
      second.emitWaterLevels(De1WaterLevels(
        currentLevel: 42.0,
        refillLevel: 10.0,
      ));
      await settle();

      expect(received.map((f) => f['currentLevel']), contains(42.0));
      await channel.sink.close();
    });
  });
}
