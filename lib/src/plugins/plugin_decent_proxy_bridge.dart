import 'package:logging/logging.dart';
import 'package:reaprime/src/plugins/plugin_manifest.dart';
import 'package:reaprime/src/services/account/decent_proxy_service.dart';

class PluginDecentProxyBridge {
  final DecentProxyService? decentProxyService;
  final Logger _log;

  PluginDecentProxyBridge({required this.decentProxyService, Logger? log})
    : _log = log ?? Logger('PluginDecentProxyBridge');

  Future<Map<String, dynamic>> proxyForPlugin({
    required String pluginId,
    required PluginManifest? manifest,
    required String? path,
    String method = 'GET',
    Map<String, String>? query,
    String? body,
    String? contentType,
  }) async {
    if (manifest == null) {
      throw StateError('Plugin is not loaded: $pluginId');
    }
    if (!manifest.permissions.contains(PluginPermissions.proxyDecentApi)) {
      _log.warning(
        'Plugin $pluginId attempted Decent proxy access without permission',
      );
      throw StateError('Plugin permission required: proxy.decent_api');
    }
    if (decentProxyService == null) {
      throw StateError('Decent account proxy is not available');
    }
    if (path == null || path.trim().isEmpty) {
      throw ArgumentError('Decent proxy path is required');
    }

    final normalizedMethod = method.toUpperCase();
    final callerId = 'plugin:$pluginId';
    final DecentProxyResponse response;
    switch (normalizedMethod) {
      case 'GET':
        response = await decentProxyService!.proxyGet(
          callerId: callerId,
          path: path,
          query: query,
        );
      case 'POST':
        response = await decentProxyService!.proxyPost(
          callerId: callerId,
          path: path,
          query: query,
          body: body,
          contentType: contentType,
        );
      case 'PUT':
        response = await decentProxyService!.proxyPut(
          callerId: callerId,
          path: path,
          query: query,
          body: body,
          contentType: contentType,
        );
      default:
        throw UnsupportedError(
          'Decent proxy supports GET, POST, PUT for plugins',
        );
    }
    return {
      'status': response.statusCode,
      'headers': response.headers,
      'body': response.body,
    };
  }
}
