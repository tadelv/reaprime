part of '../webserver_service.dart';

class SettingsHandler {
  final SettingsController _controller;
  final WebUIService _webUIService;

  SettingsHandler({required SettingsController controller, required WebUIService service})
    : _controller = controller, _webUIService = service;

  void addRoutes(RouterPlus app) {
    app.get('/api/v1/settings', () async {
      log.info("handling settings");
      final gatewayMode = _controller.gatewayMode.name;
      final webPath = _webUIService.serverPath();
      final logLevel = _controller.logLevel;
      return {
        'gatewayMode': gatewayMode,
        'webUiPath': webPath,
        'logLevel': logLevel,
      };
    });
    app.post('/api/v1/settings', (Request request) async {
      final payload = await request.readAsString();
      Map<String, dynamic> json = jsonDecode(payload);
      if (json.containsKey('gatewayMode')) {
        final GatewayMode? gatewayMode = GatewayModeFromString.fromString(
          json['gatewayMode'],
        );
        if (gatewayMode == null) {
          return Response.badRequest(
            body: {'message': '${json["gatewayMode"]} is not a gateway mode'},
          );
        }
        await _controller.updateGatewayMode(gatewayMode);
      }
      if (json.containsKey('webUiPath')) {
        final webUiPath = json['webUiPath'].toString();
        // Check path is valid
        final _ = File.fromUri(Uri.file(webUiPath));
        await _webUIService.serveFolderAtPath(webUiPath);
      }
      if (json.containsKey('logLevel')) {
        await _controller.updateLogLevel(json['logLevel']);
      }
      return Response.ok('');
    });

    // Adding logs here, even though they aren't part of Settings
    app.get('/ws/v1/logs', _handleLogsRequest);
  }

  Future<Response> _handleLogsRequest(Request req) async {
    return sws.webSocketHandler((WebSocketChannel socket) {
      StreamSubscription? sub;
      sub = Logger.root.onRecord.listen((logRecord) {
        socket.sink.add(
          jsonEncode({
            'level': logRecord.level.name,
            'timestamp': logRecord.time.toIso8601String(),
            'name': logRecord.loggerName,
            'message': logRecord.message,
          }),
        );
      });
      socket.stream.listen(
        (msg) {
          // handle incoming messages if needed
        },
        onDone: () {
          sub?.cancel();
        },
        onError: (e, _) {
          sub?.cancel();
        },
      );
    })(req);
  }
}
