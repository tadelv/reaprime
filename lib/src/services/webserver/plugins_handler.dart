part of '../webserver_service.dart';

final class PluginsHandler {
  final PluginManager pluginManager;
  final PluginLoaderService pluginService;

  final Logger _log = Logger("PluginsHandler");

  PluginsHandler({required this.pluginManager, required this.pluginService});

  void addRoutes(RouterPlus app) {
    app.get('/api/v1/plugins', (Request req) {
      final list =
          pluginManager.loadedPlugins.map((e) => e.manifest.toJson()).toList();
      return Response.ok(jsonEncode(list));
    });

    app.get('/api/v1/plugins/<id>/settings', _handlePluginSettingsGet);
    app.post('/api/v1/plugins/<id>/settings', _handlePluginSettingsPost);

    app.get('/ws/v1/plugins/<id>/<endpoint>', _handlePluginSocketEndpoint);
    app.get('/api/v1/plugins/<id>/<endpoint>', _handlePluginApiEndpoint);

  }

  Future<Response> _handlePluginSocketEndpoint(Request req) async {
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

  Future<Response> _handlePluginApiEndpoint(Request req) async {
    _log.info("handling $req");

    final id = req.params['id'];
    final endpoint = req.params['endpoint'];

    if (id == null || endpoint == null) {
      return Response.badRequest(body: "id and endpoint required");
    }
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
    if (apiEndpoint.type != ApiEndpointType.http) {
      return Response.badRequest(
        body: {'error': 'endpoint $endpoint is not a http type'},
      );
    }

    final body = await req.readAsString();
    try {
      final payload = jsonDecode(body);
      pluginManager.dispatchEvent(id, 'api', {
        'endpoint': endpoint,
        ...payload,
      });
      return Response.ok({});
    } catch (e) {
      _log.warning("invalid payload", e);
      return Response.badRequest(body: "body must be json");
    }
  }

  Future<Response> _extractPluginId(
    Request req,
    Future<Response> Function(Request, String) call,
  ) async {
    final id = req.params['id'];
    if (id == null) {
      return Response.badRequest(body: "plugin id is required");
    }
    return call(req, id);
  }

  Future<Response> _handlePluginSettingsGet(Request req) async {
    return _extractPluginId(req, (r, id) async {
      final settings = await pluginService.pluginSettings(id);
      return Response.ok(jsonEncode(settings));
    });
  }

  Future<Response> _handlePluginSettingsPost(Request req) async {
    return _extractPluginId(req, (req, id) async {
      final body = await req.readAsString();
      final json = await jsonDecode(body);
      await pluginService.savePluginSettings(id, json);
      return Response.ok(body);
    });
  }
}
