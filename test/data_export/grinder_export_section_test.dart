import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/data/grinder.dart';
import 'package:reaprime/src/services/storage/grinder_storage_service.dart';
import 'package:reaprime/src/services/webserver/data_export/data_export_section.dart';
import 'package:reaprime/src/services/webserver/data_export/grinder_export_section.dart';

class MockGrinderStorageService implements GrinderStorageService {
  final List<Grinder> grinders = [];

  @override
  Future<List<Grinder>> getAllGrinders({bool includeArchived = false}) async {
    if (includeArchived) return List.of(grinders);
    return grinders.where((g) => !g.archived).toList();
  }

  @override
  Stream<List<Grinder>> watchAllGrinders({bool includeArchived = false}) =>
      throw UnimplementedError();

  @override
  Future<Grinder?> getGrinderById(String id) async =>
      grinders.where((g) => g.id == id).firstOrNull;

  @override
  Future<void> insertGrinder(Grinder grinder) async => grinders.add(grinder);

  @override
  Future<void> updateGrinder(Grinder grinder) async {
    grinders.removeWhere((g) => g.id == grinder.id);
    grinders.add(grinder);
  }

  @override
  Future<void> deleteGrinder(String id) async =>
      grinders.removeWhere((g) => g.id == id);

  void reset() => grinders.clear();
}

Grinder _makeGrinder({
  String id = 'grinder-1',
  String model = 'Niche Zero',
}) {
  return Grinder(
    id: id,
    model: model,
    settingType: GrinderSettingType.numeric,
    createdAt: DateTime.parse('2024-01-15T10:00:00.000Z'),
    updatedAt: DateTime.parse('2024-01-15T10:00:00.000Z'),
  );
}

void main() {
  late MockGrinderStorageService storage;
  late GrinderExportSection section;

  setUp(() {
    storage = MockGrinderStorageService();
    section = GrinderExportSection(storage: storage);
  });

  tearDown(() => storage.reset());

  test('filename is grinders.json', () {
    expect(section.filename, equals('grinders.json'));
  });

  group('export', () {
    test('returns empty list when no grinders exist', () async {
      final result = await section.export();
      expect(result, isA<List>());
      expect((result as List), isEmpty);
    });

    test('returns list of grinder JSON maps', () async {
      storage.grinders.add(_makeGrinder());

      final result = await section.export();
      final list = result as List;
      expect(list, hasLength(1));
      expect(list.first['id'], equals('grinder-1'));
      expect(list.first['model'], equals('Niche Zero'));
    });

    test('includes archived grinders', () async {
      storage.grinders.add(_makeGrinder(id: 'active'));
      storage.grinders
          .add(_makeGrinder(id: 'archived').copyWith(archived: true));

      final result = await section.export();
      expect((result as List), hasLength(2));
    });

    test('exports multiple grinders', () async {
      storage.grinders.add(_makeGrinder(id: 'g-1', model: 'Niche Zero'));
      storage.grinders.add(_makeGrinder(id: 'g-2', model: 'Lagom P64'));

      final result = await section.export();
      expect((result as List), hasLength(2));
    });
  });

  group('import with skip strategy', () {
    test('imports new grinders', () async {
      final json = _makeGrinder().toJson();

      final result = await section.import([json], ConflictStrategy.skip);

      expect(result.imported, equals(1));
      expect(result.skipped, equals(0));
      expect(result.errors, isEmpty);
      expect(storage.grinders, hasLength(1));
    });

    test('skips duplicate grinders', () async {
      storage.grinders.add(_makeGrinder());

      final json = _makeGrinder().toJson();
      final result = await section.import([json], ConflictStrategy.skip);

      expect(result.imported, equals(0));
      expect(result.skipped, equals(1));
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
    test('overwrites existing grinders', () async {
      storage.grinders.add(_makeGrinder(model: 'Original'));

      final json = _makeGrinder(model: 'Updated').toJson();
      final result =
          await section.import([json], ConflictStrategy.overwrite);

      expect(result.imported, equals(1));
      expect(storage.grinders.first.model, equals('Updated'));
    });

    test('imports new grinders', () async {
      final json = _makeGrinder().toJson();
      final result =
          await section.import([json], ConflictStrategy.overwrite);

      expect(result.imported, equals(1));
      expect(storage.grinders, hasLength(1));
    });

    test('collects errors for individual failures', () async {
      final validJson = _makeGrinder().toJson();
      final invalidJson = <String, dynamic>{'garbage': true};

      final result = await section.import(
        [validJson, invalidJson],
        ConflictStrategy.overwrite,
      );

      expect(result.imported, equals(1));
      expect(result.errors, hasLength(1));
      expect(result.errors.first, contains('Failed to import grinder'));
    });
  });
}
