part of '../webserver_service.dart';

/// REST and WebSocket handler for screen display management.
class DisplayHandler {
  final DisplayController _displayController;
  final log = Logger('DisplayHandler');

  DisplayHandler({required DisplayController displayController})
      : _displayController = displayController;

  void addRoutes(RouterPlus app) {
    app.get('/api/v1/display', _getState);
    app.post('/api/v1/display/dim', _dim);
    app.post('/api/v1/display/restore', _restore);
    app.post('/api/v1/display/wakelock', _requestWakeLock);
    app.delete('/api/v1/display/wakelock', _releaseWakeLock);
    app.get('/ws/v1/display', _handleWebSocket);
  }

  /// GET /api/v1/display
  Future<Response> _getState(Request request) async {
    try {
      return jsonOk(_displayController.currentState.toJson());
    } catch (e, st) {
      log.severe('Error in getState handler', e, st);
      return jsonError({'error': e.toString()});
    }
  }

  /// POST /api/v1/display/dim
  Future<Response> _dim(Request request) async {
    try {
      await _displayController.dim();
      return jsonOk(_displayController.currentState.toJson());
    } catch (e, st) {
      log.severe('Error in dim handler', e, st);
      return jsonError({'error': e.toString()});
    }
  }

  /// POST /api/v1/display/restore
  Future<Response> _restore(Request request) async {
    try {
      await _displayController.restore();
      return jsonOk(_displayController.currentState.toJson());
    } catch (e, st) {
      log.severe('Error in restore handler', e, st);
      return jsonError({'error': e.toString()});
    }
  }

  /// POST /api/v1/display/wakelock
  Future<Response> _requestWakeLock(Request request) async {
    try {
      await _displayController.requestWakeLock();
      return jsonOk(_displayController.currentState.toJson());
    } catch (e, st) {
      log.severe('Error in requestWakeLock handler', e, st);
      return jsonError({'error': e.toString()});
    }
  }

  /// DELETE /api/v1/display/wakelock
  Future<Response> _releaseWakeLock(Request request) async {
    try {
      await _displayController.releaseWakeLock();
      return jsonOk(_displayController.currentState.toJson());
    } catch (e, st) {
      log.severe('Error in releaseWakeLock handler', e, st);
      return jsonError({'error': e.toString()});
    }
  }

  /// ws/v1/display
  /// Streams DisplayState changes to connected WebSocket clients.
  /// Auto-releases wake-lock override when the client disconnects.
  ///
  /// Note: wake-lock override is not reference-counted across multiple
  /// WebSocket clients. If multiple clients request an override, the first
  /// disconnect will release it for all. This is acceptable for the typical
  /// use case of one skin = one active WebSocket connection.
  Future<Response> _handleWebSocket(Request req) async {
    return sws.webSocketHandler((WebSocketChannel socket, String? protocol) {
      bool overrideRequested = false;
      StreamSubscription? sub;

      sub = _displayController.state.listen((state) {
        try {
          socket.sink.add(jsonEncode(state.toJson()));
        } catch (e, st) {
          log.severe('Failed to send display state', e, st);
        }
      });

      socket.stream.listen(
        (msg) {
          // Handle incoming commands over WebSocket
          try {
            final data = jsonDecode(msg as String) as Map<String, dynamic>;
            final command = data['command'] as String?;
            switch (command) {
              case 'dim':
                _displayController.dim();
                break;
              case 'restore':
                _displayController.restore();
                break;
              case 'requestWakeLock':
                overrideRequested = true;
                _displayController.requestWakeLock();
                break;
              case 'releaseWakeLock':
                overrideRequested = false;
                _displayController.releaseWakeLock();
                break;
            }
          } catch (e) {
            log.warning('Invalid WebSocket message: $e');
          }
        },
        onDone: () {
          sub?.cancel();
          // Auto-release wake-lock override when client disconnects
          if (overrideRequested) {
            log.info(
                'WebSocket client disconnected, releasing wake-lock override');
            _displayController.releaseWakeLock();
          }
        },
        onError: (e, _) {
          sub?.cancel();
          if (overrideRequested) {
            _displayController.releaseWakeLock();
          }
        },
      );
    })(req);
  }
}
