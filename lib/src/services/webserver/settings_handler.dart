part of '../webserver_service.dart';

class SettingsHandler {
  final SettingsController _controller;

  SettingsHandler({required SettingsController controller})
      : _controller = controller;

  void addRoutes(RouterPlus app) {
    app.get('/api/v1/settings', () async {
      log.info("handling settings");
      final gatewayMode = _controller.bypassShotController;
      return {
        'gatewayMode': gatewayMode,
      };
    });
    app.post('/api/v1/settings', (Request request) async {
      final payload = await request.readAsString();
      Map<String, dynamic> json = jsonDecode(payload);
      if (json.containsKey('gatewayMode')) {
        final bool gatewayMode = json['gatewayMode'];
        await _controller.updateBypassShotController(gatewayMode);
        return Response.ok('');
      }
      return Response.badRequest();
    });
  }
}
