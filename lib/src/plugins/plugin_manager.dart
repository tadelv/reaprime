import 'dart:async';
import 'dart:convert';

import 'package:flutter_js/flutter_js.dart';
import 'package:logging/logging.dart';

import 'plugin_manifest.dart';
import 'plugin_runtime.dart';
import 'plugin_types.dart';
import '../services/storage/kv_store_service.dart';
import '../controllers/de1_controller.dart';
import '../models/device/de1_interface.dart';
import '../models/device/machine.dart';

class PluginManager {
  final _log = Logger("PluginManager");

  final Map<String, PluginRuntime> _plugins = {};
  final JavascriptRuntime js;
  final KeyValueStoreService kvStore;

  final StreamController<Map<String, dynamic>> _emitController =
      StreamController.broadcast();

  Stream<Map<String, dynamic>> get emitStream => _emitController.stream;

  De1Controller? _de1controller;
  StreamSubscription<De1Interface?>? _de1Subscription;
  StreamSubscription<MachineSnapshot>? _snapshotSubscription;

  De1Controller? get de1Controller => _de1controller;

  PluginManager({required this.kvStore}) : js = getJavascriptRuntime() {
    _bootstrapJs();
  }

  // ─────────────────────────────────────────────
  // JS bootstrap (ONCE)
  // ─────────────────────────────────────────────

  void _bootstrapJs() {
    js.evaluate(r'''
      (function () {
        if (globalThis.__plugins__) return;

        globalThis.__plugins__ = Object.create(null);

        // Provide btoa function if not available
        if (typeof globalThis.btoa === 'undefined') {
          globalThis.btoa = function (input) {
            // 1. Convert to string (per spec)
            const str = String(input);

            // 2. Reject non-Latin-1 characters
            for (let i = 0; i < str.length; i++) {
              if (str.charCodeAt(i) > 0xFF) {
                throw new DOMException(
                  "The string to be encoded contains characters outside of the Latin1 range.",
                  "InvalidCharacterError"
                );
              }
            }

            const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
            let output = "";
            let i = 0;

            // 3. Encode
            while (i < str.length) {
              const byte1 = str.charCodeAt(i++);
              const byte2 = i < str.length ? str.charCodeAt(i++) : undefined;
              const byte3 = i < str.length ? str.charCodeAt(i++) : undefined;

              const enc1 = byte1 >> 2;
              const enc2 = ((byte1 & 0x03) << 4) | (byte2 !== undefined ? byte2 >> 4 : 0);
              const enc3 = byte2 !== undefined
                ? ((byte2 & 0x0f) << 2) | (byte3 !== undefined ? byte3 >> 6 : 0)
                : 64;
              const enc4 = byte3 !== undefined ? (byte3 & 0x3f) : 64;

              output +=
                chars.charAt(enc1) +
                chars.charAt(enc2) +
                (enc3 === 64 ? "=" : chars.charAt(enc3)) +
                (enc4 === 64 ? "=" : chars.charAt(enc4));
            }

            return output;
          };
        }

        globalThis.__dispatchToPlugin = function (pluginId, evt) {
          const plugin = __plugins__[pluginId];
          if (!plugin || typeof plugin.onEvent !== "function") return;
          try {
            plugin.onEvent(evt);
          } catch (e) {
            console.error("Plugin error", pluginId, e);
          }
        };

        globalThis.host = {
          log(pluginId, message) {
            sendMessage("host", JSON.stringify({
              pluginId: pluginId,
              type: "log",
              payload: { message: String(message) }
            }));
          },
          emit(pluginId, eventName, payload) {
            sendMessage("host", JSON.stringify({
              pluginId: pluginId,
              type: "emit",
              event: eventName,
              payload: payload
            }));
          },
          storage(pluginId, command) {
            sendMessage("host", JSON.stringify({
              pluginId: pluginId,
              type: "pluginStorage",
              payload: command
            }));
          }
        };
      })();
    ''');

    js.onMessage("host", (raw) {
      try {
        _log.finest("receiving: $raw");
        // final msg = jsonDecode(raw);
        final msg = raw as Map<String, dynamic>;
        final pluginId = msg['pluginId'] as String?;
        final type = msg['type'];

        if (pluginId == null) {
          _log.warning("JS message missing pluginId");
          return;
        }

        if (type == 'log') {
          _log.fine("[JS:$pluginId] ${msg['payload']?['message']}");
        } else {
          _handleMessage(pluginId, msg);
        }
      } catch (e, st) {
        _log.warning("Invalid JS message", e, st);
      }
    });
  }

  // ─────────────────────────────────────────────
  // Plugin lifecycle
  // ─────────────────────────────────────────────

