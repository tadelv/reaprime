import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/models/data/shot_annotations.dart';
import 'package:reaprime/src/models/data/steam_record.dart';
import 'package:reaprime/src/models/data/steam_snapshot.dart';
import 'package:reaprime/src/models/data/workflow.dart';
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

Workflow _workflow() => WorkflowController().currentWorkflow.copyWith(
  steamSettings: SteamSettings(
    targetTemperature: 150,
    duration: 50,
    flow: 0.8,
    stopAtTemperature: 65.0,
  ),
);

void main() {
  group('SteamRecord', () {
    test('round-trips with measurements and annotations', () {
      final original = SteamRecord(
        id: 'steam-1',
        timestamp: DateTime.utc(2026, 5, 18, 12, 0, 0),
        measurements: [
          SteamSnapshot(machine: _machineSnapshot(), milkTemperature: 50.0),
          SteamSnapshot(machine: _machineSnapshot(), milkTemperature: 65.0),
        ],
        workflow: _workflow(),
        annotations: ShotAnnotations(espressoNotes: 'silky'),
      );
      final json = original.toJson();
      final restored = SteamRecord.fromJson(json);
      expect(restored.id, equals('steam-1'));
      expect(restored.measurements, hasLength(2));
      expect(restored.measurements.last.milkTemperature, equals(65.0));
      expect(restored.workflow.steamSettings.stopAtTemperature, equals(65.0));
      expect(restored.annotations?.espressoNotes, equals('silky'));
    });

    test('round-trips with empty measurements and no annotations', () {
      final original = SteamRecord(
        id: 'steam-2',
        timestamp: DateTime.utc(2026, 5, 18, 12, 0, 0),
        measurements: const [],
        workflow: _workflow(),
      );
      final restored = SteamRecord.fromJson(original.toJson());
      expect(restored.measurements, isEmpty);
      expect(restored.annotations, isNull);
    });

    test('toJsonWithoutMeasurements omits measurements key', () {
      final r = SteamRecord(
        id: 'steam-3',
        timestamp: DateTime.utc(2026, 5, 18, 12, 0, 0),
        measurements: [
          SteamSnapshot(machine: _machineSnapshot()),
        ],
        workflow: _workflow(),
      );
      final json = r.toJsonWithoutMeasurements();
      expect(json.containsKey('measurements'), isFalse);
      expect(json['id'], equals('steam-3'));
    });
  });
}
