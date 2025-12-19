part of '../webserver_service.dart';

final class KvStoreHandler {
  final store = HiveStoreService(defaultNamespace: "kvStore");

  void addRoutes(RouterPlus app) {
    app.get('/api/v1/store/<namespace>', (Request req) async {
      final namespace = req.params['namespace'];
      if (namespace == null) {
        return Response.badRequest();
      }
      return Response.ok(jsonEncode(await store.keys(namespace: namespace)));
    });

    app.get('/api/v1/store/<namespace>/<key>', (Request req) async {
      final namespace = req.params['namespace'];
      final key = req.params['key'];
      if (namespace == null || key == null) {
        return Response.badRequest();
      }
      return Response.ok(
        jsonEncode(await store.get(namespace: namespace, key: key)),
      );
    });

    app.delete('/api/v1/store/<namespace>/<key>', (Request req) async {
      final namespace = req.params['namespace'];
      final key = req.params['key'];
      if (namespace == null || key == null) {
        return Response.badRequest();
      }
      await store.delete(key: key, namespace: namespace);
      return Response.ok("{}");
    });

    app.post('/api/v1/store/<namespace>/<key>', (Request req) async {
      final namespace = req.params['namespace'];
      final key = req.params['key'];
      final value = await req.readAsString();
      final maybeJson = jsonDecode(value);
      if (namespace == null || key == null) {
        return Response.badRequest();
      }
      await store.set(
        key: key,
        value: maybeJson ?? value,
        namespace: namespace,
      );
      return Response.ok("{}");
    });
  }
}
