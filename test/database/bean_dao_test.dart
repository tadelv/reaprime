import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/services/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  BeansCompanion _makeBean({
    String id = 'bean-1',
    String roaster = 'Test Roaster',
    String name = 'Test Bean',
    bool archived = false,
  }) {
    final now = DateTime.now();
    return BeansCompanion(
      id: Value(id),
      roaster: Value(roaster),
      name: Value(name),
      archived: Value(archived),
      createdAt: Value(now),
      updatedAt: Value(now),
    );
  }

  BeanBatchesCompanion _makeBatch({
    String id = 'batch-1',
    String beanId = 'bean-1',
    double? weight,
    double? weightRemaining,
    bool archived = false,
  }) {
    final now = DateTime.now();
    return BeanBatchesCompanion(
      id: Value(id),
      beanId: Value(beanId),
      weight: Value(weight),
      weightRemaining: Value(weightRemaining),
      archived: Value(archived),
      createdAt: Value(now),
      updatedAt: Value(now),
    );
  }

  group('BeanDao - Beans', () {
    test('inserts and retrieves a bean', () async {
      await db.beanDao.insertBean(_makeBean());
      final beans = await db.beanDao.getAllBeans();
      expect(beans, hasLength(1));
      expect(beans.first.roaster, 'Test Roaster');
      expect(beans.first.name, 'Test Bean');
    });

    test('filters archived beans by default', () async {
      await db.beanDao.insertBean(_makeBean(id: 'b1'));
      await db.beanDao.insertBean(_makeBean(id: 'b2', archived: true));

      final active = await db.beanDao.getAllBeans();
      expect(active, hasLength(1));
      expect(active.first.id, 'b1');

      final all = await db.beanDao.getAllBeans(includeArchived: true);
      expect(all, hasLength(2));
    });

    test('gets bean by ID', () async {
      await db.beanDao.insertBean(_makeBean(id: 'b1', name: 'Special'));
      final bean = await db.beanDao.getBeanById('b1');
      expect(bean, isNotNull);
      expect(bean!.name, 'Special');
    });

    test('returns null for missing bean', () async {
      final bean = await db.beanDao.getBeanById('nonexistent');
      expect(bean, isNull);
    });

    test('updates a bean', () async {
      await db.beanDao.insertBean(_makeBean(id: 'b1', name: 'Original'));
      await db.beanDao.updateBean(BeansCompanion(
        id: const Value('b1'),
        name: const Value('Updated'),
        updatedAt: Value(DateTime.now()),
      ));
      final bean = await db.beanDao.getBeanById('b1');
      expect(bean!.name, 'Updated');
    });

    test('deletes a bean', () async {
      await db.beanDao.insertBean(_makeBean(id: 'b1'));
      await db.beanDao.deleteBean('b1');
      final beans = await db.beanDao.getAllBeans(includeArchived: true);
      expect(beans, isEmpty);
    });

    test('watches bean changes', () async {
      final stream = db.beanDao.watchAllBeans();

      await db.beanDao.insertBean(_makeBean(id: 'b1'));
      await db.beanDao.insertBean(_makeBean(id: 'b2'));

      // First emission after both inserts should have 2 beans
      final beans = await stream.first;
      expect(beans, hasLength(2));
    });
  });

  group('BeanDao - BeanBatches', () {
    test('inserts and retrieves batches for a bean', () async {
      await db.beanDao.insertBean(_makeBean(id: 'bean-1'));
      await db.beanDao.insertBatch(_makeBatch(id: 'batch-1'));
      await db.beanDao.insertBatch(
          _makeBatch(id: 'batch-2', beanId: 'bean-1'));

      final batches = await db.beanDao.getBatchesForBean('bean-1');
      expect(batches, hasLength(2));
    });

    test('filters archived batches by default', () async {
      await db.beanDao.insertBean(_makeBean(id: 'bean-1'));
      await db.beanDao.insertBatch(_makeBatch(id: 'b1'));
      await db.beanDao
          .insertBatch(_makeBatch(id: 'b2', archived: true));

      final active = await db.beanDao.getBatchesForBean('bean-1');
      expect(active, hasLength(1));

      final all = await db.beanDao
          .getBatchesForBean('bean-1', includeArchived: true);
      expect(all, hasLength(2));
    });

    test('decrements batch weight', () async {
      await db.beanDao.insertBean(_makeBean(id: 'bean-1'));
      await db.beanDao.insertBatch(
          _makeBatch(id: 'batch-1', weight: 250.0, weightRemaining: 250.0));

      await db.beanDao.decrementBatchWeight('batch-1', 18.0);

      final batch = await db.beanDao.getBatchById('batch-1');
      expect(batch!.weightRemaining, closeTo(232.0, 0.01));
    });

    test('weight does not go below zero', () async {
      await db.beanDao.insertBean(_makeBean(id: 'bean-1'));
      await db.beanDao.insertBatch(
          _makeBatch(id: 'batch-1', weight: 10.0, weightRemaining: 5.0));

      await db.beanDao.decrementBatchWeight('batch-1', 20.0);

      final batch = await db.beanDao.getBatchById('batch-1');
      expect(batch!.weightRemaining, 0.0);
    });

    test('foreign key enforced - cannot insert batch for nonexistent bean',
        () async {
      expect(
        () => db.beanDao.insertBatch(_makeBatch(beanId: 'no-such-bean')),
        throwsA(anything),
      );
    });
  });
}
