import 'dart:async';

import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/plugins/plugin_manifest.dart';
import 'package:reaprime/src/plugins/plugin_runtime.dart';
import 'package:reaprime/src/plugins/plugin_types.dart';
import 'package:reaprime/src/services/storage/kv_store_service.dart';

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
      _snapshotSubscription?.cancel();
      if (de1 != null) {
        _snapshotSubscription = de1.currentSnapshot.listen((e) {
          broadcastEvent('stateUpdate', e.toJson());
        });
      }
    });
  }

  KeyValueStoreService kvStore;

  PluginManager({required this.kvStore});

  final StreamController<Map<String, dynamic>> _emitController =
      StreamController.broadcast();

  Stream<Map<String, dynamic>> get emitStream => _emitController.stream;

  Future<void> loadPlugin({
    required String id,
    required PluginManifest manifest,
    required String jsCode,
    required Map<String, dynamic> settings,
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
    await runtime.load(jsCode, settings);
    _log.info("loaded: ${runtime.pluginId}");
    _log.finest("loaded plugins ${_plugins.keys.toList()}");
  }

  Future<void> unloadPlugin(String id) async {
    final plugin = _plugins[id];
    await plugin?.dispose();
    if (plugin != null) {
      _plugins.remove(id);
    }
  }

  void broadcastEvent(String name, dynamic payload) {
    if (_plugins.isEmpty) return;

    final plugins = List.of(_plugins.values);
    for (final plugin in plugins) {
      if (plugin.isAlive) {
        plugin.dispatchEvent(name, payload);
      }
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
    try {
      final plugin = _plugins[pluginId];
      if (plugin == null || !plugin.isAlive) {
        return;
      }

      final type = msg['type'];
      if (type is! String) {
        throw Exception("Invalid message type");
      }

      _require(plugin.manifest, type);

      switch (type) {
        case 'log':
          _log.fine('[PLUGIN:$pluginId] ${msg['payload']?['message']}');
          break;

        case 'emit':
          _handlePluginEvent(
            pluginId,
            msg['payload']?['event'],
            msg['payload']?['data'],
          );
          break;

        case 'pluginStorage':
          final command = PluginStorageCommand.fromPlugin(msg['payload']);
          _handlePluginStorageRequest(pluginId, command);
          break;
      }
    } catch (e, st) {
      _log.warning("Plugin message rejected", e, st);
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
    _log.finest('Handling event from $pluginId → $event ($payload)');
    _emitController.add({'id': pluginId, 'event': event, 'payload': payload});
  }

  Future<void> _handlePluginStorageRequest(
    String pluginId,
    PluginStorageCommand command,
  ) async {
    _log.finest('Handling storage from $pluginId → $command');
    switch (command.type) {
      case PluginStorageCommandType.read:
        final data = await kvStore.get(key: command.key, namespace: pluginId);
        sendEventToPlugin(pluginId, "storageRead", {
          "key": command.key,
          "data": data,
        });
        break;
      case PluginStorageCommandType.write:
        kvStore.set(key: command.key, namespace: pluginId, value: command.data);
        sendEventToPlugin(pluginId, "storageWrite", command.data);
        break;
    }
  }

  /// Get a list of currently loaded plugins
  List<PluginRuntime> get loadedPlugins {
    return _plugins.values.toList();
  }
}
