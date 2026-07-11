import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/impl/bengle/bengle.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1.dart';

import '../helpers/fake_ble_transport.dart';
import '../helpers/mock_device_discovery_service.dart';

/// Controller-level locks for the connect-time class re-resolution in
/// `De1Controller.connectToDe1` (model-authoritative selection):
///
///  1. the controller finishes connecting the RE-RESOLVED machine, not the
///     name-picked interim;
///  2. a *demoted* Bengle interim has every capability its `onConnect`
///     initialised disposed by the controller (the discarded interim never
///     sees `Bengle.onDisconnect`, so leaving any capability out leaks its
///     subjects — an earlier implementation shipped exactly that bug);
///  3. the connect idempotency guard keys on deviceId, not object identity
///     (post-swap `_de1` is a different object for the same machine).
void main() {
  late FakeBleTransport transport;
  late De1Controller controller;

  setUp(() async {
    transport = FakeBleTransport();
    transport.queueMmrResponseInt(MMRItem.calFlowEst, 100);
    final deviceController = DeviceController([MockDeviceDiscoveryService()]);
    await deviceController.initialize();
    controller = De1Controller(controller: deviceController);
  });

  tearDown(() async {
    await controller.dispose();
    await transport.dispose();
  });

  test('connectToDe1 re-resolves a DE1-named machine reporting a Bengle model '
      'and publishes the promoted instance', () async {
    transport.queueOnConnectResponses(v13Model: 128);
    final interim = UnifiedDe1(transport: transport);

    await controller.connectToDe1(interim);

    final connected = await controller.de1.first;
    expect(connected, isA<Bengle>());
    expect(
      identical(connected, interim),
      isFalse,
      reason:
          'the name-picked interim must be replaced by the resolved '
          'Bengle',
    );
  });

  test('a demoted Bengle interim has ALL its capability subjects disposed '
      '(none may leak)', () async {
    transport.queueOnConnectResponses(v13Model: 1);
    final interim = Bengle(transport: transport);

    await controller.connectToDe1(interim);

    final connected = await controller.de1.first;
    expect(connected, isA<UnifiedDe1>());
    expect(connected, isNot(isA<Bengle>()));

    // Every capability `Bengle.onConnect` initialises must be disposed on
    // the discarded interim — its `Bengle.onDisconnect` never runs. A
    // disposed capability closes its subjects, so each stream below must
    // complete; a leaked (still-open) subject makes `toList()` hang and the
    // bounded timeout fails the test. When a new capability mixin is added
    // to Bengle, register its stream(s) here alongside the teardown in
    // `De1Controller.connectToDe1`.
    Future<void> expectDisposed(Stream<Object?> stream, String what) {
      return expectLater(
        stream.toList().timeout(const Duration(seconds: 2)),
        completes,
        reason: '$what subject leaked on the demoted Bengle interim',
      );
    }

    await expectDisposed(interim.weightSnapshot, 'IntegratedScale.weight');
    await expectDisposed(interim.stopAtWeightTarget, 'IntegratedScale.saw');
    await expectDisposed(interim.ledStripState, 'LedStrip.state');
  });

  test('connectToDe1 is idempotent by deviceId after a class swap', () async {
    transport.queueOnConnectResponses(v13Model: 128);
    final interim = UnifiedDe1(transport: transport);
    await controller.connectToDe1(interim);
    final connected = await controller.de1.first;
    expect(connected, isA<Bengle>());

    // Re-passing the (discarded) name-picked interim: same physical
    // deviceId, but a DIFFERENT object from the resolved machine. An
    // object-identity guard would fall through and tear down + rebuild the
    // live connection; the deviceId guard must exit early instead.
    final events = <De1Interface?>[];
    final sub = controller.de1.skip(1).listen(events.add);

    await controller.connectToDe1(interim);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(
      events,
      isEmpty,
      reason:
          'idempotency guard must key on deviceId, not identity — the '
          'live connection was torn down',
    );
    expect(identical(await controller.de1.first, connected), isTrue);
    await sub.cancel();
  });
}
