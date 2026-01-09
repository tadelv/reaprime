import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/data/profile_record.dart';
import 'package:reaprime/src/services/storage/profile_storage_service.dart';
import 'package:rxdart/rxdart.dart';

/// Controller for managing profile operations and business logic
class ProfileController {
  final ProfileStorageService _storage;
  final Logger _log = Logger('ProfileController');

  /// Stream of profile count updates
  final BehaviorSubject<int> _profileCountStream = BehaviorSubject.seeded(0);
  Stream<int> get profileCount => _profileCountStream.stream;

  ProfileController({required ProfileStorageService storage})
    : _storage = storage;

  /// Initialize the controller and load default profiles if needed
  Future<void> initialize() async {
    _log.info('Initializing ProfileController');
    await _storage.initialize();
    await _loadDefaultProfilesIfNeeded();
    await _updateProfileCount();
    _log.info('ProfileController initialized');
  }

  /// Load bundled default profiles from assets if they don't exist
  Future<void> _loadDefaultProfilesIfNeeded() async {
    try {
      // First, run migration for existing installations
      await _migrateDefaultProfiles();

      // Check if we already have all default profiles with correct IDs
      final manifestData = await rootBundle.loadString(
        'assets/defaultProfiles/manifest.json',
      );
      final manifest = jsonDecode(manifestData) as Map<String, dynamic>;
      final profileEntries = manifest['profiles'] as List<dynamic>;

      // Build expected IDs from manifest
      final expectedIds = <String>{};
      for (final entry in profileEntries) {
        if (entry is Map<String, dynamic>) {
          expectedIds.add(entry['id'] as String);
        }
      }

      // Check which profiles are missing
      final existingProfiles = await _storage.getAll();
      final existingDefaultIds = existingProfiles
          .where((p) => p.isDefault)
          .map((p) => p.id)
          .toSet();

      final missingIds = expectedIds.difference(existingDefaultIds);

      if (missingIds.isEmpty) {
        _log.info('All default profiles already loaded');
        return;
      }

      _log.info('Loading ${missingIds.length} missing default profiles');

      int loaded = 0;
      for (final entry in profileEntries) {
        if (entry is! Map<String, dynamic>) continue;

        final id = entry['id'] as String;
        final filename = entry['filename'] as String;

        // Skip if already exists
        if (!missingIds.contains(id)) continue;

        try {
          final profileData = await rootBundle.loadString(
            'assets/defaultProfiles/$filename',
          );
          final profileJson = jsonDecode(profileData) as Map<String, dynamic>;
          final profile = Profile.fromJson(profileJson);

          // Create a ProfileRecord wrapper with custom ID
          final record = ProfileRecord.create(
            id: id,
            profile: profile,
            isDefault: true,
            metadata: {'source': 'bundled', 'filename': filename},
          );

          await _storage.store(record);
          loaded++;
          _log.fine('Loaded default profile: $id (${profile.title})');
        } catch (e) {
          _log.warning('Failed to load default profile: $filename', e);
        }
      }

      _log.info('Loaded $loaded default profiles');
    } catch (e) {
      _log.warning(
        'Failed to load default profiles (this is okay if manifest doesn\'t exist yet)',
        e,
      );
    }
  }

