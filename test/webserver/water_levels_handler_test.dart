import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1.dart';
import 'package:reaprime/src/services/webserver_service.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:shelf_plus/shelf_plus.dart';

import '../helpers/barrier_ble_transport.dart';
import '../helpers/mock_device_discovery_service.dart';
import '../helpers/mock_settings_service.dart';

/// Locks the end-to-end contract for `POST /api/v1/machine/waterLevels`:
/// the response and the shared device-write queue stay pending until the
/// DE1 transport write completes, and transport failures come back
/// through the REST error mapping instead of as unhandled async errors.
void main() {
  late BarrierBleTransport transport;
  late Handler handler;

  setUp(() async {
    transport = BarrierBleTransport();
    addTearDown(transport.dispose);
    transport.queueOnConnectResponses();

    final de1 = UnifiedDe1(transport: transport);

    final deviceController = DeviceController([MockDeviceDiscoveryService()]);
    await deviceController.initialize();
    final de1Controller = De1Controller(controller: deviceController);
    await de1Controller.connectToDe1(de1);

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
    handler = app.call;
  });

  Future<Response> postWaterLevels(int refillLevel) async {
    return await handler(
      Request(
        'POST',
        Uri.parse('http://localhost/api/v1/machine/waterLevels'),
        body: jsonEncode({'refillLevel': refillLevel}),
        headers: {'content-type': 'application/json'},
      ),
    );
  }

  test('waterLevels POST and queued writes stay pending until the write '
      'completes', () async {
    final writeArrived = transport.nextWrite(Endpoint.waterLevels.uuid);
    final barrier = Completer<void>();
    transport.pauseNextWrite(Endpoint.waterLevels.uuid, barrier);

    final first = postWaterLevels(50);
    await writeArrived;

    var secondWriteArrived = false;
    transport.nextWrite(Endpoint.waterLevels.uuid).then((_) {
      secondWriteArrived = true;
    });
    var secondResponseArrived = false;
    final second = postWaterLevels(60).then((r) {
      secondResponseArrived = true;
      return r;
    });
    await _settle();

    expect(secondWriteArrived, isFalse);
    expect(secondResponseArrived, isFalse);

    barrier.complete();

    final firstResponse = await first;
    expect(firstResponse.statusCode, 202);
    final secondResponse = await second;
    expect(secondResponse.statusCode, 202);
    expect(secondWriteArrived, isTrue);
  });

  test('transport failure surfaces through REST error handling', () async {
    final writeArrived = transport.nextWrite(Endpoint.waterLevels.uuid);
    final barrier = Completer<void>();
    transport.pauseNextWrite(Endpoint.waterLevels.uuid, barrier);

    final response = postWaterLevels(50);
    await writeArrived;

    barrier.completeError(StateError('transport boom'));
    final res = await response;
    expect(res.statusCode, 500);
  });
}

Future<void> _settle([int turns = 10]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
