import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/data/workflow.dart';
import 'package:reaprime/src/models/data/workflow_context.dart';
import 'package:reaprime/src/services/webserver/data_export/data_export_section.dart';
import 'package:reaprime/src/services/webserver/data_export/workflow_export_section.dart';

import 'streaming_test_helpers.dart';

Workflow _makeWorkflow({String id = 'wf-1', String name = 'Test Workflow'}) {
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
      steps: [
        ProfileStepPressure(
          name: 'pour',
          transition: TransitionType.fast,
          volume: 100,
          seconds: 30,
          temperature: 93,
          sensor: TemperatureSensor.coffee,
          pressure: 9,
        ),
      ],
      tankTemperature: 0.0,
      targetWeight: 36.0,
      targetVolumeCountStart: 0,
    ),
    context: WorkflowContext(targetDoseWeight: 18.0, targetYield: 36.0),
    steamSettings: SteamSettings.defaults(),
    hotWaterData: HotWaterData.defaults(),
    rinseData: RinseData.defaults(),
  );
}

void main() {
  group('WorkflowExportSection', () {
    test('exports the current workflow as a single JSON value', () async {
      final controller = WorkflowController()..setWorkflow(_makeWorkflow());
      final section = WorkflowExportSection(controller: controller);

      final sink = CapturingJsonSink();
      await section.exportJson(sink);
      final decoded = jsonDecode(sink.json) as Map<String, dynamic>;
      expect(decoded['id'], 'wf-1');
      expect(decoded['name'], 'Test Workflow');
    });

    test('imports a valid workflow regardless of strategy', () async {
      final controller = WorkflowController()..setWorkflow(_makeWorkflow());
      final section = WorkflowExportSection(controller: controller);

      final updated = _makeWorkflow(id: 'wf-2', name: 'New Workflow');
      for (final strategy in [
        ConflictStrategy.skip,
        ConflictStrategy.overwrite,
      ]) {
        final result = await importSectionJson(
          section,
          jsonEncode(updated.toJson()),
          strategy,
        );
        expect(result.imported, 1);
        expect(controller.currentWorkflow.name, 'New Workflow');
      }
    });

    test('reports an error for invalid workflow data', () async {
      final section = WorkflowExportSection(controller: WorkflowController());
      final result = await importSectionJson(
        section,
        '{"id": 1}',
        ConflictStrategy.skip,
      );
      expect(result.errors, hasLength(1));
    });

    test('rejects malformed JSON with a section error', () async {
      final section = WorkflowExportSection(controller: WorkflowController());
      final result = await importSectionJson(
        section,
        '{"id": ',
        ConflictStrategy.skip,
      );
      expect(result.errors, hasLength(1));
      expect(result.imported, 0);
    });

    test('round-trips correctly', () async {
      final controller = WorkflowController()..setWorkflow(_makeWorkflow());
      final section = WorkflowExportSection(controller: controller);

      final sink = CapturingJsonSink();
      await section.exportJson(sink);

      final imported = WorkflowController();
      final importSection = WorkflowExportSection(controller: imported);
      await importSectionJson(importSection, sink.json, ConflictStrategy.skip);
      expect(
        imported.currentWorkflow.toJson(),
        controller.currentWorkflow.toJson(),
      );
    });
  });
}
