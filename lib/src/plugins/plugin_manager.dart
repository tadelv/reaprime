import 'package:logging/logging.dart';
import 'package:reaprime/src/plugins/plugin_manifest.dart';
import 'package:reaprime/src/plugins/plugin_runtime.dart';

class PluginManager {
  final _log = Logger("PluginManager");
  final Map<String, PluginRuntime> _plugins = {};

  Future<void> loadPlugin({
    required String id,
    required PluginManifest manifest,
    required String jsCode,
  }) async {
    if (_plugins.containsKey(id)) {
      throw Exception('Plugin already loaded: $id');
    }

    final runtime = PluginRuntime(
      pluginId: id,
      onMessage: _handleMessage,
      manifest: manifest,
    );

    _plugins[id] = runtime;
    await runtime.load(jsCode);
    _log.info("loaded: ${runtime.pluginId}");
    _log.finest("loaded plugins ${_plugins.keys.toList()}");
  }

  void unloadPlugin(String id) {
    _plugins.remove(id)?.dispose();
  }

  void broadcastEvent(String name, dynamic payload) {
    _log.fine("broadcast $name, $payload");
    for (final plugin in _plugins.values) {
      sendEventToPlugin(plugin.pluginId, name, payload);
    }
  }

  void sendEventToPlugin(String pluginId, String name, dynamic payload) {
    _plugins[pluginId]?.dispatchEvent(name, payload);
  }

  //
  // looking for the following format:
  // {
  //   type: log | emit
  //   payload: logPayload | emitPayload
  // }
  //
  // logPayload
  // {
  //   message: String
  // }
  //
  // emitPayload
  // {
  //   event: String
  //   data: Object
  // }
  void _handleMessage(String pluginId, Map<String, dynamic> msg) {
    _log.finest("handling: $pluginId, $msg");
    try {
      final plugin = _plugins[pluginId]!;
      final manifest = plugin.manifest;

      switch (msg['type']) {
        case 'log':
          _require(manifest, 'log');
          _log.fine('[PLUGIN:$pluginId] ${msg['payload']['message']}');
          break;

        case 'emit':
          _require(manifest, 'emit:events');
          _handlePluginEvent(
            pluginId,
            msg['payload']['event'],
            msg['payload']['data'],
          );
          break;
      }
    } catch (e) {
      _log.warning("failed to handle message", e);
    }
  }

  void _require(PluginManifest manifest, String perm) {
    if (!manifest.permissions.contains(perm)) {
      throw Exception('Plugin ${manifest.id} lacks permission: $perm');
    }
  }

  void _handlePluginEvent(String pluginId, String event, dynamic payload) {
    _log.fine('Handling event from $pluginId → $event ($payload)');
  }

  /// Get a list of currently loaded plugins
  List<PluginRuntime> get loadedPlugins {
    return _plugins.values.toList();
  }
}
