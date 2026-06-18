part of '../webserver_service.dart';

final class KvStoreHandler {
  final store = HiveStoreService(defaultNamespace: "kvStore");

  void addRoutes(RouterPlus app) {
    app.get('/api/v1/store/<namespace>', (Request req) async {
      final namespace = req.params['namespace'];
      if (namespace == null) {
        return jsonBadRequest({'error': 'Missing namespace'});
      }
      // `?full=1` returns the whole namespace as a {key: value} map so a client
      // can fetch (or poll) everything in one request instead of one GET per
      // key. ETag/If-None-Match (via jsonOkConditional) lets a poll come back
      // 304 when nothing changed. Without the flag we return just the key list.
      if (req.url.queryParameters['full'] == '1') {
        return jsonOkConditional(req, await store.getAll(namespace: namespace));
      }
      return jsonOk(await store.keys(namespace: namespace));
    });

    app.get('/api/v1/store/<namespace>/<key>', (Request req) async {
      final namespace = req.params['namespace'];
      final key = req.params['key'];
      if (namespace == null || key == null) {
        return jsonBadRequest({'error': 'Missing namespace or key'});
      }
      return jsonOk(await store.get(namespace: namespace, key: key));
    });

    app.delete('/api/v1/store/<namespace>/<key>', (Request req) async {
      final namespace = req.params['namespace'];
      final key = req.params['key'];
      if (namespace == null || key == null) {
        return jsonBadRequest({'error': 'Missing namespace or key'});
      }
      await store.delete(key: key, namespace: namespace);
      return jsonOk({});
    });

    app.post('/api/v1/store/<namespace>/<key>', (Request req) async {
      final namespace = req.params['namespace'];
      final key = req.params['key'];
      final value = await req.readAsString();
      final maybeJson = jsonDecode(value);
      if (namespace == null || key == null) {
        return jsonBadRequest({'error': 'Missing namespace or key'});
      }
      await store.set(
        key: key,
        value: maybeJson ?? value,
        namespace: namespace,
      );
      return jsonOk({});
    });
  }
}
