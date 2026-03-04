import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/data/bean.dart';
import 'package:reaprime/src/services/storage/bean_storage_service.dart';
import 'package:reaprime/src/services/webserver/data_export/bean_export_section.dart';
import 'package:reaprime/src/services/webserver/data_export/data_export_section.dart';

class MockBeanStorageService implements BeanStorageService {
  final List<Bean> beans = [];
  final List<BeanBatch> batches = [];

  @override
  Future<List<Bean>> getAllBeans({bool includeArchived = false}) async {
    if (includeArchived) return List.of(beans);
    return beans.where((b) => !b.archived).toList();
  }

  @override
  Stream<List<Bean>> watchAllBeans({bool includeArchived = false}) =>
      throw UnimplementedError();

  @override
  Future<Bean?> getBeanById(String id) async =>
      beans.where((b) => b.id == id).firstOrNull;

  @override
  Future<void> insertBean(Bean bean) async => beans.add(bean);

  @override
  Future<void> updateBean(Bean bean) async {
    beans.removeWhere((b) => b.id == bean.id);
    beans.add(bean);
  }

  @override
  Future<void> deleteBean(String id) async =>
      beans.removeWhere((b) => b.id == id);

  @override
  Future<List<BeanBatch>> getBatchesForBean(String beanId,
      {bool includeArchived = false}) async {
    final filtered = batches.where((b) => b.beanId == beanId);
    if (includeArchived) return filtered.toList();
    return filtered.where((b) => !b.archived).toList();
  }

  @override
  Stream<List<BeanBatch>> watchBatchesForBean(String beanId,
          {bool includeArchived = false}) =>
      throw UnimplementedError();

  @override
  Future<BeanBatch?> getBatchById(String id) async =>
      batches.where((b) => b.id == id).firstOrNull;

  @override
  Future<void> insertBatch(BeanBatch batch) async => batches.add(batch);

  @override
  Future<void> updateBatch(BeanBatch batch) async {
    batches.removeWhere((b) => b.id == batch.id);
    batches.add(batch);
  }

  @override
  Future<void> deleteBatch(String id) async =>
      batches.removeWhere((b) => b.id == id);

  @override
  Future<void> decrementBatchWeight(String batchId, double amount) async {}

  void reset() {
    beans.clear();
    batches.clear();
  }
}

Bean _makeBean({String id = 'bean-1', String roaster = 'Sey', String name = 'La Esperanza'}) {
  return Bean(
    id: id,
    roaster: roaster,
    name: name,
    createdAt: DateTime.parse('2024-01-15T10:00:00.000Z'),
    updatedAt: DateTime.parse('2024-01-15T10:00:00.000Z'),
  );
}

BeanBatch _makeBatch({
  String id = 'batch-1',
  String beanId = 'bean-1',
  String? roastLevel,
}) {
  return BeanBatch(
    id: id,
    beanId: beanId,
    roastLevel: roastLevel,
    createdAt: DateTime.parse('2024-01-15T10:00:00.000Z'),
    updatedAt: DateTime.parse('2024-01-15T10:00:00.000Z'),
  );
}

