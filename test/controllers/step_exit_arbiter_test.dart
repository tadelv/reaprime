import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/step_exit_arbiter.dart';
import 'package:reaprime/src/models/data/profile.dart';

void main() {
  late StepExitArbiter arbiter;

  setUp(() {
    arbiter = StepExitArbiter();
  });

  // ---------------------------------------------------------------
  // Pressure / over
  // ---------------------------------------------------------------

  group('pressure over exit', () {
    const exit = StepExitCondition(
      type: ExitType.pressure,
      condition: ExitCondition.over,
      value: 6.0,
    );

    test('far from threshold fires immediately', () {
      // Current pressure 2.0, exit at 6.0 → distance 4.0 > 1.5
      final verdict = arbiter.evaluate(
        profileFrame: 0,
        exit: exit,
        currentPressure: 2.0,
        currentFlow: 3.0,
      );
      expect(verdict, StepExitVerdict.fire);
    });

    test('near threshold and trending defers', () {
      // Current pressure 5.0, exit at 6.0 → distance 1.0 < 1.5
      final v1 = arbiter.evaluate(
        profileFrame: 0,
        exit: exit,
        currentPressure: 5.0,
        currentFlow: 3.0,
      );
      // First sample assumes trending → defer
      expect(v1, StepExitVerdict.defer);

      // Second sample still trending up
      final v2 = arbiter.evaluate(
        profileFrame: 0,
        exit: exit,
        currentPressure: 5.3,
        currentFlow: 3.0,
      );
      expect(v2, StepExitVerdict.defer);
    });

    test('near threshold trending hits max deferral then fires', () {
      for (var i = 0; i < StepExitArbiter.maxDeferralFrames - 1; i++) {
        final v = arbiter.evaluate(
          profileFrame: 0,
          exit: exit,
          currentPressure: 5.0 + i * 0.2,
          currentFlow: 3.0,
        );
        expect(v, StepExitVerdict.defer, reason: 'frame $i should defer');
      }

      // Max deferral reached
      final vFinal = arbiter.evaluate(
        profileFrame: 0,
        exit: exit,
        currentPressure: 5.6,
        currentFlow: 3.0,
      );
      expect(vFinal, StepExitVerdict.fire);
    });

    test('near threshold not trending fires on second frame', () {
      // First sample: assumes trending → defer
      final v1 = arbiter.evaluate(
        profileFrame: 0,
        exit: exit,
        currentPressure: 5.0,
        currentFlow: 3.0,
      );
      expect(v1, StepExitVerdict.defer);

      // Second sample: pressure dropped → not trending toward "over"
      final v2 = arbiter.evaluate(
        profileFrame: 0,
        exit: exit,
        currentPressure: 4.8,
        currentFlow: 3.0,
      );
      expect(v2, StepExitVerdict.fire);
    });

    test('sensor past threshold defers then fires at max', () {
      // Pressure 7.0 > exit 6.0 → distance -1.0 ≤ 0
      final v1 = arbiter.evaluate(
        profileFrame: 0,
        exit: exit,
        currentPressure: 7.0,
        currentFlow: 3.0,
      );
      expect(v1, StepExitVerdict.defer);

      final v2 = arbiter.evaluate(
        profileFrame: 0,
        exit: exit,
        currentPressure: 7.0,
        currentFlow: 3.0,
      );
      expect(v2, StepExitVerdict.defer);

      // Third frame hits maxDeferralFrames
      final v3 = arbiter.evaluate(
        profileFrame: 0,
        exit: exit,
        currentPressure: 7.0,
        currentFlow: 3.0,
      );
      expect(v3, StepExitVerdict.fire);
    });
  });

  // ---------------------------------------------------------------
  // Flow / under
  // ---------------------------------------------------------------

  group('flow under exit', () {
    const exit = StepExitCondition(
      type: ExitType.flow,
      condition: ExitCondition.under,
      value: 2.0,
    );

    test('far from threshold fires immediately', () {
      // Current flow 3.5, exit under 2.0 → distance 1.5 > 0.8
      final verdict = arbiter.evaluate(
        profileFrame: 0,
        exit: exit,
        currentPressure: 5.0,
        currentFlow: 3.5,
      );
      expect(verdict, StepExitVerdict.fire);
    });

    test('near threshold defers', () {
      // Current flow 2.5, exit under 2.0 → distance 0.5 < 0.8
      final verdict = arbiter.evaluate(
        profileFrame: 0,
        exit: exit,
        currentPressure: 5.0,
        currentFlow: 2.5,
      );
      expect(verdict, StepExitVerdict.defer);
    });

    test('near threshold trending down defers, not trending fires', () {
      // First: flow 2.5 → defer (assumes trending)
      arbiter.evaluate(
        profileFrame: 0,
        exit: exit,
        currentPressure: 5.0,
        currentFlow: 2.5,
      );

      // Second: flow 2.3 (dropping toward "under 2.0") → trending → defer
      final v2 = arbiter.evaluate(
        profileFrame: 0,
        exit: exit,
        currentPressure: 5.0,
        currentFlow: 2.3,
      );
      expect(v2, StepExitVerdict.defer);

      // Third: max deferral → fire
      final v3 = arbiter.evaluate(
        profileFrame: 0,
        exit: exit,
        currentPressure: 5.0,
        currentFlow: 2.1,
      );
      expect(v3, StepExitVerdict.fire);
    });

    test('near threshold flow rising fires on second frame', () {
      // First: defer (assumes trending)
      arbiter.evaluate(
        profileFrame: 0,
        exit: exit,
        currentPressure: 5.0,
        currentFlow: 2.5,
      );

      // Second: flow 2.8 — rising, not trending toward "under"
      final v2 = arbiter.evaluate(
        profileFrame: 0,
        exit: exit,
        currentPressure: 5.0,
        currentFlow: 2.8,
      );
      expect(v2, StepExitVerdict.fire);
    });
  });

  // ---------------------------------------------------------------
  // Edge cases
  // ---------------------------------------------------------------

  group('edge cases', () {
    test('exit value <= 0 fires immediately', () {
      const exit = StepExitCondition(
        type: ExitType.pressure,
        condition: ExitCondition.over,
        value: 0.0,
      );

      final verdict = arbiter.evaluate(
        profileFrame: 0,
        exit: exit,
        currentPressure: 1.0,
        currentFlow: 3.0,
      );
      expect(verdict, StepExitVerdict.fire);
    });

    test('negative exit value fires immediately', () {
      const exit = StepExitCondition(
        type: ExitType.flow,
        condition: ExitCondition.under,
        value: -1.0,
      );

      final verdict = arbiter.evaluate(
        profileFrame: 0,
        exit: exit,
        currentPressure: 5.0,
        currentFlow: 2.0,
      );
      expect(verdict, StepExitVerdict.fire);
    });

    test('onFrameAdvanced clears stale deferral state', () {
      const exit = StepExitCondition(
        type: ExitType.pressure,
        condition: ExitCondition.over,
        value: 6.0,
      );

      // Start deferring on frame 0
      arbiter.evaluate(
        profileFrame: 0,
        exit: exit,
        currentPressure: 5.0,
        currentFlow: 3.0,
      );

      // Firmware advances to frame 1
      arbiter.onFrameAdvanced(1);

      // Evaluate frame 0 again — fresh state, first sample assumes trending
      final v = arbiter.evaluate(
        profileFrame: 0,
        exit: exit,
        currentPressure: 5.0,
        currentFlow: 3.0,
      );
      expect(v, StepExitVerdict.defer, reason: 'deferral state was cleared');
    });

    test('reset clears all deferral state', () {
      const exit = StepExitCondition(
        type: ExitType.pressure,
        condition: ExitCondition.over,
        value: 6.0,
      );

      // Accumulate 2 deferrals
      arbiter.evaluate(
        profileFrame: 0,
        exit: exit,
        currentPressure: 5.0,
        currentFlow: 3.0,
      );
      arbiter.evaluate(
        profileFrame: 0,
        exit: exit,
        currentPressure: 5.2,
        currentFlow: 3.0,
      );

      arbiter.reset();

      // Same frame, same readings — should start fresh (first sample)
      final v = arbiter.evaluate(
        profileFrame: 0,
        exit: exit,
        currentPressure: 5.0,
        currentFlow: 3.0,
      );
      expect(v, StepExitVerdict.defer, reason: 'reset clears frame count');
    });

    test('independent deferral per frame', () {
      const exit0 = StepExitCondition(
        type: ExitType.pressure,
        condition: ExitCondition.over,
        value: 6.0,
      );
      const exit1 = StepExitCondition(
        type: ExitType.pressure,
        condition: ExitCondition.over,
        value: 8.0,
      );

      // Defer on frame 0
      final v0 = arbiter.evaluate(
        profileFrame: 0,
        exit: exit0,
        currentPressure: 5.0,
        currentFlow: 3.0,
      );
      expect(v0, StepExitVerdict.defer);

      // Frame 1 is far from its threshold → fire
      final v1 = arbiter.evaluate(
        profileFrame: 1,
        exit: exit1,
        currentPressure: 2.0,
        currentFlow: 3.0,
      );
      expect(v1, StepExitVerdict.fire);
    });

    test('pressure exactly at proximity boundary fires', () {
      const exit = StepExitCondition(
        type: ExitType.pressure,
        condition: ExitCondition.over,
        value: 6.0,
      );

      // distance = 6.0 - 4.5 = 1.5, which is NOT > 1.5
      final vAt = arbiter.evaluate(
        profileFrame: 0,
        exit: exit,
        currentPressure: 4.5,
        currentFlow: 3.0,
      );
      expect(vAt, StepExitVerdict.defer,
          reason: 'distance == proximity is "near", not "far"');

      // distance = 6.0 - 4.4 = 1.6, which is > 1.5
      arbiter.reset();
      final vBeyond = arbiter.evaluate(
        profileFrame: 0,
        exit: exit,
        currentPressure: 4.4,
        currentFlow: 3.0,
      );
      expect(vBeyond, StepExitVerdict.fire);
    });
  });
}
