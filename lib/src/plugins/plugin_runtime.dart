import 'dart:convert';

import 'package:flutter_js/flutter_js.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/plugins/plugin_manifest.dart';

typedef PluginMessageHandler =
    void Function(String pluginId, Map<String, dynamic> message);

class PluginRuntime {
  final String pluginId;
  final JavascriptRuntime js;
  final PluginMessageHandler onMessage;
  final PluginManifest manifest;
  late Logger _log;

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
          'default',
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
    // 1. Load plugin code
    await js.evaluateAsync(jsCode);

    // 2. Serialize settings to JSON
    final settingsJson = jsonEncode(settings);

    // 3. Call onLoad with real JS object
    await js.evaluateAsync('''
    (function () {
      if (!globalThis.Plugin) {
        throw new Error("Plugin not found");
      }
      Plugin.onLoad($settingsJson);
    })();
  ''');
  }

  void dispatchEvent(String name, dynamic payload) {
    _log.finest("dispatch: $name");
    js.evaluate('''
      if (Plugin?.onEvent) {
        Plugin.onEvent({
          name: "$name",
          payload: ${jsonEncode(payload)}
        });
      }
    ''');
  }

  Future<void> dispose() async {
    await js.evaluateAsync(r'''
      Plugin?.onUnload?.();
      Plugin = null;
    ''');
    js.executePendingJob();
    js.dispose();
  }
}
