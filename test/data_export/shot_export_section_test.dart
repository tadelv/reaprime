import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/persistence_controller.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/data/shot_annotations.dart';
import 'package:reaprime/src/models/data/shot_record.dart';
import 'package:reaprime/src/models/data/workflow.dart';
import 'package:reaprime/src/models/data/workflow_context.dart';
import 'package:reaprime/src/services/storage/storage_service.dart';
import 'package:reaprime/src/services/webserver/data_export/data_export_section.dart';
import 'package:reaprime/src/services/webserver/data_export/shot_export_section.dart';

/// Mock implementation of StorageService for testing.
class MockStorageService implements StorageService {
  final Map<String, ShotRecord> _shots = {};
  Workflow? _currentWorkflow;

  @override
  Future<void> storeShot(ShotRecord record) async {
    _shots[record.id] = record;
  }

  @override
  Future<void> updateShot(ShotRecord record) async {
    if (!_shots.containsKey(record.id)) {
      throw Exception('Shot not found: ${record.id}');
    }
    _shots[record.id] = record;
  }

  @override
  Future<void> deleteShot(String id) async {
    _shots.remove(id);
  }

  @override
  Future<List<String>> getShotIds() async {
    return _shots.keys.toList();
  }

  @override
  Future<List<ShotRecord>> getAllShots() async {
    return _shots.values.toList();
  }

  @override
  Future<ShotRecord?> getShot(String id) async {
    return _shots[id];
  }

  @override
  Future<void> storeCurrentWorkflow(Workflow workflow) async {
    _currentWorkflow = workflow;
  }

  @override
  Future<Workflow?> loadCurrentWorkflow() async {
    return _currentWorkflow;
  }

  @override
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
  }) async {
    return _shots.values.skip(offset).take(limit).toList();
  }

  @override
  Future<int> countShots({
    String? grinderId,
    String? grinderModel,
    String? beanBatchId,
    String? coffeeName,
    String? coffeeRoaster,
    String? profileTitle,
    String? search,
  }) async {
    return _shots.length;
  }

  @override
  Future<ShotRecord?> getLatestShot() async {
    if (_shots.isEmpty) return null;
    return _shots.values.last;
  }

  @override
  Future<ShotRecord?> getLatestShotMeta() => getLatestShot();

  void reset() {
    _shots.clear();
    _currentWorkflow = null;
  }
}

ShotRecord _makeShotRecord({
  String id = 'shot-1',
  String workflowName = 'Test Workflow',
  String? shotNotes,
}) {
  return ShotRecord(
    id: id,
    timestamp: DateTime.parse('2024-01-15T10:30:00.000Z'),
    measurements: [],
    workflow: Workflow(
      id: 'workflow-1',
      name: workflowName,
      description: 'Test',
      profile: Profile(
        version: '2',
        title: 'Test Profile',
        author: 'Test Author',
        notes: '',
        beverageType: BeverageType.espresso,
        steps: [],
        tankTemperature: 0.0,
        targetWeight: 36.0,
        targetVolumeCountStart: 0,
      ),
      context: WorkflowContext(targetDoseWeight: 18.0, targetYield: 36.0),
      steamSettings: SteamSettings.defaults(),
      hotWaterData: HotWaterData.defaults(),
      rinseData: RinseData.defaults(),
    ),
    annotations: shotNotes != null ? ShotAnnotations(espressoNotes: shotNotes) : null,
  );
}

void main() {
  late MockStorageService storage;
  late PersistenceController controller;
  late ShotExportSection section;

  setUp(() {
    storage = MockStorageService();
    controller = PersistenceController(storageService: storage);
    section = ShotExportSection(controller: controller);
  });

  tearDown(() {
    storage.reset();
  });

  test('filename is shots.json', () {
    expect(section.filename, equals('shots.json'));
  });

  group('export', () {
    test('returns empty list when no shots exist', () async {
      final result = await section.export();
      expect(result, isA<List>());
      expect((result as List), isEmpty);
    });

    test('returns list of shot JSON maps', () async {
      final record = _makeShotRecord();
      await storage.storeShot(record);

      final result = await section.export();
      expect(result, isA<List>());
      final list = result as List;
      expect(list, hasLength(1));
      expect(list.first['id'], equals('shot-1'));
      expect(list.first['workflow'], isA<Map<String, dynamic>>());
    });

    test('returns multiple shots', () async {
      await storage.storeShot(_makeShotRecord(id: 'shot-1'));
      await storage.storeShot(
          _makeShotRecord(id: 'shot-2', workflowName: 'Workflow 2'));

      final result = await section.export();
      final list = result as List;
      expect(list, hasLength(2));
    });
  });

  group('import with skip strategy', () {
    test('imports new shots', () async {
      final record = _makeShotRecord();
      final json = record.toJson();

      final result = await section.import([json], ConflictStrategy.skip);

      expect(result.imported, equals(1));
      expect(result.skipped, equals(0));
      expect(result.errors, isEmpty);

      final stored = await storage.getShot('shot-1');
      expect(stored, isNotNull);
      expect(stored!.id, equals('shot-1'));
    });

    test('skips duplicate shots', () async {
      final record = _makeShotRecord();
      await storage.storeShot(record);

      final json = record.toJson();
      final result = await section.import([json], ConflictStrategy.skip);

      expect(result.imported, equals(0));
      expect(result.skipped, equals(1));
      expect(result.errors, isEmpty);
    });

    test('returns error for non-list data', () async {
      final result = await section.import(
        {'not': 'a list'},
        ConflictStrategy.skip,
      );

      expect(result.imported, equals(0));
      expect(result.errors, hasLength(1));
      expect(result.errors.first, contains('Expected JSON array'));
    });
  });

  group('import with overwrite strategy', () {
    test('imports new shots', () async {
      final record = _makeShotRecord();
      final json = record.toJson();

      final result =
          await section.import([json], ConflictStrategy.overwrite);

      expect(result.imported, equals(1));
      expect(result.errors, isEmpty);

      final stored = await storage.getShot('shot-1');
      expect(stored, isNotNull);
    });

    test('overwrites existing shots', () async {
      final original = _makeShotRecord(shotNotes: 'original');
      await storage.storeShot(original);

      final updated = _makeShotRecord(shotNotes: 'updated');
      final json = updated.toJson();
      final result =
          await section.import([json], ConflictStrategy.overwrite);

      expect(result.imported, equals(1));
      expect(result.errors, isEmpty);

      final stored = await storage.getShot('shot-1');
      expect(stored, isNotNull);
      expect(stored!.annotations?.espressoNotes, equals('updated'));
    });

    test('returns error for non-list data', () async {
      final result = await section.import(
        'not a list',
        ConflictStrategy.overwrite,
      );

      expect(result.imported, equals(0));
      expect(result.errors, hasLength(1));
      expect(result.errors.first, contains('Expected JSON array'));
    });

    test('collects errors for individual shot failures', () async {
      final validRecord = _makeShotRecord();
      final validJson = validRecord.toJson();
      final invalidJson = <String, dynamic>{'garbage': true};

      final result = await section.import(
        [validJson, invalidJson],
        ConflictStrategy.overwrite,
      );

      expect(result.imported, equals(1));
      expect(result.errors, hasLength(1));
      expect(result.errors.first, contains('Failed to import shot'));
    });
  });
}
