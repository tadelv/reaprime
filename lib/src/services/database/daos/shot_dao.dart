import 'package:drift/drift.dart';
import 'package:reaprime/src/services/database/database.dart';
import 'package:reaprime/src/services/database/tables/shot_tables.dart';

part 'shot_dao.g.dart';

@DriftAccessor(tables: [ShotRecords])
class ShotDao extends DatabaseAccessor<AppDatabase> with _$ShotDaoMixin {
  ShotDao(super.db);

  /// Get all shot IDs.
  Future<List<String>> getAllShotIds() async {
    final query = selectOnly(shotRecords)..addColumns([shotRecords.id]);
    final rows = await query.get();
    return rows.map((row) => row.read(shotRecords.id)!).toList();
  }

  /// Get a single shot by ID (includes measurements).
  Future<ShotRecord?> getShotById(String id) {
    return (select(shotRecords)..where((s) => s.id.equals(id)))
        .getSingleOrNull();
  }

  /// Get all shots ordered by timestamp descending (includes measurements).
  Future<List<ShotRecord>> getAllShots() {
    return (select(shotRecords)
          ..orderBy([(s) => OrderingTerm.desc(s.timestamp)]))
        .get();
  }

  /// Paginated shot list without measurements for list views.
  /// Returns rows with measurementsJson set to '[]'.
  Future<List<ShotRecord>> getShotsPaginated({
    int limit = 20,
    int offset = 0,
    String? grinderId,
    String? grinderModel,
    String? beanBatchId,
    String? coffeeName,
    String? coffeeRoaster,
    String? profileTitle,
  }) {
    final query = select(shotRecords);

    if (grinderId != null) {
      query.where((s) => s.grinderId.equals(grinderId));
    }
    if (grinderModel != null) {
      query.where((s) => s.grinderModel.equals(grinderModel));
    }
    if (beanBatchId != null) {
      query.where((s) => s.beanBatchId.equals(beanBatchId));
    }
    if (coffeeName != null) {
      query.where((s) => s.coffeeName.equals(coffeeName));
    }
    if (coffeeRoaster != null) {
      query.where((s) => s.coffeeRoaster.equals(coffeeRoaster));
    }
    if (profileTitle != null) {
      query.where((s) => s.profileTitle.equals(profileTitle));
    }

    query
      ..orderBy([(s) => OrderingTerm.desc(s.timestamp)])
      ..limit(limit, offset: offset);

    return query.get();
  }

  /// Count total shots matching filters (for pagination metadata).
  Future<int> countShots({
    String? grinderId,
    String? grinderModel,
    String? beanBatchId,
    String? coffeeName,
    String? coffeeRoaster,
    String? profileTitle,
  }) async {
    final countExpr = shotRecords.id.count();
    final query = selectOnly(shotRecords)..addColumns([countExpr]);

    if (grinderId != null) {
      query.where(shotRecords.grinderId.equals(grinderId));
    }
    if (grinderModel != null) {
      query.where(shotRecords.grinderModel.equals(grinderModel));
    }
    if (beanBatchId != null) {
      query.where(shotRecords.beanBatchId.equals(beanBatchId));
    }
    if (coffeeName != null) {
      query.where(shotRecords.coffeeName.equals(coffeeName));
    }
    if (coffeeRoaster != null) {
      query.where(shotRecords.coffeeRoaster.equals(coffeeRoaster));
    }
    if (profileTitle != null) {
      query.where(shotRecords.profileTitle.equals(profileTitle));
    }

    final result = await query.getSingle();
    return result.read(countExpr) ?? 0;
  }

  /// Watch all shots (for reactive UI).
  Stream<List<ShotRecord>> watchAllShots() {
    return (select(shotRecords)
          ..orderBy([(s) => OrderingTerm.desc(s.timestamp)]))
        .watch();
  }

  Future<void> insertShot(ShotRecordsCompanion shot) {
    return into(shotRecords).insert(shot);
  }

  Future<void> upsertShot(ShotRecordsCompanion shot) {
    return into(shotRecords).insertOnConflictUpdate(shot);
  }

  Future<void> updateShot(ShotRecordsCompanion shot) {
    return (update(shotRecords)..where((s) => s.id.equals(shot.id.value)))
        .write(shot);
  }

  Future<void> deleteShot(String id) {
    return (delete(shotRecords)..where((s) => s.id.equals(id))).go();
  }

  /// Get the most recent shot.
  Future<ShotRecord?> getLatestShot() {
    return (select(shotRecords)
          ..orderBy([(s) => OrderingTerm.desc(s.timestamp)])
          ..limit(1))
        .getSingleOrNull();
  }
}
