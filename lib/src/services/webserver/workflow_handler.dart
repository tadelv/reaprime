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

  Timer? _debounceTimer;
  Map<String, dynamic> _pendingMerge = {};
  final List<Completer<Response>> _pendingResponses = [];
  Future<void> _mutationTail = Future<void>.value();

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
    _debounceTimer = Timer(_debounceDuration, _capturePendingUpdate);

    return completer.future;
  }

  void _capturePendingUpdate() {
    final merge = Map<String, dynamic>.from(_pendingMerge);
    final responses = List<Completer<Response>>.from(_pendingResponses);
    _pendingMerge = {};
    _pendingResponses.clear();

    _mutationTail = _mutationTail.then<void>((_) async {
      try {
        await _applyPendingUpdate(merge, responses);
      } catch (e, st) {
        _log.severe('Error in queued workflow update', e, st);
        _completeResponses(
          responses,
          () => jsonError({'error': 'Internal server error', 'message': '$e'}),
        );
      }
    });
  }

  Future<void> _applyPendingUpdate(
    Map<String, dynamic> merge,
    List<Completer<Response>> responses,
  ) async {
    try {
      while (true) {
        final oldWorkflow = _controller.currentWorkflow;
        final revision = _controller.revision;
        final resultJson = deepMergeJson(oldWorkflow.toJson(), merge);
        final updatedWorkflow = Workflow.fromJson(resultJson);

        // Profile push and Bengle stop-at-temperature target updates are
        // owned by listeners after `setWorkflow` commits the workflow.
        if (oldWorkflow.rinseData != updatedWorkflow.rinseData) {
          await _de1controller.updateFlushSettings(updatedWorkflow.rinseData);
        }
        final oldSteamSettings = oldWorkflow.steamSettings;
        final updatedSteamSettings = updatedWorkflow.steamSettings;
        final steamSettingsChanged =
            oldSteamSettings.targetTemperature !=
                updatedSteamSettings.targetTemperature ||
            oldSteamSettings.duration != updatedSteamSettings.duration ||
            oldSteamSettings.flow != updatedSteamSettings.flow;
        if (steamSettingsChanged) {
          await _de1controller.updateSteamSettings(
            SteamFormSettings(
              steamEnabled: updatedSteamSettings.duration > 0,
              targetTemp: updatedSteamSettings.targetTemperature,
              targetDuration: updatedSteamSettings.duration,
              targetFlow: updatedSteamSettings.flow,
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
          _completeResponses(responses, () => jsonOk(updatedWorkflow.toJson()));
          return;
        }
      }
    } on ArgumentError catch (e) {
      // Client sent a payload that fails validation (e.g. an invalid
      // enum value like ExitType 'weight', or a missing required
      // profile field). Return a clean 400 — matching the pattern in
      // profile_handler.dart — so the HTTP request does not hang.
      // _pendingMerge was already cleared above, so subsequent PUTs
      // start from a clean slate.
      _completeResponses(
        responses,
        () => jsonBadRequest({'error': 'Invalid request', 'message': '$e'}),
      );
    } on FormatException catch (e) {
      _completeResponses(
        responses,
        () => jsonBadRequest({'error': 'Invalid request', 'message': '$e'}),
      );
    } catch (e, st) {
      // Unexpected error — likely a server-side failure during DE1
      // side-effects (BLE writes, controller updates). Log it and
      // return 500 so the request still doesn't hang.
      _log.severe('Error in _applyPendingUpdate', e, st);
      _completeResponses(
        responses,
        () => jsonError({'error': 'Internal server error', 'message': '$e'}),
      );
    }
  }

  void _completeResponses(
    List<Completer<Response>> responses,
    Response Function() createResponse,
  ) {
    for (final completer in responses) {
      if (!completer.isCompleted) {
        completer.complete(createResponse());
      }
    }
  }
}