void main() {
  late MockBeanStorageService storage;
  late BeanExportSection section;

  setUp(() {
    storage = MockBeanStorageService();
    section = BeanExportSection(storage: storage);
  });

  tearDown(() => storage.reset());

  test('filename is beans.json', () {
    expect(section.filename, equals('beans.json'));
  });

  group('export', () {
    test('returns empty list when no beans exist', () async {
      final result = await section.export();
      expect(result, isA<List>());
      expect((result as List), isEmpty);
    });

    test('returns beans with embedded batches', () async {
      final bean = _makeBean();
      final batch = _makeBatch();
      storage.beans.add(bean);
      storage.batches.add(batch);

      final result = await section.export();
      final list = result as List;
      expect(list, hasLength(1));
      expect(list.first['id'], equals('bean-1'));
      expect(list.first['roaster'], equals('Sey'));
      expect(list.first['batches'], isA<List>());
      expect((list.first['batches'] as List), hasLength(1));
      expect(list.first['batches'][0]['id'], equals('batch-1'));
    });

    test('includes archived beans and batches', () async {
      storage.beans.add(_makeBean(id: 'bean-active'));
      storage.beans.add(_makeBean(id: 'bean-archived').copyWith(archived: true));
      storage.batches.add(_makeBatch(id: 'batch-archived', beanId: 'bean-archived').copyWith(archived: true));

      final result = await section.export();
      final list = result as List;
      expect(list, hasLength(2));
    });

    test('exports multiple beans with their respective batches', () async {
      storage.beans.add(_makeBean(id: 'bean-1'));
      storage.beans.add(_makeBean(id: 'bean-2', roaster: 'George Howell'));
      storage.batches.add(_makeBatch(id: 'batch-1', beanId: 'bean-1'));
      storage.batches.add(_makeBatch(id: 'batch-2', beanId: 'bean-2'));
      storage.batches.add(_makeBatch(id: 'batch-3', beanId: 'bean-2'));

      final result = await section.export();
      final list = result as List;
      expect(list, hasLength(2));

      final bean1 = list.firstWhere((b) => b['id'] == 'bean-1');
      final bean2 = list.firstWhere((b) => b['id'] == 'bean-2');
      expect((bean1['batches'] as List), hasLength(1));
      expect((bean2['batches'] as List), hasLength(2));
    });
  });

  group('import with skip strategy', () {
    test('imports new beans and batches', () async {
      final bean = _makeBean();
      final batch = _makeBatch();
      final json = bean.toJson();
      json['batches'] = [batch.toJson()];

      final result = await section.import([json], ConflictStrategy.skip);

      expect(result.imported, equals(2)); // 1 bean + 1 batch
      expect(result.skipped, equals(0));
      expect(result.errors, isEmpty);
      expect(storage.beans, hasLength(1));
      expect(storage.batches, hasLength(1));
    });

    test('skips duplicate beans and batches', () async {
      final bean = _makeBean();
      final batch = _makeBatch();
      storage.beans.add(bean);
      storage.batches.add(batch);

      final json = bean.toJson();
      json['batches'] = [batch.toJson()];

      final result = await section.import([json], ConflictStrategy.skip);

      expect(result.imported, equals(0));
      expect(result.skipped, equals(2)); // 1 bean + 1 batch
    });

    test('imports bean without batches', () async {
      final json = _makeBean().toJson();
      // No 'batches' key

      final result = await section.import([json], ConflictStrategy.skip);

      expect(result.imported, equals(1));
      expect(storage.beans, hasLength(1));
      expect(storage.batches, isEmpty);
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
    test('overwrites existing beans', () async {
      storage.beans.add(_makeBean(name: 'Original'));

      final json = _makeBean(name: 'Updated').toJson();
      final result = await section.import([json], ConflictStrategy.overwrite);

      expect(result.imported, equals(1));
      expect(storage.beans.first.name, equals('Updated'));
    });

    test('overwrites existing batches', () async {
      storage.beans.add(_makeBean());
      storage.batches.add(_makeBatch(roastLevel: 'Light'));

      final bean = _makeBean();
      final beanJson = bean.toJson();
      beanJson['batches'] = [_makeBatch(roastLevel: 'Dark').toJson()];

      final result = await section.import([beanJson], ConflictStrategy.overwrite);

      expect(result.imported, equals(2)); // bean + batch
      expect(storage.batches.first.roastLevel, equals('Dark'));
    });

    test('collects errors for individual failures', () async {
      final validJson = _makeBean().toJson();
      final invalidJson = <String, dynamic>{'garbage': true};

      final result = await section.import(
        [validJson, invalidJson],
        ConflictStrategy.overwrite,
      );

      expect(result.imported, equals(1));
      expect(result.errors, hasLength(1));
      expect(result.errors.first, contains('Failed to import bean'));
    });
  });
}
