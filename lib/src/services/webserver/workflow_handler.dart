import 'dart:async';
import 'dart:convert';

import 'package:logging/logging.dart';
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

  static final _log = Logger('WorkflowHandler');
  Future<void> _workflowQueue = Future<void>.value();

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

  Future<Response> _updateWorkflow(Request req) {
    final payload = req.readAsString();
    final operation = _workflowQueue.then((_) => _applyPayload(payload));
    _workflowQueue = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        _log.severe('Error completing workflow queue entry', error, stackTrace);
      },
    );
    return operation;
  }

  Future<Response> _applyPayload(Future<String> payloadFuture) async {
    try {
      final decoded = jsonDecode(await payloadFuture);
      if (decoded is! Map<String, dynamic>) {
        return jsonBadRequest({'error': 'Request body must be a JSON object'});
      }
      return await _applyUpdate(Map<String, dynamic>.from(decoded));
    } on FormatException catch (e) {
      return jsonBadRequest({'error': 'Invalid request', 'message': '$e'});
    } catch (e, st) {
      _log.severe('Error reading workflow request', e, st);
      return jsonError({'error': 'Internal server error', 'message': '$e'});
    }
  }

  Future<Response> _applyUpdate(Map<String, dynamic> merge) async {
    try {
      while (true) {
        final oldWorkflow = _controller.currentWorkflow;
        final revision = _controller.revision;
        final currentJson = oldWorkflow.toJson();
        final resultJson = deepMergeJson(currentJson, merge);
        final updatedWorkflow = Workflow.fromJson(resultJson);

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
        if (_controller.setWorkflowIfRevision(updatedWorkflow, revision)) {
          return jsonOk(updatedWorkflow.toJson());
        }
      }
    } on ArgumentError catch (e) {
      return jsonBadRequest({'error': 'Invalid request', 'message': '$e'});
    } on FormatException catch (e) {
      return jsonBadRequest({'error': 'Invalid request', 'message': '$e'});
    } catch (e, st) {
      _log.severe('Error in workflow queue entry', e, st);
      return jsonError({'error': 'Internal server error', 'message': '$e'});
    }
  }
}
