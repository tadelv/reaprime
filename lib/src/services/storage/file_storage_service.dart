import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/models/data/shot_record.dart';
import 'package:reaprime/src/services/storage/storage_service.dart';
import 'package:path_provider/path_provider.dart';

class FileStorageService implements StorageService {
  final Directory _path;
  late Directory _shotsPath;

	final _log = Logger("FileStorageService");

  FileStorageService({required Directory path}) : _path = path {
    _shotsPath = Directory('${_path.path}/shots');
    _shotsPath.createSync(recursive: true);
  }
  @override
  Future<List<ShotRecord>> getAllShots() async {
    var paths = await _getShotFiles();
    var records = <ShotRecord>[];
    for (var path in paths) {
      File f = File(path);
      try {
        var jsonString = await f.readAsString();
        var json = jsonDecode(jsonString);
        records.add(ShotRecord.fromJson(json));
      } catch (e) {
			_log.severe("Failed to read shot file: $path", e);
			}
    }
    return records;
  }

  @override
  Future<ShotRecord?> getShot(String id) async {
    var paths = await _getShotFiles();
    var file =
        paths.firstWhereOrNull((e) => e.replaceAll(".json", "").endsWith(id));
    if (file == null) {
      return null;
    }
    File f = File(file);
    var jsonString = await f.readAsString();
    var json = jsonDecode(jsonString);
    return ShotRecord.fromJson(json);
  }

  @override
  Future<List<String>> getShotIds() async {
    var files = await _getShotFiles();
    var ids = files.map((e) => e.split('/').last).toList();
    return ids;
  }

  @override
  Future<void> storeShot(ShotRecord record) async {
    File file = File('${_shotsPath.path}/${record.id}.json');
    await file.writeAsString(jsonEncode(record.toJson()));
		_log.info("Stored shot: ${record.id} at ${file.path}");
  }

  Future<List<String>> _getShotFiles() {
    return _shotsPath.list().map((e) => e.path).toList();
  }
}
