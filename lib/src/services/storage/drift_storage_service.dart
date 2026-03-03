import 'package:reaprime/src/models/data/shot_record.dart' as domain;
import 'package:reaprime/src/models/data/workflow.dart' as domain_wf;
import 'package:reaprime/src/services/database/database.dart';
import 'package:reaprime/src/services/database/mappers/shot_mapper.dart';
import 'package:reaprime/src/services/database/mappers/workflow_mapper.dart';
import 'package:reaprime/src/services/storage/storage_service.dart';

/// Drift/SQLite implementation of [StorageService] for shots and workflow.
class DriftStorageService implements StorageService {
  final AppDatabase _db;

  DriftStorageService(this._db);

  @override
  Future<void> storeShot(domain.ShotRecord record) {
    return _db.shotDao.insertShot(ShotMapper.toCompanion(record));
  }

  @override
  Future<void> updateShot(domain.ShotRecord record) {
    return _db.shotDao.updateShot(ShotMapper.toCompanion(record));
  }

  @override
  Future<void> deleteShot(String id) {
    return _db.shotDao.deleteShot(id);
  }

  @override
  Future<List<String>> getShotIds() {
    return _db.shotDao.getAllShotIds();
  }

  @override
  Future<List<domain.ShotRecord>> getAllShots() async {
    final rows = await _db.shotDao.getAllShots();
    return rows.map(ShotMapper.fromRow).toList();
  }

  @override
  Future<domain.ShotRecord?> getShot(String id) async {
    final row = await _db.shotDao.getShotById(id);
    return row == null ? null : ShotMapper.fromRow(row);
  }

  @override
  Future<void> storeCurrentWorkflow(domain_wf.Workflow workflow) {
    return _db.workflowDao
        .saveCurrentWorkflow(WorkflowMapper.toCompanion(workflow));
  }

  @override
  Future<domain_wf.Workflow?> loadCurrentWorkflow() async {
    final row = await _db.workflowDao.loadCurrentWorkflow();
    return row == null ? null : WorkflowMapper.fromRow(row);
  }

  @override
  Future<List<domain.ShotRecord>> getShotsPaginated({
    int limit = 20,
    int offset = 0,
    String? grinderId,
    String? grinderModel,
    String? beanBatchId,
    String? coffeeName,
    String? coffeeRoaster,
    String? profileTitle,
  }) async {
    final rows = await _db.shotDao.getShotsPaginated(
      limit: limit,
      offset: offset,
      grinderId: grinderId,
      grinderModel: grinderModel,
      beanBatchId: beanBatchId,
      coffeeName: coffeeName,
      coffeeRoaster: coffeeRoaster,
      profileTitle: profileTitle,
    );
    return rows.map(ShotMapper.fromRow).toList();
  }

  @override
  Future<int> countShots({
    String? grinderId,
    String? grinderModel,
    String? beanBatchId,
    String? coffeeName,
    String? coffeeRoaster,
    String? profileTitle,
  }) {
    return _db.shotDao.countShots(
      grinderId: grinderId,
      grinderModel: grinderModel,
      beanBatchId: beanBatchId,
      coffeeName: coffeeName,
      coffeeRoaster: coffeeRoaster,
      profileTitle: profileTitle,
    );
  }

  @override
  Future<domain.ShotRecord?> getLatestShot() async {
    final row = await _db.shotDao.getLatestShot();
    return row == null ? null : ShotMapper.fromRow(row);
  }
}
