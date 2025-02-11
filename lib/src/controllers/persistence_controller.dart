import 'package:reaprime/src/models/data/shot_record.dart';
import 'package:reaprime/src/services/storage/storage_service.dart';

class PersistenceController {
  final StorageService storageService;

  PersistenceController({required this.storageService});

  Future<void> persistShot(ShotRecord record) async {
    await storageService.storeShot(record);
  }

  Future<List<ShotRecord>> loadShots() async {
    return storageService.getAllShots();
  }
}
