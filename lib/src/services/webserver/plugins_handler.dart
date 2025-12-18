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
    // if (manifest.api?.endpoints.contains(endpoint) == false) {
    //   return Response.notFound('endpoint $endpoint not available');
    // }
    //
    //
    return sws.webSocketHandler((socket) {
      final sub = pluginManager.emitStream
          .where((e) {
            return e['id'] == id && e['event'] == endpoint;
          })
          .listen((data) {
            socket.sink.add(jsonEncode(data['payload']));
          });
      socket.stream.listen(
        (msg) {
          // handle incoming messages if needed
        },
        onDone: sub.cancel,
        onError: (_, _) => sub.cancel(),
      );
    })(req);
  }
}
