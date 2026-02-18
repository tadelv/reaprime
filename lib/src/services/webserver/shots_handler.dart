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
    app.get('/api/v1/shots/<id>', _getShot);
    app.put('/api/v1/shots/<id>', _updateShot);
    app.delete('/api/v1/shots/<id>', _deleteShot);
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

    final orderBy = req.url.queryParameters['orderBy'];
    if (orderBy != null && orderBy != 'timestamp') {
      return Response.badRequest(
        body: jsonEncode({"error": "Invalid orderBy value. Supported: timestamp"}),
      );
    }

    final order = req.url.queryParameters['order'] ?? 'desc';
    if (order != 'asc' && order != 'desc') {
      return Response.badRequest(
        body: jsonEncode({"error": "Invalid order value. Supported: asc, desc"}),
      );
    }

    shots.sort((a, b) => order == 'asc'
        ? a.timestamp.compareTo(b.timestamp)
        : b.timestamp.compareTo(a.timestamp));

    final shotObjects = shots.map((e) => e.toJson()).toList();
    return Response.ok(jsonEncode(shotObjects));
  }

  Future<Response> _getIds(Request req) async {
    List<ShotRecord> shots = await _controller.shots.first;

    final orderBy = req.url.queryParameters['orderBy'];
    if (orderBy != null && orderBy != 'timestamp') {
      return Response.badRequest(
        body: jsonEncode({"error": "Invalid orderBy value. Supported: timestamp"}),
      );
    }

    final order = req.url.queryParameters['order'] ?? 'desc';
    if (order != 'asc' && order != 'desc') {
      return Response.badRequest(
        body: jsonEncode({"error": "Invalid order value. Supported: asc, desc"}),
      );
    }

    shots.sort((a, b) => order == 'asc'
        ? a.timestamp.compareTo(b.timestamp)
        : b.timestamp.compareTo(a.timestamp));

    final ids = shots.map((e) => e.id);
    return Response.ok(jsonEncode(ids.toList()));
  }

  Future<Response> _getLatestShot(Request req) async {
    List<ShotRecord> shots = await _controller.shots.first;
    return Response.ok(jsonEncode(shots.lastOrNull?.toJson()));
  }

  Future<Response> _getShot(Request req, String id) async {
    id = Uri.decodeComponent(id);
    try {
      final shot = await _controller.storageService.getShot(id);
      if (shot == null) {
        return Response.notFound(jsonEncode({"error": "Shot not found"}));
      }
      return Response.ok(jsonEncode(shot.toJson()));
    } catch (e, st) {
      _log.severe("Error getting shot $id", e, st);
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
      );
    }
  }

  Future<Response> _updateShot(Request req, String id) async {
    id = Uri.decodeComponent(id);
    try {
      final body = await req.body.asString;
      final json = jsonDecode(body) as Map<String, dynamic>;
      
      // Validate that the ID in the path matches the ID in the body (if provided)
      if (json['id'] != null && json['id'] != id) {
        return Response.badRequest(
          body: jsonEncode({"error": "ID in path does not match ID in body"}),
        );
      }
      
      // Ensure ID is set in the JSON
      json['id'] = id;
      
      final updatedShot = ShotRecord.fromJson(json);
      await _controller.updateShot(updatedShot);
      
      return Response.ok(jsonEncode(updatedShot.toJson()));
    } catch (e, st) {
      _log.severe("Error updating shot $id", e, st);
      if (e.toString().contains("not found")) {
        return Response.notFound(jsonEncode({"error": "Shot not found"}));
      }
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
      );
    }
  }

  Future<Response> _deleteShot(Request req, String id) async {
    id = Uri.decodeComponent(id);
    try {
      await _controller.deleteShot(id);
      return Response.ok(jsonEncode({"success": true, "id": id}));
    } catch (e, st) {
      _log.severe("Error deleting shot $id", e, st);
      if (e.toString().contains("not found")) {
        return Response.notFound(jsonEncode({"error": "Shot not found"}));
      }
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
      );
    }
  }
}


