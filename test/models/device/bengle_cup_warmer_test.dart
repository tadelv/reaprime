import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
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
  });
}
