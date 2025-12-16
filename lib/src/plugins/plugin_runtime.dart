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
        // FORCE string materialization via concatenation
        sendMessage(
          'default',
          JSON.stringify(obj)
        );
      }

      globalThis.host = {
        log(message) {
          sendJson({
            type: "log",
            payload: {
              message: String(message)
            }
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
        }
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

  void load(String jsCode) {
    js.evaluate(jsCode);
    js.evaluate(r'''
      if (!globalThis.Plugin) {
        throw new Error("Plugin not found");
      }
      Plugin.onLoad({});
    ''');
  }

  void dispatchEvent(String name, dynamic payload) {
    js.evaluate('''
      if (Plugin?.onEvent) {
        Plugin.onEvent({
          name: "$name",
          payload: ${jsonEncode(payload)}
        });
      }
    ''');
  }

  void dispose() {
    js.evaluate(r'''
      Plugin?.onUnload?.();
      Plugin = null;
    ''');
    js.dispose();
  }
}
