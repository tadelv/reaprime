import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/models/data/shot_annotations.dart';
import 'package:reaprime/src/models/data/shot_record.dart';

void main() {
  test('canonical constructor annotations stay authoritative when null', () {
    final serialized = ShotRecord(
      id: 'shot-1',
      timestamp: DateTime.utc(2026, 7, 23),
      measurements: const [],
      workflow: WorkflowController().currentWorkflow,
      annotations: const ShotAnnotations(),
      shotNotes: 'legacy notes',
      metadata: const {'favorite': true},
    ).toJson();

    expect(serialized['annotations'], isEmpty);
    expect(serialized.containsKey('shotNotes'), isFalse);
    expect(serialized.containsKey('metadata'), isFalse);
  });

  test(
    'legacy aliases synthesize annotations when canonical key is absent',
    () {
      final json = _baseJson()
        ..addAll({
          'shotNotes': 'legacy notes',
          'metadata': {'favorite': true},
        });

      final serialized = ShotRecord.fromJson(json).toJson();

      expect(serialized['annotations'], {
        'espressoNotes': 'legacy notes',
        'extras': {'favorite': true},
      });
      expect(serialized['shotNotes'], 'legacy notes');
      expect(serialized['metadata'], {'favorite': true});
    },
  );

  test('canonical annotation object ignores conflicting legacy aliases', () {
    final json = _baseJson()
      ..addAll({
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

  test('explicit canonical null does not reconstruct stale aliases', () {
    final json = _baseJson()
      ..addAll({
        'annotations': null,
        'shotNotes': 'stale notes',
        'metadata': {'favorite': false},
      });

    final serialized = ShotRecord.fromJson(json).toJson();

    expect(serialized.containsKey('annotations'), isFalse);
    expect(serialized.containsKey('shotNotes'), isFalse);
    expect(serialized.containsKey('metadata'), isFalse);
  });
}

Map<String, dynamic> _baseJson() => ShotRecord(
  id: 'shot-1',
  timestamp: DateTime.utc(2026, 7, 23),
  measurements: const [],
  workflow: WorkflowController().currentWorkflow,
).toJson();
