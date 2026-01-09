import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/models/data/profile_record.dart';
import 'package:reaprime/src/services/storage/profile_storage_service.dart';

/// Hive-based implementation of ProfileStorageService
class HiveProfileStorageService implements ProfileStorageService {
  static const String _boxName = 'profiles';
  final Logger _log = Logger('HiveProfileStorageService');

  Box<dynamic>? _box;

  /// Deep cast a Map from Hive storage to Map\<String, dynamic\>
  /// 
  /// Hive returns Map\<dynamic, dynamic\> which needs to be recursively
  /// converted to Map\<String, dynamic\> for JSON deserialization.
  static Map<String, dynamic> _deepCastMap(Map map) {
    return map.map((key, value) {
      if (value is Map) {
        return MapEntry(key.toString(), _deepCastMap(value));
      } else if (value is List) {
        return MapEntry(key.toString(), _deepCastList(value));
      } else {
        return MapEntry(key.toString(), value);
      }
    });
  }

  /// Deep cast a List from Hive storage
  static List<dynamic> _deepCastList(List list) {
    return list.map((item) {
      if (item is Map) {
        return _deepCastMap(item);
      } else if (item is List) {
        return _deepCastList(item);
      } else {
        return item;
      }
    }).toList();
  }

  Box<dynamic> get box {
    if (_box == null || !_box!.isOpen) {
      throw StateError('HiveProfileStorageService not initialized');
    }
    return _box!;
  }

  @override
  Future<void> initialize() async {
    try {
      _box = await Hive.openBox(_boxName);
      _log.info(
        'HiveProfileStorageService initialized with ${box.length} profiles',
      );
    } catch (e, st) {
      _log.severe('Failed to initialize HiveProfileStorageService', e, st);
      rethrow;
    }
  }

  @override
  Future<void> store(ProfileRecord record) async {
    try {
      await box.put(record.id, record.toJson());
      _log.fine('Stored profile: ${record.id} (${record.profile.title})');
    } catch (e, st) {
      _log.severe('Failed to store profile: ${record.id}', e, st);
      rethrow;
    }
  }

  @override
  Future<ProfileRecord?> get(String id) async {
    try {
      final data = box.get(id);
      if (data == null) {
        return null;
      }
      return ProfileRecord.fromJson(_deepCastMap(data as Map));
    } catch (e, st) {
      _log.severe('Failed to get profile: $id', e, st);
      rethrow;
    }
  }

  @override
  Future<List<ProfileRecord>> getAll({Visibility? visibility}) async {
    try {
      final records = <ProfileRecord>[];

      for (final key in box.keys) {
        try {
          final data = box.get(key);
          if (data != null) {
            final record = ProfileRecord.fromJson(
              _deepCastMap(data as Map),
            );

            // Filter by visibility if specified
            if (visibility == null || record.visibility == visibility) {
              records.add(record);
            }
          }
        } catch (e) {
          _log.warning('Failed to parse profile record with key: $key', e);
        }
      }

      // Sort by updatedAt descending (most recent first)
      records.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      _log.fine(
        'Retrieved ${records.length} profiles (visibility: ${visibility?.name ?? "all"})',
      );
      return records;
    } catch (e, st) {
      _log.severe('Failed to get all profiles', e, st);
      rethrow;
    }
  }

  @override
  Future<void> update(ProfileRecord record) async {
    try {
      // Update the updatedAt timestamp
      final updatedRecord = record.copyWith(updatedAt: DateTime.now());
      await box.put(updatedRecord.id, updatedRecord.toJson());
      _log.fine('Updated profile: ${updatedRecord.id}');
    } catch (e, st) {
      _log.severe('Failed to update profile: ${record.id}', e, st);
      rethrow;
    }
  }

  @override
  Future<void> delete(String id) async {
    try {
      await box.delete(id);
      _log.fine('Deleted profile: $id');
    } catch (e, st) {
      _log.severe('Failed to delete profile: $id', e, st);
      rethrow;
    }
  }

  @override
  Future<bool> exists(String id) async {
    return box.containsKey(id);
  }

  @override
  Future<List<String>> getAllIds() async {
    return box.keys.map((key) => key.toString()).toList();
  }

  @override
  Future<List<ProfileRecord>> getByParentId(String parentId) async {
    try {
      final records = <ProfileRecord>[];

      for (final key in box.keys) {
        try {
          final data = box.get(key);
          if (data != null) {
            final record = ProfileRecord.fromJson(
              _deepCastMap(data as Map),
            );

            if (record.parentId == parentId) {
              records.add(record);
            }
          }
        } catch (e) {
          _log.warning('Failed to parse profile record with key: $key', e);
        }
      }

      // Sort by createdAt (chronological order)
      records.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      _log.fine(
        'Retrieved ${records.length} profiles with parentId: $parentId',
      );
      return records;
    } catch (e, st) {
      _log.severe('Failed to get profiles by parentId: $parentId', e, st);
      rethrow;
    }
  }

  @override
  Future<void> storeAll(List<ProfileRecord> records) async {
    try {
      final Map<String, dynamic> entries = {};
      for (final record in records) {
        entries[record.id] = record.toJson();
      }
      await box.putAll(entries);
      _log.info('Stored ${records.length} profiles in batch');
    } catch (e, st) {
      _log.severe('Failed to store profiles in batch', e, st);
      rethrow;
    }
  }

  @override
  Future<void> clear() async {
    try {
      await box.clear();
      _log.warning('Cleared all profiles from storage');
    } catch (e, st) {
      _log.severe('Failed to clear profiles', e, st);
      rethrow;
    }
  }

  @override
  Future<int> count({Visibility? visibility}) async {
    if (visibility == null) {
      return box.length;
    }

    int count = 0;
    for (final key in box.keys) {
      try {
        final data = box.get(key);
        if (data != null) {
          final record = ProfileRecord.fromJson(
            _deepCastMap(data as Map),
          );
          if (record.visibility == visibility) {
            count++;
          }
        }
      } catch (e) {
        // Skip invalid records
      }
    }
    return count;
  }
}
