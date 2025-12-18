import 'dart:async';

import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/plugins/plugin_manifest.dart';
import 'package:reaprime/src/plugins/plugin_runtime.dart';

class PluginManager {
  final _log = Logger("PluginManager");
  final Map<String, PluginRuntime> _plugins = {};

  De1Controller? _de1controller;
  StreamSubscription<De1Interface?>? _de1Subscription;
  StreamSubscription<MachineSnapshot>? _snapshotSubscription;
  De1Controller? get de1Controller => _de1controller;
  set de1Controller(De1Controller? controller) {
    _log.info("subscribing to $controller");
    _de1Subscription?.cancel();
    _de1controller = controller;
    if (controller == null) {
      return;
    }
    _de1Subscription = controller.de1.listen((de1) {
      if (de1 != null) {
        _snapshotSubscription?.cancel();
        _snapshotSubscription = de1.currentSnapshot.listen((e) {
          broadcastEvent('stateUpdate', e.toJson());
        });
      }
    });
  }

  StreamController<Map<String, dynamic>> _emitController =
      StreamController.broadcast();

  Stream<Map<String, dynamic>> get emitStream => _emitController.stream;

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
    final plugin = _plugins[id];
    plugin?.dispose();
    if (plugin != null) {
      _plugins.remove(id);
    }
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
      final plugin = _plugins[pluginId];
      if (plugin == null) {
        _log.warning("received from unloaded plugin: $pluginId, msg: $msg");
        return;
      }
      final manifest = plugin.manifest;

      _require(manifest, msg['type']);

      switch (msg['type']) {
        case 'log':
          _log.fine('[PLUGIN:$pluginId] ${msg['payload']['message']}');
          break;

        case 'emit':
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
    final permission = PluginPermissions.fromString(perm);
    if (permission == null) {
      throw Exception(
        'Plugin ${manifest.id} requires unknown permission: $perm',
      );
    }
    if (!manifest.permissions.contains(permission)) {
      _log.warning("perms: ${manifest.permissions}");
      throw Exception('Plugin ${manifest.id} lacks permission: $perm');
    }
  }

  void _handlePluginEvent(String pluginId, String event, dynamic payload) {
    _log.fine('Handling event from $pluginId → $event ($payload)');
    _emitController.add({
        'id': pluginId,
        'event': event,
        'payload': payload
      });
  }

  /// Get a list of currently loaded plugins
  List<PluginRuntime> get loadedPlugins {
    return _plugins.values.toList();
  }
}
