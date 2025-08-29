import 'dart:convert';

import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/models/data/workflow.dart';
import 'package:shelf_plus/shelf_plus.dart';

class WorkflowHandler {
  final WorkflowController _controller;
  final De1Controller _de1controller;

  WorkflowHandler(
      {required WorkflowController controller,
      required De1Controller de1controller})
      : _controller = controller,
        _de1controller = de1controller;

  void addRoutes(RouterPlus app) {
    app.get('/api/v1/workflow', _getWorkflow);
    app.put('/api/v1/workflow', _updateWorkflow);
  }

  Future<Response> _getWorkflow(Request req) async {
    final workflow = _controller.currentWorkflow;
    return Response.ok(jsonEncode(workflow.toJson()));
  }

  Future<Response> _updateWorkflow(Request req) async {
    final payload = await req.readAsString();
    final Map<String, dynamic> json = jsonDecode(payload);
    var updatedWorkflow = _controller.currentWorkflow;
    final currentWorkflowJson = updatedWorkflow.toJson();

    currentWorkflowJson.addAll(json);
    updatedWorkflow = Workflow.fromJson(currentWorkflowJson);

    _controller.setWorkflow(updatedWorkflow);
    _de1controller.connectedDe1().setProfile(updatedWorkflow.profile);
    return Response.ok(jsonEncode(updatedWorkflow.toJson()));
  }
}
