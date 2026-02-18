import 'dart:convert';
import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/persistence_controller.dart';
import 'package:reaprime/src/models/data/shot_record.dart';
import 'package:reaprime/src/services/webserver/json_response.dart';
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
      return jsonBadRequest({"error": "Invalid orderBy value. Supported: timestamp"});
    }

    final order = req.url.queryParameters['order'] ?? 'desc';
    if (order != 'asc' && order != 'desc') {
      return jsonBadRequest({"error": "Invalid order value. Supported: asc, desc"});
    }

    shots.sort((a, b) => order == 'asc'
        ? a.timestamp.compareTo(b.timestamp)
        : b.timestamp.compareTo(a.timestamp));

    final shotObjects = shots.map((e) => e.toJson()).toList();
    return jsonOk(shotObjects);
  }

  Future<Response> _getIds(Request req) async {
    List<ShotRecord> shots = await _controller.shots.first;

    final orderBy = req.url.queryParameters['orderBy'];
    if (orderBy != null && orderBy != 'timestamp') {
      return jsonBadRequest({"error": "Invalid orderBy value. Supported: timestamp"});
    }

    final order = req.url.queryParameters['order'] ?? 'desc';
    if (order != 'asc' && order != 'desc') {
      return jsonBadRequest({"error": "Invalid order value. Supported: asc, desc"});
    }

    shots.sort((a, b) => order == 'asc'
        ? a.timestamp.compareTo(b.timestamp)
        : b.timestamp.compareTo(a.timestamp));

    final ids = shots.map((e) => e.id);
    return jsonOk(ids.toList());
  }

  Future<Response> _getLatestShot(Request req) async {
    List<ShotRecord> shots = await _controller.shots.first;
    return jsonOk(shots.firstOrNull?.toJson());
  }

  Future<Response> _getShot(Request req, String id) async {
    id = Uri.decodeComponent(id);
    try {
      final shot = await _controller.storageService.getShot(id);
      if (shot == null) {
        return jsonNotFound({"error": "Shot not found"});
      }
      return jsonOk(shot.toJson());
    } catch (e, st) {
      _log.severe("Error getting shot $id", e, st);
      return jsonError({"error": e.toString()});
    }
  }

  Future<Response> _updateShot(Request req, String id) async {
    id = Uri.decodeComponent(id);
    try {
      final body = await req.body.asString;
      final json = jsonDecode(body) as Map<String, dynamic>;

      // Validate that the ID in the path matches the ID in the body (if provided)
      if (json['id'] != null && json['id'] != id) {
        return jsonBadRequest({"error": "ID in path does not match ID in body"});
      }

      // Fetch existing shot for partial update support
      final existingShot = await _controller.storageService.getShot(id);
      if (existingShot == null) {
        return jsonNotFound({"error": "Shot not found"});
      }

      // Deep merge partial payload onto existing shot data
      final merged = _deepMerge(existingShot.toJson(), json);
      merged['id'] = id;

      final updatedShot = ShotRecord.fromJson(merged);
      await _controller.updateShot(updatedShot);

      return jsonOk(updatedShot.toJson());
    } catch (e, st) {
      _log.severe("Error updating shot $id", e, st);
      return jsonError({"error": e.toString()});
    }
  }

  Future<Response> _deleteShot(Request req, String id) async {
    id = Uri.decodeComponent(id);
    try {
      await _controller.deleteShot(id);
      return jsonOk({"success": true, "id": id});
    } catch (e, st) {
      _log.severe("Error deleting shot $id", e, st);
      if (e.toString().contains("not found")) {
        return jsonNotFound({"error": "Shot not found"});
      }
      return jsonError({"error": e.toString()});
    }
  }

  Map<String, dynamic> _deepMerge(
    Map<String, dynamic> base,
    Map<String, dynamic> overrides,
  ) {
    final result = Map<String, dynamic>.from(base);
    for (final key in overrides.keys) {
      final baseValue = result[key];
      final overrideValue = overrides[key];
      if (baseValue is Map<String, dynamic> &&
          overrideValue is Map<String, dynamic>) {
        result[key] = _deepMerge(baseValue, overrideValue);
      } else {
        result[key] = overrideValue;
      }
    }
    return result;
  }
}
