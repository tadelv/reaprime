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

  GrindersCompanion _makeGrinder({
    String id = 'grinder-1',
    String model = 'Test Grinder',
    bool archived = false,
  }) {
    final now = DateTime.now();
    return GrindersCompanion(
      id: Value(id),
      model: Value(model),
      archived: Value(archived),
      createdAt: Value(now),
      updatedAt: Value(now),
    );
  }

  test('inserts and retrieves a grinder', () async {
    await db.grinderDao.insertGrinder(_makeGrinder());
    final grinders = await db.grinderDao.getAllGrinders();
    expect(grinders, hasLength(1));
    expect(grinders.first.model, 'Test Grinder');
  });

  test('filters archived grinders by default', () async {
    await db.grinderDao.insertGrinder(_makeGrinder(id: 'g1'));
    await db.grinderDao
        .insertGrinder(_makeGrinder(id: 'g2', archived: true));

    final active = await db.grinderDao.getAllGrinders();
    expect(active, hasLength(1));

    final all = await db.grinderDao.getAllGrinders(includeArchived: true);
    expect(all, hasLength(2));
  });

  test('gets grinder by ID', () async {
    await db.grinderDao
        .insertGrinder(_makeGrinder(id: 'g1', model: 'Niche Zero'));
    final grinder = await db.grinderDao.getGrinderById('g1');
    expect(grinder, isNotNull);
    expect(grinder!.model, 'Niche Zero');
  });

  test('updates a grinder', () async {
    await db.grinderDao
        .insertGrinder(_makeGrinder(id: 'g1', model: 'Old'));
    await db.grinderDao.updateGrinder(GrindersCompanion(
      id: const Value('g1'),
      model: const Value('New'),
      updatedAt: Value(DateTime.now()),
    ));
    final grinder = await db.grinderDao.getGrinderById('g1');
    expect(grinder!.model, 'New');
  });

  test('deletes a grinder', () async {
    await db.grinderDao.insertGrinder(_makeGrinder(id: 'g1'));
    await db.grinderDao.deleteGrinder('g1');
    final grinders =
        await db.grinderDao.getAllGrinders(includeArchived: true);
    expect(grinders, isEmpty);
  });

  test('watches grinder changes', () async {
    final stream = db.grinderDao.watchAllGrinders();
    await db.grinderDao.insertGrinder(_makeGrinder(id: 'g1'));
    final grinders = await stream.first;
    expect(grinders, hasLength(1));
  });

  test('stores setting type and values', () async {
    final now = DateTime.now();
    await db.grinderDao.insertGrinder(GrindersCompanion(
      id: const Value('g1'),
      model: const Value('DYE2'),
      settingType: const Value('preset'),
      settingValues: const Value(['Coarse', 'Medium', 'Fine']),
      createdAt: Value(now),
      updatedAt: Value(now),
    ));

    final grinder = await db.grinderDao.getGrinderById('g1');
    expect(grinder!.settingType, 'preset');
    expect(grinder.settingValues, ['Coarse', 'Medium', 'Fine']);
  });
}
