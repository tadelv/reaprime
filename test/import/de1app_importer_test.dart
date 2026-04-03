import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/import/de1app_importer.dart';
import 'package:reaprime/src/import/import_result.dart';
import 'package:reaprime/src/models/data/bean.dart';
import 'package:reaprime/src/models/data/grinder.dart';
import 'package:reaprime/src/models/data/profile_record.dart';
import 'package:reaprime/src/models/data/shot_record.dart';
import 'package:reaprime/src/models/data/workflow.dart';
import 'package:reaprime/src/services/storage/bean_storage_service.dart';
import 'package:reaprime/src/services/storage/grinder_storage_service.dart';
import 'package:reaprime/src/services/storage/profile_storage_service.dart';
import 'package:reaprime/src/services/storage/storage_service.dart';

// ---------------------------------------------------------------------------
// In-memory fake implementations
// ---------------------------------------------------------------------------

class FakeStorageService implements StorageService {
  final shots = <String, ShotRecord>{};
  final List<String> _existingIds;

  FakeStorageService({List<String>? existingIds})
      : _existingIds = existingIds ?? [];

  @override
  Future<void> storeShot(ShotRecord record) async =>
      shots[record.id] = record;

  @override
  Future<List<String>> getShotIds() async => List.unmodifiable(_existingIds);

  // Stubbed — not needed for import tests
  @override
  Future<void> updateShot(ShotRecord record) => throw UnimplementedError();
  @override
  Future<void> deleteShot(String id) => throw UnimplementedError();
  @override
  Future<List<ShotRecord>> getAllShots() => throw UnimplementedError();
  @override
  Future<ShotRecord?> getShot(String id) => throw UnimplementedError();
  @override
  Future<void> storeCurrentWorkflow(Workflow workflow) =>
      throw UnimplementedError();
  @override
  Future<Workflow?> loadCurrentWorkflow() => throw UnimplementedError();
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
  }) => throw UnimplementedError();
  @override
  Future<int> countShots({
    String? grinderId,
    String? grinderModel,
    String? beanBatchId,
    String? coffeeName,
    String? coffeeRoaster,
    String? profileTitle,
  }) => throw UnimplementedError();
  @override
  Future<ShotRecord?> getLatestShot() => throw UnimplementedError();
  @override
  Future<ShotRecord?> getLatestShotMeta() => throw UnimplementedError();
}

class FakeProfileStorageService implements ProfileStorageService {
  final profiles = <String, ProfileRecord>{};

  @override
  Future<void> store(ProfileRecord record) async =>
      profiles[record.id] = record;

  @override
  Future<ProfileRecord?> get(String id) async => profiles[id];

  @override
  Future<void> initialize() async {}

  @override
  Future<List<ProfileRecord>> getAll({Visibility? visibility}) async =>
      profiles.values.toList();

  @override
  Future<void> update(ProfileRecord record) async =>
      profiles[record.id] = record;

  @override
  Future<void> delete(String id) async => profiles.remove(id);

  @override
  Future<bool> exists(String id) async => profiles.containsKey(id);

  @override
  Future<List<String>> getAllIds() async => profiles.keys.toList();

  @override
  Future<List<ProfileRecord>> getByParentId(String parentId) async => [];

  @override
  Future<void> storeAll(List<ProfileRecord> records) async {
    for (final r in records) {
      profiles[r.id] = r;
    }
  }

  @override
  Future<void> clear() async => profiles.clear();

  @override
  Future<int> count({Visibility? visibility}) async => profiles.length;
}

class FakeBeanStorageService implements BeanStorageService {
  final beans = <String, Bean>{};
  final batches = <String, BeanBatch>{};

  @override
  Future<void> insertBean(Bean bean) async => beans[bean.id] = bean;

  @override
  Future<void> insertBatch(BeanBatch batch) async =>
      batches[batch.id] = batch;

  @override
  Future<List<Bean>> getAllBeans({bool includeArchived = false}) async =>
      beans.values.toList();

  @override
  Stream<List<Bean>> watchAllBeans({bool includeArchived = false}) =>
      throw UnimplementedError();

  @override
  Future<Bean?> getBeanById(String id) async => beans[id];

  @override
  Future<void> updateBean(Bean bean) async => beans[bean.id] = bean;

  @override
  Future<void> deleteBean(String id) async => beans.remove(id);

  @override
  Future<List<BeanBatch>> getBatchesForBean(String beanId,
          {bool includeArchived = false}) async =>
      batches.values.where((b) => b.beanId == beanId).toList();

  @override
  Stream<List<BeanBatch>> watchBatchesForBean(String beanId,
          {bool includeArchived = false}) =>
      throw UnimplementedError();

