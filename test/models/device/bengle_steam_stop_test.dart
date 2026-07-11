import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/impl/bengle/bengle.dart';
import 'package:reaprime/src/models/device/impl/bengle/bengle_mmr.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';
import 'package:reaprime/src/models/device/impl/de1/mmr_address.dart';

import '../../helpers/fake_ble_transport.dart';

/// milk-probe steam stop target.
///
/// `Bengle.setStopAtTemperatureTarget` maps the app's target (°C) onto the
/// firmware `TargetMilkTemp` register (`0x008038A8`, RWD, scale ×10 decicelsius,
/// `0` = disable, max 850 = 85 °C). The live probe reading is separate (rides
/// `0xA013`, not an MMR). These tests assert the wire bytes.
void main() {
  group('Bengle stop-at-temperature → TargetMilkTemp MMR', () {
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

    FakeBleWrite? lastMmrWrite() {
      for (final w in transport.writes.reversed) {
        if (w.characteristicUUID == Endpoint.writeToMMR.uuid) return w;
      }
      return null;
    }

    test('target maps to the real TargetMilkTemp register', () {
      final addr = BengleSteamMmr.stopAtTemperatureTarget;
      expect(addr.address, 0x008038A8);
      expect(addr.kind, MmrValueKind.scaledFloat);
      expect(addr.writeScale, 10.0);
      expect(addr.readScale, 0.1);
      expect(addr.min, 0);
      expect(addr.max, 850); // 85.0 °C × 10
    });

    test('setStopAtTemperatureTarget writes the scaled LE int32 to 0x008038A8',
        () async {
      await bengle.setStopAtTemperatureTarget(65.0);

      final w = lastMmrWrite();
      expect(w, isNotNull, reason: 'a real MMR write must hit the wire');
      final d = w!.data;
      // Length byte + big-endian address low 3 bytes (0x80,0x38,0xA8).
      expect(d[0], 4);
      expect(d.sublist(1, 4), [0x80, 0x38, 0xA8]);
      // Payload: 65.0 °C × 10 = 650 = 0x028A, little-endian.
      expect(d.sublist(4, 8), [0x8A, 0x02, 0x00, 0x00]);
    });

    test('0.0 disables autonomous stop (writes 0)', () async {
      await bengle.setStopAtTemperatureTarget(0.0);
      expect(lastMmrWrite()!.data.sublist(4, 8), [0x00, 0x00, 0x00, 0x00]);
    });

    test('clamps °C to 0..85 before scaling', () async {
      await bengle.setStopAtTemperatureTarget(120.0);
      // 85 °C × 10 = 850 = 0x0352, little-endian.
      expect(lastMmrWrite()!.data.sublist(4, 8), [0x52, 0x03, 0x00, 0x00]);
      expect(await bengle.stopAtTemperatureTarget.first, 85.0);

      transport.writes.clear();
      await bengle.setStopAtTemperatureTarget(-5.0);
      expect(lastMmrWrite()!.data.sublist(4, 8), [0x00, 0x00, 0x00, 0x00]);
      expect(await bengle.stopAtTemperatureTarget.first, 0.0);
    });

    test('stream emits the set value to subscribers', () async {
      await bengle.setStopAtTemperatureTarget(55.0);
      expect(await bengle.stopAtTemperatureTarget.first, 55.0);
    });

    test('getStopAtTemperatureTarget reads, unscales, and echoes the register',
        () async {
      transport.queueMmrResponseInt(
          BengleSteamMmr.stopAtTemperatureTarget, 600); // 60.0 °C × 10
      expect(await bengle.getStopAtTemperatureTarget(), closeTo(60.0, 1e-6));
      // The read side-effects the BehaviorSubject so replay subscribers
      // see post-read truth.
      expect(await bengle.stopAtTemperatureTarget.first, closeTo(60.0, 1e-6));
    });

    test('probeAttached stays false on real Bengle (reading rides 0xA013)',
        () async {
      expect(await bengle.probeAttached.first, isFalse);
    });
  });
}
