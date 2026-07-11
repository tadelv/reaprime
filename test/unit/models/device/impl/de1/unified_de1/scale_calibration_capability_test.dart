import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/impl/bengle/bengle.dart';
import 'package:reaprime/src/models/device/impl/de1/de1.models.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1.dart';
import 'package:reaprime/src/models/device/scale_calibration.dart';

import '../../../../../../helpers/fake_ble_transport.dart';

/// Pack a ScaleCalState word: Step[31:24] SubState[23:16] Remaining[15:8]
/// CalStatus[7:0] (firmware layout). `status` = E_CalStatus (0xFF = none).
int _packState({
  required int step,
  int sub = 0,
  int remaining = 0,
  int status = 0xFF,
}) =>
    (step << 24) | (sub << 16) | (remaining << 8) | (status & 0xFF);

void main() {
  group('ScaleCalibrationCapability (FIX-07, two-point)', () {
    late FakeBleTransport transport;
    late Bengle bengle;

    setUp(() async {
      transport = FakeBleTransport();
      // calFlowEst keeps onConnect from eating the MMR read-retry timeout.
      transport.queueMmrResponseInt(MMRItem.calFlowEst, 100);
      transport.queueOnConnectResponses(v13Model: 128);
      bengle = Bengle(transport: transport);
      await bengle.onConnect();
      bengle.configureScaleCalibrationTiming(
        pollInterval: const Duration(milliseconds: 1),
        deadline: const Duration(milliseconds: 50),
      );
      transport.writes.clear();
    });

    tearDown(() => transport.dispose());

    List<FakeBleWrite> mmrWrites() => transport.writes
        .where((w) => w.characteristicUUID == Endpoint.writeToMMR.uuid)
        .toList();

    FakeBleWrite? mmrWriteTo(int addr) {
      final b = [(addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF];
      for (final w in mmrWrites()) {
        if (w.data[1] == b[0] && w.data[2] == b[1] && w.data[3] == b[2]) {
          return w;
        }
      }
      return null;
    }

    test('cal MMR slots map to the firmware registers', () {
      expect(BengleCalMmr.cmd.address, 0x00803880);
      expect(BengleCalMmr.state.address, 0x00803884);
      expect(BengleCalMmr.weight.address, 0x00803888);
      expect(BengleCalMmr.weight.writeScale, 10.0);
      expect(BengleCalMmr.weight.readScale, 0.1);
    });

    test('command wire values match firmware (zero=1, latch=2)', () {
      expect(ScaleCalCommand.abort.wire, 0);
      expect(ScaleCalCommand.zero.wire, 1);
      expect(ScaleCalCommand.latch.wire, 2);
    });

    test('fromRaw pins Step to the HIGH byte and CalStatus to the LOW byte',
        () {
      // Literal word (NOT built by _packState) anchors the byte positions to
      // the spec layout Step[31:24]|SubState[23:16]|Remaining[15:8]|CalStatus[7:0].
      final s = ScaleCalStatus.fromRaw(0x05020301);
      expect(s.step, ScaleCalStep.complete); // 0x05
      expect(s.subState, ScaleCalSubState.done); // 0x02
      expect(s.remainingSeconds, 3); // 0x03
      expect(s.pointStatus, ScaleCalPointStatus.incomplete); // 0x01
    });

    test('fromRaw decodes a two-point solved word and coerces the high bit',
        () {
      final ok = ScaleCalStatus.fromRaw(
          _packState(step: 5, sub: 2, remaining: 0, status: 0));
      expect(ok.step, ScaleCalStep.complete);
      expect(ok.pointStatus, ScaleCalPointStatus.ok);
      expect(ok.isComplete, isTrue);

      // Sign-extended int32 (bit 31 set): mask must recover the byte fields.
      final hi = ScaleCalStatus.fromRaw(-1); // 0xFFFFFFFF
      expect(hi.step, ScaleCalStep.unknown); // 0xFF
      expect(hi.pointStatus, ScaleCalPointStatus.none); // 0xFF
      expect(hi.remainingSeconds, 255);
    });

    test('calibrateScaleZero writes cmd=1 and polls to Complete', () async {
      transport.queueMmrResponseIntSequence(BengleCalMmr.state, [
        _packState(step: 1, sub: 0, remaining: 3), // zeroing/settling
        _packState(step: 1, sub: 1, remaining: 1), // zeroing/averaging
        _packState(step: 5, sub: 2, remaining: 0), // complete
      ]);

      final result = await bengle.calibrateScaleZero();

      expect(result.success, isTrue);
      expect(result.finalStep, ScaleCalStep.complete);
      final cmd = mmrWriteTo(0x00803880);
      expect(cmd, isNotNull);
      expect(cmd!.data.sublist(4, 8), [0x01, 0x00, 0x00, 0x00]);
    });

    test('calibrateScaleWeightLeft writes weight ×10 + cmd=2, first latch',
        () async {
      // 500.0 g × 10 = 5000 read back to confirm.
      transport.queueMmrResponseInt(BengleCalMmr.weight, 5000);
      transport.queueMmrResponseIntSequence(BengleCalMmr.state, [
        _packState(step: 2, sub: 1, remaining: 2), // calLatch/averaging
        _packState(step: 5, sub: 2, remaining: 0, status: 1), // complete/incomplete
      ]);

      final result = await bengle.calibrateScaleWeightLeft(500.0);

      expect(result.success, isTrue);
      expect(result.pointStatus, ScaleCalPointStatus.incomplete);
      // Reference weight write: 5000 = 0x1388, little-endian.
      final wWrite = mmrWriteTo(0x00803888);
      expect(wWrite, isNotNull);
      expect(wWrite!.data.sublist(4, 8), [0x88, 0x13, 0x00, 0x00]);
      // Command trigger = 2 (auto-detect latch).
      expect(
          mmrWriteTo(0x00803880)!.data.sublist(4, 8), [0x02, 0x00, 0x00, 0x00]);
    });

    test('calibrateScaleWeightRight writes cmd=2, solves (status Ok)', () async {
      transport.queueMmrResponseInt(BengleCalMmr.weight, 5000);
      transport.queueMmrResponseIntSequence(BengleCalMmr.state, [
        _packState(step: 2, sub: 1, remaining: 2), // calLatch/averaging
        _packState(step: 5, sub: 2, remaining: 0, status: 0), // complete/ok
      ]);

      final result = await bengle.calibrateScaleWeightRight(500.0);

      expect(result.success, isTrue);
      expect(result.pointStatus, ScaleCalPointStatus.ok);
      expect(
          mmrWriteTo(0x00803880)!.data.sublist(4, 8), [0x02, 0x00, 0x00, 0x00]);
    });

    test('fromRaw decodes the detected-cell nibble in the SubState byte', () {
      // done (0x2) with cell A in the high nibble (0x1) -> SubState byte 0x12.
      final a = ScaleCalStatus.fromRaw(0x05120001);
      expect(a.isComplete, isTrue); // low nibble still decodes the phase
      expect(a.detectedCell, 0); // cell A / left
      // cell B (0x2 nibble) -> SubState byte 0x22.
      final b = ScaleCalStatus.fromRaw(0x05220001);
      expect(b.detectedCell, 1); // cell B / right
      // no cell yet.
      final none = ScaleCalStatus.fromRaw(0x05020001);
      expect(none.detectedCell, isNull);
    });

    test('a NotIsolated reject decodes and fails with the reason', () async {
      transport.queueMmrResponseInt(BengleCalMmr.weight, 5000);
      transport.queueMmrResponseIntSequence(BengleCalMmr.state, [
        // Compute-time reject: Error step, NotIsolated (8) status.
        _packState(step: 6, sub: 3, remaining: 0, status: 8),
      ]);

      final result = await bengle.calibrateScaleWeightLeft(500.0);
      expect(result.success, isFalse);
      expect(result.pointStatus, ScaleCalPointStatus.notIsolated);
      expect(result.message, contains('notIsolated'));
    });

    test('a rejected latch (Complete + non-ok CalStatus) fails with the reason',
        () async {
      transport.queueMmrResponseInt(BengleCalMmr.weight, 5000);
      transport.queueMmrResponseIntSequence(BengleCalMmr.state, [
        // Compute-time reject: Complete step but IllConditioned status.
        _packState(step: 5, sub: 2, remaining: 0, status: 6),
      ]);

      final result = await bengle.calibrateScaleWeightRight(500.0);
      expect(result.success, isFalse);
      expect(result.pointStatus, ScaleCalPointStatus.illConditioned);
      expect(result.message, contains('illConditioned'));
    });

    test('an Error step (upfront reject, e.g. NoZero) fails with the status',
        () async {
      transport.queueMmrResponseInt(BengleCalMmr.weight, 5000);
      transport.queueMmrResponseIntSequence(BengleCalMmr.state, [
        _packState(step: 6, sub: 3, remaining: 0, status: 2), // error / NoZero
      ]);

      final result = await bengle.calibrateScaleWeightLeft(500.0);
      expect(result.success, isFalse);
      expect(result.finalStep, ScaleCalStep.error);
      expect(result.message, contains('noZero'));
    });

    test('calibrateScaleWeightLeft rejects a reference-weight readback mismatch '
        'and never triggers cmd=4', () async {
      transport.queueMmrResponseInt(BengleCalMmr.weight, 9990); // 999.0 g

      final result = await bengle.calibrateScaleWeightLeft(500.0);

      expect(result.success, isFalse);
      expect(result.message, contains('not confirmed'));
      expect(mmrWriteTo(0x00803888), isNotNull, reason: 'weight was written');
      expect(mmrWriteTo(0x00803880), isNull,
          reason: 'a rejected readback must not trigger the latch');
    });

    test('single-flight guard rejects a concurrent calibration', () async {
      transport.queueMmrResponseIntSequence(
          BengleCalMmr.state, [_packState(step: 1, sub: 0, remaining: 5)]);

      final first = bengle.calibrateScaleZero();
      final second = await bengle.calibrateScaleZero();
      expect(second.success, isFalse);
      expect(second.message, contains('in progress'));

      final firstResult = await first;
      expect(firstResult.success, isFalse); // times out on the sticky state
    });

    test('abortScaleCalibration stops an in-flight poll promptly with an '
        '"aborted" result (not a timeout)', () async {
      bengle.configureScaleCalibrationTiming(
        pollInterval: const Duration(milliseconds: 1),
        deadline: const Duration(seconds: 10),
      );
      transport.queueMmrResponseIntSequence(
          BengleCalMmr.state, [_packState(step: 1, sub: 0, remaining: 5)]);

      final run = bengle.calibrateScaleZero();
      await pumpEventQueue();
      await bengle.abortScaleCalibration();
      final result = await run;

      expect(result.success, isFalse);
      expect(result.message, 'aborted');
      expect(mmrWrites().last.data.sublist(4, 8), [0x00, 0x00, 0x00, 0x00]);
      expect(bengle.scaleCalibrationInProgress, isFalse);
    });

    test('disposeScaleCalibration unwinds an in-flight poll; a reconnected '
        'stream sees no stale status', () async {
      bengle.configureScaleCalibrationTiming(
        pollInterval: const Duration(milliseconds: 1),
        deadline: const Duration(seconds: 10),
      );
      transport.queueMmrResponseIntSequence(
          BengleCalMmr.state, [_packState(step: 1, sub: 0, remaining: 5)]);

      final run = bengle.calibrateScaleZero();
      await pumpEventQueue();
      await bengle.disposeScaleCalibration();
      await bengle.initScaleCalibration();

      final seen = <ScaleCalStatus>[];
      final sub = bengle.scaleCalibrationProgress.listen(seen.add);
      final result = await run;
      await pumpEventQueue();
      await sub.cancel();

      expect(result.success, isFalse);
      expect(result.message, 'aborted');
      expect(seen, isEmpty);
    });

    test('progress stream emits each polled status', () async {
      transport.queueMmrResponseIntSequence(BengleCalMmr.state, [
        _packState(step: 1, sub: 0, remaining: 2),
        _packState(step: 5, sub: 2, remaining: 0),
      ]);
      final seen = <ScaleCalStatus>[];
      final sub = bengle.scaleCalibrationProgress.listen(seen.add);
      await bengle.calibrateScaleZero();
      await pumpEventQueue();
      await sub.cancel();
      expect(seen, isNotEmpty);
      expect(seen.last.isComplete, isTrue);
    });
  });
}
