import 'dart:async';
import 'dart:convert';

import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/home_feature/forms/hot_water_form.dart';
import 'package:reaprime/src/home_feature/forms/steam_form.dart';
import 'package:reaprime/src/models/data/json_utils.dart';
import 'package:reaprime/src/models/data/workflow.dart';
import 'package:reaprime/src/services/webserver/json_response.dart';
import 'package:shelf_plus/shelf_plus.dart';

class WorkflowHandler {
  final WorkflowController _controller;
  final De1Controller _de1controller;

  Timer? _debounceTimer;
  Map<String, dynamic> _pendingMerge = {};
  final List<Completer<Response>> _pendingResponses = [];

  static const _debounceDuration = Duration(milliseconds: 400);

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
    return jsonOk(workflow.toJson());
  }

  Future<Response> _updateWorkflow(Request req) async {
    final payload = await req.readAsString();
    final Map<String, dynamic> json = jsonDecode(payload);

    _pendingMerge = deepMergeJson(_pendingMerge, json);

    final completer = Completer<Response>();
    _pendingResponses.add(completer);

    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, _applyPendingUpdate);

    return completer.future;
  }

  Future<void> _applyPendingUpdate() async {
    final merge = _pendingMerge;
    final responses = List<Completer<Response>>.from(_pendingResponses);
    _pendingMerge = {};
    _pendingResponses.clear();

    final oldWorkflow = _controller.currentWorkflow;
    final currentJson = oldWorkflow.toJson();
    final resultJson = deepMergeJson(currentJson, merge);
    final updatedWorkflow = Workflow.fromJson(resultJson);

    _controller.setWorkflow(updatedWorkflow);
    // Profile push is owned by WorkflowDeviceSync — it observes
    // `setWorkflow` and uploads the profile if it changed. Keeping a
    // second setProfile call here would race against that listener and
    // write every BLE frame twice (see the profile-double-upload P0).
    if (oldWorkflow.rinseData != updatedWorkflow.rinseData) {
      await _de1controller.updateFlushSettings(updatedWorkflow.rinseData);
    }
    if (oldWorkflow.steamSettings != updatedWorkflow.steamSettings) {
      await _de1controller.updateSteamSettings(
        SteamFormSettings(
          steamEnabled: updatedWorkflow.steamSettings.duration > 0,
          targetTemp: updatedWorkflow.steamSettings.targetTemperature,
          targetDuration: updatedWorkflow.steamSettings.duration,
          targetFlow: updatedWorkflow.steamSettings.flow,
        ),
      );
    }
    if (oldWorkflow.hotWaterData != updatedWorkflow.hotWaterData) {
      await _de1controller.updateHotWaterSettings(
        HotWaterFormSettings(
          targetTemperature: updatedWorkflow.hotWaterData.targetTemperature,
          flow: updatedWorkflow.hotWaterData.flow,
          volume: updatedWorkflow.hotWaterData.volume,
          duration: updatedWorkflow.hotWaterData.duration,
        ),
      );
    }

    for (final completer in responses) {
      completer.complete(jsonOk(updatedWorkflow.toJson()));
    }
  }
}
