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
  /// 
  /// Uses content-based hashing: if a profile with the same hash already exists,
  /// it won't be loaded again. This automatically handles deduplication.
  Future<void> _loadDefaultProfilesIfNeeded() async {
    try {
      // Load the manifest to get list of profile files
      final manifestData = await rootBundle.loadString(
        'assets/defaultProfiles/manifest.json',
      );
      final manifest = jsonDecode(manifestData) as Map<String, dynamic>;
      final profileFiles = manifest['profiles'] as List<dynamic>;

      int loaded = 0;
      int skipped = 0;
      
      for (final filename in profileFiles) {
        try {
          final profileData = await rootBundle.loadString(
            'assets/defaultProfiles/$filename',
          );
          final profileJson = jsonDecode(profileData) as Map<String, dynamic>;
          final profile = Profile.fromJson(profileJson);

          // Create a ProfileRecord - ID will be calculated from content
          final record = ProfileRecord.create(
            profile: profile,
            isDefault: true,
            metadata: {'source': 'bundled', 'filename': filename},
          );

          // Check if this profile already exists (by hash)
          final existing = await _storage.get(record.id);
          if (existing != null) {
            skipped++;
            _log.fine('Skipped existing default profile: ${record.id} (${profile.title})');
            continue;
          }

          await _storage.store(record);
          loaded++;
          _log.fine('Loaded default profile: ${record.id} (${profile.title})');
        } catch (e) {
          _log.warning('Failed to load default profile: $filename', e);
        }
      }

      if (loaded > 0) {
        _log.info('Loaded $loaded new default profiles (skipped $skipped existing)');
      } else {
        _log.info('All default profiles already loaded (${profileFiles.length} total)');
      }
    } catch (e) {
      _log.warning(
        'Failed to load default profiles (this is okay if manifest doesn\'t exist yet)',
        e,
      );
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

  /// Get a single profile by ID (hash)
  Future<ProfileRecord?> get(String id) async {
    return await _storage.get(id);
  }

  /// Create a new profile
  /// 
  /// The profile ID will be automatically calculated from its content.
  /// If a profile with the same execution-relevant fields already exists,
  /// it will have the same hash.
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

    // Check if this exact profile already exists
    final existing = await _storage.get(record.id);
    if (existing != null) {
      _log.info('Profile with hash ${record.id} already exists (${profile.title})');
      return existing;
    }

    await _storage.store(record);
    await _updateProfileCount();
    _log.info('Created profile: ${record.id} (${profile.title})');

    return record;
  }

  /// Update an existing profile
  /// 
  /// Note: If execution-relevant fields change, the profile hash (ID) will change,
  /// creating effectively a new profile. Consider using parentId to track lineage.
  Future<ProfileRecord> update(String id, {
    Profile? profile,
    Map<String, dynamic>? metadata,
  }) async {
    final existing = await _storage.get(id);
    if (existing == null) {
      throw ArgumentError('Profile not found: $id');
    }

    // Can't modify default profiles' execution fields
    if (existing.isDefault && profile != null) {
      throw ArgumentError('Cannot modify default profile content');
    }

    final updated = existing.copyWith(
      profile: profile,
      metadata: metadata,
    );

    // If the profile content changed, the hash will be different
    if (updated.id != existing.id) {
      _log.warning(
        'Profile hash changed from ${existing.id} to ${updated.id}. '
        'This creates a new profile. Consider using parentId for versioning.',
      );
      
      // Delete old, store new
      await _storage.delete(existing.id);
      await _storage.store(updated);
    } else {
      await _storage.update(updated);
    }

    _log.info('Updated profile: ${updated.id}');
    return updated;
  }

  /// Delete a profile
  /// 
  /// Default profiles are hidden, user profiles are soft-deleted.
  Future<void> delete(String id) async {
    final existing = await _storage.get(id);
    if (existing == null) {
      throw ArgumentError('Profile not found: $id');
    }

    if (existing.isDefault) {
      // Default profiles can't be deleted, only hidden
      final hidden = existing.copyWith(visibility: Visibility.hidden);
      await _storage.update(hidden);
      _log.info('Hid default profile: $id');
    } else {
      // User profiles are soft-deleted
      final deleted = existing.copyWith(visibility: Visibility.deleted);
      await _storage.update(deleted);
      _log.info('Soft-deleted user profile: $id');
    }

    await _updateProfileCount();
  }

  /// Permanently delete a profile (purge)
  /// 
  /// Cannot purge default profiles.
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

  /// Change profile visibility
  Future<ProfileRecord> setVisibility(String id, Visibility visibility) async {
    final existing = await _storage.get(id);
    if (existing == null) {
      throw ArgumentError('Profile not found: $id');
    }

    // Can't set default profiles to deleted
    if (existing.isDefault && visibility == Visibility.deleted) {
      throw ArgumentError('Cannot delete default profiles, only hide them');
    }

    final updated = existing.copyWith(visibility: visibility);
    await _storage.update(updated);
    await _updateProfileCount();
    _log.info('Changed visibility of profile $id to ${visibility.name}');

    return updated;
  }

  /// Get profile lineage (all parents and children)
  Future<List<ProfileRecord>> getLineage(String id) async {
    final profile = await _storage.get(id);
    if (profile == null) {
      throw ArgumentError('Profile not found: $id');
    }

    final lineage = <ProfileRecord>[];

    // Get all parents
    var current = profile;
    lineage.add(current);
    while (current.parentId != null) {
      final parent = await _storage.get(current.parentId!);
      if (parent == null) break;
      lineage.insert(0, parent);
      current = parent;
    }

    // Get all children recursively
    Future<void> addChildren(String parentId) async {
      final children = await _storage.getByParentId(parentId);
      for (final child in children) {
        lineage.add(child);
        await addChildren(child.id);
      }
    }

    await addChildren(id);

    return lineage;
  }

  /// Import profiles from JSON
  Future<Map<String, dynamic>> importProfiles(
    List<Map<String, dynamic>> profilesJson,
  ) async {
    int imported = 0;
    int skipped = 0;
    int failed = 0;
    final errors = <String>[];

    for (final json in profilesJson) {
      try {
        final record = ProfileRecord.fromJson(json);

        // Check if profile already exists (by hash)
        final existing = await _storage.get(record.id);
        if (existing != null) {
          skipped++;
          continue;
        }

        await _storage.store(record);
        imported++;
      } catch (e) {
        failed++;
        errors.add('Failed to import profile: $e');
      }
    }

    await _updateProfileCount();
    _log.info('Import complete: $imported imported, $skipped skipped, $failed failed');

    return {
      'imported': imported,
      'skipped': skipped,
      'failed': failed,
      'errors': errors,
    };
  }

  /// Export profiles to JSON
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
  /// 
  /// Loads the profile from assets and stores it, making it visible again.
  Future<ProfileRecord> restoreDefault(String filename) async {
    try {
      final profileData = await rootBundle.loadString(
        'assets/defaultProfiles/$filename',
      );
      final profileJson = jsonDecode(profileData) as Map<String, dynamic>;
      final profile = Profile.fromJson(profileJson);

      // Create record with hash-based ID
      final record = ProfileRecord.create(
        profile: profile,
        isDefault: true,
        metadata: {'source': 'bundled', 'filename': filename},
      );

      // Check if it exists
      final existing = await _storage.get(record.id);
      if (existing != null) {
        // Just restore visibility
        final restored = existing.copyWith(
          visibility: Visibility.visible,
        );
        await _storage.update(restored);
        _log.info('Restored visibility of default profile: ${record.id}');
        return restored;
      }

      // Doesn't exist, store it
      await _storage.store(record);
      await _updateProfileCount();
      _log.info('Restored default profile from assets: ${record.id}');

      return record;
    } catch (e) {
      _log.severe('Failed to restore default profile: $filename', e);
      throw ArgumentError('Failed to restore default profile: $filename');
    }
  }

  /// Dispose resources
  void dispose() {
    _profileCountStream.close();
  }
}
