part of '../webserver_service.dart';

/// REST API handler for WebUI skin management
class WebUIHandler {
  final WebUIStorage _storage;

  WebUIHandler({required WebUIStorage storage}) : _storage = storage;

  void addRoutes(RouterPlus app) {
    // List all installed skins
    app.get('/api/v1/webui/skins', _handleListSkins);

    // Get specific skin details
    app.get('/api/v1/webui/skins/<id>', _handleGetSkin);

    // Get default skin
    app.get('/api/v1/webui/skins/default', _handleGetDefaultSkin);

    // Install skin from GitHub release
    app.post('/api/v1/webui/skins/install/github-release', _handleInstallFromGitHubRelease);

    // Install skin from GitHub branch
    app.post('/api/v1/webui/skins/install/github-branch', _handleInstallFromGitHubBranch);

    // Install skin from URL
    app.post('/api/v1/webui/skins/install/url', _handleInstallFromUrl);

    // Remove/uninstall skin
    app.delete('/api/v1/webui/skins/<id>', _handleRemoveSkin);
  }

  /// GET /api/v1/webui/skins
  /// List all installed skins
  Future<Response> _handleListSkins(Request request) async {
    try {
      final skins = _storage.installedSkins;

      return Response.ok(
        jsonEncode(skins.map((skin) => skin.toJson()).toList()),
      );
    } catch (e, st) {
      log.severe('Failed to list skins', e, st);
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }

  /// GET /api/v1/webui/skins/{id}
  /// Get specific skin details
  Future<Response> _handleGetSkin(Request request, String id) async {
    try {
      final skin = _storage.getSkin(id);

      if (skin == null) {
        return Response.notFound(
          jsonEncode({'error': 'Skin not found: $id'}),
        );
      }

      return Response.ok(
        jsonEncode(skin.toJson()),
      );
    } catch (e, st) {
      log.severe('Failed to get skin: $id', e, st);
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }

  /// GET /api/v1/webui/skins/default
  /// Get the default skin
  Future<Response> _handleGetDefaultSkin(Request request) async {
    try {
      final defaultSkin = _storage.defaultSkin;

      if (defaultSkin == null) {
        return Response.notFound(
          jsonEncode({'error': 'No default skin available'}),
        );
      }

      return Response.ok(
        jsonEncode(defaultSkin.toJson()),
      );
    } catch (e, st) {
      log.severe('Failed to get default skin', e, st);
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }

  /// POST /api/v1/webui/skins/install/github-release
  /// Install skin from GitHub release
  /// 
  /// Body:
  /// {
  ///   "repo": "username/repo",
  ///   "asset": "skin.zip",       // optional
  ///   "prerelease": false         // optional
  /// }
  Future<Response> _handleInstallFromGitHubRelease(Request request) async {
    try {
      final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final repo = body['repo'] as String?;

      if (repo == null || repo.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing required field: repo'}),
        );
      }

      final asset = body['asset'] as String?;
      final prerelease = body['prerelease'] as bool? ?? false;

      log.info('Installing skin from GitHub release: $repo');

      await _storage.installFromGitHubRelease(
        repo,
        assetName: asset,
        includePrerelease: prerelease,
      );

      return Response.ok(
        jsonEncode({
          'success': true,
          'message': 'Skin installed successfully from GitHub release',
          'repo': repo,
        }),
      );
    } catch (e, st) {
      log.severe('Failed to install skin from GitHub release', e, st);
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }

  /// POST /api/v1/webui/skins/install/github-branch
  /// Install skin from GitHub branch
  /// 
  /// Body:
  /// {
  ///   "repo": "username/repo",
  ///   "branch": "main"            // optional, defaults to "main"
  /// }
  Future<Response> _handleInstallFromGitHubBranch(Request request) async {
    try {
      final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final repo = body['repo'] as String?;

      if (repo == null || repo.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing required field: repo'}),
        );
      }

      final branch = body['branch'] as String? ?? 'main';

      log.info('Installing skin from GitHub branch: $repo/$branch');

      await _storage.installFromGitHub(repo, branch: branch);

      return Response.ok(
        jsonEncode({
          'success': true,
          'message': 'Skin installed successfully from GitHub branch',
          'repo': repo,
          'branch': branch,
        }),
      );
    } catch (e, st) {
      log.severe('Failed to install skin from GitHub branch', e, st);
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }

  /// POST /api/v1/webui/skins/install/url
  /// Install skin from direct URL
  /// 
  /// Body:
  /// {
  ///   "url": "https://example.com/skin.zip"
  /// }
  Future<Response> _handleInstallFromUrl(Request request) async {
    try {
      final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final url = body['url'] as String?;

      if (url == null || url.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing required field: url'}),
        );
      }

      log.info('Installing skin from URL: $url');

      await _storage.installFromUrl(url);

      return Response.ok(
        jsonEncode({
          'success': true,
          'message': 'Skin installed successfully from URL',
          'url': url,
        }),
      );
    } catch (e, st) {
      log.severe('Failed to install skin from URL', e, st);
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }

  /// DELETE /api/v1/webui/skins/{id}
  /// Remove/uninstall a skin
  Future<Response> _handleRemoveSkin(Request request, String id) async {
    try {
      log.info('Removing skin: $id');

      await _storage.removeSkin(id);

      return Response.ok(
        jsonEncode({
          'success': true,
          'message': 'Skin removed successfully',
          'id': id,
        }),
      );
    } catch (e, st) {
      log.severe('Failed to remove skin: $id', e, st);
      
      // Check if it's because it's a bundled skin
      if (e.toString().contains('Cannot remove bundled skin')) {
        return Response(
          403,
          body: jsonEncode({'error': e.toString()}),
        );
      }

      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }
}
