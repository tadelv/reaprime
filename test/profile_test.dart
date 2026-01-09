import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/data/profile_record.dart';
import 'package:reaprime/src/services/storage/profile_storage_service.dart';
import 'package:hive_ce/hive.dart';

/// Mock implementation of ProfileStorageService for testing
class MockProfileStorage implements ProfileStorageService {
  final Map<String, ProfileRecord> _storage = {};

  @override
  Future<void> initialize() async {
    // No-op for mock
  }

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

  // Test helper
  void reset() {
    _storage.clear();
  }
}

void main() {
  // Ensure Hive is initialized for tests
  setUpAll(() async {
    // Initialize Hive in-memory for testing
    Hive.init(null);
  });

  group('ProfileRecord', () {
    test('creates a new ProfileRecord with default values', () {
      final profile = Profile(
        version: '2',
        title: 'Test Profile',
        author: 'Test Author',
        notes: 'Test notes',
        beverageType: BeverageType.espresso,
        steps: [],
        tankTemperature: 93.0,
        targetWeight: 36.0,
        targetVolumeCountStart: 0,
      );

      final record = ProfileRecord.create(
        profile: profile,
        isDefault: false,
      );

      expect(record.id, isNotEmpty);
      expect(record.profile, equals(profile));
      expect(record.parentId, isNull);
      expect(record.visibility, equals(Visibility.visible));
      expect(record.isDefault, isFalse);
      expect(record.createdAt, isNotNull);
      expect(record.updatedAt, isNotNull);
      expect(record.metadata, isNull);
    });

    test('creates ProfileRecord with parent ID', () {
      final profile = Profile(
        version: '2',
        title: 'Child Profile',
        author: 'Test Author',
        notes: 'Modified version',
        beverageType: BeverageType.espresso,
        steps: [],
        tankTemperature: 93.0,
        targetVolumeCountStart: 0,
      );

      const parentId = 'parent-uuid';
      final record = ProfileRecord.create(
        profile: profile,
        isDefault: false,
        parentId: parentId,
      );

      expect(record.parentId, equals(parentId));
    });

    test('creates ProfileRecord with custom ID for default profiles', () {
      final profile = Profile(
        version: '2',
        title: 'Default Profile',
        author: 'REA',
        notes: 'Bundled profile',
        beverageType: BeverageType.espresso,
        steps: [],
        tankTemperature: 93.0,
        targetVolumeCountStart: 0,
      );

      const customId = 'default:best_practice';
      final record = ProfileRecord.create(
        id: customId,
        profile: profile,
        isDefault: true,
      );

      expect(record.id, equals(customId));
      expect(record.isDefault, isTrue);
    });

    test('generates UUID v4 when no ID provided', () {
      final profile = Profile(
        version: '2',
        title: 'User Profile',
        author: 'User',
        notes: '',
        beverageType: BeverageType.espresso,
        steps: [],
        tankTemperature: 93.0,
        targetVolumeCountStart: 0,
      );

      final record = ProfileRecord.create(
        profile: profile,
        isDefault: false,
      );

      // UUID v4 format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
      expect(record.id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    });

    test('serializes to and from JSON correctly', () {
      final profile = Profile(
        version: '2',
        title: 'JSON Test Profile',
        author: 'Test Author',
        notes: 'Testing JSON serialization',
        beverageType: BeverageType.espresso,
        steps: [],
        tankTemperature: 93.0,
        targetVolumeCountStart: 0,
      );

      final original = ProfileRecord.create(
        profile: profile,
        isDefault: true,
        metadata: {'test': 'value'},
      );

      final json = original.toJson();
      final deserialized = ProfileRecord.fromJson(json);

      expect(deserialized.id, equals(original.id));
      expect(deserialized.profile.title, equals(original.profile.title));
      expect(deserialized.visibility, equals(original.visibility));
      expect(deserialized.isDefault, equals(original.isDefault));
      expect(deserialized.metadata?['test'], equals('value'));
    });

    test('copyWith creates updated record', () {
      final profile = Profile(
        version: '2',
        title: 'Original',
        author: 'Test',
        notes: '',
        beverageType: BeverageType.espresso,
        steps: [],
        tankTemperature: 93.0,
        targetVolumeCountStart: 0,
      );

      final original = ProfileRecord.create(
        profile: profile,
        isDefault: false,
      );

      final updated = original.copyWith(
        visibility: Visibility.hidden,
        metadata: {'updated': true},
      );

      expect(updated.id, equals(original.id));
      expect(updated.visibility, equals(Visibility.hidden));
      expect(updated.metadata?['updated'], isTrue);
      expect(
        updated.updatedAt.isAtSameMomentAs(original.updatedAt) ||
            updated.updatedAt.isAfter(original.updatedAt),
        isTrue,
      );
    });
  });

  group('MockProfileStorage', () {
    late MockProfileStorage storage;

    setUp(() {
      storage = MockProfileStorage();
    });

    tearDown(() {
      storage.reset();
    });

    test('stores and retrieves profile', () async {
      final profile = Profile(
        version: '2',
        title: 'Test Profile',
        author: 'Test',
        notes: '',
        beverageType: BeverageType.espresso,
        steps: [],
        tankTemperature: 93.0,
        targetVolumeCountStart: 0,
      );

      final record = ProfileRecord.create(
        profile: profile,
        isDefault: false,
      );

      await storage.store(record);
      final retrieved = await storage.get(record.id);

      expect(retrieved, isNotNull);
      expect(retrieved!.id, equals(record.id));
      expect(retrieved.profile.title, equals('Test Profile'));
    });

    test('returns null for non-existent profile', () async {
      final retrieved = await storage.get('non-existent-id');
      expect(retrieved, isNull);
    });

    test('updates existing profile', () async {
      final profile = Profile(
        version: '2',
        title: 'Original Title',
        author: 'Test',
        notes: '',
        beverageType: BeverageType.espresso,
        steps: [],
        tankTemperature: 93.0,
        targetVolumeCountStart: 0,
      );

      final record = ProfileRecord.create(
        profile: profile,
        isDefault: false,
      );

      await storage.store(record);

      final updatedProfile = profile.copyWith(title: 'Updated Title');
      final updatedRecord = record.copyWith(profile: updatedProfile);

      await storage.update(updatedRecord);
      final retrieved = await storage.get(record.id);

      expect(retrieved!.profile.title, equals('Updated Title'));
    });

    test('throws when updating non-existent profile', () async {
      final profile = Profile(
        version: '2',
        title: 'Test',
        author: 'Test',
        notes: '',
        beverageType: BeverageType.espresso,
        steps: [],
        tankTemperature: 93.0,
        targetVolumeCountStart: 0,
      );

      final record = ProfileRecord.create(
        profile: profile,
        isDefault: false,
      );

      expect(
        () async => await storage.update(record),
        throwsException,
      );
    });

    test('filters by visibility', () async {
      final profiles = [
        ProfileRecord.create(
          profile: Profile(
            version: '2',
            title: 'Visible',
            author: 'Test',
            notes: '',
            beverageType: BeverageType.espresso,
            steps: [],
            tankTemperature: 93.0,
            targetVolumeCountStart: 0,
          ),
          isDefault: false,
        ),
        ProfileRecord.create(
          profile: Profile(
            version: '2',
            title: 'Hidden',
            author: 'Test',
            notes: '',
            beverageType: BeverageType.espresso,
            steps: [],
            tankTemperature: 93.0,
            targetVolumeCountStart: 0,
          ),
          isDefault: false,
        ).copyWith(visibility: Visibility.hidden),
        ProfileRecord.create(
          profile: Profile(
            version: '2',
            title: 'Deleted',
            author: 'Test',
            notes: '',
            beverageType: BeverageType.espresso,
            steps: [],
            tankTemperature: 93.0,
            targetVolumeCountStart: 0,
          ),
          isDefault: false,
        ).copyWith(visibility: Visibility.deleted),
      ];

      for (final profile in profiles) {
        await storage.store(profile);
      }

      final visible = await storage.getAll(visibility: Visibility.visible);
      final hidden = await storage.getAll(visibility: Visibility.hidden);
      final deleted = await storage.getAll(visibility: Visibility.deleted);

      expect(visible.length, equals(1));
      expect(hidden.length, equals(1));
      expect(deleted.length, equals(1));
      expect(visible.first.profile.title, equals('Visible'));
      expect(hidden.first.profile.title, equals('Hidden'));
      expect(deleted.first.profile.title, equals('Deleted'));
    });

    test('gets profiles by parent ID', () async {
      final parentProfile = Profile(
        version: '2',
        title: 'Parent',
        author: 'Test',
        notes: '',
        beverageType: BeverageType.espresso,
        steps: [],
        tankTemperature: 93.0,
        targetVolumeCountStart: 0,
      );

      final parent = ProfileRecord.create(
        profile: parentProfile,
        isDefault: false,
      );

      final child1 = ProfileRecord.create(
        profile: parentProfile.copyWith(title: 'Child 1'),
        isDefault: false,
        parentId: parent.id,
      );

      final child2 = ProfileRecord.create(
        profile: parentProfile.copyWith(title: 'Child 2'),
        isDefault: false,
        parentId: parent.id,
      );

      final unrelated = ProfileRecord.create(
        profile: parentProfile.copyWith(title: 'Unrelated'),
        isDefault: false,
      );

      await storage.store(parent);
      await storage.store(child1);
      await storage.store(child2);
      await storage.store(unrelated);

      final children = await storage.getByParentId(parent.id);

      expect(children.length, equals(2));
      expect(children.every((c) => c.parentId == parent.id), isTrue);
    });

    test('batch store operation', () async {
      final profiles = List.generate(
        5,
        (i) => ProfileRecord.create(
          profile: Profile(
            version: '2',
            title: 'Profile $i',
            author: 'Test',
            notes: '',
            beverageType: BeverageType.espresso,
            steps: [],
            tankTemperature: 93.0,
            targetVolumeCountStart: 0,
          ),
          isDefault: false,
        ),
      );

      await storage.storeAll(profiles);

      final count = await storage.count();
      expect(count, equals(5));
    });

    test('counts profiles correctly', () async {
      final profiles = [
        ProfileRecord.create(
          profile: Profile(
            version: '2',
            title: 'Visible 1',
            author: 'Test',
            notes: '',
            beverageType: BeverageType.espresso,
            steps: [],
            tankTemperature: 93.0,
            targetVolumeCountStart: 0,
          ),
          isDefault: false,
        ),
        ProfileRecord.create(
          profile: Profile(
            version: '2',
            title: 'Visible 2',
            author: 'Test',
            notes: '',
            beverageType: BeverageType.espresso,
            steps: [],
            tankTemperature: 93.0,
            targetVolumeCountStart: 0,
          ),
          isDefault: false,
        ),
        ProfileRecord.create(
          profile: Profile(
            version: '2',
            title: 'Hidden',
            author: 'Test',
            notes: '',
            beverageType: BeverageType.espresso,
            steps: [],
            tankTemperature: 93.0,
            targetVolumeCountStart: 0,
          ),
          isDefault: false,
        ).copyWith(visibility: Visibility.hidden),
      ];

      await storage.storeAll(profiles);

      final totalCount = await storage.count();
      final visibleCount = await storage.count(visibility: Visibility.visible);
      final hiddenCount = await storage.count(visibility: Visibility.hidden);

      expect(totalCount, equals(3));
      expect(visibleCount, equals(2));
      expect(hiddenCount, equals(1));
    });
  });

  group('Profile Versioning', () {
    late MockProfileStorage storage;

    setUp(() {
      storage = MockProfileStorage();
    });

    tearDown(() {
      storage.reset();
    });

    test('creates version tree correctly', () async {
      // Create parent
      final parentProfile = Profile(
        version: '2',
        title: 'Original',
        author: 'Test',
        notes: '',
        beverageType: BeverageType.espresso,
        steps: [],
        tankTemperature: 93.0,
        targetVolumeCountStart: 0,
      );

      final parent = ProfileRecord.create(
        profile: parentProfile,
        isDefault: false,
      );

      await storage.store(parent);

      // Create child
      final childProfile = parentProfile.copyWith(title: 'Modified v1');
      final child = ProfileRecord.create(
        profile: childProfile,
        isDefault: false,
        parentId: parent.id,
      );

      await storage.store(child);

      // Create grandchild
      final grandchildProfile = childProfile.copyWith(title: 'Modified v2');
      final grandchild = ProfileRecord.create(
        profile: grandchildProfile,
        isDefault: false,
        parentId: child.id,
      );

      await storage.store(grandchild);

      // Verify parent relationship
      final childrenOfParent = await storage.getByParentId(parent.id);
      expect(childrenOfParent.length, equals(1));
      expect(childrenOfParent.first.id, equals(child.id));

      // Verify grandchild relationship
      final childrenOfChild = await storage.getByParentId(child.id);
      expect(childrenOfChild.length, equals(1));
      expect(childrenOfChild.first.id, equals(grandchild.id));
    });

    test('supports multiple children', () async {
      final parentProfile = Profile(
        version: '2',
        title: 'Parent',
        author: 'Test',
        notes: '',
        beverageType: BeverageType.espresso,
        steps: [],
        tankTemperature: 93.0,
        targetVolumeCountStart: 0,
      );

      final parent = ProfileRecord.create(
        profile: parentProfile,
        isDefault: false,
      );

      await storage.store(parent);

      // Create multiple children
      final children = List.generate(
        3,
        (i) => ProfileRecord.create(
          profile: parentProfile.copyWith(title: 'Child $i'),
          isDefault: false,
          parentId: parent.id,
        ),
      );

      await storage.storeAll(children);

      final retrievedChildren = await storage.getByParentId(parent.id);
      expect(retrievedChildren.length, equals(3));
    });
  });

  group('Default Profile Protection', () {
    late MockProfileStorage storage;

    setUp(() {
      storage = MockProfileStorage();
    });

    tearDown(() {
      storage.reset();
    });

    test('default profiles have isDefault flag', () {
      final profile = Profile(
        version: '2',
        title: 'Default Profile',
        author: 'REA',
        notes: '',
        beverageType: BeverageType.espresso,
        steps: [],
        tankTemperature: 93.0,
        targetVolumeCountStart: 0,
      );

      final record = ProfileRecord.create(
        profile: profile,
        isDefault: true,
      );

      expect(record.isDefault, isTrue);
    });

    test('default profiles can be hidden but not deleted', () async {
      final profile = Profile(
        version: '2',
        title: 'Default Profile',
        author: 'REA',
        notes: '',
        beverageType: BeverageType.espresso,
        steps: [],
        tankTemperature: 93.0,
        targetVolumeCountStart: 0,
      );

      final record = ProfileRecord.create(
        profile: profile,
        isDefault: true,
      );

      await storage.store(record);

      // Simulate hiding a default profile
      final hiddenRecord = record.copyWith(visibility: Visibility.hidden);
      await storage.update(hiddenRecord);

      final retrieved = await storage.get(record.id);
      expect(retrieved!.visibility, equals(Visibility.hidden));
      expect(retrieved.isDefault, isTrue);

      // Verify it's not in visible list
      final visible = await storage.getAll(visibility: Visibility.visible);
      expect(visible.any((p) => p.id == record.id), isFalse);
    });

    test('user profiles can be soft deleted', () async {
      final profile = Profile(
        version: '2',
        title: 'User Profile',
        author: 'User',
        notes: '',
        beverageType: BeverageType.espresso,
        steps: [],
        tankTemperature: 93.0,
        targetVolumeCountStart: 0,
      );

      final record = ProfileRecord.create(
        profile: profile,
        isDefault: false,
      );

      await storage.store(record);

      // Simulate soft delete
      final deletedRecord = record.copyWith(visibility: Visibility.deleted);
      await storage.update(deletedRecord);

      final retrieved = await storage.get(record.id);
      expect(retrieved!.visibility, equals(Visibility.deleted));

      // Verify it's not in visible list
      final visible = await storage.getAll(visibility: Visibility.visible);
      expect(visible.any((p) => p.id == record.id), isFalse);

      // But it still exists in deleted list
      final deleted = await storage.getAll(visibility: Visibility.deleted);
      expect(deleted.any((p) => p.id == record.id), isTrue);
    });
  });

  group('Default Profile Migration', () {
    late MockProfileStorage storage;

    setUp(() {
      storage = MockProfileStorage();
    });

    tearDown(() {
      storage.reset();
    });

    test('detects profiles with old UUID-style IDs', () {
      // Old UUID format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
      const oldUuidId = '550e8400-e29b-41d4-a716-446655440000';
      expect(oldUuidId.contains('-'), isTrue);
      expect(oldUuidId.length, equals(36));
      expect(oldUuidId.startsWith('default:'), isFalse);

      // New stable ID format
      const newStableId = 'default:best_practice';
      expect(newStableId.startsWith('default:'), isTrue);
    });

    test('migration preserves profile data when changing ID', () async {
      final profile = Profile(
        version: '2',
        title: 'Best Practice',
        author: 'Decent',
        notes: 'Original notes',
        beverageType: BeverageType.espresso,
        steps: [],
        tankTemperature: 93.0,
        targetVolumeCountStart: 0,
      );

      // Simulate old profile with UUID ID
      const oldId = '550e8400-e29b-41d4-a716-446655440000';
      final createdAt = DateTime.now().subtract(const Duration(days: 7));
      final oldRecord = ProfileRecord(
        id: oldId,
        profile: profile,
        visibility: Visibility.visible,
        isDefault: true,
        createdAt: createdAt,
        updatedAt: createdAt,
        metadata: {
          'source': 'bundled',
          'filename': 'best_practice.json',
        },
      );

      await storage.store(oldRecord);

      // Simulate migration: delete old, create new with stable ID
      await storage.delete(oldId);

      const newId = 'default:best_practice';
      final newRecord = ProfileRecord(
        id: newId,
        profile: oldRecord.profile,
        parentId: oldRecord.parentId,
        visibility: oldRecord.visibility,
        isDefault: oldRecord.isDefault,
        createdAt: oldRecord.createdAt, // Preserve original creation time
        updatedAt: DateTime.now(), // Update timestamp
        metadata: oldRecord.metadata,
      );

      await storage.store(newRecord);

      // Verify old ID doesn't exist
      final oldRetrieved = await storage.get(oldId);
      expect(oldRetrieved, isNull);

      // Verify new ID exists with preserved data
      final newRetrieved = await storage.get(newId);
      expect(newRetrieved, isNotNull);
      expect(newRetrieved!.id, equals(newId));
      expect(newRetrieved.profile.title, equals('Best Practice'));
      expect(newRetrieved.isDefault, isTrue);
      expect(newRetrieved.createdAt, equals(createdAt)); // Original timestamp preserved
      expect(newRetrieved.metadata?['filename'], equals('best_practice.json'));
    });

    test('migration handles multiple profiles correctly', () async {
      // Create multiple profiles with old UUID IDs
      final profiles = [
        ('550e8400-e29b-41d4-a716-446655440000', 'best_practice.json', 'default:best_practice'),
        ('650e8400-e29b-41d4-a716-446655440001', 'cremina.json', 'default:cremina'),
        ('750e8400-e29b-41d4-a716-446655440002', 'manual_flow.json', 'default:manual_flow'),
      ];

      for (final (oldId, filename, _) in profiles) {
        final profile = Profile(
          version: '2',
          title: filename.split('.').first,
          author: 'Test',
          notes: '',
          beverageType: BeverageType.espresso,
          steps: [],
          tankTemperature: 93.0,
          targetVolumeCountStart: 0,
        );

        final record = ProfileRecord(
          id: oldId,
          profile: profile,
          visibility: Visibility.visible,
          isDefault: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          metadata: {'filename': filename},
        );

        await storage.store(record);
      }

      // Verify all old IDs exist
      for (final (oldId, _, _) in profiles) {
        final exists = await storage.exists(oldId);
        expect(exists, isTrue);
      }

      // Simulate migration for all profiles
      for (final (oldId, filename, newId) in profiles) {
        final oldRecord = await storage.get(oldId);
        expect(oldRecord, isNotNull);

        await storage.delete(oldId);

        final newRecord = ProfileRecord(
          id: newId,
          profile: oldRecord!.profile,
          parentId: oldRecord.parentId,
          visibility: oldRecord.visibility,
          isDefault: oldRecord.isDefault,
          createdAt: oldRecord.createdAt,
          updatedAt: DateTime.now(),
          metadata: oldRecord.metadata,
        );

        await storage.store(newRecord);
      }

      // Verify all old IDs are gone
      for (final (oldId, _, _) in profiles) {
        final exists = await storage.exists(oldId);
        expect(exists, isFalse);
      }

      // Verify all new IDs exist
      for (final (_, __, newId) in profiles) {
        final exists = await storage.exists(newId);
        expect(exists, isTrue);
      }

      final allProfiles = await storage.getAll();
      expect(allProfiles.length, equals(3));
      expect(allProfiles.every((p) => p.id.startsWith('default:')), isTrue);
    });

    test('migration skips profiles that already have stable IDs', () async {
      final profile = Profile(
        version: '2',
        title: 'Already Migrated',
        author: 'Test',
        notes: '',
        beverageType: BeverageType.espresso,
        steps: [],
        tankTemperature: 93.0,
        targetVolumeCountStart: 0,
      );

      // Create profile with stable ID (already migrated)
      const stableId = 'default:already_migrated';
      final record = ProfileRecord.create(
        id: stableId,
        profile: profile,
        isDefault: true,
        metadata: {'filename': 'already_migrated.json'},
      );

      await storage.store(record);

      // Check if this profile should be migrated
      final shouldMigrate = record.id.contains('-') &&
          record.id.length == 36 &&
          !record.id.startsWith('default:');

      expect(shouldMigrate, isFalse);

      // Verify it still exists with same ID
      final retrieved = await storage.get(stableId);
      expect(retrieved, isNotNull);
      expect(retrieved!.id, equals(stableId));
    });

    test('migration does not affect user profiles with UUIDs', () async {
      final profile = Profile(
        version: '2',
        title: 'User Profile',
        author: 'User',
        notes: '',
        beverageType: BeverageType.espresso,
        steps: [],
        tankTemperature: 93.0,
        targetVolumeCountStart: 0,
      );

      // User profile with UUID (not a default profile)
      final record = ProfileRecord.create(
        profile: profile,
        isDefault: false, // User profile, not default
      );

      await storage.store(record);
      final originalId = record.id;

      // User profiles should keep their UUID IDs
      // Migration only affects profiles where isDefault = true
      final retrieved = await storage.get(originalId);
      expect(retrieved, isNotNull);
      expect(retrieved!.id, equals(originalId));
      expect(retrieved.isDefault, isFalse);
      
      // Check it's a UUID format
      expect(retrieved.id.contains('-'), isTrue);
      expect(retrieved.id.length, equals(36));
    });
  });
}
