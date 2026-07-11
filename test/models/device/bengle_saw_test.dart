import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/impl/bengle/bengle.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';
import 'package:reaprime/src/models/device/impl/de1/mmr_address.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1.dart';

import '../../helpers/fake_ble_transport.dart';

/// autonomous stop-at-weight.
///
/// `IntegratedScaleCapability.setStopAtWeightTarget` maps the app's SAW
/// target (grams) onto the firmware `EndOfShotWeight` register
/// (`0x00803864`, RWD, scale ×100, `0` = disable, max 10000 g). Writes
/// go through the shared `writeMmrScaled` helper, which rounds the
/// scaled value to match de1plus. These tests assert the wire bytes are
/// byte-exact against the firmware register.
void main() {
  group('Bengle SAW → EndOfShotWeight MMR', () {
    late FakeBleTransport transport;
    late Bengle bengle;

    setUp(() async {
      transport = FakeBleTransport();
      // calFlowEst keeps onConnect from eating the MMR read-retry timeout.
      transport.queueMmrResponseInt(MMRItem.calFlowEst, 100);
      transport.queueOnConnectResponses(v13Model: 128); // real Bengle
      bengle = Bengle(transport: transport);
      await bengle.onConnect();
      transport.writes.clear();
    });

    tearDown(() {
      transport.dispose();
    });

    /// Most recent write to the MMR write characteristic, or null.
    FakeBleWrite? lastMmrWrite() {
      for (final w in transport.writes.reversed) {
        if (w.characteristicUUID == Endpoint.writeToMMR.uuid) return w;
      }
      return null;
    }

    test('SAW target maps to the real EndOfShotWeight register', () {
      final addr = BengleScaleMmr.stopAtWeightTarget;
      expect(addr.address, 0x00803864);
      expect(addr.kind, MmrValueKind.scaledFloat);
      expect(addr.writeScale, 100.0);
      expect(addr.readScale, 0.01);
      expect(addr.min, 0);
      expect(addr.max, 1000000); // 10000.0 g × 100
    });

    test(
      'setStopAtWeightTarget writes the scaled LE int32 to 0x00803864',
      () async {
        await bengle.setStopAtWeightTarget(36.0);

        final w = lastMmrWrite();
        expect(w, isNotNull, reason: 'a real MMR write must hit the wire');
        final d = w!.data;
        // Length byte + big-endian address low 3 bytes (0x80,0x38,0x64).
        expect(d[0], 4);
        expect(d[1], 0x80);
        expect(d[2], 0x38);
        expect(d[3], 0x64);
        // Payload: 36.0 g × 100 = 3600 = 0x0E10, little-endian.
        expect(d.sublist(4, 8), [0x10, 0x0E, 0x00, 0x00]);
      },
    );

    test('rounds the ×100 write (2.3 g → 230, not 229)', () async {
      // 2.3 * 100 == 229.999… under doubles; truncating drops a whole
      // centigram. writeMmrScaled rounds, so the wire carries 230 (0xE6).
      await bengle.setStopAtWeightTarget(2.3);

      final d = lastMmrWrite()!.data;
      expect(d.sublist(4, 8), [0xE6, 0x00, 0x00, 0x00]); // 230, not 229 (0xE5)
    });

    test('0.0 disables SAW (writes 0)', () async {
      await bengle.setStopAtWeightTarget(0.0);
      final d = lastMmrWrite()!.data;
      expect(d.sublist(4, 8), [0x00, 0x00, 0x00, 0x00]);
    });

    test('clamps grams to 0..10000 before scaling', () async {
      await bengle.setStopAtWeightTarget(20000.0);
      // 10000 g × 100 = 1_000_000 = 0x0F4240, little-endian.
      expect(lastMmrWrite()!.data.sublist(4, 8), [0x40, 0x42, 0x0F, 0x00]);
      expect(await bengle.stopAtWeightTarget.first, 10000.0);

      transport.writes.clear();
      await bengle.setStopAtWeightTarget(-5.0);
      expect(lastMmrWrite()!.data.sublist(4, 8), [0x00, 0x00, 0x00, 0x00]);
      expect(await bengle.stopAtWeightTarget.first, 0.0);
    });

    test(
      'getStopAtWeightTarget reads back from the wire and hydrates cache',
      () async {
        // Firmware reports raw 3000 → 3000 × 0.01 = 30.0 g.
        transport.queueMmrResponseInt(BengleScaleMmr.stopAtWeightTarget, 3000);
        expect(await bengle.getStopAtWeightTarget(), closeTo(30.0, 1e-9));
        // Cache hydrated, so the stream now replays 30.0.
        expect(await bengle.stopAtWeightTarget.first, closeTo(30.0, 1e-9));
      },
    );

    test(
      'stopAtWeightTarget stream emits the cached target to subscribers',
      () async {
        await bengle.setStopAtWeightTarget(42.0);
        expect(await bengle.stopAtWeightTarget.first, 42.0);
      },
    );
  });
}
