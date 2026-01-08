import 'package:reaprime/src/models/data/profile_record.dart';

/// Abstract interface for profile storage operations
/// This allows for different storage implementations (Hive, SQLite, etc.)
abstract class ProfileStorageService {
  /// Initialize the storage service
  Future<void> initialize();

  /// Store a profile record
  Future<void> store(ProfileRecord record);

  /// Get a profile record by ID
  Future<ProfileRecord?> get(String id);

  /// Get all profile records
  /// Optionally filter by visibility
  Future<List<ProfileRecord>> getAll({Visibility? visibility});

  /// Update an existing profile record
  Future<void> update(ProfileRecord record);

  /// Delete a profile record by ID
  Future<void> delete(String id);

  /// Check if a profile with the given ID exists
  Future<bool> exists(String id);

  /// Get all profile IDs
  Future<List<String>> getAllIds();

  /// Get profiles by parent ID (for version tracking)
  Future<List<ProfileRecord>> getByParentId(String parentId);

  /// Store multiple profiles (batch operation for import)
  Future<void> storeAll(List<ProfileRecord> records);

  /// Clear all profiles (use with caution)
  Future<void> clear();

  /// Get count of profiles by visibility
  Future<int> count({Visibility? visibility});
}
