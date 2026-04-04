import 'package:logging/logging.dart';
import 'package:reaprime/src/models/data/shot_record.dart';
import 'package:reaprime/src/models/data/workflow.dart';
import 'package:reaprime/src/services/storage/storage_service.dart';
import 'package:rxdart/rxdart.dart';

class PersistenceController {
  final StorageService storageService;
  final _log = Logger("PersistenceController");

  PersistenceController({required this.storageService});

  /// Fires whenever shots are added, updated, or deleted.
  /// Consumers should re-query what they need from [storageService].
  final _shotsChangedSubject = PublishSubject<void>();
  Stream<void> get shotsChanged => _shotsChangedSubject.stream;

  /// Manually fire a shots-changed notification.
  /// Used after external mutations (e.g., ZIP import via REST endpoint).
  void notifyShotsChanged() {
    _shotsChangedSubject.add(null);
  }

  Future<void> persistShot(ShotRecord record) async {
    _log.info("Storing shot");
    try {
      await storageService.storeShot(record);
      _shotsChangedSubject.add(null);
    } catch (e, st) {
      _log.severe("Error saving shot:", e, st);
    }
  }

  Future<void> updateShot(ShotRecord record) async {
    _log.info("Updating shot: ${record.id}");
    try {
      await storageService.updateShot(record);
      _shotsChangedSubject.add(null);
    } catch (e, st) {
      _log.severe("Error updating shot:", e, st);
      rethrow;
    }
  }

  Future<void> deleteShot(String id) async {
    _log.info("Deleting shot: $id");
    try {
      await storageService.deleteShot(id);
      _shotsChangedSubject.add(null);
    } catch (e, st) {
      _log.severe("Error deleting shot:", e, st);
      rethrow;
    }
  }

  Future<void> saveWorkflow(Workflow workflow) async {
    await storageService.storeCurrentWorkflow(workflow);
  }

  Future<Workflow?> loadWorkflow() async {
    return storageService.loadCurrentWorkflow();
  }

  void dispose() {
    _shotsChangedSubject.close();
  }
}
