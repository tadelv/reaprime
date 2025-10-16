import 'dart:convert';
import 'package:reaprime/src/controllers/persistence_controller.dart';
import 'package:shelf_plus/shelf_plus.dart';

class ShotsHandler {
  final PersistenceController _controller;

  ShotsHandler({required PersistenceController controller})
    : _controller = controller;

  void addRoutes(RouterPlus app) {
    app.get('/api/v1/shots', _getShots);
  }

  Future<Response> _getShots(Request req) async {
    // TODO: pagination required
    final shots = await _controller.shots.first;
    final shotObjects = shots.map((e) => e.toJson()).toList();
    return Response.ok(jsonEncode(shotObjects));
  }
}
