part of '../webserver_service.dart';

final class PluginsHandler {
  final PluginManager pluginManager;
  final Logger _log = Logger("PluginsHandler");

  PluginsHandler({required this.pluginManager});

  void addRoutes(RouterPlus app) {
    app.get('/api/v1/plugins', (Request req) {
      final list =
          pluginManager.loadedPlugins.map((e) => e.manifest.toJson()).toList();
      return Response.ok(jsonEncode(list));
    });

    app.get('/ws/v1/plugins/<id>/<endpoint>', _handlePluginEndpoint);
  }

  Future<Response> _handlePluginEndpoint(Request req) async {
    _log.info("handling $req");
    final id = req.params['id'];
    final endpoint = req.params['endpoint'];
    final manifest =
        pluginManager.loadedPlugins
            .firstWhereOrNull((e) => e.pluginId == id)
            ?.manifest;
    if (manifest == null) {
      return Response.notFound('plugin with $id not loaded');
    }
    final apiEndpoint = manifest.api?.endpoints.firstWhereOrNull(
      (e) => e.id == endpoint,
    );
    if (apiEndpoint == null) {
      return Response.notFound('endpoint $endpoint not available');
    }
    if (apiEndpoint.type != ApiEndpointType.websocket) {
      return Response.badRequest(
        body: {'error': 'endpoint $endpoint is not a websocket type'},
      );
    }

    return sws.webSocketHandler((WebSocketChannel socket) {
      StreamSubscription<Map<String, dynamic>>? sub;
      sub = pluginManager.emitStream
          .where((e) {
            return e['pluginId'] == id && e['event'] == endpoint;
          })
          .listen(
            (data) {
              socket.sink.add(jsonEncode(data['payload']));
            },
            onDone: () {
              socket.sink.close();
              sub?.cancel();
            },
            onError: (e) {
              _log.warning("plugin $id listen errored out:", e);
              sub?.cancel();
            },
          );
      socket.stream.listen(
        (msg) {
          // handle incoming messages if needed
        },
        onDone: () {
          sub?.cancel();
        },
        onError: (e, _) {
          sub?.cancel();
          _log.warning("socket connection error: ", e);
        },
      );
    })(req);
  }
}
