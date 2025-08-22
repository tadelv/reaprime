import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/sensor_controller.dart';
import 'package:shelf_plus/shelf_plus.dart';

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
  }
}