  Future<void> loadPlugin({
    required String id,
    required PluginManifest manifest,
    required String jsCode,
    required Map<String, dynamic> settings,
  }) async {
    await unloadPlugin(id);

    final runtime = PluginRuntime(pluginId: id, manifest: manifest);

    _plugins[id] = runtime;

    try {
      // Direct injection approach with standard factory name
      final wrapperCode = '''
        (function () {
          const pluginId = "$id";
          
          // Create the host object for this plugin
          const host = {
            log: (msg) => globalThis.host.log(pluginId, msg),
            emit: (type, payload) => globalThis.host.emit(pluginId, type, payload),
            storage: (cmd) => globalThis.host.storage(pluginId, cmd)
          };
          
          // Inject and evaluate the plugin code
          ${jsCode}
          
          // The plugin must export a function named 'createPlugin'
          if (typeof createPlugin !== 'function') {
            throw new Error("Plugin must export a 'createPlugin' function. Got: " + typeof createPlugin);
          }
          
          // Call the factory function with the host object
          const plugin = createPlugin(host);
          
          if (!plugin || typeof plugin !== "object") {
            throw new Error("createPlugin did not return an object, got: " + typeof plugin);
          }
          
          // Verify the plugin has the required id
          if (plugin.id !== pluginId) {
            throw new Error("Plugin ID mismatch. Expected: " + pluginId + ", Got: " + plugin.id);
          }
          
          // Store the plugin object
          __plugins__[pluginId] = plugin;
          
          // Call onLoad if it exists
          if (typeof plugin.onLoad === "function") {
            plugin.onLoad(${jsonEncode(settings)});
          }
          
          return plugin;
        })();
      ''';

      final result = js.evaluate(wrapperCode);
      _log.fine("Plugin evaluation result: ${result.stringResult}");
      _log.fine("Is error: ${result.isError}");

      if (result.isError) {
        throw Exception("JS evaluation error: ${result.stringResult}");
      }

      runtime.markRunning();
      _log.info("loaded: $id");
    } catch (e, st) {
      _plugins.remove(id);
      js.evaluate('''
        delete __plugins__["$id"];
      ''');
      _log.severe("Failed to load plugin $id", e, st);
      rethrow;
    }
  }

  Future<void> unloadPlugin(String id) async {
    final runtime = _plugins.remove(id);
    if (runtime == null) return;

    try {
      js.evaluate('''
        (function () {
          try {
            const plugin = __plugins__["$id"];
            plugin?.onUnload?.();
            delete __plugins__["$id"];
          } catch (e) {
            console.error("Unload failed ($id)", e);
          }
        })();
      ''');
    } catch (e, st) {
      _log.warning("Error during plugin unload: $id", e, st);
    }

    runtime.markDisposed();
    _log.info("unloaded: $id");
  }

  // ─────────────────────────────────────────────
  // Dart → JS events
  // ─────────────────────────────────────────────

  void broadcastEvent(String name, dynamic payload) {
    for (final plugin in _plugins.values) {
      if (plugin.isAlive) {
        dispatchEvent(plugin.pluginId, name, payload);
      }
    }
  }

  void dispatchEvent(String pluginId, String name, dynamic payload) {
    if (!_plugins.containsKey(pluginId)) return;

    js.evaluate('''
      __dispatchToPlugin("$pluginId", {
        name: "$name",
        payload: ${jsonEncode(payload)}
      });
    ''');
  }

  // ─────────────────────────────────────────────
  // JS → Dart messages
  // ─────────────────────────────────────────────

  void _handleMessage(String pluginId, Map<String, dynamic> msg) {
    _log.finest("handle message: $msg");
    final type = msg['type'];
    final payload = msg['payload'];

    switch (type) {
      case 'emit':
        final Map<String, dynamic> eventData = {
          'pluginId': pluginId,
          'event': msg['event'],
          'payload': payload,
        };
        _log.finest("emitting: $eventData");
        _emitController.add(eventData);
        break;

      case 'pluginStorage':
        final cmd = PluginStorageCommand.fromPlugin(payload);
        _handlePluginStorage(pluginId, cmd);
        break;
    }
  }

  Future<void> _handlePluginStorage(
    String pluginId,
    PluginStorageCommand cmd,
  ) async {
    // Use pluginId as namespace for storage isolation
    final namespace = pluginId;

    switch (cmd.type) {
      case PluginStorageCommandType.read:
        final value = await kvStore.get(key: cmd.key, namespace: namespace);
        dispatchEvent(pluginId, "storageRead", {
          "key": cmd.key,
          "value": value,
        });
        break;

      case PluginStorageCommandType.write:
        await kvStore.set(key: cmd.key, namespace: namespace, value: cmd.data);
        dispatchEvent(pluginId, "storageWrite", cmd.data);
        break;
    }
  }

  // ─────────────────────────────────────────────
  // External API (UNCHANGED)
  // ─────────────────────────────────────────────

  List<PluginRuntime> get loadedPlugins => _plugins.values.toList();

  set de1Controller(De1Controller? controller) {
    _de1Subscription?.cancel();
    _snapshotSubscription?.cancel();

    _de1controller = controller;
    if (controller == null) return;

    _de1Subscription = controller.de1.listen((de1) {
      _snapshotSubscription?.cancel();
      if (de1 != null) {
        _snapshotSubscription = de1.currentSnapshot.listen((snap) {
          broadcastEvent('stateUpdate', snap.toJson());
        });
      }
    });
  }
}
