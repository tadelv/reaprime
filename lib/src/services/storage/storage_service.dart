import 'package:reaprime/src/models/data/shot_record.dart';

abstract class StorageService {
  Future<void> storeShot(ShotRecord record);
  Future<List<String>> getShotIds();
  Future<List<ShotRecord>> getAllShots();
  Future<ShotRecord?> getShot(String id);
}