  @override
  Future<BeanBatch?> getBatchById(String id) async => batches[id];

  @override
  Future<void> updateBatch(BeanBatch batch) async =>
      batches[batch.id] = batch;

  @override
  Future<void> deleteBatch(String id) async => batches.remove(id);

  @override
  Future<void> decrementBatchWeight(String batchId, double amount) =>
      throw UnimplementedError();
}

class FakeGrinderStorageService implements GrinderStorageService {
  final grinders = <String, Grinder>{};

  @override
  Future<void> insertGrinder(Grinder grinder) async =>
      grinders[grinder.id] = grinder;

  @override
  Future<List<Grinder>> getAllGrinders({bool includeArchived = false}) async =>
      grinders.values.toList();

  @override
  Stream<List<Grinder>> watchAllGrinders({bool includeArchived = false}) =>
      throw UnimplementedError();

  @override
  Future<Grinder?> getGrinderById(String id) async => grinders[id];

  @override
  Future<void> updateGrinder(Grinder grinder) async =>
      grinders[grinder.id] = grinder;

  @override
  Future<void> deleteGrinder(String id) async => grinders.remove(id);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

De1appImporter makeImporter({
  FakeStorageService? storage,
  FakeProfileStorageService? profileStorage,
  FakeBeanStorageService? beanStorage,
  FakeGrinderStorageService? grinderStorage,
}) {
  return De1appImporter(
    storageService: storage ?? FakeStorageService(),
    profileStorageService: profileStorage ?? FakeProfileStorageService(),
    beanStorageService: beanStorage ?? FakeBeanStorageService(),
    grinderStorageService: grinderStorage ?? FakeGrinderStorageService(),
  );
}

const _fixturesPath = 'test/fixtures/de1app';

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('De1appImporter', () {
    group('imports shots from history_v2', () {
      late FakeStorageService storage;
      late ImportResult result;

      setUpAll(() async {
        storage = FakeStorageService();
        final scanResult = ScanResult(
          shotCount: 1,
          profileCount: 1,
          hasDyeGrinders: true,
          sourcePath: _fixturesPath,
          shotSource: 'history_v2',
        );
        result = await makeImporter(storage: storage).import(scanResult);
      });

      test('imports exactly 1 shot', () {
        expect(result.shotsImported, equals(1));
      });

      test('shot is stored in storage service', () {
        expect(storage.shots, hasLength(1));
      });

      test('no shots skipped', () {
        expect(result.shotsSkipped, equals(0));
      });
    });

    group('imports profiles from profiles_v2', () {
      late FakeProfileStorageService profileStorage;
      late ImportResult result;

      setUpAll(() async {
        profileStorage = FakeProfileStorageService();
        final scanResult = ScanResult(
          shotCount: 0,
          profileCount: 1,
          hasDyeGrinders: false,
          sourcePath: _fixturesPath,
          shotSource: null,
        );
        result = await makeImporter(profileStorage: profileStorage)
            .import(scanResult);
      });

      test('imports exactly 1 profile', () {
        expect(result.profilesImported, equals(1));
      });

      test('profile is stored in profile storage service', () {
        expect(profileStorage.profiles, hasLength(1));
      });

      test('no profiles skipped', () {
        expect(result.profilesSkipped, equals(0));
      });
    });

    group('creates bean and grinder entities', () {
      late FakeBeanStorageService beanStorage;
      late FakeGrinderStorageService grinderStorage;
      late ImportResult result;

      setUpAll(() async {
        beanStorage = FakeBeanStorageService();
        grinderStorage = FakeGrinderStorageService();
        final scanResult = ScanResult(
          shotCount: 1,
          profileCount: 0,
          hasDyeGrinders: false,
          sourcePath: _fixturesPath,
          shotSource: 'history_v2',
        );
        result = await makeImporter(
          beanStorage: beanStorage,
          grinderStorage: grinderStorage,
        ).import(scanResult);
      });

      test('creates at least one bean', () {
        expect(result.beansCreated, greaterThan(0));
        expect(beanStorage.beans, isNotEmpty);
      });

      test('creates at least one bean batch', () {
        expect(beanStorage.batches, isNotEmpty);
      });

      test('creates at least one grinder', () {
        expect(result.grindersCreated, greaterThan(0));
        expect(grinderStorage.grinders, isNotEmpty);
      });
    });

    group('skips duplicate shots', () {
      late FakeStorageService storage;
      late ImportResult result;

      setUpAll(() async {
        // The fixture shot has id 'de1app-1710510622'
        storage = FakeStorageService(existingIds: ['de1app-1710510622']);
        final scanResult = ScanResult(
          shotCount: 1,
          profileCount: 0,
          hasDyeGrinders: false,
          sourcePath: _fixturesPath,
          shotSource: 'history_v2',
        );
        result = await makeImporter(storage: storage).import(scanResult);
      });

      test('skips the duplicate shot', () {
        expect(result.shotsSkipped, equals(1));
      });

      test('does not import the duplicate', () {
        expect(result.shotsImported, equals(0));
      });

      test('nothing written to storage', () {
        expect(storage.shots, isEmpty);
      });
    });

    group('continues on parse errors', () {
      late Directory tempDir;
      late ImportResult result;

      setUpAll(() async {
        tempDir = await Directory.systemTemp.createTemp('de1app_importer_err_');

        // Copy the valid fixture shot
        final validFile = File('$_fixturesPath/history_v2/20240315T143022.json');
        final historyV2 = Directory('${tempDir.path}/history_v2');
        await historyV2.create();
        await validFile.copy('${tempDir.path}/history_v2/valid.json');

        // Create a malformed file
        await File('${tempDir.path}/history_v2/bad.json').writeAsString(
          'THIS IS NOT JSON {{{',
        );

        final scanResult = ScanResult(
          shotCount: 2,
          profileCount: 0,
          hasDyeGrinders: false,
          sourcePath: tempDir.path,
          shotSource: 'history_v2',
        );

        result = await makeImporter().import(scanResult);
      });

      tearDownAll(() async {
        await tempDir.delete(recursive: true);
      });

      test('records an error for the bad file', () {
        expect(result.errors, hasLength(1));
        expect(result.errors.first.filename, equals('bad.json'));
      });

      test('still imports the valid shot', () {
        expect(result.shotsImported, equals(1));
      });
    });

    group('fires progress callbacks', () {
      test('fires shot progress callbacks', () async {
        final progressEvents = <ImportProgress>[];
        final scanResult = ScanResult(
          shotCount: 1,
          profileCount: 0,
          hasDyeGrinders: false,
          sourcePath: _fixturesPath,
          shotSource: 'history_v2',
        );

        await makeImporter().import(
          scanResult,
          onProgress: progressEvents.add,
        );

        final shotEvents = progressEvents.where((e) => e.phase == 'shots');
        expect(shotEvents, isNotEmpty);
        expect(shotEvents.last.current, equals(1));
        expect(shotEvents.last.total, equals(1));
      });

      test('fires profile progress callbacks', () async {
        final progressEvents = <ImportProgress>[];
        final scanResult = ScanResult(
          shotCount: 0,
          profileCount: 1,
          hasDyeGrinders: false,
          sourcePath: _fixturesPath,
          shotSource: null,
        );

        await makeImporter().import(
          scanResult,
          onProgress: progressEvents.add,
        );

        final profileEvents =
            progressEvents.where((e) => e.phase == 'profiles');
        expect(profileEvents, isNotEmpty);
        expect(profileEvents.last.current, equals(1));
        expect(profileEvents.last.total, equals(1));
      });
    });

    group('merges DYE grinder specs when available', () {
      late FakeGrinderStorageService grinderStorage;
      late ImportResult result;

      setUpAll(() async {
        grinderStorage = FakeGrinderStorageService();
        final scanResult = ScanResult(
          shotCount: 1,
          profileCount: 0,
          hasDyeGrinders: true,
          sourcePath: _fixturesPath,
          shotSource: 'history_v2',
        );
        result = await makeImporter(grinderStorage: grinderStorage)
            .import(scanResult);
      });

      test('stores grinders after DYE merge', () {
        expect(grinderStorage.grinders, isNotEmpty);
        expect(result.grindersCreated, greaterThan(0));
      });
    });

    group('links shots to bean batch and grinder IDs', () {
      late FakeStorageService storage;

      setUpAll(() async {
        storage = FakeStorageService();
        final scanResult = ScanResult(
          shotCount: 1,
          profileCount: 0,
          hasDyeGrinders: false,
          sourcePath: _fixturesPath,
          shotSource: 'history_v2',
        );
        await makeImporter(storage: storage).import(scanResult);
      });

      test('stored shot has beanBatchId in workflow context', () {
        expect(storage.shots, hasLength(1));
        final shot = storage.shots.values.first;
        final context = shot.workflow.context;
        expect(context, isNotNull);
        expect(context!.beanBatchId, isNotNull);
      });

      test('stored shot has grinderId in workflow context', () {
        final shot = storage.shots.values.first;
        final context = shot.workflow.context;
        expect(context, isNotNull);
        expect(context!.grinderId, isNotNull);
      });
    });
  });
}
