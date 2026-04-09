part of '../webserver_service.dart';

final class PluginsHandler {
  final PluginManager pluginManager;
  final PluginLoaderService pluginService;

  final Logger _log = Logger("PluginsHandler");

  final Random _random = Random();

  PluginsHandler({required this.pluginManager, required this.pluginService});

  void addRoutes(RouterPlus app) {
    app.get('/api/v1/plugins', (Request req) async {
      final list = <Map<String, dynamic>>[];
      for (final manifest in pluginService.availablePlugins) {
        final json = manifest.toJson();
        json['loaded'] = pluginService.isPluginLoaded(manifest.id);
        json['autoLoad'] = await pluginService.shouldAutoLoad(manifest.id);
        list.add(json);
      }
      return Response.ok(jsonEncode(list),
          headers: {'Content-Type': 'application/json'});
    });

    app.post('/api/v1/plugins/install', (Request request) async {
      try {
        final payload = await request.readAsString();
        final json = jsonDecode(payload) as Map<String, dynamic>;
        final url = json['url'] as String?;
        if (url == null || url.isEmpty) {
          return Response.badRequest(
              body: jsonEncode({'error': 'url is required'}),
              headers: {'Content-Type': 'application/json'});
        }
        // Plugin install from URL not yet implemented
        return Response(501,
            body: jsonEncode(
                {'error': 'Plugin install from URL not yet implemented'}),
            headers: {'Content-Type': 'application/json'});
      } catch (e) {
        return Response.internalServerError(
            body: jsonEncode({'error': 'Failed to install plugin: $e'}),
            headers: {'Content-Type': 'application/json'});
      }
    });

    app.get('/api/v1/plugins/<id>/settings', _handlePluginSettingsGet);
    app.post('/api/v1/plugins/<id>/settings', _handlePluginSettingsPost);

    app.post('/api/v1/plugins/<id>/enable',
        (Request request, String id) async {
      try {
        if (!pluginService.isPluginLoaded(id)) {
          await pluginService.loadPlugin(id);
        }
        await pluginService.setPluginAutoLoad(id, true);
        return Response.ok(
            jsonEncode({'message': 'Plugin enabled', 'id': id}),
            headers: {'Content-Type': 'application/json'});
      } catch (e) {
        return Response.internalServerError(
            body: jsonEncode({'error': 'Failed to enable plugin: $e'}),
            headers: {'Content-Type': 'application/json'});
      }
    });

    app.post('/api/v1/plugins/<id>/disable',
        (Request request, String id) async {
      try {
        if (pluginService.isPluginLoaded(id)) {
          await pluginService.unloadPlugin(id);
        }
        await pluginService.setPluginAutoLoad(id, false);
        return Response.ok(
            jsonEncode({'message': 'Plugin disabled', 'id': id}),
            headers: {'Content-Type': 'application/json'});
      } catch (e) {
        return Response.internalServerError(
            body: jsonEncode({'error': 'Failed to disable plugin: $e'}),
            headers: {'Content-Type': 'application/json'});
      }
    });

    app.delete('/api/v1/plugins/<id>', (Request request, String id) async {
      try {
        await pluginService.removePlugin(id);
        return Response.ok(
            jsonEncode({'message': 'Plugin removed', 'id': id}),
            headers: {'Content-Type': 'application/json'});
      } catch (e) {
        return Response.internalServerError(
            body: jsonEncode({'error': 'Failed to remove plugin: $e'}),
            headers: {'Content-Type': 'application/json'});
      }
    });

    app.get('/ws/v1/plugins/<id>/<endpoint>', _handlePluginSocketEndpoint);
    app.all('/api/v1/plugins/<id>/<endpoint>', _handlePluginApiEndpoint);
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

    return sws.webSocketHandler((WebSocketChannel socket, String? protocol) {
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
    _log.info("handling ${req.toString()}");

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

    // Read request details
    final method = req.method;
    final headers = <String, String>{};
    req.headers.forEach((name, values) {
      headers[name] = values;
    });

    final body = await req.readAsString();

    // Generate a unique request ID
    final requestId =
        '${id}_${endpoint}_${DateTime.now().millisecondsSinceEpoch}_${_random.nextInt(100000)}';

    try {
      // Prepare the request data to send to the plugin
      final requestData = {
        'requestId': requestId,
        'endpoint': endpoint,
        'method': method,
        'headers': headers,
        'body': body.isNotEmpty ? jsonDecode(body) : null,
        'query': req.url.queryParameters,
      };

      // Dispatch the event to the plugin
      pluginManager.dispatchEvent(id, 'httpRequest', requestData);

      // Wait for the plugin's response (with timeout)
      final response = await _waitForPluginResponse(requestId);

      if (response == null) {
        return Response.internalServerError(
          body: 'Plugin did not respond in time',
        );
      }

      // Parse the plugin's response
      final status = response['status'] as int? ?? 200;
      final responseHeaders = (response['headers'] as Map<String, dynamic>? ??
              {})
          .map((k, v) => MapEntry(k, v.toString()));
      final responseBody = response['body'];

      // Send the response back to the client
      return Response(status, body: responseBody, headers: responseHeaders);
    } catch (e) {
      _log.warning("Error handling HTTP request for plugin $id", e);
      return Response.internalServerError(
        body: "Error processing request: ${e.toString()}",
      );
    }
  }

  Future<Map<String, dynamic>?> _waitForPluginResponse(String requestId) async {
    final Completer<Map<String, dynamic>?> completer = Completer();
    final stopwatch = Stopwatch()..start();

    // Check every 100ms for up to 30 seconds
    Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (stopwatch.elapsed > const Duration(seconds: 30)) {
        timer.cancel();
        completer.complete(null);
        return;
      }

      // Check if the plugin has responded
      final response = pluginManager.getPendingHttpResponse(requestId);
      if (response != null) {
        timer.cancel();
        completer.complete(response);
      }
    });

    return completer.future;
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
      try {
        await pluginService.savePluginSettings(id, json);
      } on PluginSettingsValidationException catch (e) {
        return Response.badRequest(
          body: jsonEncode({'error': e.message}),
          headers: {'content-type': 'application/json'},
        );
      }
      await pluginService.reloadPlugin(id);
      return Response.ok(body);
    });
  }
}
