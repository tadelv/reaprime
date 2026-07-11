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

    test('tareIntegratedScale logs and no-ops until it is wired', () async {
      // The ScaleTare MMR write-trigger belongs to the stop-at-weight/tare
      // branch; until then tare must not write anything to the wire.
      logRecords.clear();
      transport.writes.clear();
      await bengle.tareIntegratedScale();
      expect(
        logRecords.any(
          (r) =>
              r.message.contains('IntegratedScaleCapability') &&
              r.message.contains('tare'),
        ),
        isTrue,
        reason: 'expected tare log entry about the pending tare wiring',
      );
      expect(
        transport.writes,
        isEmpty,
        reason: 'tare must stay off the wire until then',
      );
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
