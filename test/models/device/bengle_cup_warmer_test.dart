import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/bengle_interface.dart';
import 'package:reaprime/src/models/device/impl/bengle/bengle.dart';
import 'package:reaprime/src/models/device/impl/bengle/bengle_mmr.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1.dart';

import '../../helpers/fake_ble_transport.dart';

/// Wires the real `Bengle` class through `FakeBleTransport` to confirm the
/// public cup-warmer API (setCupWarmerTemperature / getCupWarmerTemperature)
/// rides the scaledFloat MMR helpers and the `BengleMmr.matSetPoint` address.
///
/// This is the integration point between `BengleInterface`,
/// `Bengle`'s extension on `UnifiedDe1`'s `@protected` MMR helpers, and the
/// `MmrValueKind.scaledFloat` plumbing. The unit-level mechanics
/// (clamping, packing, kind-mismatch errors) live in
/// `test/unit/models/device/impl/de1/unified_de1/protected_surface_test.dart`.
void main() {
  group('Bengle cup warmer wiring', () {
    late FakeBleTransport transport;
    late Bengle bengle;

    setUp(() async {
      transport = FakeBleTransport();
      bengle = Bengle(transport: transport);
      transport.queueOnConnectResponses(v13Model: 128); // Bengle marker
      await bengle.onConnect();
    });

    tearDown(() {
      transport.dispose();
    });

    test(
      'setCupWarmerTemperature writes a whole-°C uint32 to BengleMmr.matSetPoint',
      () async {
        transport.writes.clear();
        await bengle.setCupWarmerTemperature(70.0);

        final frame = transport.writes.firstWhere(
          (w) => w.characteristicUUID == Endpoint.writeToMMR.uuid,
        );

        // Address bytes [1..3] match BengleMmr.matSetPoint (0x00803874).
        final addr = ByteData(4)
          ..setInt32(0, BengleMmr.matSetPoint.address, Endian.big);
        expect(frame.data[1], addr.getUint8(1));
        expect(frame.data[2], addr.getUint8(2));
        expect(frame.data[3], addr.getUint8(3));

        // firmware mult=1, so 70 °C encodes as LE 70 (not 700).
        final payload = ByteData.sublistView(frame.data, 4, 8);
        expect(payload.getUint32(0, Endian.little), equals(70));
      },
    );

    test('getCupWarmerTemperature reads a whole-°C uint32 back from the wire', () async {
      // Pre-queue a 50 °C reading (raw uint32, mult=1) at the matSetPoint addr.
      final bytes = ByteData(4)..setUint32(0, 50, Endian.little);
      transport.queueMmrResponseRaw(
        BengleMmr.matSetPoint,
        List<int>.generate(4, (i) => bytes.getUint8(i)),
      );

      final result = await bengle.getCupWarmerTemperature();
      expect(result, closeTo(50.0, 1e-6));
    });

    test('setCupWarmerTemperature clamps over-range writes', () async {
      transport.writes.clear();
      await bengle.setCupWarmerTemperature(120.0); // FW max is 80 °C

      final frame = transport.writes.firstWhere(
        (w) => w.characteristicUUID == Endpoint.writeToMMR.uuid,
      );
      final payload = ByteData.sublistView(frame.data, 4, 8);
      expect(payload.getUint32(0, Endian.little), equals(80));
    });

    // --- CupWarmerMode enable + re-send on connect ---

    Iterable<FakeBleWrite> writesTo(int address) {
      final ba = ByteData(4)..setInt32(0, address, Endian.big);
      return transport.writes.where((w) =>
          w.characteristicUUID == Endpoint.writeToMMR.uuid &&
          w.data[1] == ba.getUint8(1) &&
          w.data[2] == ba.getUint8(2) &&
          w.data[3] == ba.getUint8(3));
    }

    int payloadOf(FakeBleWrite w) =>
        ByteData.sublistView(w.data, 4, 8).getUint32(0, Endian.little);

    test('setCupWarmerTemperature also enables CupWarmerMode', () async {
      transport.writes.clear();
      await bengle.setCupWarmerTemperature(70.0);
      final mode = writesTo(BengleMmr.cupWarmerMode.address);
      expect(mode, isNotEmpty,
          reason: 'CupWarmerMode (0x008038AC) must be written — temperature '
              'alone does nothing');
      expect(payloadOf(mode.last), equals(1));
    });

    test('setCupWarmerTemperature(0) disables CupWarmerMode', () async {
      transport.writes.clear();
      await bengle.setCupWarmerTemperature(0.0);
      expect(payloadOf(writesTo(BengleMmr.cupWarmerMode.address).last),
          equals(0));
    });

    test('CupWarmerMode + target are re-asserted on reconnect when enabled',
        () async {
      await bengle.setCupWarmerTemperature(70.0); // enable
      await bengle.disconnect();

      transport.queueOnConnectResponses(v13Model: 128);
      transport.writes.clear();
      await bengle.onConnect();

      expect(writesTo(BengleMmr.matSetPoint.address), isNotEmpty,
          reason: 'matSetPoint re-pushed on connect');
      final mode = writesTo(BengleMmr.cupWarmerMode.address);
      expect(mode, isNotEmpty, reason: 'CupWarmerMode re-pushed on connect');
      expect(payloadOf(mode.last), equals(1));
    });

    test('a disabled warmer does not re-push on reconnect', () async {
      // never enabled → _cupWarmerTarget stays 0
      await bengle.disconnect();
      transport.queueOnConnectResponses(v13Model: 128);
      transport.writes.clear();
      await bengle.onConnect();
      expect(writesTo(BengleMmr.cupWarmerMode.address), isEmpty);
    });

    // --- MatCurrentTemp live mat temperature (defensive read) ---

    test('getCupWarmerCurrentTemperature unscales a live ×10 reading',
        () async {
      transport.queueMmrResponseInt(
          BengleMmr.matCurrentTemp, 425); // 42.5 °C × 10
      expect(
          await bengle.getCupWarmerCurrentTemperature(), closeTo(42.5, 1e-6));
    });

    test('getCupWarmerCurrentTemperature maps raw 0 to null (no reading)',
        () async {
      transport.queueMmrResponseInt(BengleMmr.matCurrentTemp, 0);
      expect(await bengle.getCupWarmerCurrentTemperature(), isNull,
          reason: 'raw 0 = NTC open/short — never fake a temperature');
    });

    test('getCupWarmerCurrentTemperature returns null when the read fails',
        () async {
      // Older firmware has no MatCurrentTemp register: simulate the read
      // request failing at the transport rather than waiting out the
      // MMR-read timeout ladder.
      final failing =
          _MmrReadFailsTransport({BengleMmr.matCurrentTemp.address});
      final b = Bengle(transport: failing);
      failing.queueOnConnectResponses(v13Model: 128);
      await b.onConnect();
      expect(await b.getCupWarmerCurrentTemperature(), isNull);
      failing.dispose();
    });

    // --- Scheduled pre-warm: MatPreheatEnable / LeadMin / Active (rows 59-61)

    test('setCupWarmerPrewarm writes 1 to MatPreheatEnable and the lead to '
        'MatPreheatLeadMin', () async {
      transport.writes.clear();
      await bengle.setCupWarmerPrewarm(true, 45);

      final enable = writesTo(BengleMmr.matPreheatEnable.address);
      expect(enable, isNotEmpty,
          reason: 'MatPreheatEnable (0x008038D0) must be written');
      expect(payloadOf(enable.last), equals(1));

      final lead = writesTo(BengleMmr.matPreheatLeadMin.address);
      expect(lead, isNotEmpty,
          reason: 'MatPreheatLeadMin (0x008038D4) must be written');
      expect(payloadOf(lead.last), equals(45));
    });

    test('setCupWarmerPrewarm(false, …) writes 0 to MatPreheatEnable',
        () async {
      transport.writes.clear();
      await bengle.setCupWarmerPrewarm(false, 30);
      expect(payloadOf(writesTo(BengleMmr.matPreheatEnable.address).last),
          equals(0));
      expect(payloadOf(writesTo(BengleMmr.matPreheatLeadMin.address).last),
          equals(30));
    });

    test('lead minutes clamp at the bottom (-5 → 0)', () async {
      transport.writes.clear();
      await bengle.setCupWarmerPrewarm(true, -5);
      expect(payloadOf(writesTo(BengleMmr.matPreheatLeadMin.address).last),
          equals(0),
          reason: 'a negative lead must never reach the wire — the FW clamps '
              'too, but a rejected write is a silent no-op');
    });

    test('lead minutes clamp at the top (999 → 120)', () async {
      transport.writes.clear();
      await bengle.setCupWarmerPrewarm(true, 999);
      expect(payloadOf(writesTo(BengleMmr.matPreheatLeadMin.address).last),
          equals(120));
    });

    test('setCupWarmerPrewarm never writes the read-only MatPreheatActive',
        () async {
      transport.writes.clear();
      await bengle.setCupWarmerPrewarm(true, 30);
      expect(writesTo(BengleMmr.matPreheatActive.address), isEmpty,
          reason: 'MatPreheatActive (0x008038D8) is firmware status — the app '
              'never writes it');
    });

    test('getCupWarmerPrewarm reads MatPreheatEnable + MatPreheatLeadMin',
        () async {
      transport.queueMmrResponseInt(BengleMmr.matPreheatEnable, 1);
      transport.queueMmrResponseInt(BengleMmr.matPreheatLeadMin, 45);
      final prewarm = await bengle.getCupWarmerPrewarm();
      expect(prewarm, isNotNull);
      expect(prewarm!.enabled, isTrue);
      expect(prewarm.leadMinutes, 45);
    });

    test('getCupWarmerPrewarmActive maps raw 1 to true (schedule driving the '
        'mat)', () async {
      transport.queueMmrResponseInt(BengleMmr.matPreheatActive, 1);
      expect(await bengle.getCupWarmerPrewarmActive(), isTrue);
    });

    test('getCupWarmerPrewarmActive maps raw 0 to false', () async {
      transport.queueMmrResponseInt(BengleMmr.matPreheatActive, 0);
      expect(await bengle.getCupWarmerPrewarmActive(), isFalse);
    });

    test('getCupWarmerPrewarm returns null on firmware without the registers',
        () async {
      // Older firmware (older firmware) has no rows 59-61: the read fails.
      final failing = _MmrReadFailsTransport({
        BengleMmr.matPreheatEnable.address,
        BengleMmr.matPreheatLeadMin.address,
        BengleMmr.matPreheatActive.address,
      });
      final b = Bengle(transport: failing);
      failing.queueOnConnectResponses(v13Model: 128);
      await b.onConnect(); // must not throw — degradation, not a crash
      expect(await b.getCupWarmerPrewarm(), isNull,
          reason: 'absent registers ⇒ "unavailable", never invented settings');
      expect(await b.getCupWarmerPrewarmActive(), isNull,
          reason: 'never fabricate prewarmActive: false — the truth is that we '
              'cannot tell');
      failing.dispose();
    });

    test('a failed pre-warm read latches: no retry storm on later polls',
        () async {
      final failing = _MmrReadFailsTransport({
        BengleMmr.matPreheatEnable.address,
        BengleMmr.matPreheatLeadMin.address,
        BengleMmr.matPreheatActive.address,
      });
      final b = Bengle(transport: failing);
      failing.queueOnConnectResponses(v13Model: 128);
      await b.onConnect();

      expect(await b.getCupWarmerPrewarm(), isNull);
      final attemptsAfterFirst = failing.mmrReadAttempts;
      expect(attemptsAfterFirst, greaterThan(0),
          reason: 'the first read is genuinely attempted');

      // A polled REST client hits GET /cupWarmer repeatedly; none of these may
      // re-enter the MMR read timeout ladder.
      for (var i = 0; i < 5; i++) {
        expect(await b.getCupWarmerPrewarm(), isNull);
        expect(await b.getCupWarmerPrewarmActive(), isNull);
      }
      expect(failing.mmrReadAttempts, attemptsAfterFirst,
          reason: 'the unsupported latch must suppress every later read');
      failing.dispose();
    });

    test('polls that land INSIDE the first read share it: one ladder, not one '
        'per poll', () async {
      // The latch above can only be set once a read RESOLVES, and on the validated firmware build
      // the read does not fail fast: the firmware ACCEPTS the request and never
      // answers, so it fails only when the MMR timeout ladder gives up, seconds
      // later. The REST surface is polled every ~5 s. Every poll inside that
      // window therefore still sees `_prewarmUnsupported == false` — and
      // without a single-flight guard each opens its own ladder, which is
      // precisely the storm the latch exists to prevent.
      final failing = _MmrReadFailsTransport({
        BengleMmr.matPreheatEnable.address,
        BengleMmr.matPreheatLeadMin.address,
        BengleMmr.matPreheatActive.address,
      });
      failing.holdFailingReads(); // the firmware "never answers" — yet
      final b = Bengle(transport: failing);
      failing.queueOnConnectResponses(v13Model: 128);
      await b.onConnect();

      // Three polls arrive while the first read is still open on the wire.
      final polls = [
        b.getCupWarmerPrewarm(),
        b.getCupWarmerPrewarm(),
        b.getCupWarmerPrewarm(),
      ];
      await pumpEventQueue();
      expect(failing.mmrReadAttempts, 1,
          reason: 'concurrent polls must await the ONE in-flight read, not each '
              'open their own timeout ladder');

      failing.releaseFailingReads(); // the ladder finally gives up
      expect(await Future.wait(polls), everyElement(isNull),
          reason: 'every caller gets the same honest "unavailable"');

      // …and the latch, now set, absorbs the polls that follow.
      expect(await b.getCupWarmerPrewarm(), isNull);
      expect(await b.getCupWarmerPrewarmActive(), isNull);
      expect(failing.mmrReadAttempts, 1,
          reason: 'the whole degradation costs exactly one read attempt');
      failing.dispose();
    });

    test('the unsupported latch is re-probed on reconnect', () async {
      final failing = _MmrReadFailsTransport({
        BengleMmr.matPreheatEnable.address,
        BengleMmr.matPreheatLeadMin.address,
      });
      final b = Bengle(transport: failing);
      failing.queueOnConnectResponses(v13Model: 128);
      await b.onConnect();
      expect(await b.getCupWarmerPrewarm(), isNull); // latches

      // Machine reflashed with pre-warm firmware, app reconnects.
      await b.disconnect();
      failing.queueOnConnectResponses(v13Model: 128);
      failing.stopFailing();
      await b.onConnect();
      failing.queueMmrResponseInt(BengleMmr.matPreheatEnable, 1);
      failing.queueMmrResponseInt(BengleMmr.matPreheatLeadMin, 30);

      final prewarm = await b.getCupWarmerPrewarm();
      expect(prewarm, isNotNull,
          reason: 'the latch is per-connection — a reconnect re-probes');
      expect(prewarm!.leadMinutes, 30);
      failing.dispose();
    });
  });

  group('cup-warmer registers stay Bengle-only', () {
    test('a plain DE1 connect never touches MatSetPoint or CupWarmerMode',
        () async {
      final transport = FakeBleTransport();
      final de1 = UnifiedDe1(transport: transport);
      transport.queueOnConnectResponses(); // v13Model: 1 — plain DE1
      await de1.onConnect();

      Iterable<FakeBleWrite> writesTo(int address) {
        final ba = ByteData(4)..setInt32(0, address, Endian.big);
        return transport.writes.where((w) =>
            w.characteristicUUID == Endpoint.writeToMMR.uuid &&
            w.data[1] == ba.getUint8(1) &&
            w.data[2] == ba.getUint8(2) &&
            w.data[3] == ba.getUint8(3));
      }

      expect(writesTo(BengleMmr.matSetPoint.address), isEmpty,
          reason: 'cup-warmer re-assert is Bengle.onConnect machinery — the '
              'shared DE1 connect path must never write it');
      expect(writesTo(BengleMmr.cupWarmerMode.address), isEmpty);
      transport.dispose();
    });

    test('a plain DE1 connect never touches the MatPreheat registers',
        () async {
      final transport = FakeBleTransport();
      final de1 = UnifiedDe1(transport: transport);
      transport.queueOnConnectResponses(); // v13Model: 1 — plain DE1
      await de1.onConnect();

      bool touched(int address) {
        final ba = ByteData(4)..setInt32(0, address, Endian.big);
        return transport.writes.any((w) =>
            (w.characteristicUUID == Endpoint.writeToMMR.uuid ||
                w.characteristicUUID == Endpoint.readFromMMR.uuid) &&
            w.data.length >= 4 &&
            w.data[1] == ba.getUint8(1) &&
            w.data[2] == ba.getUint8(2) &&
            w.data[3] == ba.getUint8(3));
      }

      expect(touched(BengleMmr.matPreheatEnable.address), isFalse,
          reason: 'pre-warm is Bengle-only: a DE1 must see neither a write nor '
              'a read of 0x008038D0');
      expect(touched(BengleMmr.matPreheatLeadMin.address), isFalse);
      expect(touched(BengleMmr.matPreheatActive.address), isFalse);
      transport.dispose();
    });

    test('the pre-warm API is not reachable on a plain DE1 (compile-time '
        'gate)', () {
      final transport = FakeBleTransport();
      final de1 = UnifiedDe1(transport: transport);
      // The REST layer's `de1 is! BengleInterface -> 404` gate is exactly this
      // type test: a plain DE1 exposes no pre-warm surface to write with.
      expect(de1 is BengleInterface, isFalse);
      transport.dispose();
    });
  });
}

