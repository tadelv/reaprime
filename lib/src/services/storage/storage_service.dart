import 'package:reaprime/src/models/data/shot_record.dart';
import 'package:reaprime/src/models/data/workflow.dart';

abstract class StorageService {
  Future<void> storeShot(ShotRecord record);
  Future<void> updateShot(ShotRecord record);
  Future<void> deleteShot(String id);
  Future<List<String>> getShotIds();
  Future<List<ShotRecord>> getAllShots();
  Future<ShotRecord?> getShot(String id);

  Future<void> storeCurrentWorkflow(Workflow workflow);
  Future<Workflow?> loadCurrentWorkflow();

  /// Get paginated shots with optional filters.
  /// Returns shots without measurement data for list views.
  Future<List<ShotRecord>> getShotsPaginated({
    int limit = 20,
    int offset = 0,
    String? grinderId,
    String? grinderModel,
    String? beanBatchId,
    String? coffeeName,
    String? coffeeRoaster,
    String? profileTitle,
    String? search,
  });

  /// Count total shots matching the given filters.
  Future<int> countShots({
    String? grinderId,
    String? grinderModel,
    String? beanBatchId,
    String? coffeeName,
    String? coffeeRoaster,
    String? profileTitle,
    String? search,
  });

  /// Get the most recent shot (full row including measurements).
  Future<ShotRecord?> getLatestShot();

  /// Get the most recent shot metadata (excludes measurements).
  Future<ShotRecord?> getLatestShotMeta();
}
