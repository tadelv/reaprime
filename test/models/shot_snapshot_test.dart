import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/models/data/shot_snapshot.dart';
import 'package:reaprime/src/models/device/machine.dart';

MachineSnapshot _machineSnapshot() => MachineSnapshot(
      timestamp: DateTime.utc(2026, 7, 1, 12, 0, 0),
      state: const MachineStateSnapshot(
        state: MachineState.espresso,
        substate: MachineSubstate.pouring,
      ),
      flow: 2.0,
      pressure: 9.0,
      targetFlow: 2.0,
      targetPressure: 9.0,
      mixTemperature: 92.0,
      groupTemperature: 92.0,
      targetMixTemperature: 92.0,
      targetGroupTemperature: 92.0,
      profileFrame: 0,
      steamTemperature: 0,
    );

void main() {
  group('ShotSnapshot', () {
    test('round-trips with probeTemperature', () {
      final original = ShotSnapshot(
        machine: _machineSnapshot(),
        scale: WeightSnapshot(
          timestamp: DateTime.utc(2026, 7, 1, 12, 0, 1),
          weight: 36.0,
          weightFlow: 1.5,
        ),
        volume: 40.0,
        probeTemperature: 93.5,
      );
      final json = original.toJson();
      final restored = ShotSnapshot.fromJson(json);
      expect(restored.probeTemperature, equals(93.5));
      expect(restored.volume, equals(40.0));
      expect(restored.scale?.weight, equals(36.0));
    });

    test('round-trips without probeTemperature (null)', () {
      final original = ShotSnapshot(machine: _machineSnapshot());
      final json = original.toJson();
      expect(json['probeTemperature'], isNull);
      final restored = ShotSnapshot.fromJson(json);
      expect(restored.probeTemperature, isNull);
    });

    test('fromJson handles int probeTemperature', () {
      final json = {
        'machine': _machineSnapshot().toJson(),
        'probeTemperature': 94,
      };
      final restored = ShotSnapshot.fromJson(json);
      expect(restored.probeTemperature, equals(94.0));
    });

    test('copyWith preserves and overrides probeTemperature', () {
      final base = ShotSnapshot(
        machine: _machineSnapshot(),
        probeTemperature: 90.0,
      );
      expect(base.copyWith().probeTemperature, equals(90.0));
      expect(
        base.copyWith(probeTemperature: 95.0).probeTemperature,
        equals(95.0),
      );
    });
  });
}
