import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/impl/bengle/bengle.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1.dart';
import 'package:reaprime/src/models/device/led_strip.dart';

import '../../../../../../helpers/fake_ble_transport.dart';

/// Rejects every MMR read request that targets an LED register (address
/// prefix 0x8038, low byte 0x90..0xA4) with an immediate error, while the
/// foundation `onConnect` reads (0x8000xx) pass through — simulates firmware
/// without the LED registers so the failed-hydration fallback can be tested
/// without waiting out the 4 s × 3 read-timeout ladder.
class _LedReadFailingTransport extends FakeBleTransport {
  @override
  Future<void> write(
    String serviceUUID,
    String characteristicUUID,
    Uint8List data, {
    bool withResponse = true,
    Duration? timeout,
  }) {
    if (characteristicUUID == Endpoint.readFromMMR.uuid &&
        data.length >= 4 &&
        data[1] == 0x80 &&
        data[2] == 0x38 &&
        data[3] >= 0x90 &&
        data[3] <= 0xA4) {
      throw Exception('simulated LED register read failure');
    }
    return super.write(
      serviceUUID,
      characteristicUUID,
      data,
      withResponse: withResponse,
      timeout: timeout,
    );
  }
}

/// LED strip via MMR.
///
/// `LedStripCapability` maps the app's [LedStripState] onto the firmware LED
/// palette registers (front/rear × awake/sleep, raw `0x00RRGGBB` int32). There
/// is no switch register — the switch mirrors the front strip. These tests
/// assert the wire bytes are byte-exact against the firmware registers.
void main() {
  group('LedStripCapability → LED palette MMR', () {
    late FakeBleTransport transport;
    late Bengle bengle;

    setUp(() async {
      transport = FakeBleTransport();
      bengle = Bengle(transport: transport);
      transport.queueOnConnectResponses(v13Model: 128); // Bengle marker
      await bengle.onConnect();
      transport.writes.clear();
    });

    tearDown(() {
      transport.dispose();
    });

    List<FakeBleWrite> mmrWrites() => transport.writes
        .where((w) => w.characteristicUUID == Endpoint.writeToMMR.uuid)
        .toList();

    test('LED registers map to the real firmware addresses', () {
      expect(BengleLedMmr.frontAwake.address, 0x00803898);
      expect(BengleLedMmr.frontSleep.address, 0x008038A0);
      expect(BengleLedMmr.rearAwake.address, 0x0080389C);
      expect(BengleLedMmr.rearSleep.address, 0x008038A4);
      expect(BengleLedMmr.frontLive.address, 0x00803890);
      expect(BengleLedMmr.rearLive.address, 0x00803894);
    });

    test(
      'setLedStrip writes 4 palette registers with packed 0x00RRGGBB',
      () async {
        await bengle.setLedStrip(
          const LedStripState(
            frontStrip: ZoneLedState(
              awake: Color16(
                0x3838,
                0x5A5A,
                0x9292,
              ), // #385A92 (16-bit/channel)
              sleeping: Color16.off,
            ),
            backStrip: ZoneLedState(
              awake: Color16(0xFFFF, 0x7A7A, 0x0000), // #FF7A00
              sleeping: Color16.off,
            ),
          ),
        );

        final w = mmrWrites();
        expect(w.length, 4, reason: 'front+rear × awake+sleep');

        // frontAwake 0x803898 ← 0x385A92 (little-endian payload)
        expect(w[0].data[0], 4);
        expect(w[0].data.sublist(1, 4), [0x80, 0x38, 0x98]);
        expect(w[0].data.sublist(4, 8), [0x92, 0x5A, 0x38, 0x00]);
        // frontSleep 0x8038A0 ← off
        expect(w[1].data.sublist(1, 4), [0x80, 0x38, 0xA0]);
        expect(w[1].data.sublist(4, 8), [0x00, 0x00, 0x00, 0x00]);
        // rearAwake 0x80389C ← 0xFF7A00
        expect(w[2].data.sublist(1, 4), [0x80, 0x38, 0x9C]);
        expect(w[2].data.sublist(4, 8), [0x00, 0x7A, 0xFF, 0x00]);
        // rearSleep 0x8038A4 ← off
        expect(w[3].data.sublist(1, 4), [0x80, 0x38, 0xA4]);
        expect(w[3].data.sublist(4, 8), [0x00, 0x00, 0x00, 0x00]);
      },
    );

    test('16-bit channels are truncated to the FW 8-bit high byte', () async {
      // Only the high byte of each 16-bit channel reaches the wire.
      await bengle.setLedStrip(
        const LedStripState(
          frontStrip: ZoneLedState(awake: Color16(0xABCD, 0x1234, 0x89FF)),
        ),
      );
      // packed = 0x00 AB 12 89 → little-endian [0x89, 0x12, 0xAB, 0x00]
      expect(mmrWrites()[0].data.sublist(4, 8), [0x89, 0x12, 0xAB, 0x00]);
    });

    test('cache reflects the written state', () async {
      const state = LedStripState(
        frontStrip: ZoneLedState(awake: Color16(0x3838, 0x5A5A, 0x9292)),
      );
      await bengle.setLedStrip(state);
      final got = await bengle.getLedStripState();
      expect(got.frontStrip.awake, const Color16(0x3838, 0x5A5A, 0x9292));
    });

    test('resetLedStrip reads the 4 registers back into the cache', () async {
      // FW returns 0x00RRGGBB; decode byte-replicates to 16-bit (0xAB → 0xABAB).
      transport.queueMmrResponseInt(BengleLedMmr.frontAwake, 0x385A92);
      transport.queueMmrResponseInt(BengleLedMmr.frontSleep, 0x000000);
      transport.queueMmrResponseInt(BengleLedMmr.rearAwake, 0xFF7A00);
      transport.queueMmrResponseInt(BengleLedMmr.rearSleep, 0x000000);

      await bengle.resetLedStrip();
      final s = await bengle.getLedStripState();
      expect(s.frontStrip.awake, const Color16(0x3838, 0x5A5A, 0x9292));
      expect(s.backStrip.awake, const Color16(0xFFFF, 0x7A7A, 0x0000));
      // switch mirrors front
      expect(s.frontSwitch.awake, s.frontStrip.awake);
    });

    test('commitLedStrip re-writes the cached palette', () async {
      await bengle.setLedStrip(
        const LedStripState(
          frontStrip: ZoneLedState(awake: Color16(0x3838, 0x5A5A, 0x9292)),
        ),
      );
      transport.writes.clear();
      await bengle.commitLedStrip();
      expect(mmrWrites().length, 4);
    });

    test('previewLedColor writes only the 2 live registers — palette and cache '
        'untouched', () async {
      // Seed a known palette first so "cache untouched" is observable.
      const palette = LedStripState(
        frontStrip: ZoneLedState(awake: Color16(0x3838, 0x5A5A, 0x9292)),
        backStrip: ZoneLedState(awake: Color16(0xFFFF, 0x7A7A, 0x0000)),
      );
      await bengle.setLedStrip(palette);
      transport.writes.clear();

      final emitted = <LedStripState>[];
      final sub = bengle.ledStripState.skip(1).listen(emitted.add);
      addTearDown(sub.cancel);

      await bengle.previewLedColor(
        const Color16(0xFFFF, 0x0000, 0x0000), // #FF0000
        const Color16(0x0000, 0x0000, 0xFFFF), // #0000FF
      );

      final w = mmrWrites();
      expect(w.length, 2, reason: 'frontLive + rearLive only — no palette');
      // frontLive 0x803890 ← 0xFF0000 (little-endian payload)
      expect(w[0].data[0], 4);
      expect(w[0].data.sublist(1, 4), [0x80, 0x38, 0x90]);
      expect(w[0].data.sublist(4, 8), [0x00, 0x00, 0xFF, 0x00]);
      // rearLive 0x803894 ← 0x0000FF
      expect(w[1].data.sublist(1, 4), [0x80, 0x38, 0x94]);
      expect(w[1].data.sublist(4, 8), [0xFF, 0x00, 0x00, 0x00]);

      // Stored palette cache is untouched and nothing was emitted.
      final cached = await bengle.getLedStripState();
      expect(cached.frontStrip.awake, const Color16(0x3838, 0x5A5A, 0x9292));
      await Future(() {}); // let any stray emission propagate
      expect(
        emitted,
        isEmpty,
        reason: 'preview must not emit on ledStripState',
      );
    });

    test('clearLedPreview restores the cached awake pair into the live '
        'registers', () async {
      await bengle.setLedStrip(
        const LedStripState(
          frontStrip: ZoneLedState(awake: Color16(0x3838, 0x5A5A, 0x9292)),
          backStrip: ZoneLedState(awake: Color16(0xFFFF, 0x7A7A, 0x0000)),
        ),
      );
      transport.writes.clear();

      await bengle.clearLedPreview();

      final w = mmrWrites();
      expect(w.length, 2);
      // frontLive 0x803890 ← cached front awake 0x385A92
      expect(w[0].data.sublist(1, 4), [0x80, 0x38, 0x90]);
      expect(w[0].data.sublist(4, 8), [0x92, 0x5A, 0x38, 0x00]);
      // rearLive 0x803894 ← cached rear awake 0xFF7A00
      expect(w[1].data.sublist(1, 4), [0x80, 0x38, 0x94]);
      expect(w[1].data.sublist(4, 8), [0x00, 0x7A, 0xFF, 0x00]);
    });

    test('initial state is all-off when the machine stores an all-off '
        'palette', () async {
      // setUp queued the default (all-zero) palette responses, so the
      // connect-time hydration read back black for every slot.
      final state = await bengle.getLedStripState();
      expect(state.frontStrip.awake, Color16.off);
      expect(state.backStrip.awake, Color16.off);
    });

    test('connect hydrates the cache from the four stored palette registers',
        () async {
      // Hydration must serve the machine's stored colours on the first GET
      // after an app restart — byte-exact: FW packed 0x00RRGGBB decodes by
      // byte-replication (0xAB → 0xABAB) for every palette slot.
      final t = FakeBleTransport();
      final b = Bengle(transport: t);
      t.queueOnConnectResponses(
        v13Model: 128,
        ledFrontAwake: 0x385A92,
        ledFrontSleep: 0x112233,
        ledRearAwake: 0xFF7A00,
        ledRearSleep: 0x0000FF,
      );
      await b.onConnect();
      addTearDown(t.dispose);

      final s = await b.getLedStripState();
      expect(s.frontStrip.awake, const Color16(0x3838, 0x5A5A, 0x9292));
      expect(s.frontStrip.sleeping, const Color16(0x1111, 0x2222, 0x3333));
      expect(s.backStrip.awake, const Color16(0xFFFF, 0x7A7A, 0x0000));
      expect(s.backStrip.sleeping, const Color16(0x0000, 0x0000, 0xFFFF));
      // Switch mirrors the front strip on read (no switch register).
      expect(s.frontSwitch.awake, s.frontStrip.awake);
      expect(s.frontSwitch.sleeping, s.frontStrip.sleeping);
    });

    test('connect-time hydration is read-only — no LED register writes, '
        'live/preview pair untouched', () async {
      final t = FakeBleTransport();
      final b = Bengle(transport: t);
      t.queueOnConnectResponses(
        v13Model: 128,
        ledFrontAwake: 0x385A92,
        ledRearAwake: 0xFF7A00,
      );
      await b.onConnect();
      addTearDown(t.dispose);

      List<int> addrBytes(BengleLedMmr reg) => [
        (reg.address >> 16) & 0xFF,
        (reg.address >> 8) & 0xFF,
        reg.address & 0xFF,
      ];
      bool targets(FakeBleWrite w, BengleLedMmr reg) {
        final a = addrBytes(reg);
        return w.data.length >= 4 &&
            w.data[1] == a[0] &&
            w.data[2] == a[1] &&
            w.data[3] == a[2];
      }

      // No writeToMMR frame may target ANY LED register — hydration must
      // never change machine state.
      final ledWrites = t.writes.where(
        (w) =>
            w.characteristicUUID == Endpoint.writeToMMR.uuid &&
            BengleLedMmr.values.any((reg) => targets(w, reg)),
      );
      expect(
        ledWrites,
        isEmpty,
        reason: 'hydration must not write any LED register',
      );

      // The live/preview pair must see no traffic at all — not even reads —
      // so hydration can never disturb an in-flight preview or flash the
      // strips.
      final liveTraffic = t.writes.where(
        (w) =>
            (w.characteristicUUID == Endpoint.writeToMMR.uuid ||
                w.characteristicUUID == Endpoint.readFromMMR.uuid) &&
            (targets(w, BengleLedMmr.frontLive) ||
                targets(w, BengleLedMmr.rearLive)),
      );
      expect(
        liveTraffic,
        isEmpty,
        reason: 'hydration must not touch the live/preview registers',
      );

      // And the four palette registers were read (readFromMMR), once each.
      for (final reg in const [
        BengleLedMmr.frontAwake,
        BengleLedMmr.frontSleep,
        BengleLedMmr.rearAwake,
        BengleLedMmr.rearSleep,
      ]) {
        final reads = t.writes.where(
          (w) =>
              w.characteristicUUID == Endpoint.readFromMMR.uuid &&
              targets(w, reg),
        );
        expect(reads.length, 1, reason: 'one hydration read of ${reg.name}');
      }
    });

    test('failed hydration read leaves the cache all-off and the connect '
        'completes', () async {
      // Failure-tolerant: on FW without the LED registers (or a dropped
      // read) the cache keeps its pre-hydration all-off seed and GET falls
      // back to the old behavior — the connect itself must not throw.
      final t = _LedReadFailingTransport();
      final b = Bengle(transport: t);
      t.queueOnConnectResponses(v13Model: 128);
      await b.onConnect(); // must not throw
      addTearDown(t.dispose);

      final s = await b.getLedStripState();
      expect(s.frontStrip.awake, Color16.off);
      expect(s.frontStrip.sleeping, Color16.off);
      expect(s.backStrip.awake, Color16.off);
      expect(s.backStrip.sleeping, Color16.off);
    });

    test('disposeLedStrip closes the subject', () async {
      await bengle.onDisconnect();
      await expectLater(
        bengle.ledStripState,
        emitsInOrder([isA<LedStripState>(), emitsDone]),
      );
    });

    test('reconnect re-inits the subject leak-free', () async {
      await bengle.disconnect();
      transport.queueOnConnectResponses(v13Model: 128);
      await bengle.onConnect();

      var closed = false;
      try {
        await bengle.ledStripState.first.timeout(
          const Duration(milliseconds: 50),
        );
      } on TimeoutException {
        // Expected: open but quiet — capability is alive.
      } on StateError {
        closed = true;
      }
      expect(
        closed,
        isFalse,
        reason:
            'ledStripState closed after reconnect — mixin failed to '
            're-init its BehaviorSubject',
      );
    });
  });
}