  /// Migrate existing default profiles to use stable IDs
  /// 
  /// For installations that have default profiles with auto-generated UUIDs,
  /// this attempts to match them to the new stable IDs based on profile title
  /// and replaces them with the correct IDs.
  Future<void> _migrateDefaultProfiles() async {
    try {
      final existingProfiles = await _storage.getAll();
      final defaultProfiles = existingProfiles.where((p) => p.isDefault).toList();

      // If no default profiles, nothing to migrate
      if (defaultProfiles.isEmpty) return;

      // Check if any default profile has a UUID-style ID (contains dashes in UUID format)
      final hasOldStyleIds = defaultProfiles.any((p) => 
        p.id.contains('-') && 
        p.id.length == 36 && 
        !p.id.startsWith('default:')
      );

      if (!hasOldStyleIds) {
        _log.fine('No migration needed - all default profiles have stable IDs');
        return;
      }

      _log.info('Migrating default profiles to stable IDs');

      // Load manifest to get ID mappings
      final manifestData = await rootBundle.loadString(
        'assets/defaultProfiles/manifest.json',
      );
      final manifest = jsonDecode(manifestData) as Map<String, dynamic>;
      final profileEntries = manifest['profiles'] as List<dynamic>;

      // Build a mapping from filename to stable ID
      final filenameToId = <String, String>{};
      for (final entry in profileEntries) {
        if (entry is Map<String, dynamic>) {
          filenameToId[entry['filename'] as String] = entry['id'] as String;
        }
      }

      int migrated = 0;
      for (final oldRecord in defaultProfiles) {
        // Skip if already has stable ID
        if (!oldRecord.id.contains('-') || 
            oldRecord.id.startsWith('default:')) {
          continue;
        }

        // Try to find stable ID from metadata filename
        final filename = oldRecord.metadata?['filename'] as String?;
        if (filename == null) {
          _log.warning('Cannot migrate profile ${oldRecord.id}: no filename in metadata');
          continue;
        }

        final newId = filenameToId[filename];
        if (newId == null) {
          _log.warning('Cannot migrate profile ${oldRecord.id}: filename $filename not in manifest');
          continue;
        }

        // Check if new ID already exists (shouldn't happen, but be safe)
        final existingWithNewId = await _storage.get(newId);
        if (existingWithNewId != null) {
          _log.warning('Cannot migrate profile ${oldRecord.id}: target ID $newId already exists');
          continue;
        }

        // Delete old record
        await _storage.delete(oldRecord.id);

        // Create new record with stable ID
        final newRecord = ProfileRecord(
          id: newId,
          profile: oldRecord.profile,
          parentId: oldRecord.parentId,
          visibility: oldRecord.visibility,
          isDefault: oldRecord.isDefault,
          createdAt: oldRecord.createdAt,
          updatedAt: DateTime.now(),
          metadata: oldRecord.metadata,
        );

        await _storage.store(newRecord);
        migrated++;
        _log.info('Migrated profile ${oldRecord.id} -> $newId (${oldRecord.profile.title})');
      }

      if (migrated > 0) {
        _log.info('Successfully migrated $migrated default profiles to stable IDs');
      }
    } catch (e, st) {
      _log.warning('Error during default profile migration', e, st);
      // Don't throw - migration failure shouldn't block app startup
    }
  }

  /// Update the profile count stream
  Future<void> _updateProfileCount() async {
    final count = await _storage.count(visibility: Visibility.visible);
    _profileCountStream.add(count);
  }

  /// Get all profiles, optionally filtered by visibility
  Future<List<ProfileRecord>> getAll({
    Visibility? visibility,
    bool includeHidden = false,
  }) async {
    if (includeHidden) {
      return await _storage.getAll();
    }
    return await _storage.getAll(visibility: visibility ?? Visibility.visible);
  }

  /// Get a single profile by ID
  Future<ProfileRecord?> get(String id) async {
    return await _storage.get(id);
  }

  /// Create a new profile
  Future<ProfileRecord> create({
    required Profile profile,
    String? parentId,
    Map<String, dynamic>? metadata,
  }) async {
    // Validate that parent exists if parentId is provided
    if (parentId != null) {
      final parent = await _storage.get(parentId);
      if (parent == null) {
        throw ArgumentError('Parent profile not found: $parentId');
      }
    }

    final record = ProfileRecord.create(
      profile: profile,
      parentId: parentId,
      metadata: metadata,
    );

    await _storage.store(record);
    await _updateProfileCount();
    _log.info('Created profile: ${record.id} (${profile.title})');

    return record;
  }

  /// Update an existing profile
  Future<ProfileRecord> update({
    required String id,
    Profile? profile,
    Map<String, dynamic>? metadata,
  }) async {
    final existing = await _storage.get(id);
    if (existing == null) {
      throw ArgumentError('Profile not found: $id');
    }

    // Can't update default profiles' core data, only metadata
    if (existing.isDefault && profile != null) {
      throw ArgumentError('Cannot modify default profile content');
    }

    final updated = existing.copyWith(
      profile: profile ?? existing.profile,
      metadata: metadata ?? existing.metadata,
      updatedAt: DateTime.now(),
    );

    await _storage.update(updated);
    _log.info('Updated profile: $id');

    return updated;
  }

  /// Delete a profile (soft delete for user profiles, hide for defaults)
  Future<void> delete(String id) async {
    final existing = await _storage.get(id);
    if (existing == null) {
      throw ArgumentError('Profile not found: $id');
    }

    if (existing.isDefault) {
      // Default profiles can't be deleted, only hidden
      final hidden = existing.copyWith(
        visibility: Visibility.hidden,
        updatedAt: DateTime.now(),
      );
      await _storage.update(hidden);
      _log.info('Hidden default profile: $id');
    } else {
      // User profiles are soft-deleted
      final deleted = existing.copyWith(
        visibility: Visibility.deleted,
        updatedAt: DateTime.now(),
      );
      await _storage.update(deleted);
      _log.info('Soft-deleted profile: $id');
    }

    await _updateProfileCount();
  }

