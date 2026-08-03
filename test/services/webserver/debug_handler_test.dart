import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/impl/mock_de1/mock_de1.dart';
import 'package:reaprime/src/services/webserver/debug_handler.dart';
import 'package:shelf_plus/shelf_plus.dart';

import '../../helpers/mock_device_discovery_service.dart';
import '../../helpers/test_de1.dart';

void main() {
  late ScaleController scaleController;
  late De1Controller de1Controller;
  late Handler handler;

  setUp(() async {
    scaleController = ScaleController();
    final deviceController = DeviceController([MockDeviceDiscoveryService()]);
    await deviceController.initialize();
    de1Controller = De1Controller(controller: deviceController);
    final app = Router().plus;
    DebugHandler(
      scaleController: scaleController,
      de1Controller: de1Controller,
    ).addRoutes(app);
    handler = app.call;
  });

  tearDown(() async {
    scaleController.dispose();
    await de1Controller.dispose();
  });

  Future<Response> get() async => await handler(
    Request('GET', Uri.parse('http://localhost/api/v1/debug/flow-smoothing')),
  );

  Future<Response> post(Object body) async => await handler(
    Request(
      'POST',
      Uri.parse('http://localhost/api/v1/debug/flow-smoothing'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode(body),
    ),
  );

  Future<Response> machineCommand(String command) async => await handler(
    Request(
      'POST',
      Uri.parse('http://localhost/api/v1/debug/machine/$command'),
    ),
  );

  test('gets and updates flow smoothing', () async {
    final initial = await get();
    expect(initial.statusCode, 200);
    expect(jsonDecode(await initial.readAsString()), {
      'windowMs': 600,
      'movingAverageSamples': 10,
    });

    final updated = await post({'windowMs': 800, 'movingAverageSamples': 6});
    expect(updated.statusCode, 200);
    expect(jsonDecode(await updated.readAsString()), {
      'windowMs': 800,
      'movingAverageSamples': 6,
    });
  });

  test('rejects invalid updates atomically', () async {
    for (final body in [
      {'windowMs': '800', 'movingAverageSamples': 6},
      {'windowMs': 99, 'movingAverageSamples': 6},
      {'windowMs': 800, 'movingAverageSamples': 51},
    ]) {
      final response = await post(body);
      expect(response.statusCode, 400);
    }

    final current = await get();
    expect(jsonDecode(await current.readAsString()), {
      'windowMs': 600,
      'movingAverageSamples': 10,
    });
  });

  group('POST /api/v1/debug/machine', () {
    test(
      'disconnect emits a disconnected state and clears the machine',
      () async {
        final mock = MockDe1();
        await de1Controller.connectToDe1(mock);

        final res = await machineCommand('disconnect');
        expect(res.statusCode, 200);
        expect(jsonDecode(await res.readAsString()), {
          'status': 'disconnected',
        });

        await Future<void>.delayed(Duration.zero);
        expect(de1Controller.connectedDe1OrNull, isNull);
      },
    );

    test('rejects with 400 when no machine is connected', () async {
      final res = await machineCommand('disconnect');
      expect(res.statusCode, 400);
    });

    test(
      'rejects with 400 when the connected machine is not a MockDe1',
      () async {
        final testDe1 = TestDe1();
        await de1Controller.connectToDe1(testDe1);
        testDe1.emitShotSettings(
          De1ShotSettings(
            steamSetting: 0,
            targetSteamTemp: 150,
            targetSteamDuration: 30,
            targetHotWaterTemp: 75,
            targetHotWaterVolume: 50,
            targetHotWaterDuration: 30,
            targetShotVolume: 36,
            groupTemp: 94.0,
          ),
        );
        await Future<void>.delayed(Duration.zero);

        final res = await machineCommand('disconnect');
        expect(res.statusCode, 400);
      },
    );

    test('unknown commands return 404', () async {
      final mock = MockDe1();
      await de1Controller.connectToDe1(mock);

      final res = await machineCommand('frobnicate');
      expect(res.statusCode, 404);
    });

    test(
      'unknown commands return 404 even without a connected machine',
      () async {
        final res = await machineCommand('frobnicate');
        expect(res.statusCode, 404);
      },
    );
  });
}
