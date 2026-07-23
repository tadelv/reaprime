import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/models/data/shot_record.dart';

void main() {
  test('canonical annotations override stale legacy aliases', () {
    final json =
        ShotRecord(
          id: 'shot-1',
          timestamp: DateTime.utc(2026, 7, 23),
          measurements: const [],
          workflow: WorkflowController().currentWorkflow,
        ).toJson()..addAll({
          'annotations': {
            'espressoNotes': 'canonical notes',
            'extras': {'favorite': true},
          },
          'shotNotes': 'stale notes',
          'metadata': {'favorite': false},
        });

    final serialized = ShotRecord.fromJson(json).toJson();

    expect(serialized['shotNotes'], 'canonical notes');
    expect(serialized['metadata'], {'favorite': true});
  });
}
