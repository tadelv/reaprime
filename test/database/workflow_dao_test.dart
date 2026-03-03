import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/services/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Map<String, dynamic> _makeWorkflowJson({String name = 'Test Workflow'}) {
    return {
      'id': 'wf-1',
      'name': name,
      'description': 'Test',
      'profile': {
        'title': 'Test Profile',
        'author': 'Test',
        'notes': '',
        'beverage_type': 'espresso',
        'steps': [],
        'tank_temperature': 0.0,
        'target_weight': 36.0,
        'target_volume_count_start': 0,
        'version': '2',
      },
      'context': {
        'targetDoseWeight': 18.0,
        'targetYield': 36.0,
      },
      'steamSettings': {
        'targetTemperature': 150,
        'duration': 50,
        'flow': 0.8,
      },
      'hotWaterData': {
        'targetTemperature': 90,
        'duration': 15,
        'volume': 100,
        'flow': 4.0,
      },
      'rinseData': {
        'targetTemperature': 90,
        'duration': 10,
        'flow': 6.0,
      },
    };
  }

  test('returns null when no workflow saved', () async {
    final result = await db.workflowDao.loadCurrentWorkflow();
    expect(result, isNull);
  });

  test('saves and loads current workflow', () async {
    await db.workflowDao.saveCurrentWorkflow(WorkflowsCompanion(
      workflowJson: Value(_makeWorkflowJson(name: 'My Workflow')),
      updatedAt: Value(DateTime.now()),
    ));

    final result = await db.workflowDao.loadCurrentWorkflow();
    expect(result, isNotNull);
    expect(result!.workflowJson['name'], 'My Workflow');
  });

  test('upserts workflow (replaces existing)', () async {
    await db.workflowDao.saveCurrentWorkflow(WorkflowsCompanion(
      workflowJson: Value(_makeWorkflowJson(name: 'First')),
      updatedAt: Value(DateTime.now()),
    ));
    await db.workflowDao.saveCurrentWorkflow(WorkflowsCompanion(
      workflowJson: Value(_makeWorkflowJson(name: 'Second')),
      updatedAt: Value(DateTime.now()),
    ));

    final result = await db.workflowDao.loadCurrentWorkflow();
    expect(result!.workflowJson['name'], 'Second');
  });
}