  /// Permanently delete a profile (use with caution)
  Future<void> purge(String id) async {
    final existing = await _storage.get(id);
    if (existing == null) {
      throw ArgumentError('Profile not found: $id');
    }

    if (existing.isDefault) {
      throw ArgumentError('Cannot purge default profiles');
    }

    await _storage.delete(id);
    await _updateProfileCount();
    _log.info('Purged profile: $id');
  }

  /// Change visibility of a profile
  Future<ProfileRecord> setVisibility(String id, Visibility visibility) async {
    final existing = await _storage.get(id);
    if (existing == null) {
      throw ArgumentError('Profile not found: $id');
    }

    // Default profiles can only be visible or hidden, not deleted
    if (existing.isDefault && visibility == Visibility.deleted) {
      throw ArgumentError('Cannot delete default profiles, only hide them');
    }

    final updated = existing.copyWith(
      visibility: visibility,
      updatedAt: DateTime.now(),
    );

    await _storage.update(updated);
    await _updateProfileCount();
    _log.info('Changed visibility of profile $id to ${visibility.name}');

    return updated;
  }

  /// Get profile lineage (all versions in the chain)
  Future<List<ProfileRecord>> getLineage(String id) async {
    final lineage = <ProfileRecord>[];
    final profile = await _storage.get(id);

    if (profile == null) {
      return lineage;
    }

    // Add current profile
    lineage.add(profile);

    // Traverse up the parent chain
    String? currentParentId = profile.parentId;
    while (currentParentId != null) {
      final parent = await _storage.get(currentParentId);
      if (parent == null) {
        break;
      }
      lineage.insert(0, parent); // Insert at beginning
      currentParentId = parent.parentId;
    }

    // Get all children recursively
    await _addChildren(id, lineage);

    return lineage;
  }

  /// Helper to recursively add children to lineage
  Future<void> _addChildren(
    String parentId,
    List<ProfileRecord> lineage,
  ) async {
    final children = await _storage.getByParentId(parentId);
    for (final child in children) {
      if (!lineage.any((p) => p.id == child.id)) {
        lineage.add(child);
        await _addChildren(child.id, lineage);
      }
    }
  }

  /// Import profiles from JSON array
  Future<Map<String, dynamic>> importProfiles(
    List<Map<String, dynamic>> profilesJson,
  ) async {
    int imported = 0;
    int skipped = 0;
    int failed = 0;
    final List<String> errors = [];

    for (final json in profilesJson) {
      try {
        final record = ProfileRecord.fromJson(json);

        // Check if profile already exists
        final exists = await _storage.exists(record.id);
        if (exists) {
          skipped++;
          continue;
        }

        await _storage.store(record);
        imported++;
      } catch (e) {
        failed++;
        errors.add('Failed to import profile: $e');
        _log.warning('Failed to import profile', e);
      }
    }

    await _updateProfileCount();

    _log.info(
      'Import complete: $imported imported, $skipped skipped, $failed failed',
    );

    return {
      'imported': imported,
      'skipped': skipped,
      'failed': failed,
      'errors': errors,
    };
  }

  /// Export all profiles to JSON array
  Future<List<Map<String, dynamic>>> exportProfiles({
    bool includeHidden = false,
    bool includeDeleted = false,
  }) async {
    List<ProfileRecord> profiles;

    if (includeDeleted) {
      profiles = await _storage.getAll();
    } else if (includeHidden) {
      profiles = await _storage.getAll();
      profiles =
          profiles.where((p) => p.visibility != Visibility.deleted).toList();
    } else {
      profiles = await _storage.getAll(visibility: Visibility.visible);
    }

    return profiles.map((p) => p.toJson()).toList();
  }

  /// Restore a default profile from assets
  Future<ProfileRecord> restoreDefault(String filename) async {
    try {
      final profileData = await rootBundle.loadString(
        'assets/defaultProfiles/$filename',
      );
      final profileJson = jsonDecode(profileData) as Map<String, dynamic>;
      // Profile loaded but not used since we restore from existing record
      Profile.fromJson(profileJson);

      // Check if this default profile already exists
      final existingProfiles = await _storage.getAll();
      final existing = existingProfiles.firstWhere(
        (p) => p.isDefault && p.metadata?['filename'] == filename,
        orElse: () => throw ArgumentError('Default profile not found'),
      );

      // Restore visibility
      final restored = existing.copyWith(
        visibility: Visibility.visible,
        updatedAt: DateTime.now(),
      );

      await _storage.update(restored);
      await _updateProfileCount();
      _log.info('Restored default profile: $filename');

      return restored;
    } catch (e, st) {
      _log.severe('Failed to restore default profile: $filename', e, st);
      rethrow;
    }
  }

  /// Dispose resources
  void dispose() {
    _profileCountStream.close();
  }
}
