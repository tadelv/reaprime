import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// What source to serve a skin from — overrides the registry default.
@immutable
class SkinOverride {
  final SkinSource source;
  final String? value;

  const SkinOverride.registry() : source = SkinSource.registry, value = null;

  const SkinOverride.path(String path) : source = SkinSource.path, value = path;

  const SkinOverride.id(String skinId) : source = SkinSource.id, value = skinId;
}

enum SkinSource {
  /// Normal behavior: lookup from WebUIStorage registry.
  registry,

  /// Serve directly from a filesystem path (--skin-path).
  path,

  /// Serve a specific skin ID from the registry, session-only (future).
  id,
}

/// Injects the account-proxy skin token into served HTML so skin JS can read it
/// from `window.__REA_PROXY_TOKEN__` and send it as `Authorization: Bearer` to
/// the proxy on :8080. Inserted before `</head>`, else `</body>`, else
/// prepended. Returns [html] unchanged if [token] is null/empty.
String injectProxyTokenScript(String html, String? token) {
  if (token == null || token.isEmpty) return html;
  final script =
      '<script>window.__REA_PROXY_TOKEN__=${jsonEncode(token)};</script>';
  for (final marker in const ['</head>', '</body>']) {
    final i = html.indexOf(marker);
    if (i != -1) {
      return '${html.substring(0, i)}$script${html.substring(i)}';
    }
  }
  return '$script$html';
}

class WebUIService {
  final _log = Logger("WebUIService");
  HttpServer? _server;
  int port = 3000;
  String _path = "";
  String? _localIP;

  /// Test seam: override in tests to simulate offline/no-WiFi without
  /// touching the real platform channel. Returns null when no WiFi IP is
  /// available (null-collapsed by [_resolveLocalIP]).
  @visibleForTesting
  static Future<String?> Function() resolveWifiIP = NetworkInfo().getWifiIP;

  /// Resolves the device's WiFi IP for the browser-hero card and QR code.
  /// Must not block the critical path — falls back to "localhost" when the
  /// platform call throws or the device is offline (gh#337).
  Future<String> _resolveLocalIP() async {
    try {
      final ip = await resolveWifiIP();
      if (ip != null && ip.isNotEmpty) return ip;
    } catch (e) {
      _log.warning('Failed to resolve WiFi IP, falling back to localhost', e);
    }
    return 'localhost';
  }

  /// Overrides the skin source for the initialization step. Set from CLI flags
  /// (--skin-path) before the onboarding flow starts. Defaults to [SkinSource.registry].
  SkinOverride skinOverride = const SkinOverride.registry();

  /// Current account-proxy skin token, set from `ProxyTokenService.skinToken`.
  /// Injected into served HTML so skins can call the proxy. Null = no injection.
  String? skinProxyToken;

  // WebUI server methods

  Future<void> serveFolderAtPath(String path, {int port = 3000}) async {
    await _server?.close(force: true);
    _localIP ??= await _resolveLocalIP();

    // 1. Get system temp directory
    // final documents = await getApplicationDocumentsDirectory();
    // final tempDir = Directory("${documents.path}/served_folder_");
    // if (await tempDir.exists()) {
    //   await tempDir.delete(recursive: true);
    // }
    // final tempPath = tempDir.path;
    // final srcDir = Directory(path);
    // _log.fine("attempting copy from:");
    // _log.fine("${srcDir.listSync(recursive: true)}");
    // if (await srcDir.exists() == false) {
    //     throw "No";
    //   }

    // 2. Copy folder to temp
    // await tempDir.create(recursive: true);
    // await _copyDirectory(Directory(path), tempDir);
    // copyDirectorySync(srcDir, tempDir);

    // _log.fine("copied data:");
    // final list = tempDir.listSync(recursive: true);
    // _log.fine("${list}");
    //
    // _log.fine("loading from $tempPath");

    final webUI = createStaticHandler(
      path,
      defaultDocument: 'index.html',
      serveFilesOutsidePath: false,
      listDirectories: true,
    );

    Future<Response> Function(Request request) expirationModifier(
      Handler innerHandler,
    ) {
      return (Request request) async {
        _log.fine("handling request: ${request.requestedUri.path}");
        final response = await innerHandler(request);

        // Option 1: Check by path if it starts with "/ws" (or any other condition)
        if (request.requestedUri.path.startsWith('/ws')) {
          return response;
        }

        // Option 2: Alternatively, check if the request has an Upgrade header
        // if ((request.headers['upgrade']?.toLowerCase() ?? '') == 'websocket') {
        //   return response;
        // }

        // Add the header to responses that aren’t websocket-related.
        return response.change(
          headers: {
            ...response.headersAll,
            'Cache-Control': 'no-cache, no-store, must-revalidate',
            'Expires': "0",
          },
        );
      };
    }

    Future<Response> Function(Request request) proxyTokenInjector(
      Handler innerHandler,
    ) {
      return (Request request) async {
        final response = await innerHandler(request);
        final contentType = response.headers['content-type'] ?? '';
        if (!contentType.contains('text/html')) {
          return response;
        }
        final body = await response.readAsString();
        final injected = injectProxyTokenScript(body, skinProxyToken);
        // Drop content-length: the body length changed and shelf recomputes it.
        final headers = Map<String, String>.from(response.headers)
          ..remove('content-length');
        return response.change(body: injected, headers: headers);
      };
    }

    //   final handler = (Request request) async {
    //   return Response.ok('<html><body><h1>Hello WebView</h1></body></html>',
    //     headers: {'Content-Type': 'text/html'});
    // };
    // NOTE: no CORS middleware here on purpose. The skin token is injected into
    // served HTML, so the :3000 host must NOT send Access-Control-Allow-Origin:
    // * — otherwise a malicious site could fetch the skin cross-origin and
    // scrape the token. Skins read their own assets same-origin (no CORS needed)
    // and call the :8080 API cross-origin (governed by :8080's CORS).
    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(expirationModifier)
        .addMiddleware(proxyTokenInjector)
        .addHandler(webUI.call);

    try {
      _server = await shelf_io.serve(handler, '0.0.0.0', port);
      _log.fine("serving $path");
      _path = path;
    } catch (e, st) {
      _log.severe("failed to start serving", e, st);
      rethrow;
    }
  }

  String serverIP() {
    _log.fine("server ip: ${_server?.address.address}");
    return Platform.isAndroid
        ? _server?.address.address ?? "localhost"
        : "localhost";
  }

  String deviceIp() {
    return _localIP ?? "";
  }

  String serverPath() {
    return _path;
  }

  bool get isServing => _server != null;

  Future<void> stopServing() async {
    if (_server != null) {
      _log.info('Stopping WebUI server on port $port');
      await _server?.close(force: true);
      _server = null;
      _path = "";
      _log.info('WebUI server stopped');
    }
  }
}
