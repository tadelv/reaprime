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

  Future<List<ShotRecord>> loadShots() async {
    _shots.clear();
    _shots.addAll(await storageService.getAllShots());
    _shotsController.add(_shots);
    return _shots;
  }

  final BehaviorSubject<List<ShotRecord>> _shotsController =
      BehaviorSubject.seeded([]);

  Stream<List<ShotRecord>> get shots => _shotsController.stream;

  List<GrinderData> grinderOptions() {
    return _shots.fold(
      <GrinderData>[],
      (res, el) {
        if (el.workflow.grinderData != null) {
          res.add(el.workflow.grinderData!);
        }
        return res;
      },
    ).toList();
  }

  List<CoffeeData> coffeeOptions() {
    return _shots.fold(
      <CoffeeData>[],
      (res, el) {
        if (el.workflow.coffeeData != null) {
          res.add(el.workflow.coffeeData!);
        }
        return res;
      },
    ).toList();
  }
}
