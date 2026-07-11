import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/impl/bengle/bengle.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1.dart';
import 'package:reaprime/src/models/device/machine.dart';

import '../../../../../../helpers/fake_ble_transport.dart';

/// Golden 0xA013 frame: weight 36.5 g, group pressure 9.00 bar, GFlow 1.80 g/s,
/// milk 0. (Full byte breakdown lives in `bengle_shot_sample_test.dart`.)
final Uint8List _golden0xA013 = Uint8List.fromList(const [
  0x03, 0xE8, 0x03, 0x84, 0x02, 0x58, 0x00, 0xFA, 0x00, 0xC8, 0x00, 0xB4, //
  0x24, 0x22, 0x22, 0x60, 0x24, 0x54, 0x23, 0x28, 0x04, 0x90, 0x07, 0x34, //
  0xBC, 0x00, 0x00, 0x00,
]);

void main() {
  group('Bengle 0xA013 snapshot pipeline', () {
    late FakeBleTransport transport;
    late Bengle bengle;

    setUp(() async {
      transport = FakeBleTransport();
      // `queueOnConnectResponses` doesn't cover `calFlowEst` (the flow-cal
      // warm-up read at the tail of onConnect); queue it so onConnect returns
      // promptly instead of eating the MMR read-retry timeout.
      transport.queueMmrResponseInt(MMRItem.calFlowEst, 100);
      transport.queueOnConnectResponses(v13Model: 128);
      bengle = Bengle(transport: transport);
      await bengle.onConnect();
      expect(bengle.isBengle, isTrue);
    });

    tearDown(() => transport.dispose());

    test(
      '0xA013 is the SOLE snapshot source — 0xA00D is parse-and-dropped',
      () async {
        final snapshots = <MachineSnapshot>[];
        final sub = bengle.currentSnapshot.listen(snapshots.add);
        await pumpEventQueue();
        // The seeded 28-zero frame emits one initial snapshot.
        final baseline = snapshots.length;

        // Inject a 0xA00D shot sample — on a Bengle this must NOT become a
        // snapshot (firmware streams both 0xA00D and 0xA013 at 15 Hz; charting
        // both would double-sample).
        final cb00D = transport.subscribers[Endpoint.shotSample.uuid];
        expect(
          cb00D,
          isNotNull,
          reason: '0xA00D stays subscribed even on a Bengle',
        );
        cb00D!(Uint8List(19)..[0] = 0x05);
        await pumpEventQueue();
        expect(
          snapshots.length,
          baseline,
          reason: '0xA00D must be parse-and-dropped on a Bengle',
        );

        // Inject a 0xA013 frame — exactly one snapshot, carrying the decoded
        // weight / gravimetric flow / group pressure.
        final cb013 = transport.subscribers[Endpoint.bengleShotSample.uuid];
        expect(
          cb013,
          isNotNull,
          reason: 'onConnect must subscribe 0xA013 on a Bengle',
        );
        cb013!(_golden0xA013);
        await pumpEventQueue();

        expect(
          snapshots.length,
          baseline + 1,
          reason: 'exactly one snapshot, from 0xA013',
        );
        final snap = snapshots.last;
        expect(snap.pressure, closeTo(9.00, 1e-9));
        expect(snap.weight, closeTo(36.5, 1e-9));
        expect(snap.weightFlow, closeTo(1.80, 1e-9));
        expect(snap.milkTemperature, closeTo(0.0, 1e-9));

        await sub.cancel();
      },
    );

    test(
      'every MachineSnapshot field maps from the 0xA013 frame + state frame '
      '(incl. steamTemperature rounding)',
      () async {
        final snapshots = <MachineSnapshot>[];
        final sub = bengle.currentSnapshot.listen(snapshots.add);
        await pumpEventQueue();
        final baseline = snapshots.length;

        // Latest state frame: espresso (0x04) / pour (0x05) — read exactly
        // like the 0xA00D path (state layout is transport-shared).
        transport.subscribers[Endpoint.stateInfo.uuid]!(
          Uint8List.fromList([0x04, 0x05]),
        );
        // Golden frame with SteamTemp raw 13550 (0x34EE) -> 135.5 °C: the
        // int snapshot field must carry `.round()` = 136, matching the
        // whole-degree 0xA00D field (G14 — don't widen the shared type).
        final frame = Uint8List.fromList(_golden0xA013);
        frame[23] = 0x34;
        frame[24] = 0xEE;
        transport.subscribers[Endpoint.bengleShotSample.uuid]!(frame);
        await pumpEventQueue();

        expect(snapshots.length, baseline + 1);
        final snap = snapshots.last;
        expect(snap.state.state, MachineState.espresso);
        expect(snap.state.substate, MachineSubstate.pouring);
        expect(snap.pressure, closeTo(9.00, 1e-9));
        expect(snap.flow, closeTo(2.50, 1e-9));
        expect(snap.mixTemperature, closeTo(92.50, 1e-9));
        expect(snap.groupTemperature, closeTo(88.00, 1e-9));
        expect(snap.targetMixTemperature, closeTo(93.00, 1e-9));
        expect(snap.targetGroupTemperature, closeTo(90.00, 1e-9));
        expect(snap.targetPressure, closeTo(6.00, 1e-9));
        expect(snap.targetFlow, closeTo(2.00, 1e-9));
        expect(snap.profileFrame, 7);
        expect(
          snap.steamTemperature,
          136,
          reason: '135.5 °C must round, not truncate',
        );
        expect(snap.weight, closeTo(36.5, 1e-9));
        expect(snap.weightFlow, closeTo(1.80, 1e-9));
        expect(snap.milkTemperature, closeTo(0.0, 1e-9));

        await sub.cancel();
      },
    );

    test(
      'a truncated (<28 byte) 0xA013 frame is dropped, not decoded',
      () async {
        final snapshots = <MachineSnapshot>[];
        final sub = bengle.currentSnapshot.listen(snapshots.add);
        await pumpEventQueue();
        final baseline = snapshots.length;

        final cb013 = transport.subscribers[Endpoint.bengleShotSample.uuid]!;
        // 20 bytes < 28 — must be dropped without a RangeError or a snapshot.
        cb013(Uint8List(20));
        await pumpEventQueue();

        expect(
          snapshots.length,
          baseline,
          reason: 'short frame dropped — no new snapshot, no crash',
        );

        await sub.cancel();
      },
    );
  });

  group('plain DE1 (v13Model < 128)', () {
    test('never subscribes the 0xA013 characteristic', () async {
      // Blind-enabling a characteristic a plain DE1 lacks throws and
      // permanently stalls the BLE command queue (de1plus
      // de1_comms.tcl:777-785) — the subscribe must be identity-gated.
      final transport = FakeBleTransport();
      transport.queueMmrResponseInt(MMRItem.calFlowEst, 100);
      transport.queueOnConnectResponses(v13Model: 1);
      final de1 = UnifiedDe1(transport: transport);
      await de1.onConnect();

      expect(de1.isBengle, isFalse);
      expect(
        transport.subscribers[Endpoint.bengleShotSample.uuid],
        isNull,
        reason: 'a plain DE1 must NOT get a 0xA013 CCCD subscribe',
      );
      expect(
        transport.subscribers[Endpoint.shotSample.uuid],
        isNotNull,
        reason: 'the 0xA00D pipeline is untouched on a plain DE1',
      );

      await transport.dispose();
    });
  });
}
