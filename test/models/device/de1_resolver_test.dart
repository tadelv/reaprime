import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/impl/bengle/bengle.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';
import 'package:reaprime/src/models/device/impl/de1/de1_resolver.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1.dart';

import '../../helpers/fake_ble_transport.dart';

/// Model-authoritative class selection — BLE discovery picks the machine
/// class by advertised name (`DeviceMatcher`), but `v13Model`, read on
/// connect, is authoritative. `resolveMachineForModel` runs after
/// `onConnect` and returns the concrete machine matching the detected model:
/// the same instance when the name-picked class already agrees, otherwise a
/// fresh instance of the right class over the same connected transport with
/// the read identity carried over. This mirrors the serial path, which
/// already instantiates `Bengle` vs `UnifiedDe1` from `v13Model >= 128`.
void main() {
  group('resolveMachineForModel', () {
    late FakeBleTransport transport;

    setUp(() {
      transport = FakeBleTransport();
      // onConnect warms the flow-cal cache (calFlowEst); queue it so onConnect
      // returns immediately instead of eating the MMR read-retry timeout.
      transport.queueMmrResponseInt(MMRItem.calFlowEst, 100);
    });

    tearDown(() => transport.dispose());

    test(
      'DE1-named device reporting v13Model >= 128 resolves to Bengle',
      () async {
        transport.queueOnConnectResponses(v13Model: 128, serialN: 4242);
        final machine = UnifiedDe1(transport: transport);
        await machine.onConnect();

        final resolved = resolveMachineForModel(machine);

        expect(resolved, isA<Bengle>());
        expect(
          identical(resolved, machine),
          isFalse,
          reason: 'must be a fresh Bengle, not the name-picked UnifiedDe1',
        );
        // Identity read on connect is carried over (no MMR re-read needed).
        expect(resolved.machineInfo.serialNumber, '4242');
        expect((resolved as Bengle).isBengle, isTrue);
      },
    );

    test(
      'plain DE1 (model 1) stays UnifiedDe1 — no swap, same instance',
      () async {
        transport.queueOnConnectResponses(v13Model: 1);
        final machine = UnifiedDe1(transport: transport);
        await machine.onConnect();

        final resolved = resolveMachineForModel(machine);

        expect(identical(resolved, machine), isTrue);
        expect(resolved, isA<UnifiedDe1>());
        expect(resolved, isNot(isA<Bengle>()));
      },
    );

    test(
      'Bengle-named device reporting model >= 128 stays Bengle — no swap',
      () async {
        transport.queueOnConnectResponses(v13Model: 128);
        final machine = Bengle(transport: transport);
        await machine.onConnect();

        final resolved = resolveMachineForModel(machine);

        expect(identical(resolved, machine), isTrue);
        expect(resolved, isA<Bengle>());
      },
    );

    test(
      'Bengle-named device reporting a DE1 model demotes to UnifiedDe1',
      () async {
        transport.queueOnConnectResponses(v13Model: 1);
        final machine = Bengle(transport: transport);
        await machine.onConnect();

        final resolved = resolveMachineForModel(machine);

        expect(resolved, isA<UnifiedDe1>());
        expect(resolved, isNot(isA<Bengle>()));
        expect(identical(resolved, machine), isFalse);
        expect((resolved as UnifiedDe1).isBengle, isFalse);
      },
    );

    test(
      'a re-resolved Bengle completes onConnect over the shared transport '
      'after the MMR queue is drained (identity short-circuits re-reads)',
      () async {
        // The interim onConnect consumes the queued MMR responses. The crux of
        // the design: the re-resolved instance carries the identity over, so its
        // onConnect must short-circuit the MMR reads (its `_info` is set) and
        // still complete — NOT hang on the now-empty queue.
        transport.queueOnConnectResponses(v13Model: 128, serialN: 7);
        final machine = UnifiedDe1(transport: transport);
        await machine.onConnect();

        final resolved = resolveMachineForModel(machine) as Bengle;
        // Mirrors De1Controller.connectToDe1: finish connecting the resolved
        // instance. With no re-queued responses this would time out (~12s) and
        // throw if it re-read MMRs.
        await resolved.onConnect().timeout(const Duration(seconds: 8));

        expect(resolved.isBengle, isTrue);
        expect(resolved.machineInfo.serialNumber, '7');
      },
    );

    test(
      'detaching the interim after a promotion leaves the resolved instance '
      'working over the shared transport (detach must not dispose it)',
      () async {
        transport.queueOnConnectResponses(v13Model: 128, serialN: 9);
        final interim = UnifiedDe1(transport: transport);
        await interim.onConnect();
        final resolved = resolveMachineForModel(interim) as Bengle;
        await resolved.onConnect();

        // Mirror De1Controller.connectToDe1: tear down the discarded interim.
        await interim.detachTransport();

        // The shared transport must still be alive — the resolved instance can
        // still round-trip an MMR read. (If detach had disposed the transport,
        // this would hang/throw.)
        transport.queueMmrResponseInt(MMRItem.fanThreshold, 55);
        expect(
          await resolved.getFanThreshhold().timeout(const Duration(seconds: 8)),
          55,
        );
      },
    );
  });
}
