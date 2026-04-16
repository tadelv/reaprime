import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/models/device/impl/mock_scale/mock_scale.dart';
import 'package:reaprime/src/services/webserver/json_response.dart';
import 'package:shelf_plus/shelf_plus.dart';

/// Debug endpoints for controlling simulated devices.
/// Only registered when running in simulate mode.
class DebugHandler {
  final ScaleController _scaleController;
  final Logger _log = Logger('DebugHandler');

  DebugHandler({required ScaleController scaleController})
      : _scaleController = scaleController;

  void addRoutes(RouterPlus app) {
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
