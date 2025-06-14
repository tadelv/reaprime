import 'dart:io';

import 'package:logging/logging.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

class WebUIService {
  final _log = Logger("WebUIService");
  HttpServer? _server;
  final int port = 3000;

  Future<void> serveFolderAtPath(String path) async {
    await _server?.close(force: true);

    final handler = createStaticHandler(
      path,
      defaultDocument: 'index.html',
      serveFilesOutsidePath: true,
    );

    _server = await shelf_io.serve(handler, 'localhost', port);
    _log.info("serving $path");
  }
}
