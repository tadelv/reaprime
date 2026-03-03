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

  ProfileRecordsCompanion _makeProfile({
    String id = 'profile:abc12345678901234567',
    String title = 'Test Profile',
    String visibility = 'visible',
    bool isDefault = false,
    String? parentId,
  }) {
    final now = DateTime.now();
    return ProfileRecordsCompanion(
      id: Value(id),
      metadataHash: Value('mhash-$id'),
      compoundHash: Value('chash-$id'),
      parentId: Value(parentId),
      visibility: Value(visibility),
      isDefault: Value(isDefault),
      createdAt: Value(now),
      updatedAt: Value(now),
      profileJson: Value({
        'title': title,
        'author': 'Test',
        'notes': '',
        'beverage_type': 'espresso',
        'steps': [],
        'tank_temperature': 0.0,
        'target_weight': 36.0,
        'target_volume_count_start': 0,
        'version': '2',
      }),
    );
  }

  group('ProfileDao - CRUD', () {
    test('inserts and retrieves a profile', () async {
      await db.profileDao.insertProfile(_makeProfile());
      final profiles = await db.profileDao.getAllProfiles();
      expect(profiles, hasLength(1));
      expect(profiles.first.profileJson['title'], 'Test Profile');
    });

    test('filters by visibility', () async {
      await db.profileDao.insertProfile(_makeProfile(
        id: 'p1',
        visibility: 'visible',
      ));
      await db.profileDao.insertProfile(_makeProfile(
        id: 'p2',
        visibility: 'hidden',
      ));
      await db.profileDao.insertProfile(_makeProfile(
        id: 'p3',
        visibility: 'deleted',
      ));

      final visible =
          await db.profileDao.getAllProfiles(visibility: 'visible');
      expect(visible, hasLength(1));
      expect(visible.first.id, 'p1');

      final all = await db.profileDao.getAllProfiles();
      expect(all, hasLength(3));
    });

    test('checks if profile exists', () async {
      await db.profileDao.insertProfile(_makeProfile(id: 'p1'));
      expect(await db.profileDao.profileExists('p1'), isTrue);
      expect(await db.profileDao.profileExists('p2'), isFalse);
    });

    test('gets all profile IDs', () async {
      await db.profileDao.insertProfile(_makeProfile(id: 'p1'));
      await db.profileDao.insertProfile(_makeProfile(id: 'p2'));
      final ids = await db.profileDao.getAllProfileIds();
      expect(ids, hasLength(2));
      expect(ids, containsAll(['p1', 'p2']));
    });

    test('gets by parent ID', () async {
      await db.profileDao.insertProfile(_makeProfile(id: 'parent'));
      await db.profileDao.insertProfile(
          _makeProfile(id: 'child1', parentId: 'parent'));
      await db.profileDao.insertProfile(
          _makeProfile(id: 'child2', parentId: 'parent'));
      await db.profileDao.insertProfile(
          _makeProfile(id: 'other', parentId: 'other-parent'));

      final children = await db.profileDao.getByParentId('parent');
      expect(children, hasLength(2));
    });

    test('counts profiles by visibility', () async {
      await db.profileDao.insertProfile(_makeProfile(
        id: 'p1',
        visibility: 'visible',
      ));
      await db.profileDao.insertProfile(_makeProfile(
        id: 'p2',
        visibility: 'visible',
      ));
      await db.profileDao.insertProfile(_makeProfile(
        id: 'p3',
        visibility: 'hidden',
      ));

      final total = await db.profileDao.countProfiles();
      expect(total, 3);

      final visibleCount =
          await db.profileDao.countProfiles(visibility: 'visible');
      expect(visibleCount, 2);
    });

    test('updates a profile', () async {
      await db.profileDao.insertProfile(_makeProfile(id: 'p1'));
      await db.profileDao.updateProfile(ProfileRecordsCompanion(
        id: const Value('p1'),
        visibility: const Value('hidden'),
        updatedAt: Value(DateTime.now()),
      ));
      final profile = await db.profileDao.getProfileById('p1');
      expect(profile!.visibility, 'hidden');
    });

    test('deletes a profile', () async {
      await db.profileDao.insertProfile(_makeProfile(id: 'p1'));
      await db.profileDao.deleteProfile('p1');
      final profiles = await db.profileDao.getAllProfiles();
      expect(profiles, isEmpty);
    });

    test('clears all profiles', () async {
      await db.profileDao.insertProfile(_makeProfile(id: 'p1'));
      await db.profileDao.insertProfile(_makeProfile(id: 'p2'));
      await db.profileDao.clearAll();
      final profiles = await db.profileDao.getAllProfiles();
      expect(profiles, isEmpty);
    });

    test('batch inserts profiles', () async {
      await db.profileDao.insertAllProfiles([
        _makeProfile(id: 'p1', title: 'Profile 1'),
        _makeProfile(id: 'p2', title: 'Profile 2'),
        _makeProfile(id: 'p3', title: 'Profile 3'),
      ]);
      final profiles = await db.profileDao.getAllProfiles();
      expect(profiles, hasLength(3));
    });
  });

  group('ProfileDao - Watch', () {
    test('watches profile changes', () async {
      final stream =
          db.profileDao.watchAllProfiles(visibility: 'visible');
      await db.profileDao.insertProfile(_makeProfile(id: 'p1'));
      final profiles = await stream.first;
      expect(profiles, hasLength(1));
    });
  });
}
