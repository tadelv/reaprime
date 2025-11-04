part of '../webserver_service.dart';

class SettingsHandler {
  final SettingsController _controller;

  SettingsHandler({required SettingsController controller})
    : _controller = controller;

  void addRoutes(RouterPlus app) {
    app.get('/api/v1/settings', () async {
      log.info("handling settings");
      final gatewayMode = _controller.gatewayMode.name;
      final webPath = WebUIService.serverPath();
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
        await WebUIService.serveFolderAtPath(webUiPath);
      }
      if (json.containsKey('logLevel')) {
        await _controller.updateLogLevel(json['logLevel']);
      }
      return Response.ok('');
    });
  }
}
