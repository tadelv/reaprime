import 'dart:io';

import 'package:logging/logging.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:path/path.dart' as p;

class WebUIService {
  static final _log = Logger("WebUIService");
  static HttpServer? _server;
  static final int port = 3000;

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

    final handler = createStaticHandler(
      path,
      defaultDocument: 'index.html',
      serveFilesOutsidePath: false,
      listDirectories: true,
    );
    //   final handler = (Request request) async {
    //   return Response.ok('<html><body><h1>Hello WebView</h1></body></html>',
    //     headers: {'Content-Type': 'text/html'});
    // };

    try {
      _server = await shelf_io.serve(handler, '0.0.0.0', port);
    } catch (e, st) {
      _log.severe("failed to start serving", e, st);
    }
    _log.fine("serving $path");
  }

  static String serverIP() {
    _log.fine("server ip: ${_server?.address.address}");
    return Platform.isAndroid ? _server?.address.address ?? "localhost" : "localhost";
  }

  /// Recursively copy directory contents
  static Future<void> _copyDirectory(Directory src, Directory dst) async {
    _log.fine("beginning copy directory");
    await for (var entity in src.list(recursive: true)) {
      _log.fine("copying: ${entity.path}");
      if (entity is File) {
        final newPath = p.join(dst.path, p.basename(entity.path));
        await entity.copy(newPath);
      } else if (entity is Directory) {
        final newDirectory =
            Directory(p.join(dst.path, p.basename(entity.path)));
        await newDirectory.create();
        await _copyDirectory(entity, newDirectory);
      }
    }
  }

  static void copyDirectorySync(Directory source, Directory destination) {
    _log.fine("beginning copy directory");
    /// create destination folder if not exist
    if (!destination.existsSync()) {
      destination.createSync(recursive: true);
    }

    /// get all files from source (recursive: false is important here)
    source.listSync(recursive: false).forEach((entity) {
      _log.fine("copying: ${entity.path}");
      final newPath =
          destination.path + Platform.pathSeparator + p.basename(entity.path);
      if (entity is File) {
        entity.copySync(newPath);
      } else if (entity is Directory) {
        copyDirectorySync(entity, Directory(newPath));
      }
    });
  }

  static bool get isServing => _server != null;
}
