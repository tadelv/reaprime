import 'package:reaprime/src/models/data/shot_record.dart';
import 'package:reaprime/src/models/data/workflow.dart';

abstract class StorageService {
  Future<void> storeShot(ShotRecord record);
  Future<List<String>> getShotIds();
  Future<List<ShotRecord>> getAllShots();
  Future<ShotRecord?> getShot(String id);

	Future<void> storeCurrentWorkflow(Workflow workflow);
	Future<Workflow?> loadCurrentWorkflow();
}
