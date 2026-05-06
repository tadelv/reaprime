import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/impl/bengle/bengle.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1.dart';
import 'package:reaprime/src/models/device/led_strip.dart';

import '../../../../../../helpers/fake_ble_transport.dart';

void main() {
  group('LedStripCapability', () {
    late FakeBleTransport transport;
    late Bengle bengle;
    late List<LogRecord> logRecords;
    late StreamSubscription<LogRecord> logSub;

    setUp(() async {
      logRecords = <LogRecord>[];
      Logger.root.level = Level.ALL;
      logSub = Logger.root.onRecord.listen(logRecords.add);
      transport = FakeBleTransport();
      bengle = Bengle(transport: transport);
      transport.queueOnConnectResponses();
      await bengle.onConnect();
    });

    tearDown(() async {
      await logSub.cancel();
      transport.dispose();
    });

    test('ledStripState returns a Stream<LedStripState>', () {
      expect(bengle.ledStripState, isA<Stream<LedStripState>>());
    });

    test('initial state is all-off (0,0,0)', () async {
      final state = await bengle.getLedStripState();
      expect(state.frontRed, 0);
      expect(state.frontGreen, 0);
      expect(state.frontBlue, 0);
      expect(state.backRed, 0);
      expect(state.backGreen, 0);
      expect(state.backBlue, 0);
    });

    test('initLedStrip logs and no-ops when wires are unwired', () {
      // initLedStrip was already called via onConnect in setUp.
      expect(
        logRecords.any((r) =>
            r.message.contains('LedStripCapability') &&
            r.message.contains('unwired')),
        isTrue,
        reason: 'expected init log entry about unwired endpoints',
      );
    });

    test('setLedStrip logs and no-ops when wires are unwired', () async {
      logRecords.clear();
      await bengle.setLedStrip(LedStripState(
        frontRed: 255,
        frontGreen: 128,
        frontBlue: 0,
        backRed: 0,
        backGreen: 64,
        backBlue: 128,
      ));
      expect(
        logRecords.any((r) =>
            r.message.contains('LedStripCapability') &&
            r.message.contains('setLedStrip')),
        isTrue,
        reason: 'expected log entry about unwired endpoint',
      );
    });

    test('disposeLedStrip closes the subject', () async {
      await bengle.onDisconnect();
      // Seeded BehaviorSubject replays the last value before done.
      await expectLater(
        bengle.ledStripState,
        emitsInOrder([isA<LedStripState>(), emitsDone]),
      );
    });

    test('BengleLedEndpoint.front.uuid and representation are null', () {
      expect(BengleLedEndpoint.front.uuid, isNull);
      expect(BengleLedEndpoint.front.representation, isNull);
    });

    test('BengleLedEndpoint.back.uuid and representation are null', () {
      expect(BengleLedEndpoint.back.uuid, isNull);
      expect(BengleLedEndpoint.back.representation, isNull);
    });

    test('connect → disconnect → connect lifecycle is leak-free', () async {
      await bengle.disconnect();
      // Seeded BehaviorSubject replays the last value before done.
      await expectLater(
        bengle.ledStripState,
        emitsInOrder([isA<LedStripState>(), emitsDone]),
      );

      transport.queueOnConnectResponses();
      await bengle.onConnect();

      // Stream should be alive (not done) after reconnect.
      var streamCompletedWithoutValue = false;
      try {
        await bengle.ledStripState
            .first
            .timeout(const Duration(milliseconds: 50));
      } on TimeoutException {
        // Expected: stream is open but quiet — capability is alive.
      } on StateError {
        streamCompletedWithoutValue = true;
      }
      expect(streamCompletedWithoutValue, isFalse,
          reason: 'ledStripState was closed after reconnect — mixin '
              'failed to re-init its BehaviorSubject');
    });
  });
}
