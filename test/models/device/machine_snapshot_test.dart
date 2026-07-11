import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/machine.dart';

/// Locks the additive-compat contract of the `MachineSnapshot`
/// fields (`weight`, `weightFlow`, `milkTemperature`): payloads predating the
/// fields must still decode, defaulting all three to `0.0`.
void main() {
  MachineSnapshot snapshot() => MachineSnapshot(
    timestamp: DateTime.utc(2026, 7, 11, 12, 0, 0),
    state: MachineStateSnapshot(
      state: MachineState.espresso,
      substate: MachineSubstate.pouring,
    ),
    flow: 2.5,
    pressure: 9.0,
    targetFlow: 2.0,
    targetPressure: 6.0,
    mixTemperature: 92.5,
    groupTemperature: 88.0,
    targetMixTemperature: 93.0,
    targetGroupTemperature: 90.0,
    profileFrame: 7,
    steamTemperature: 135,
    weight: 36.5,
    weightFlow: 1.8,
    milkTemperature: 61.98,
  );

  group('MachineSnapshot json (additive fields)', () {
    test('fromJson defaults weight/weightFlow/milkTemperature to 0.0 when '
        'absent (pre-FIX payloads decode)', () {
      final json = snapshot().toJson()
        ..remove('weight')
        ..remove('weightFlow')
        ..remove('milkTemperature');

      final decoded = MachineSnapshot.fromJson(json);

      expect(decoded.weight, 0.0);
      expect(decoded.weightFlow, 0.0);
      expect(decoded.milkTemperature, 0.0);
      // The legacy fields still decode unchanged.
      expect(decoded.pressure, closeTo(9.0, 1e-9));
      expect(decoded.steamTemperature, 135);
    });

    test('toJson -> fromJson round-trips the three fields', () {
      final decoded = MachineSnapshot.fromJson(snapshot().toJson());

      expect(decoded.weight, closeTo(36.5, 1e-9));
      expect(decoded.weightFlow, closeTo(1.8, 1e-9));
      expect(decoded.milkTemperature, closeTo(61.98, 1e-9));
    });

    test('fromJson tolerates integer-typed values (json num -> double)', () {
      final json = snapshot().toJson()
        ..['weight'] = 36
        ..['weightFlow'] = 2
        ..['milkTemperature'] = 0;

      final decoded = MachineSnapshot.fromJson(json);

      expect(decoded.weight, 36.0);
      expect(decoded.weightFlow, 2.0);
      expect(decoded.milkTemperature, 0.0);
    });

    test('copyWith carries and overrides the three fields', () {
      final base = snapshot();
      expect(base.copyWith().weight, closeTo(36.5, 1e-9));
      expect(base.copyWith(weight: 40.0).weight, closeTo(40.0, 1e-9));
      expect(base.copyWith(weightFlow: 2.2).weightFlow, closeTo(2.2, 1e-9));
      expect(
        base.copyWith(milkTemperature: 55.0).milkTemperature,
        closeTo(55.0, 1e-9),
      );
    });
  });
}
