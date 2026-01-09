part of '../webserver_service.dart';

/// REST API handler for profile management operations
class ProfileHandler {
  final ProfileController _controller;

  ProfileHandler({required ProfileController controller})
    : _controller = controller;

  void addRoutes(RouterPlus app) {
    // Get all profiles
    app.get('/api/v1/profiles', _handleGetAll);

    // Get single profile by ID
    app.get('/api/v1/profiles/<id>', _handleGetById);

    // Create new profile
    app.post('/api/v1/profiles', _handleCreate);

    // Update existing profile
    app.put('/api/v1/profiles/<id>', _handleUpdate);

    // Delete profile
    app.delete('/api/v1/profiles/<id>', _handleDelete);

    // Change profile visibility
    app.put('/api/v1/profiles/<id>/visibility', _handleSetVisibility);

    // Get profile lineage (version history)
    app.get('/api/v1/profiles/<id>/lineage', _handleGetLineage);

    // Import profiles
    app.post('/api/v1/profiles/import', _handleImport);

    // Export profiles
    app.get('/api/v1/profiles/export', _handleExport);

    // Restore default profile
    app.post('/api/v1/profiles/restore/<filename>', _handleRestoreDefault);

    // Permanently purge a deleted profile
    app.delete('/api/v1/profiles/<id>/purge', _handlePurge);
  }

  /// GET /api/v1/profiles
  /// Query params: visibility, includeHidden, parentId
  Future<Response> _handleGetAll(Request request) async {
    try {
      final params = request.url.queryParameters;
      final visibilityParam = params['visibility'];
      final includeHidden = params['includeHidden'] == 'true';
      final parentId = params['parentId'];

      Visibility? visibility;
      if (visibilityParam != null) {
        try {
          visibility = VisibilityExtension.fromString(visibilityParam);
        } catch (e) {
          return Response.badRequest(
            body: jsonEncode({
              'error': 'Invalid visibility value',
              'message': 'Valid values: visible, hidden, deleted',
            }),
          );
        }
      }

      List<ProfileRecord> profiles;

      if (parentId != null) {
        // Get profiles by parent ID
        final allProfiles = await _controller.getAll(includeHidden: true);
        profiles = allProfiles.where((p) => p.parentId == parentId).toList();
      } else {
        // Get all profiles with optional filtering
        profiles = await _controller.getAll(
          visibility: visibility,
          includeHidden: includeHidden,
        );
      }

      return Response.ok(
        jsonEncode(profiles.map((p) => p.toJson()).toList()),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, st) {
      log.severe('Error in _handleGetAll', e, st);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error', 'message': '$e'}),
      );
    }
  }

  /// GET /api/v1/profiles/{id}
  Future<Response> _handleGetById(Request request, String id) async {
    try {
      final profile = await _controller.get(id);

      if (profile == null) {
        return Response.notFound(
          jsonEncode({'error': 'Profile not found', 'id': id}),
        );
      }

      return Response.ok(
        jsonEncode(profile.toJson()),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, st) {
      log.severe('Error in _handleGetById', e, st);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error', 'message': '$e'}),
      );
    }
  }

