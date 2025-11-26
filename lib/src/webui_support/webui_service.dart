import 'dart:io';

import 'package:logging/logging.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_cors_headers/shelf_cors_headers.dart';

class WebUIService {
  static final _log = Logger("WebUIService");
  static HttpServer? _server;
  static final int port = 3000;
  static String _path = "";

  static Future<void> serveFolderAtPath(String path) async {
    await _server?.close(force: true);

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

    //   final handler = (Request request) async {
    //   return Response.ok('<html><body><h1>Hello WebView</h1></body></html>',
    //     headers: {'Content-Type': 'text/html'});
    // };
    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(corsHeaders())
        .addMiddleware(expirationModifier)
        .addHandler(webUI.call);

    try {
      _server = await shelf_io.serve(handler, '0.0.0.0', port);
    } catch (e, st) {
      _log.severe("failed to start serving", e, st);
    }
    _log.fine("serving $path");
    _path = path;
  }

  static String serverIP() {
    _log.fine("server ip: ${_server?.address.address}");
    return Platform.isAndroid
        ? _server?.address.address ?? "localhost"
        : "localhost";
  }

  static String serverPath() {
    return _path;
  }

  static bool get isServing => _server != null;
}
