import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1.dart';
import 'package:reaprime/src/models/device/impl/mock_de1/mock_de1.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/errors.dart';
import 'package:reaprime/src/services/firmware/bundled_firmware_catalog.dart';
import 'package:reaprime/src/services/webserver/firmware_handler.dart';
import 'package:shelf_plus/shelf_plus.dart';

import '../helpers/fake_ble_transport.dart';
import '../helpers/mock_device_discovery_service.dart';

final class _FixedController extends De1Controller {
  _FixedController({required super.controller, this.machine});

  De1Interface? machine;

  @override
  De1Interface connectedDe1() {
    return machine ?? (throw const DeviceNotConnectedException.machine());
  }
}

final class _FirmwareDe1 extends MockDe1 {
  _FirmwareDe1({required this.version});

  final String version;

  @override
  MachineInfo get machineInfo => MachineInfo(
    version: version,
    model: 'DE1Pro',
    serialNumber: 'firmware-test',
    groupHeadControllerPresent: false,
    extra: const {},
  );

  @override
  Future<void> updateFirmware(
    Uint8List fwImage, {
    required void Function(double progress) onProgress,
  }) async {
    onProgress(1);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Handler handler;
  late _FixedController controller;

  setUp(() async {
    final devices = DeviceController([MockDeviceDiscoveryService()]);
    await devices.initialize();
    controller = _FixedController(
      controller: devices,
      machine: _FirmwareDe1(version: '1352'),
    );
    final app = Router().plus;
    FirmwareHandler(
      controller: controller,
      catalog: BundledFirmwareCatalog(bundle: rootBundle),
    ).addRoutes(app);
    handler = app.call;
  });

  test('raw upload rejects an empty body and a missing machine', () async {
    final empty = await _raw(handler, const []);
    expect(empty.statusCode, 400);

    controller.machine = null;
    final unavailable = await _raw(handler, const [1]);
    expect(unavailable.statusCode, 503);
  });

  test('raw upload returns pre-stream 409 while an update is active', () async {
    controller.machine = MockDe1();
    final first = await _raw(handler, const [1]);
    expect(first.statusCode, 200);

    final second = await _raw(handler, const [1]);
    expect(second.statusCode, 409);

    final subscription = first.read().listen((_) {});
    await subscription.cancel();
  });

  test('NDJSON stays open until successful verification', () async {
    final transport = FakeBleTransport();
    addTearDown(transport.dispose);
    transport.queueOnConnectResponses(v13Model: 3);
    transport.queueMmrResponseInt(MMRItem.calFlowEst, 0);
    final de1 = UnifiedDe1(
      transport: transport,
      firmwareEraseTimeout: const Duration(seconds: 1),
      firmwareVerificationTimeout: const Duration(seconds: 1),
    );
    await de1.onConnect();
    controller.machine = de1;
    transport.queueFirmwareMapResponse([0, 0, 0, 1, 0xff, 0xff, 0xff]);

    final response = await _raw(handler, List.filled(16, 1));
    final lines = StreamIterator(
      response.read().transform(utf8.decoder).transform(const LineSplitter()),
    );
    expect(await lines.moveNext(), isTrue);
    expect(lines.current, contains('"status":"erasing"'));
    expect(await lines.moveNext(), isTrue);
    expect(lines.current, contains('"status":"uploading"'));

    var terminalArrived = false;
    final terminal = lines.moveNext().then((value) {
      terminalArrived = true;
      return value;
    });
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(terminalArrived, isFalse);

    transport.emitFirmwareMapResponse([0, 0, 0, 1, 0xff, 0xff, 0xfd]);
    expect(await terminal, isTrue);
    expect(lines.current, contains('"status":"done"'));
    await lines.cancel();
  });

  test('DELETE is idempotent without a machine', () async {
    controller.machine = null;
    final response = await handler(
      Request('DELETE', Uri.parse('http://localhost/api/v1/machine/firmware')),
    );
    expect(response.statusCode, 202);
    expect(await response.readAsString(), contains('"state":"idle"'));
  });

  test('managed apply rejects malformed JSON and invalid force', () async {
    final malformed = await _apply(handler, '{');
    expect(malformed.statusCode, 400);

    final invalidForce = await _apply(
      handler,
      jsonEncode({'artifactId': 'de1-1352', 'force': 'yes'}),
    );
    expect(invalidForce.statusCode, 400);
  });

  test('managed apply returns 404 for an unknown artifact', () async {
    final response = await _apply(
      handler,
      jsonEncode({'artifactId': 'missing'}),
    );
    expect(response.statusCode, 404);
  });

  test('force allows apply when installed build is unknown', () async {
    controller.machine = _FirmwareDe1(version: 'unknown');
    final response = await _apply(
      handler,
      jsonEncode({'artifactId': 'de1-1352', 'force': true}),
    );

    expect(response.statusCode, 200);
    expect(await response.readAsString(), contains('"status":"done"'));
  });

  test('catalog reports false when connected machine is up to date', () async {
    final response = await handler(
      Request('GET', Uri.parse('http://localhost/api/v1/machine/firmware')),
    );
    final body =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;

    expect(body['updateAvailable'], isFalse);
    expect(body['recommendedArtifactId'], isNull);
  });
}

Future<Response> _raw(Handler handler, List<int> body) async {
  return await handler(
    Request(
      'POST',
      Uri.parse('http://localhost/api/v1/machine/firmware'),
      headers: {'content-type': 'application/octet-stream'},
      body: body,
    ),
  );
}

Future<Response> _apply(Handler handler, String body) async {
  return await handler(
    Request(
      'POST',
      Uri.parse('http://localhost/api/v1/machine/firmware/apply'),
      headers: {'content-type': 'application/json'},
      body: body,
    ),
  );
}
