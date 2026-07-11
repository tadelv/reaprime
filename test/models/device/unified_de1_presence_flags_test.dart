import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/impl/bengle/bengle.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1.dart';

import '../../helpers/fake_ble_transport.dart';

/// (document-only) — the connect-time presence advertisement.
///
/// `UnifiedDe1.onConnect` ends with an UNCONDITIONAL
/// `enableUserPresenceFeature()` → `AppFeatureFlags = 1` (0x00803858,
/// bit0 = UserNotPresent feature) on EVERY machine, DE1 and Bengle alike.
/// Advertising the bit commits the client to ongoing `UserPresent` writes;
/// the upstream `PresenceController` fulfils that obligation when the user
/// enables presence, and firmware's 120 s absence timeout emits substate
/// 0x13, which the app already decodes safely. This test locks the
/// advertisement so it cannot be "helpfully" removed — the machine-side
/// feature set changes with it. (The audit's capability-derived
/// alternative is recorded in HW-CONTRACT.md / the Phase-0 issue.)
void main() {
  Iterable<Uint8List> writesTo(FakeBleTransport transport, int address) {
    final ba = ByteData(4)..setInt32(0, address, Endian.big);
    return transport.writes
        .where(
          (w) =>
              w.characteristicUUID == Endpoint.writeToMMR.uuid &&
              w.data[1] == ba.getUint8(1) &&
              w.data[2] == ba.getUint8(2) &&
              w.data[3] == ba.getUint8(3),
        )
        .map((w) => w.data);
  }

  int payloadOf(Uint8List frame) =>
      ByteData.sublistView(frame, 4, 8).getUint32(0, Endian.little);

  group('connect-time AppFeatureFlags advertisement (doc-only)', () {
    test('plain DE1 connect writes AppFeatureFlags = 1', () async {
      final transport = FakeBleTransport();
      final de1 = UnifiedDe1(transport: transport);
      transport.queueOnConnectResponses(); // v13Model: 1 — plain DE1
      await de1.onConnect();

      final frames = writesTo(transport, MMRItem.appFeatureFlags.address);
      expect(
        frames,
        isNotEmpty,
        reason:
            'onConnect must advertise the UserNotPresent feature '
            '(AppFeatureFlags 0x00803858)',
      );
      expect(payloadOf(frames.last), 1);
      transport.dispose();
    });

    test(
      'Bengle connect writes AppFeatureFlags = 1 (advert is unconditional)',
      () async {
        final transport = FakeBleTransport();
        final bengle = Bengle(transport: transport);
        transport.queueOnConnectResponses(v13Model: 128); // Bengle marker
        await bengle.onConnect();

        final frames = writesTo(transport, MMRItem.appFeatureFlags.address);
        expect(frames, isNotEmpty);
        expect(payloadOf(frames.last), 1);
        transport.dispose();
      },
    );
  });
}
