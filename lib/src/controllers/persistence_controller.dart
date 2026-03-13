import 'package:collection/collection.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/models/data/shot_record.dart';
import 'package:reaprime/src/models/data/workflow.dart';
import 'package:reaprime/src/services/storage/storage_service.dart';
import 'package:rxdart/rxdart.dart';

class PersistenceController {
  final StorageService storageService;
  final _log = Logger("PersistenceController");

  final List<ShotRecord> _shots = [];

  PersistenceController({required this.storageService});

  Future<void> persistShot(ShotRecord record) async {
    _log.info("Storing shot");
    try {
      await storageService.storeShot(record);
      _shots.add(record);
      _shotsController.add(_shots);
    } catch (e, st) {
      _log.severe("Error saving shot:", e, st);
    }
  }

  Future<void> updateShot(ShotRecord record) async {
    _log.info("Updating shot: ${record.id}");
    try {
      await storageService.updateShot(record);
      final index = _shots.indexWhere((s) => s.id == record.id);
      if (index != -1) {
        _shots[index] = record;
        _shotsController.add(_shots);
      } else {
        _log.warning("Shot ${record.id} not found in memory cache");
      }
    } catch (e, st) {
      _log.severe("Error updating shot:", e, st);
      rethrow;
    }
  }

  Future<void> deleteShot(String id) async {
    _log.info("Deleting shot: $id");
    try {
      await storageService.deleteShot(id);
      _shots.removeWhere((s) => s.id == id);
      _shotsController.add(_shots);
    } catch (e, st) {
      _log.severe("Error deleting shot:", e, st);
      rethrow;
    }
  }

  Future<List<ShotRecord>> loadShots() async {
    var loadedShots = await storageService.getAllShots();
    _log.fine("shots loaded: ${loadedShots.length}");
    _shots.clear();
    _log.fine("shots cleared: ${_shots.length}");
    _shots.addAll(
      loadedShots.sortedBy((element) {
        return element.timestamp;
      }),
    );
    _shotsController.add(_shots);
    _log.fine("shots changed: ${_shots.length}");
    return _shots;
  }

  final BehaviorSubject<List<ShotRecord>> _shotsController =
      BehaviorSubject.seeded([]);

  Stream<List<ShotRecord>> get shots => _shotsController.stream;

  List<({String setting, String? model})> grinderOptions() {
    return _shots
        .where((el) => el.workflow.context?.grinderSetting != null)
        .map((el) => (
              setting: el.workflow.context!.grinderSetting!,
              model: el.workflow.context!.grinderModel,
            ))
        .toList();
  }

  List<({String name, String? roaster})> coffeeOptions() {
    return _shots
        .where((el) => el.workflow.context?.coffeeName != null)
        .map((el) => (
              name: el.workflow.context!.coffeeName!,
              roaster: el.workflow.context!.coffeeRoaster,
            ))
        .toList();
  }

  Future<void> saveWorkflow(Workflow workflow) async {
    await storageService.storeCurrentWorkflow(workflow);
  }

  Future<Workflow?> loadWorkflow() async {
    return storageService.loadCurrentWorkflow();
  }
}
