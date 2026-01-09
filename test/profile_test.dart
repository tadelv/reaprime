import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/data/profile_hash.dart';
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

  group('ProfileHash', () {
    test('calculates consistent profile hash from execution fields', () {
      final profile1 = Profile(
        version: '2',
        title: 'Test Profile',
        author: 'Author 1',
        notes: 'Some notes',
        beverageType: BeverageType.espresso,
        steps: [],
        tankTemperature: 93.0,
        targetWeight: 36.0,
        targetVolumeCountStart: 0,
      );

      final profile2 = Profile(
        version: '2',
        title: 'Different Title',  // Metadata different
        author: 'Author 2',
        notes: 'Different notes',
        beverageType: BeverageType.espresso,  // Execution fields same
        steps: [],
        tankTemperature: 93.0,
        targetWeight: 36.0,
        targetVolumeCountStart: 0,
      );

      final hash1 = ProfileHash.calculateProfileHash(profile1);
      final hash2 = ProfileHash.calculateProfileHash(profile2);

      // Same execution fields = same hash
      expect(hash1, equals(hash2));
      expect(hash1.startsWith('profile:'), isTrue);
      expect(hash1.length, equals(24)); // 'profile:' + 16 chars
    });

    test('different execution fields produce different profile hashes', () {
      final profile1 = Profile(
        version: '2',
        title: 'Test',
        author: 'Test',
        notes: '',
        beverageType: BeverageType.espresso,
        steps: [],
        tankTemperature: 93.0,
        targetVolumeCountStart: 0,
      );

      final profile2 = Profile(
        version: '2',
        title: 'Test',
        author: 'Test',
        notes: '',
        beverageType: BeverageType.espresso,
        steps: [],
        tankTemperature: 94.0,  // Different temperature
        targetVolumeCountStart: 0,
      );

      final hash1 = ProfileHash.calculateProfileHash(profile1);
      final hash2 = ProfileHash.calculateProfileHash(profile2);

      expect(hash1, isNot(equals(hash2)));
    });

    test('calculates different metadata hashes for different metadata', () {
      final profile1 = Profile(
        version: '2',
        title: 'Title 1',
        author: 'Author 1',
        notes: 'Notes 1',
        beverageType: BeverageType.espresso,
        steps: [],
        tankTemperature: 93.0,
        targetVolumeCountStart: 0,
      );

      final profile2 = Profile(
        version: '2',
        title: 'Title 2',
        author: 'Author 2',
        notes: 'Notes 2',
        beverageType: BeverageType.espresso,
        steps: [],
        tankTemperature: 93.0,
        targetVolumeCountStart: 0,
      );

      final hash1 = ProfileHash.calculateMetadataHash(profile1);
      final hash2 = ProfileHash.calculateMetadataHash(profile2);

      expect(hash1, isNot(equals(hash2)));
    });

    test('calculateAll returns all three hashes', () {
      final profile = Profile(
        version: '2',
        title: 'Test Profile',
        author: 'Test Author',
        notes: 'Test notes',
        beverageType: BeverageType.espresso,
        steps: [],
        tankTemperature: 93.0,
        targetVolumeCountStart: 0,
      );

      final hashes = ProfileHash.calculateAll(profile);

      expect(hashes.profileHash.startsWith('profile:'), isTrue);
      expect(hashes.metadataHash, isNotEmpty);
      expect(hashes.compoundHash, isNotEmpty);
      expect(hashes.profileHash.length, equals(24));
      expect(hashes.metadataHash.length, equals(64)); // SHA-256 hex
      expect(hashes.compoundHash.length, equals(64));
    });
  });

  group('ProfileRecord with Hashes', () {
    test('creates ProfileRecord with hash-based ID', () {
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

      expect(record.id.startsWith('profile:'), isTrue);
      expect(record.id.length, equals(24));
      expect(record.metadataHash, isNotEmpty);
      expect(record.compoundHash, isNotEmpty);
      expect(record.profile, equals(profile));
      expect(record.parentId, isNull);
      expect(record.visibility, equals(Visibility.visible));
      expect(record.isDefault, isFalse);
    });

    test('identical profiles produce identical IDs', () {
      final profile1 = Profile(
        version: '2',
        title: 'Test',
        author: 'Author',
        notes: 'Notes',
        beverageType: BeverageType.espresso,
        steps: [],
        tankTemperature: 93.0,
        targetVolumeCountStart: 0,
      );

      final profile2 = Profile(
        version: '2',
        title: 'Test',
        author: 'Author',
        notes: 'Notes',
        beverageType: BeverageType.espresso,
        steps: [],
        tankTemperature: 93.0,
        targetVolumeCountStart: 0,
      );

      final record1 = ProfileRecord.create(profile: profile1, isDefault: false);
      final record2 = ProfileRecord.create(profile: profile2, isDefault: false);

      expect(record1.id, equals(record2.id));
      expect(record1.metadataHash, equals(record2.metadataHash));
      expect(record1.compoundHash, equals(record2.compoundHash));
    });

    test('same execution different metadata produces same profile ID', () {
      final profile1 = Profile(
        version: '2',
        title: 'Original Title',
        author: 'Author 1',
        notes: 'Notes 1',
        beverageType: BeverageType.espresso,
        steps: [],
        tankTemperature: 93.0,
        targetVolumeCountStart: 0,
      );

      final profile2 = Profile(
        version: '2',
        title: 'Changed Title',
        author: 'Author 2',
        notes: 'Notes 2',
        beverageType: BeverageType.espresso,
        steps: [],
        tankTemperature: 93.0,
        targetVolumeCountStart: 0,
      );

      final record1 = ProfileRecord.create(profile: profile1, isDefault: false);
      final record2 = ProfileRecord.create(profile: profile2, isDefault: false);

      // Same profile hash (execution fields)
      expect(record1.id, equals(record2.id));
      
      // Different metadata hash
      expect(record1.metadataHash, isNot(equals(record2.metadataHash)));
      
      // Different compound hash
      expect(record1.compoundHash, isNot(equals(record2.compoundHash)));
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
      expect(deserialized.metadataHash, equals(original.metadataHash));
      expect(deserialized.compoundHash, equals(original.compoundHash));
      expect(deserialized.profile.title, equals(original.profile.title));
      expect(deserialized.visibility, equals(original.visibility));
      expect(deserialized.isDefault, equals(original.isDefault));
      expect(deserialized.metadata?['test'], equals('value'));
    });

    test('copyWith recalculates hashes when profile changes', () {
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

      final updatedProfile = profile.copyWith(tankTemperature: 94.0);
      final updated = original.copyWith(profile: updatedProfile);

      // Different profile hash due to temperature change
      expect(updated.id, isNot(equals(original.id)));
      
      // Metadata hash unchanged (title/author/notes same)
      expect(updated.metadataHash, equals(original.metadataHash));
      
      // Compound hash changed (profile hash changed)
      expect(updated.compoundHash, isNot(equals(original.compoundHash)));
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

    test('stores and retrieves profile by hash ID', () async {
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

    test('automatic deduplication with hash-based IDs', () async {
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

      final record1 = ProfileRecord.create(profile: profile, isDefault: false);
      final record2 = ProfileRecord.create(profile: profile, isDefault: false);

      // Both have same ID
      expect(record1.id, equals(record2.id));

      await storage.store(record1);
      
      // Storing record2 overwrites record1 (same ID)
      await storage.store(record2);

      final count = await storage.count();
      expect(count, equals(1)); // Only one profile
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
            tankTemperature: 94.0,  // Different to get different hash
            targetVolumeCountStart: 0,
          ),
          isDefault: false,
        ).copyWith(visibility: Visibility.hidden),
      ];

      for (final profile in profiles) {
        await storage.store(profile);
      }

      final visible = await storage.getAll(visibility: Visibility.visible);
      final hidden = await storage.getAll(visibility: Visibility.hidden);

      expect(visible.length, equals(1));
      expect(hidden.length, equals(1));
      expect(visible.first.profile.title, equals('Visible'));
      expect(hidden.first.profile.title, equals('Hidden'));
    });
  });

  group('Profile Versioning with Hashes', () {
    late MockProfileStorage storage;

    setUp(() {
      storage = MockProfileStorage();
    });

    tearDown(() {
      storage.reset();
    });

    test('creates version tree with parent ID references', () async {
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

      // Create modified version with different execution field
      final childProfile = parentProfile.copyWith(tankTemperature: 94.0);
      final child = ProfileRecord.create(
        profile: childProfile,
        parentId: parent.id,  // Reference parent
        isDefault: false,
      );

      await storage.store(child);

      // Verify different IDs (different execution fields)
      expect(child.id, isNot(equals(parent.id)));
      expect(child.parentId, equals(parent.id));

      final children = await storage.getByParentId(parent.id);
      expect(children.length, equals(1));
      expect(children.first.id, equals(child.id));
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
      expect(record.id.startsWith('profile:'), isTrue);
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
    });
  });

  group('Hash Update Mechanics', () {
    test('updating metadata only keeps same profile ID', () {
      final profile = Profile(
        version: '2',
        title: 'Original Title',
        author: 'Original Author',
        notes: 'Original notes',
        beverageType: BeverageType.espresso,
        steps: [],
        tankTemperature: 93.0,
        targetVolumeCountStart: 0,
      );

      final original = ProfileRecord.create(profile: profile, isDefault: false);
      
      // Update only metadata fields
      final updatedProfile = profile.copyWith(
        title: 'New Title',
        author: 'New Author',
        notes: 'New notes',
      );
      
      final updated = original.copyWith(profile: updatedProfile);

      // Same profile ID (execution fields unchanged)
      expect(updated.id, equals(original.id));
      
      // Different metadata hash
      expect(updated.metadataHash, isNot(equals(original.metadataHash)));
      
      // Different compound hash
      expect(updated.compoundHash, isNot(equals(original.compoundHash)));
    });

    test('updating execution fields changes profile ID', () {
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

      final original = ProfileRecord.create(profile: profile, isDefault: false);
      
      // Update execution field
      final updatedProfile = profile.copyWith(tankTemperature: 94.0);
      final updated = original.copyWith(profile: updatedProfile);

      // Different profile ID (execution field changed)
      expect(updated.id, isNot(equals(original.id)));
      
      // Same metadata hash (metadata unchanged)
      expect(updated.metadataHash, equals(original.metadataHash));
      
      // Different compound hash
      expect(updated.compoundHash, isNot(equals(original.compoundHash)));
    });

    test('updating both metadata and execution changes all hashes', () {
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

      final original = ProfileRecord.create(profile: profile, isDefault: false);
      
      // Update both
      final updatedProfile = profile.copyWith(
        title: 'Updated',
        tankTemperature: 94.0,
      );
      final updated = original.copyWith(profile: updatedProfile);

      // All hashes different
      expect(updated.id, isNot(equals(original.id)));
      expect(updated.metadataHash, isNot(equals(original.metadataHash)));
      expect(updated.compoundHash, isNot(equals(original.compoundHash)));
    });

    test('identical profiles from different sources have same ID', () {
      // Simulate two users creating the "same" profile
      final profile1 = Profile(
        version: '2',
        title: 'User A Version',
        author: 'Alice',
        notes: 'Created by Alice',
        beverageType: BeverageType.espresso,
        steps: [],
        tankTemperature: 93.0,
        targetVolumeCountStart: 0,
      );

      final profile2 = Profile(
        version: '2',
        title: 'User B Version',
        author: 'Bob',
        notes: 'Created by Bob',
        beverageType: BeverageType.espresso,
        steps: [],
        tankTemperature: 93.0,
        targetVolumeCountStart: 0,
      );

      final record1 = ProfileRecord.create(profile: profile1, isDefault: false);
      final record2 = ProfileRecord.create(profile: profile2, isDefault: false);

      // Same functional profile → same ID
      expect(record1.id, equals(record2.id));
      
      // Can detect they're different presentations
      expect(record1.metadataHash, isNot(equals(record2.metadataHash)));
      expect(record1.compoundHash, isNot(equals(record2.compoundHash)));
    });

    test('hash remains stable across serialization', () {
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

      final original = ProfileRecord.create(profile: profile, isDefault: false);
      
      // Serialize and deserialize
      final json = original.toJson();
      final deserialized = ProfileRecord.fromJson(json);

      // All hashes preserved
      expect(deserialized.id, equals(original.id));
      expect(deserialized.metadataHash, equals(original.metadataHash));
      expect(deserialized.compoundHash, equals(original.compoundHash));
    });

    test('changing beverage type changes profile hash', () {
      final profile1 = Profile(
        version: '2',
        title: 'Test',
        author: 'Test',
        notes: '',
        beverageType: BeverageType.espresso,
        steps: [],
        tankTemperature: 93.0,
        targetVolumeCountStart: 0,
      );

      final profile2 = Profile(
        version: '2',
        title: 'Test',
        author: 'Test',
        notes: '',
        beverageType: BeverageType.pourover,  // Different beverage type
        steps: [],
        tankTemperature: 93.0,
        targetVolumeCountStart: 0,
      );

      final record1 = ProfileRecord.create(profile: profile1, isDefault: false);
      final record2 = ProfileRecord.create(profile: profile2, isDefault: false);

      // Different beverage type → different profile hash
      expect(record1.id, isNot(equals(record2.id)));
    });
  });
}
