import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/impl/bengle/bengle.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';
import 'package:reaprime/src/models/device/scale.dart';

import '../../../../../../helpers/fake_ble_transport.dart';

/// Golden 0xA013 frame: weight 36.5 g (full breakdown in
/// `bengle_shot_sample_test.dart`).
final Uint8List _golden0xA013 = Uint8List.fromList(const [
  0x03, 0xE8, 0x03, 0x84, 0x02, 0x58, 0x00, 0xFA, 0x00, 0xC8, 0x00, 0xB4, //
  0x24, 0x22, 0x22, 0x60, 0x24, 0x54, 0x23, 0x28, 0x04, 0x90, 0x07, 0x34, //
  0xBC, 0x00, 0x00, 0x00,
]);

void main() {
  group('IntegratedScaleCapability', () {
    late FakeBleTransport transport;
    late Bengle bengle;
    late List<LogRecord> logRecords;
    late StreamSubscription<LogRecord> logSub;

    setUp(() async {
      logRecords = <LogRecord>[];
      Logger.root.level = Level.ALL;
      logSub = Logger.root.onRecord.listen(logRecords.add);
      transport = FakeBleTransport();
      // calFlowEst keeps onConnect from eating the MMR read-retry timeout.
      transport.queueMmrResponseInt(MMRItem.calFlowEst, 100);
      transport.queueOnConnectResponses(v13Model: 128); // real Bengle
      bengle = Bengle(transport: transport);
      await bengle.onConnect();
    });

    tearDown(() async {
      await logSub.cancel();
      transport.dispose();
    });

    test('weightSnapshot returns a Stream<ScaleSnapshot>', () {
      expect(bengle.weightSnapshot, isA<Stream<ScaleSnapshot>>());
    });

    test(
      'initIntegratedScale bridges 0xA013 Weight into the scale',
      () async {
        final weights = <ScaleSnapshot>[];
        final sub = bengle.weightSnapshot.listen(weights.add);
        await pumpEventQueue();

        final cb = transport.subscribers[Endpoint.bengleShotSample.uuid];
        expect(
          cb,
          isNotNull,
          reason: 'onConnect must subscribe the 0xA013 characteristic',
        );
        cb!(_golden0xA013);
        await pumpEventQueue();

        expect(weights, isNotEmpty);
        // Weight is already tare-netted in firmware — trust it directly.
        expect(weights.last.weight, closeTo(36.5, 1e-9));
        // Mains-powered sentinel keeps ScaleSnapshot.batteryLevel
        // non-nullable (design D6).
        expect(weights.last.batteryLevel, 100);

        await sub.cancel();
      },
    );

    test('disposeIntegratedScale closes the subject', () async {
      await bengle.onDisconnect();
      // The subject is closed; a late listener sees the replayed last value
      // (if any) followed by done. `emitsThrough(emitsDone)` asserts closure.
      await expectLater(bengle.weightSnapshot, emitsThrough(emitsDone));
    });

    test('tareIntegratedScale triggers the ScaleTare MMR', () async {
      // tare is a write-trigger to ScaleTare (0x0080388C) — write any
      // value (de1plus writes 1). The firmware performs an immediate tare.
      transport.writes.clear();
      await bengle.tareIntegratedScale();

      final mmrWrites = transport.writes
          .where((w) => w.characteristicUUID == Endpoint.writeToMMR.uuid)
          .toList();
      expect(
        mmrWrites,
        hasLength(1),
        reason: 'tare must write exactly one MMR frame',
      );
      final d = mmrWrites.single.data;
      // Length byte + big-endian address low 3 bytes (0x80,0x38,0x8C).
      expect(d[0], 4);
      expect(d[1], 0x80);
      expect(d[2], 0x38);
      expect(d[3], 0x8C);
      // Payload = 1, little-endian.
      expect(d.sublist(4, 8), [0x01, 0x00, 0x00, 0x00]);
    });

    test('connect → disconnect → connect lifecycle is leak-free', () async {
      // First lifecycle was set up in setUp(). Disconnect routes through
      // UnifiedDe1.disconnect → onDisconnect → disposeIntegratedScale, which
      // closes the subject.
      await bengle.disconnect();
      await expectLater(bengle.weightSnapshot, emitsThrough(emitsDone));

      // Reconnect on the same instance. Bengle.onConnect re-runs
      // initIntegratedScale, which must recreate the closed BehaviorSubject —
      // otherwise a fresh listener would observe `done` immediately and the
      // capability would be dead until re-instantiation. (The reconnect
      // short-circuits the MMR reads, so no re-queue is needed.)
      await bengle.onConnect();

      // A live re-inited subject emits (at least the bridged replay of the
      // transport's seeded frame); a stale closed one would complete without
      // a value (StateError on `.first`).
      final v = await bengle.weightSnapshot.first.timeout(
        const Duration(seconds: 1),
      );
      expect(
        v,
        isA<ScaleSnapshot>(),
        reason: 'weightSnapshot must be live after reconnect',
      );
    });
  });
}
