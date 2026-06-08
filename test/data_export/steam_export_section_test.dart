import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/persistence_controller.dart';
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/models/data/shot_record.dart';
import 'package:reaprime/src/models/data/steam_record.dart';
import 'package:reaprime/src/models/data/workflow.dart';
import 'package:reaprime/src/services/storage/storage_service.dart';
import 'package:reaprime/src/services/webserver/data_export/data_export_section.dart';
import 'package:reaprime/src/services/webserver/data_export/steam_export_section.dart';

class _MockStorage implements StorageService {
  final Map<String, SteamRecord> _steams = {};

  @override
  Future<void> storeSteam(SteamRecord record) async {
    _steams[record.id] = record;
  }

  @override
  Future<void> updateSteam(SteamRecord record) async {
    _steams[record.id] = record;
  }

  @override
  Future<void> deleteSteam(String id) async {
    _steams.remove(id);
  }

  @override
  Future<List<String>> getSteamIds() async => _steams.keys.toList();
  @override
  Future<List<SteamRecord>> getAllSteams() async => _steams.values.toList();
  @override
  Future<SteamRecord?> getSteam(String id) async => _steams[id];
  @override
  Future<SteamRecord?> getLatestSteam() async =>
      _steams.values.isEmpty ? null : _steams.values.last;
  @override
  Future<SteamRecord?> getLatestSteamMeta() async => getLatestSteam();

  void reset() => _steams.clear();

  // Unused surface --------------------------------------------------
  @override
  Future<void> storeShot(ShotRecord record) async {}
  @override
  Future<void> updateShot(ShotRecord record) async {}
  @override
  Future<void> deleteShot(String id) async {}
  @override
  Future<List<String>> getShotIds() async => [];
  @override
  Future<List<ShotRecord>> getAllShots() async => [];
  @override
  Future<ShotRecord?> getShot(String id) async => null;
  @override
  Future<void> storeCurrentWorkflow(Workflow workflow) async {}
  @override
  Future<Workflow?> loadCurrentWorkflow() async => null;
  @override
  Future<List<ShotRecord>> getShotsPaginated({
    int limit = 20,
    int offset = 0,
    String? grinderId,
    String? grinderModel,
    String? beanBatchId,
    List<String>? beanBatchIds,
    String? coffeeName,
    String? coffeeRoaster,
    String? profileTitle,
    String? search,
    bool ascending = false,
  }) async =>
      [];
  @override
  Future<int> countShots({
    String? grinderId,
    String? grinderModel,
    String? beanBatchId,
    List<String>? beanBatchIds,
    String? coffeeName,
    String? coffeeRoaster,
    String? profileTitle,
    String? search,
  }) async =>
      0;
  @override
  Future<ShotRecord?> getLatestShot() async => null;
  @override
  Future<ShotRecord?> getLatestShotMeta() async => null;
}

SteamRecord makeSteam(String id) => SteamRecord(
      id: id,
      timestamp: DateTime.utc(2026, 5, 18, 12, 0, 0),
      measurements: const [],
      workflow: WorkflowController().currentWorkflow,
    );

void main() {
  late _MockStorage storage;
  late PersistenceController controller;
  late SteamExportSection section;

  setUp(() {
    storage = _MockStorage();
    controller = PersistenceController(storageService: storage);
    section = SteamExportSection(controller: controller);
  });

  tearDown(() {
    storage.reset();
    controller.dispose();
  });

  test('filename is steams.json', () {
    expect(section.filename, equals('steams.json'));
  });

  group('export', () {
    test('returns empty list when no records exist', () async {
      final result = await section.export();
      expect(result, isA<List>());
      expect(result as List, isEmpty);
    });

    test('returns persisted records as JSON', () async {
      await controller.persistSteam(makeSteam('s1'));
      await controller.persistSteam(makeSteam('s2'));
      final result = await section.export();
      expect((result as List).map((m) => (m as Map)['id']),
          containsAll(['s1', 's2']));
    });
  });

  group('import', () {
    test('rejects non-list payloads', () async {
      final result =
          await section.import({'not': 'a list'}, ConflictStrategy.skip);
      expect(result.errors, isNotEmpty);
      expect(result.imported, 0);
    });

    test('inserts new records', () async {
      final payload = [makeSteam('s1').toJson(), makeSteam('s2').toJson()];
      final result = await section.import(payload, ConflictStrategy.skip);
      expect(result.imported, 2);
      expect(result.skipped, 0);
      expect(await storage.getSteam('s1'), isNotNull);
      expect(await storage.getSteam('s2'), isNotNull);
    });

    test('skip strategy leaves existing records untouched', () async {
      await controller.persistSteam(makeSteam('s1'));
      final result = await section
          .import([makeSteam('s1').toJson()], ConflictStrategy.skip);
      expect(result.imported, 0);
      expect(result.skipped, 1);
    });

    test('overwrite strategy updates existing records', () async {
      await controller.persistSteam(makeSteam('s1'));
      final result = await section
          .import([makeSteam('s1').toJson()], ConflictStrategy.overwrite);
      expect(result.imported, 1);
      expect(result.skipped, 0);
    });

    test('reports failures as errors', () async {
      final result = await section.import(
          [
            {'malformed': true}
          ],
          ConflictStrategy.skip);
      expect(result.errors, hasLength(1));
      expect(result.imported, 0);
    });
  });
}