/// Fails any MMR read request that targets one of [_failAddresses] —
/// simulates older firmware where the register does not exist and the
/// transport/read path errors instead of answering.
///
/// [mmrReadAttempts] counts the read requests that actually reached the
/// wire for those addresses, so a test can prove the app does NOT keep
/// re-asking a firmware that has already answered "not mapped" (retry storm).
class _MmrReadFailsTransport extends FakeBleTransport {
  _MmrReadFailsTransport(this._failAddresses);

  final Set<int> _failAddresses;

  /// Read requests to [_failAddresses] seen on the wire.
  int mmrReadAttempts = 0;

  bool _failing = true;

  /// Holds a failing read OPEN instead of failing it immediately — the real
  /// the validated firmware build behaviour, and the one that matters: the firmware ACCEPTS the
  /// read request and simply never answers, so the app only learns of the
  /// failure when its MMR timeout ladder gives up, seconds later. Everything
  /// the app does in that window (poll, poll, poll) happens with the
  /// "unsupported" latch still unset. [releaseFailingReads] plays the ladder
  /// giving up.
  Completer<void>? _held;

  void holdFailingReads() => _held ??= Completer<void>();

  void releaseFailingReads() {
    final held = _held;
    _held = null;
    held?.complete();
  }

  /// Simulate the machine being reflashed with firmware that HAS the
  /// registers: subsequent reads are answered normally.
  void stopFailing() => _failing = false;

  @override
  Future<void> write(
      String serviceUUID, String characteristicUUID, Uint8List data,
      {bool withResponse = true, Duration? timeout}) async {
    if (characteristicUUID == Endpoint.readFromMMR.uuid && data.length >= 4) {
      for (final address in _failAddresses) {
        final ba = ByteData(4)..setInt32(0, address, Endian.big);
        if (data[1] == ba.getUint8(1) &&
            data[2] == ba.getUint8(2) &&
            data[3] == ba.getUint8(3)) {
          mmrReadAttempts++;
          if (_failing) {
            await _held?.future;
            throw Exception('simulated: register not mapped on this FW');
          }
        }
      }
    }
    return super.write(serviceUUID, characteristicUUID, data,
        withResponse: withResponse, timeout: timeout);
  }
}
