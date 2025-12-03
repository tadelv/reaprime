part of '../webserver_service.dart';

final class SensorsHandler {
  final SensorController _controller;
  final Logger _log = Logger("Sensor handler");

  SensorsHandler({required SensorController controller})
      : _controller = controller;

  void addRoutes(RouterPlus app) {
    app.get('/api/v1/sensors', (Request req) {
      final list = _controller.sensors.values.map((s) {
        final info = s.info;
        return {'id': s.deviceId, 'info': info.toJson()};
      }).toList();
      return Response.ok(jsonEncode(list));
    });

    app.get('/api/v1/sensors/<id>', (Request req, String id) async {
      final sensor = _controller.sensors[id];
      if (sensor == null) {
        return Response.notFound('not found');
      }
      return Response.ok(sensor.info.toJson());
    });

    app.get('/ws/v1/sensors/<id>/snapshot', (Request req) {
      final id = req.params['id']; // works for normal handlers
      return sws.webSocketHandler((socket) {
        final sensor = _controller.sensors[id];
        if (sensor == null) {
          socket.sink.add(jsonEncode({'error': 'not found'}));
          socket.sink.close();
          return;
        }

        final sub = sensor.data.listen(
          (snapshot) => socket.sink.add(jsonEncode(snapshot)),
          onError: (e, st) => log.severe('send error', e, st),
        );

        socket.stream.listen(
          (msg) {
            // handle incoming messages if needed
          },
          onDone: sub.cancel,
          onError: (_, __) => sub.cancel(),
        );
      })(req); // <-- don't forget to call the returned handler
    });

    app.post('/api/v1/sensors/<id>/execute', (Request req, String id) async {
      final sensor = _controller.sensors[id];
      if (sensor == null) {
        return Response.notFound('not found');
      }

      final body = await req.readAsString();
      final jsonBody = jsonDecode(body);
      final cmdId = jsonBody['commandId'] as String;
      final params = jsonBody['params'] as Map<String, dynamic>?;
      try {
        final res = await sensor.execute(cmdId, params);
        return Response.ok(jsonEncode({'status': 'ok', 'result': res}),
            headers: {'content-type': 'application/json'});
      } catch (e) {
        return Response.internalServerError(
            body: jsonEncode({'status': 'error', 'message': e.toString()}),
            headers: {'content-type': 'application/json'});
      }
    });
  }
}
