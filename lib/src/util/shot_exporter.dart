import 'dart:convert';

import 'package:reaprime/src/services/storage/storage_service.dart';

class ShotExporter {
  final StorageService storage;

  ShotExporter({required this.storage});

  Future<String> exportJson() async {
    final allShots = await storage.getAllShots();
    return jsonEncode(allShots);
  }
}
