import 'dart:convert';
import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/persistence_controller.dart';
import 'package:reaprime/src/models/data/shot_record.dart';
import 'package:shelf_plus/shelf_plus.dart';

class ShotsHandler {
  final PersistenceController _controller;

  final Logger _log = Logger("ShotsHandler");

  ShotsHandler({required PersistenceController controller})
    : _controller = controller;

  void addRoutes(RouterPlus app) {
    app.get('/api/v1/shots', _getShots);
    app.get('/api/v1/shots/ids', _getIds);
    app.get('/api/v1/shots/latest', _getLatestShot);
  }

  Future<Response> _getShots(Request req) async {
    // TODO: pagination required

    _log.fine('params: ${req.url.queryParametersAll}');
    List<ShotRecord> shots = await _controller.shots.first;
    var ids = req.url.queryParametersAll['ids'];
    if (ids != null) {
      shots =
          shots.where((e) {
            return ids.contains(e.id);
          }).toList();
    }
    final shotObjects = shots.map((e) => e.toJson()).toList();
    return Response.ok(jsonEncode(shotObjects));
  }

  Future<Response> _getIds(Request req) async {
    List<ShotRecord> shots = await _controller.shots.first;
    final ids = shots.map((e) => e.id);
    return Response.ok(jsonEncode(ids.toList()));
  }

  Future<Response> _getLatestShot(Request req) async {
    List<ShotRecord> shots = await _controller.shots.first;
    return Response.ok(jsonEncode(shots.lastOrNull?.toJson()));
  }
}
