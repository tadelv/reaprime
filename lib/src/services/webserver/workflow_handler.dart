import 'dart:convert';

import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/home_feature/forms/hot_water_form.dart';
import 'package:reaprime/src/home_feature/forms/steam_form.dart';
import 'package:reaprime/src/models/data/json_utils.dart';
import 'package:reaprime/src/models/data/workflow.dart';
import 'package:shelf_plus/shelf_plus.dart';

class WorkflowHandler {
  final WorkflowController _controller;
  final De1Controller _de1controller;

  WorkflowHandler({
    required WorkflowController controller,
    required De1Controller de1controller,
  }) : _controller = controller,
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
    final oldWorkflow = updatedWorkflow.copyWith();
    final currentWorkflowJson = updatedWorkflow.toJson();

    final resultJson = deepMergeJson(currentWorkflowJson, json);

    updatedWorkflow = Workflow.fromJson(resultJson);

    _controller.setWorkflow(updatedWorkflow);
    _de1controller.connectedDe1().setProfile(updatedWorkflow.profile);
    if (oldWorkflow.rinseData != updatedWorkflow.rinseData) {
      _de1controller.updateFlushSettings(updatedWorkflow.rinseData);
    }
    if (oldWorkflow.steamSettings != updatedWorkflow.steamSettings) {
      _de1controller.updateSteamSettings(
        SteamFormSettings(
          steamEnabled: updatedWorkflow.steamSettings.duration > 0,
          targetTemp: updatedWorkflow.steamSettings.targetTemperature,
          targetDuration: updatedWorkflow.steamSettings.duration,
          targetFlow: updatedWorkflow.steamSettings.flow,
        ),
      );
    }
    if (oldWorkflow.hotWaterData != updatedWorkflow.hotWaterData) {
      _de1controller.updateHotWaterSettings(
        HotWaterFormSettings(
          targetTemperature: updatedWorkflow.hotWaterData.targetTemperature,
          flow: updatedWorkflow.hotWaterData.flow,
          volume: updatedWorkflow.hotWaterData.volume,
          duration: updatedWorkflow.hotWaterData.duration,
        ),
      );
    }
    return Response.ok(jsonEncode(updatedWorkflow.toJson()));
  }
}
