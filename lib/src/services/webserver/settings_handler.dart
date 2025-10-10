part of '../webserver_service.dart';

class SettingsHandler {
  final SettingsController _controller;

  SettingsHandler({required SettingsController controller})
      : _controller = controller;

  void addRoutes(RouterPlus app) {
    app.get('/api/v1/settings', () async {
      log.info("handling settings");
      final gatewayMode = _controller.gatewayMode.name;
      return {
        'gatewayMode': gatewayMode,
      };
    });
    app.post('/api/v1/settings', (Request request) async {
      final payload = await request.readAsString();
      Map<String, dynamic> json = jsonDecode(payload);
      if (json.containsKey('gatewayMode')) {
        final GatewayMode? gatewayMode =
            GatewayModeFromString.fromString(json['gatewayMode']);
        if (gatewayMode == null) {
          return Response.badRequest(body: {
            'message': '${json["gatewayMode"]} is not a gateway mode'
          });
        }
        await _controller.updateGatewayMode(gatewayMode);
        return Response.ok('');
      }
      return Response.badRequest();
    });
  }
}
