import 'package:logging/logging.dart';
import 'package:reaprime/src/models/data/shot_record.dart';
import 'package:reaprime/src/services/storage/storage_service.dart';

class PersistenceController {
  final StorageService storageService;
  final _log = Logger("PersistenceController");

  PersistenceController({required this.storageService});

  Future<void> persistShot(ShotRecord record) async {
    _log.info("Storing shot");
		try {
    await storageService.storeShot(record);
		} catch (e, st) {
		_log.severe("Error saving shot:", e, st);
		}
  }

  Future<List<ShotRecord>> loadShots() async {
    return storageService.getAllShots();
  }
}
