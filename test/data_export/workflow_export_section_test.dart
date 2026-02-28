import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/data/workflow.dart';
import 'package:reaprime/src/services/webserver/data_export/data_export_section.dart';
import 'package:reaprime/src/services/webserver/data_export/workflow_export_section.dart';

Workflow _makeWorkflow({
  String id = 'wf-1',
  String name = 'Test Workflow',
}) {
  return Workflow(
    id: id,
    name: name,
    description: 'Test Description',
    profile: Profile(
      version: '2',
      title: 'Test Profile',
      author: 'Test Author',
      notes: '',
      beverageType: BeverageType.espresso,
      steps: [],
      tankTemperature: 0.0,
      targetWeight: 36.0,
      targetVolumeCountStart: 0,
    ),
    doseData: DoseData(doseIn: 18.0, doseOut: 36.0),
    steamSettings: SteamSettings.defaults(),
    hotWaterData: HotWaterData.defaults(),
    rinseData: RinseData.defaults(),
  );
}

void main() {
  late WorkflowController controller;
  late WorkflowExportSection section;

  setUp(() {
    controller = WorkflowController();
    section = WorkflowExportSection(controller: controller);
  });

  tearDown(() {
    controller.dispose();
  });

  test('filename is workflow.json', () {
    expect(section.filename, equals('workflow.json'));
  });

  group('export', () {
    test('exports the current workflow as JSON', () async {
      final workflow = _makeWorkflow(name: 'My Workflow');
      controller.setWorkflow(workflow);

      final result = await section.export();
      expect(result, isA<Map<String, dynamic>>());
      final map = result as Map<String, dynamic>;
      expect(map['name'], equals('My Workflow'));
      expect(map['id'], equals('wf-1'));
      expect(map['profile'], isA<Map<String, dynamic>>());
      expect(map['doseData'], isA<Map<String, dynamic>>());
    });

    test('exports default workflow when none set', () async {
      final result = await section.export();
      expect(result, isA<Map<String, dynamic>>());
      final map = result as Map<String, dynamic>;
      expect(map['name'], equals('Workflow'));
    });
  });

  group('import', () {
    test('imports a valid workflow', () async {
      final workflow = _makeWorkflow(name: 'Imported Workflow');
      final json = workflow.toJson();

      final result = await section.import(json, ConflictStrategy.skip);

      expect(result.imported, equals(1));
      expect(result.errors, isEmpty);
      expect(controller.currentWorkflow.name, equals('Imported Workflow'));
      expect(controller.currentWorkflow.id, equals('wf-1'));
    });

    test('overwrites current workflow regardless of strategy', () async {
      final original = _makeWorkflow(name: 'Original');
      controller.setWorkflow(original);

      final imported = _makeWorkflow(name: 'Imported');
      final json = imported.toJson();

      // Even with skip strategy, workflow is always replaced (there's only one)
      final result = await section.import(json, ConflictStrategy.skip);

      expect(result.imported, equals(1));
      expect(controller.currentWorkflow.name, equals('Imported'));
    });

    test('returns error for invalid data', () async {
      final result =
          await section.import('not a map', ConflictStrategy.skip);

      expect(result.imported, equals(0));
      expect(result.errors, hasLength(1));
      expect(result.errors.first, contains('Failed to import workflow'));
    });

    test('returns error for malformed workflow JSON', () async {
      final result = await section.import(
        <String, dynamic>{'garbage': true},
        ConflictStrategy.skip,
      );

      expect(result.imported, equals(0));
      expect(result.errors, hasLength(1));
      expect(result.errors.first, contains('Failed to import workflow'));
    });

    test('round-trips correctly', () async {
      final workflow = _makeWorkflow(name: 'Round Trip');
      controller.setWorkflow(workflow);

      final exported = await section.export();

      // Reset controller
      controller.setWorkflow(_makeWorkflow(name: 'Reset'));
      expect(controller.currentWorkflow.name, equals('Reset'));

      // Import back
      final result = await section.import(exported, ConflictStrategy.skip);

      expect(result.imported, equals(1));
      expect(controller.currentWorkflow.name, equals('Round Trip'));
    });
  });
}
