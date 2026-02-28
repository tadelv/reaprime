import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/models/data/workflow.dart';
import 'package:reaprime/src/services/webserver/data_export/data_export_section.dart';

class WorkflowExportSection implements DataExportSection {
  final WorkflowController _controller;

  WorkflowExportSection({required WorkflowController controller})
      : _controller = controller;

  @override
  String get filename => 'workflow.json';

  @override
  Future<dynamic> export() async {
    return _controller.currentWorkflow.toJson();
  }

  @override
  Future<SectionImportResult> import(
    dynamic data,
    ConflictStrategy strategy,
  ) async {
    try {
      final workflow = Workflow.fromJson(data as Map<String, dynamic>);
      _controller.setWorkflow(workflow);
      return const SectionImportResult(imported: 1);
    } catch (e) {
      return SectionImportResult(errors: ['Failed to import workflow: $e']);
    }
  }
}
