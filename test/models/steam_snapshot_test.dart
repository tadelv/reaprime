import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/data/steam_snapshot.dart';
import 'package:reaprime/src/models/device/machine.dart';

MachineSnapshot _machineSnapshot() => MachineSnapshot(
  timestamp: DateTime.utc(2026, 5, 18, 12, 0, 0),
  state: const MachineStateSnapshot(
    state: MachineState.steam,
    substate: MachineSubstate.pouring,
  ),
  flow: 0,
  pressure: 0,
  targetFlow: 0,
  targetPressure: 0,
  mixTemperature: 90,
  groupTemperature: 90,
  targetMixTemperature: 93,
  targetGroupTemperature: 93,
  profileFrame: 0,
  steamTemperature: 140,
);

void main() {
  group('SteamSnapshot', () {
    test('round-trips with milkTemperature', () {
      final original = SteamSnapshot(
        machine: _machineSnapshot(),
        milkTemperature: 65.5,
      );
      final json = original.toJson();
      final restored = SteamSnapshot.fromJson(json);
      expect(restored.milkTemperature, equals(65.5));
      expect(restored.machine.steamTemperature, equals(140));
      expect(restored.machine.state.state, equals(MachineState.steam));
    });

    test('round-trips without milkTemperature (null)', () {
      final original = SteamSnapshot(machine: _machineSnapshot());
      final json = original.toJson();
      expect(json['milkTemperature'], isNull);
      final restored = SteamSnapshot.fromJson(json);
      expect(restored.milkTemperature, isNull);
    });

    test('copyWith preserves and overrides milkTemperature', () {
      final base = SteamSnapshot(
        machine: _machineSnapshot(),
        milkTemperature: 50.0,
      );
      expect(base.copyWith().milkTemperature, equals(50.0));
      expect(
        base.copyWith(milkTemperature: 70.0).milkTemperature,
        equals(70.0),
      );
    });
  });
}