  /// POST /api/v1/profiles
  /// Body: { profile: {...}, parentId?: string, metadata?: {...} }
  Future<Response> _handleCreate(Request request) async {
    try {
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;

      if (!json.containsKey('profile')) {
        return Response.badRequest(
          body: jsonEncode({
            'error': 'Missing required field',
            'message': 'Request must contain "profile" field',
          }),
        );
      }

      final profile = Profile.fromJson(json['profile'] as Map<String, dynamic>);
      final parentId = json['parentId'] as String?;
      final metadata = json['metadata'] as Map<String, dynamic>?;

      final record = await _controller.create(
        profile: profile,
        parentId: parentId,
        metadata: metadata,
      );

      return Response(
        201,
        body: jsonEncode(record.toJson()),
        headers: {'Content-Type': 'application/json'},
      );
    } on ArgumentError catch (e) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Invalid request', 'message': '$e'}),
      );
    } catch (e, st) {
      log.severe('Error in _handleCreate', e, st);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error', 'message': '$e'}),
      );
    }
  }

  /// PUT /api/v1/profiles/{id}
  /// Body: { profile?: {...}, metadata?: {...} }
  Future<Response> _handleUpdate(Request request, String id) async {
    try {
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;

      Profile? profile;
      if (json.containsKey('profile')) {
        profile = Profile.fromJson(json['profile'] as Map<String, dynamic>);
      }

      final metadata = json['metadata'] as Map<String, dynamic>?;

      final record = await _controller.update(
        id,
        profile: profile,
        metadata: metadata,
      );

      return Response.ok(
        jsonEncode(record.toJson()),
        headers: {'Content-Type': 'application/json'},
      );
    } on ArgumentError catch (e) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Invalid request', 'message': '$e'}),
      );
    } catch (e, st) {
      log.severe('Error in _handleUpdate', e, st);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error', 'message': '$e'}),
      );
    }
  }

  /// DELETE /api/v1/profiles/{id}
  Future<Response> _handleDelete(Request request, String id) async {
    try {
      await _controller.delete(id);

      return Response.ok(
        jsonEncode({'success': true, 'message': 'Profile deleted', 'id': id}),
        headers: {'Content-Type': 'application/json'},
      );
    } on ArgumentError catch (e) {
      return Response.notFound(
        jsonEncode({'error': 'Not found', 'message': '$e'}),
      );
    } catch (e, st) {
      log.severe('Error in _handleDelete', e, st);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error', 'message': '$e'}),
      );
    }
  }

  /// PUT /api/v1/profiles/{id}/visibility
  /// Body: { visibility: "visible" | "hidden" | "deleted" }
  Future<Response> _handleSetVisibility(Request request, String id) async {
    try {
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;

      if (!json.containsKey('visibility')) {
        return Response.badRequest(
          body: jsonEncode({
            'error': 'Missing required field',
            'message': 'Request must contain "visibility" field',
          }),
        );
      }

      final visibilityStr = json['visibility'] as String;
      final visibility = VisibilityExtension.fromString(visibilityStr);

      final record = await _controller.setVisibility(id, visibility);

      return Response.ok(
        jsonEncode(record.toJson()),
        headers: {'Content-Type': 'application/json'},
      );
    } on ArgumentError catch (e) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Invalid request', 'message': '$e'}),
      );
    } catch (e, st) {
      log.severe('Error in _handleSetVisibility', e, st);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error', 'message': '$e'}),
      );
    }
  }

  /// GET /api/v1/profiles/{id}/lineage
  Future<Response> _handleGetLineage(Request request, String id) async {
    try {
      final lineage = await _controller.getLineage(id);

      if (lineage.isEmpty) {
        return Response.notFound(
          jsonEncode({'error': 'Profile not found', 'id': id}),
        );
      }

      return Response.ok(
        jsonEncode(lineage.map((p) => p.toJson()).toList()),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, st) {
      log.severe('Error in _handleGetLineage', e, st);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error', 'message': '$e'}),
      );
    }
  }

  /// POST /api/v1/profiles/import
  /// Body: [{ id, profile, ... }, ...]
  Future<Response> _handleImport(Request request) async {
    try {
      final body = await request.readAsString();
      final json = jsonDecode(body);

      if (json is! List) {
        return Response.badRequest(
          body: jsonEncode({
            'error': 'Invalid request',
            'message': 'Request body must be an array of profile records',
          }),
        );
      }

      final profilesJson = json.cast<Map<String, dynamic>>();
      final result = await _controller.importProfiles(profilesJson);

      return Response.ok(
        jsonEncode(result),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, st) {
      log.severe('Error in _handleImport', e, st);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error', 'message': '$e'}),
      );
    }
  }

  /// GET /api/v1/profiles/export
  /// Query params: includeHidden, includeDeleted
  Future<Response> _handleExport(Request request) async {
    try {
      final params = request.url.queryParameters;
      final includeHidden = params['includeHidden'] == 'true';
      final includeDeleted = params['includeDeleted'] == 'true';

      final profiles = await _controller.exportProfiles(
        includeHidden: includeHidden,
        includeDeleted: includeDeleted,
      );

      return Response.ok(
        jsonEncode(profiles),
        headers: {
          'Content-Type': 'application/json',
          'Content-Disposition': 'attachment; filename="profiles_export.json"',
        },
      );
    } catch (e, st) {
      log.severe('Error in _handleExport', e, st);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error', 'message': '$e'}),
      );
    }
  }

  /// POST /api/v1/profiles/restore/{filename}
  Future<Response> _handleRestoreDefault(
    Request request,
    String filename,
  ) async {
    try {
      final record = await _controller.restoreDefault(filename);

      return Response.ok(
        jsonEncode(record.toJson()),
        headers: {'Content-Type': 'application/json'},
      );
    } on ArgumentError catch (e) {
      return Response.notFound(
        jsonEncode({'error': 'Not found', 'message': '$e'}),
      );
    } catch (e, st) {
      log.severe('Error in _handleRestoreDefault', e, st);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error', 'message': '$e'}),
      );
    }
  }

  /// DELETE /api/v1/profiles/{id}/purge
  Future<Response> _handlePurge(Request request, String id) async {
    try {
      await _controller.purge(id);

      return Response.ok(
        jsonEncode({
          'success': true,
          'message': 'Profile permanently deleted',
          'id': id,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } on ArgumentError catch (e) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Invalid request', 'message': '$e'}),
      );
    } catch (e, st) {
      log.severe('Error in _handlePurge', e, st);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error', 'message': '$e'}),
      );
    }
  }
}

