import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/profile_controller.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/data/profile_record.dart';
import 'package:reaprime/src/services/webserver/data_export/data_export_section.dart';
import 'package:reaprime/src/services/webserver/data_export/profile_export_section.dart';
import 'package:reaprime/src/services/storage/profile_storage_service.dart';

/// Mock implementation of ProfileStorageService for testing.
/// Mirrors the one in profile_test.dart.
class MockProfileStorage implements ProfileStorageService {
  final Map<String, ProfileRecord> _storage = {};

  @override
  Future<void> initialize() async {}

  @override
  Future<void> store(ProfileRecord record) async {
    _storage[record.id] = record;
  }

  @override
  Future<ProfileRecord?> get(String id) async {
    return _storage[id];
  }

  @override
  Future<List<ProfileRecord>> getAll({Visibility? visibility}) async {
    if (visibility == null) {
      return _storage.values.toList();
    }
    return _storage.values
        .where((record) => record.visibility == visibility)
        .toList();
  }

  @override
  Future<void> update(ProfileRecord record) async {
    if (!_storage.containsKey(record.id)) {
      throw Exception('Profile not found');
    }
    _storage[record.id] = record;
  }

  @override
  Future<void> delete(String id) async {
    _storage.remove(id);
  }

  @override
  Future<bool> exists(String id) async {
    return _storage.containsKey(id);
  }

  @override
  Future<List<String>> getAllIds() async {
    return _storage.keys.toList();
  }

  @override
  Future<List<ProfileRecord>> getByParentId(String parentId) async {
    return _storage.values
        .where((record) => record.parentId == parentId)
        .toList();
  }

  @override
  Future<void> storeAll(List<ProfileRecord> records) async {
    for (final record in records) {
      _storage[record.id] = record;
    }
  }

  @override
  Future<void> clear() async {
    _storage.clear();
  }

  @override
  Future<int> count({Visibility? visibility}) async {
    if (visibility == null) {
      return _storage.length;
    }
    return _storage.values
        .where((record) => record.visibility == visibility)
        .length;
  }

  void reset() {
    _storage.clear();
  }
}

Profile _makeProfile({
  double temperature = 93.0,
  String title = 'Test Profile',
}) {
  return Profile(
    version: '2',
    title: title,
    author: 'Test Author',
    notes: 'Test notes',
    beverageType: BeverageType.espresso,
    steps: [],
    tankTemperature: temperature,
    targetWeight: 36.0,
    targetVolumeCountStart: 0,
  );
}

void main() {
  late MockProfileStorage storage;
  late ProfileController controller;
  late ProfileExportSection section;

  setUp(() {
    storage = MockProfileStorage();
    controller = ProfileController(storage: storage);
    section = ProfileExportSection(controller: controller);
  });

  tearDown(() {
    storage.reset();
    controller.dispose();
  });

  test('filename is profiles.json', () {
    expect(section.filename, equals('profiles.json'));
  });

  group('export', () {
    test('returns empty list when no profiles exist', () async {
      final result = await section.export();
      expect(result, isA<List>());
      expect((result as List), isEmpty);
    });

    test('returns list of profile JSON maps', () async {
      final record = ProfileRecord.create(
        profile: _makeProfile(),
        isDefault: false,
      );
      await storage.store(record);

      final result = await section.export();
      expect(result, isA<List>());
      final list = result as List<Map<String, dynamic>>;
      expect(list, hasLength(1));
      expect(list.first['id'], equals(record.id));
      expect(list.first['profile'], isA<Map<String, dynamic>>());
    });

    test('includes hidden and deleted profiles', () async {
      final visibleRecord = ProfileRecord.create(
        profile: _makeProfile(temperature: 93.0),
        isDefault: false,
      );
      final hiddenRecord = ProfileRecord.create(
        profile: _makeProfile(temperature: 94.0),
        isDefault: false,
      ).copyWith(visibility: Visibility.hidden);
      final deletedRecord = ProfileRecord.create(
        profile: _makeProfile(temperature: 95.0),
        isDefault: false,
      ).copyWith(visibility: Visibility.deleted);

      await storage.store(visibleRecord);
      await storage.store(hiddenRecord);
      await storage.store(deletedRecord);

      final result = await section.export();
      final list = result as List<Map<String, dynamic>>;
      expect(list, hasLength(3));
    });
  });

  group('import with skip strategy', () {
    test('imports new profiles', () async {
      final record = ProfileRecord.create(
        profile: _makeProfile(),
        isDefault: false,
      );
      final json = record.toJson();

      final result = await section.import([json], ConflictStrategy.skip);

      expect(result.imported, equals(1));
      expect(result.skipped, equals(0));
      expect(result.errors, isEmpty);

      final stored = await storage.get(record.id);
      expect(stored, isNotNull);
    });

    test('skips duplicate profiles', () async {
      final record = ProfileRecord.create(
        profile: _makeProfile(),
        isDefault: false,
      );
      await storage.store(record);

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
    test('imports new profiles', () async {
      final record = ProfileRecord.create(
        profile: _makeProfile(),
        isDefault: false,
      );
      final json = record.toJson();

      final result = await section.import([json], ConflictStrategy.overwrite);

      expect(result.imported, equals(1));
      expect(result.errors, isEmpty);

      final stored = await storage.get(record.id);
      expect(stored, isNotNull);
    });

    test('overwrites existing profiles', () async {
      final originalProfile = _makeProfile(title: 'Original');
      final originalRecord = ProfileRecord.create(
        profile: originalProfile,
        isDefault: false,
        metadata: {'source': 'original'},
      );
      await storage.store(originalRecord);

      // Create a new record with same execution fields (same ID) but different metadata
      final updatedProfile = _makeProfile(title: 'Updated');
      final updatedRecord = ProfileRecord.create(
        profile: updatedProfile,
        isDefault: false,
        metadata: {'source': 'updated'},
      );

      // Same execution fields means same ID
      expect(updatedRecord.id, equals(originalRecord.id));

      final json = updatedRecord.toJson();
      final result = await section.import([json], ConflictStrategy.overwrite);

      expect(result.imported, equals(1));
      expect(result.errors, isEmpty);

      final stored = await storage.get(originalRecord.id);
      expect(stored, isNotNull);
      expect(stored!.metadata?['source'], equals('updated'));
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

    test('collects errors for individual profile failures', () async {
      final validRecord = ProfileRecord.create(
        profile: _makeProfile(),
        isDefault: false,
      );
      final validJson = validRecord.toJson();
      final invalidJson = <String, dynamic>{'garbage': true};

      final result = await section.import(
        [validJson, invalidJson],
        ConflictStrategy.overwrite,
      );

      expect(result.imported, equals(1));
      expect(result.errors, hasLength(1));
    });
  });
}
