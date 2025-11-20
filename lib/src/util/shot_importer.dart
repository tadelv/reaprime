import 'dart:convert';

import 'package:reaprime/src/models/data/shot_record.dart';
import 'package:reaprime/src/services/storage/storage_service.dart';

class ShotImporter {
  final StorageService storage;

  ShotImporter({required this.storage});

  Future<void> importShotsJson(String data) async {
    final shots = jsonDecode(data) as List<ShotRecord>;

    for (var shot in shots) {
      await storage.storeShot(shot);
    }
  }

  Future<void> importShotJson(String data) async {
    final json = jsonDecode(data);
    final shot = ShotRecord.fromJson(json);
    await storage.storeShot(shot);
  }
}
