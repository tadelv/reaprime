import 'dart:convert';

import 'package:flutter_js/flutter_js.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/plugins/plugin_manifest.dart';

typedef PluginMessageHandler =
    void Function(String pluginId, Map<String, dynamic> message);

enum PluginRuntimeState { loading, running, disposing, disposed }

class PluginRuntime {
  final String pluginId;
  final JavascriptRuntime js;
  final PluginMessageHandler onMessage;
  final PluginManifest manifest;

  late Logger _log;
  PluginRuntimeState _state = PluginRuntimeState.loading;

  bool get isAlive => _state == PluginRuntimeState.running;

  PluginRuntime({
    required this.pluginId,
    required this.onMessage,
    required this.manifest,
  }) : js = getJavascriptRuntime() {
    _log = Logger("Runtime::$pluginId");
    _injectHostApi();
  }

  void _injectHostApi() {
    js.evaluate(r'''
    (function () {

      function sendJson(obj) {
        sendMessage(
          "default",
          JSON.stringify(obj)
        );
      }

      globalThis.host = {
        log(message) {
          sendJson({
            type: "log",
            payload: { message: String(message) }
          });
        },

        emit(event, payload) {
          sendJson({
            type: "emit",
            payload: {
              event: String(event),
              data: payload
            }
          });
        },

        storage(payload) {
          sendJson({
            type: "pluginStorage",
            payload: payload
          });
        }
      };

      // ---- Base64 ----

      const _b64chars =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";

      globalThis.base64Encode = function (str) {
        let output = "";
        let i = 0;

        while (i < str.length) {
          const chr1 = str.charCodeAt(i++);
          const chr2 = str.charCodeAt(i++);
          const chr3 = str.charCodeAt(i++);

          const enc1 = chr1 >> 2;
          const enc2 = ((chr1 & 3) << 4) | (chr2 >> 4);
          const enc3 = isNaN(chr2)
            ? 64
            : (((chr2 & 15) << 2) | (chr3 >> 6));
          const enc4 = isNaN(chr3) ? 64 : (chr3 & 63);

          output +=
            _b64chars.charAt(enc1) +
            _b64chars.charAt(enc2) +
            _b64chars.charAt(enc3) +
            _b64chars.charAt(enc4);
        }

        return output;
      };

    })();
    ''');

    js.onMessage('default', (raw) {
      if (_state != PluginRuntimeState.running) return;

      _log.finest("recv: $raw");

      final decoded = _safeDecode(raw);
      onMessage(pluginId, decoded);
    });
  }

  Map<String, dynamic> _safeDecode(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    _log.warning("message is not a string Map");
    try {
      return Map<String, dynamic>.from(jsonDecode(raw));
    } catch (_) {
      return {"type": "error", "raw": raw};
    }
  }

  Future<void> load(String jsCode, Map<String, dynamic> settings) async {
    if (_state != PluginRuntimeState.loading) return;

    try {
      js.evaluate(jsCode);

      final settingsJson = jsonEncode(settings);

      js.evaluate('''
      try {
        if (!globalThis.Plugin) {
          throw new Error("Plugin not found");
        }
        Plugin.onLoad($settingsJson);
      } catch (e) {
        host.log("onLoad error: " + e);
      }
    ''');
    } catch (e, st) {
      _log.severe("Plugin load failed", e, st);
      rethrow;
    }

    _state = PluginRuntimeState.running;
  }

  void dispatchEvent(String name, dynamic payload) {
    if (!isAlive) {
      _log.finest("Skipping dispatch to dead plugin $pluginId");
      return;
    }

    final safePayload = _safeJson(payload);

    try {
      js.evaluate('''
      try {
        if (Plugin?.onEvent) {
          Plugin.onEvent({
            name: "$name",
            payload: $safePayload
          });
        }
      } catch (e) {
        host.log("onEvent error: " + e);
      }
    ''');
    } catch (e, st) {
      _log.warning("dispatchEvent failed", e, st);
    }
  }

  String _safeJson(dynamic value) {
    try {
      return jsonEncode(value);
    } catch (e) {
      return jsonEncode({
        "_error": "non_json_payload",
        "string": value.toString(),
      });
    }
  }

  Future<void> dispose() async {
    if (_state == PluginRuntimeState.disposed ||
        _state == PluginRuntimeState.disposing) {
      return;
    }

    _state = PluginRuntimeState.disposing;

    try {
      js.evaluate(r'''
      try {
        Plugin?.onUnload?.();
        Plugin = null;
      } catch (e) {}
    ''');
      js.executePendingJob();
    } catch (_) {}

    js.dispose();
    _state = PluginRuntimeState.disposed;
  }
}
