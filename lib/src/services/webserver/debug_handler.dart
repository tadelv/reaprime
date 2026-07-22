import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/models/device/impl/mock_scale/mock_scale.dart';
import 'package:reaprime/src/services/update_check_service.dart';
import 'package:reaprime/src/services/webserver/json_response.dart';
import 'package:shelf_plus/shelf_plus.dart';

/// Debug endpoints for controlling simulated devices.
/// Only registered when running in simulate mode.
class DebugHandler {
  final ScaleController _scaleController;
  final UpdateCheckService? _updateCheckService;
  final Logger _log = Logger('DebugHandler');

  DebugHandler({
    required ScaleController scaleController,
    UpdateCheckService? updateCheckService,
  }) : _scaleController = scaleController,
       _updateCheckService = updateCheckService;

  Map<String, int> get _flowSmoothing => {
    'windowMs': _scaleController.flowSmoothingWindowMs,
    'movingAverageSamples': _scaleController.flowSmoothingSamples,
  };

  void addRoutes(RouterPlus app) {
    // Force a fake "update available" so the update API/UI can be tested
    // without a real newer release. `version`/`downloadUrl` query params
    // override the defaults (default downloadUrl is a real APK so the
    // download/install path runs end-to-end).
    app.post('/api/v1/debug/update/force', (request) {
      final svc = _updateCheckService;
      if (svc == null) {
        return jsonBadRequest({'error': 'UpdateCheckService unavailable'});
      }
      final version = request.url.queryParameters['version'] ?? '99.0.0';
      final downloadUrl = request.url.queryParameters['downloadUrl'];
      svc.debugForceUpdate(version: version, downloadUrl: downloadUrl);
      _log.info('Forced update available: $version');
      return jsonOk(svc.currentState.toJson());
    });

    app.get('/api/v1/debug/flow-smoothing', (request) {
      return jsonOk(_flowSmoothing);
    });

    app.post('/api/v1/debug/flow-smoothing', (request) async {
      try {
        final body = jsonDecode(await request.readAsString());
        if (body is! Map<String, dynamic> ||
            body['windowMs'] is! int ||
            body['movingAverageSamples'] is! int) {
          return jsonBadRequest({
            'error': 'Expected integer windowMs and movingAverageSamples',
          });
        }
        _scaleController.setFlowSmoothing(
          windowMs: body['windowMs'],
          movingAverageSamples: body['movingAverageSamples'],
        );
        return jsonOk(_flowSmoothing);
      } on FormatException {
        return jsonBadRequest({'error': 'Invalid JSON'});
      } on RangeError catch (e) {
        return jsonBadRequest({'error': e.message});
      }
    });

    app.post('/api/v1/debug/scale/<command>', (request, command) async {
      final MockScale mock;
      try {
        final scale = _scaleController.connectedScale();
        if (scale is! MockScale) {
          return jsonBadRequest(
            {'error': 'Connected scale is not a MockScale'},
          );
        }
        mock = scale;
      } catch (e) {
        return jsonBadRequest({'error': 'No scale connected'});
      }

      switch (command) {
        case 'stall':
          _log.info('Simulating data stall on MockScale');
          mock.simulateDataStall();
          return jsonOk({'status': 'stalled'});
        case 'resume':
          _log.info('Resuming MockScale data emission');
          mock.simulateResume();
          return jsonOk({'status': 'resumed'});
        case 'disconnect':
          _log.info('Simulating MockScale disconnect');
          mock.simulateDisconnect();
          return jsonOk({'status': 'disconnected'});
        default:
          return jsonNotFound({'error': 'Unknown command: $command'});
      }
    });
  }
}
