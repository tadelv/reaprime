# Full Data Export/Import Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add REST endpoints for exporting/importing all persistent app data as a ZIP archive.

**Architecture:** A standalone handler (`DataExportHandler`) with a registry of `DataExportSection` implementations. Each section handles one data type (profiles, shots, workflow, settings, KV store). The handler builds/parses ZIP archives using the existing `archive` package. New endpoints: `GET /api/v1/data/export` and `POST /api/v1/data/import?onConflict=skip|overwrite`.

**Tech Stack:** Dart, Shelf/shelf_plus, archive package (already in pubspec), existing controllers/services.

**Design doc:** `doc/plans/2026-02-28-data-export-design.md`

---

### Task 1: Add `namespaces` getter to HiveStoreService

We need to enumerate all KV store namespaces for export. Currently `_boxes` is private with no way to list namespaces.

**Files:**
- Modify: `lib/src/services/storage/kv_store_service.dart`
- Modify: `lib/src/services/storage/hive_store_service.dart`
- Test: `test/hive_store_service_test.dart`

**Step 1: Write the failing test**

Create `test/hive_store_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:reaprime/src/services/storage/hive_store_service.dart';

void main() {
  late HiveStoreService store;

  setUp(() async {
    Hive.init('./test_hive_data_export');
    store = HiveStoreService(defaultNamespace: 'testKvStore');
    await store.initialize();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await Hive.close();
  });

  group('namespaces', () {
    test('returns default namespace after initialization', () async {
      final ns = store.namespaces;
      expect(ns, contains('testKvStore'));
    });

    test('includes namespaces created by set()', () async {
      await store.set(namespace: 'pluginData', key: 'k1', value: 'v1');
      final ns = store.namespaces;
      expect(ns, contains('pluginData'));
    });
  });

  group('getAll', () {
    test('returns all key-value pairs in a namespace', () async {
      await store.set(key: 'a', value: 'alpha');
      await store.set(key: 'b', value: 'beta');
      final all = await store.getAll();
      expect(all, {'a': 'alpha', 'b': 'beta'});
    });

    test('returns empty map for empty namespace', () async {
      await store.set(namespace: 'empty', key: 'temp', value: '1');
      await store.delete(namespace: 'empty', key: 'temp');
      final all = await store.getAll(namespace: 'empty');
      expect(all, isEmpty);
    });
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/hive_store_service_test.dart`
Expected: FAIL — `namespaces` getter and `getAll` method don't exist.

**Step 3: Add abstract methods to KeyValueStoreService**

In `lib/src/services/storage/kv_store_service.dart`, add to the abstract class:

```dart
/// Returns all currently opened namespace names.
List<String> get namespaces;

/// Returns all key-value pairs in the given namespace.
Future<Map<String, Object>> getAll({String namespace = "default"});
```

**Step 4: Implement in HiveStoreService**

In `lib/src/services/storage/hive_store_service.dart`, add:

```dart
@override
List<String> get namespaces => _boxes.keys
    .where((k) => k != 'default')
    .map((k) => k == 'default' ? defaultNamespace : k)
    .toList();
```

Wait — the `_boxes` map uses `"default"` as key for the default namespace (set in `initialize()`). Let me re-examine. In `initialize()`: `_boxes["default"] = await Hive.openBox(defaultNamespace);`. And in `_getOrCreateNamespace()`: `_boxes[namespace] = await Hive.openBox(namespace);` where namespace is the actual namespace name. So the map has key `"default"` mapping to the default box, and other keys are the actual namespace names.

Correct implementation:

```dart
@override
List<String> get namespaces {
  final result = <String>{defaultNamespace};
  for (final key in _boxes.keys) {
    if (key != 'default') {
      result.add(key);
    }
  }
  return result.toList();
}

@override
Future<Map<String, Object>> getAll({String? namespace}) async {
  final box = await _getOrCreateNamespace(namespace ?? defaultNamespace);
  final result = <String, Object>{};
  for (final key in box.keys) {
    final value = box.get(key);
    if (value != null) {
      result[key.toString()] = value;
    }
  }
  return result;
}
```

**Step 5: Run test to verify it passes**

Run: `flutter test test/hive_store_service_test.dart`
Expected: PASS

**Step 6: Run analyzer**

Run: `flutter analyze`
Expected: No new issues.

**Step 7: Commit**

```bash
git add lib/src/services/storage/kv_store_service.dart lib/src/services/storage/hive_store_service.dart test/hive_store_service_test.dart
git commit -m "feat: add namespaces and getAll to KV store service for data export"
```

---

### Task 2: Create DataExportSection interface and ConflictStrategy enum

Define the extensible section interface that all export sections will implement.

**Files:**
- Create: `lib/src/services/webserver/data_export/data_export_section.dart`

**Step 1: Create the file**

```dart
/// Strategy for handling conflicts during import.
enum ConflictStrategy { skip, overwrite }

/// Result of importing a single section.
class SectionImportResult {
  final int imported;
  final int skipped;
  final List<String> errors;
  final List<String> warnings;

  const SectionImportResult({
    this.imported = 0,
    this.skipped = 0,
    this.errors = const [],
    this.warnings = const [],
  });

  Map<String, dynamic> toJson() => {
    'imported': imported,
    'skipped': skipped,
    if (errors.isNotEmpty) 'errors': errors,
    if (warnings.isNotEmpty) 'warnings': warnings,
  };
}

/// A single section of the data export archive.
///
/// Each section corresponds to one JSON file in the ZIP.
/// Implementations handle exporting and importing their specific data type.
///
/// To add a new data type to the export:
/// 1. Create a class implementing DataExportSection
/// 2. Register it in DataExportHandler's constructor
abstract class DataExportSection {
  /// The filename for this section in the ZIP archive (e.g., 'profiles.json').
  String get filename;

  /// Export this section's data as a JSON-serializable object.
  Future<dynamic> export();

  /// Import data for this section.
  ///
  /// [data] is the parsed JSON from the archive file.
  /// [strategy] controls how conflicts (duplicate IDs) are handled.
  Future<SectionImportResult> import(
    dynamic data,
    ConflictStrategy strategy,
  );
}
```

**Step 2: Run analyzer**

Run: `flutter analyze`
Expected: No new issues.

**Step 3: Commit**

```bash
git add lib/src/services/webserver/data_export/data_export_section.dart
git commit -m "feat: add DataExportSection interface for extensible data export"
```

---

### Task 3: Implement ProfileExportSection

Wraps existing `ProfileController.exportProfiles()` / `importProfiles()`.

**Files:**
- Create: `lib/src/services/webserver/data_export/profile_export_section.dart`
- Test: `test/data_export/profile_export_section_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/profile_controller.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/data/profile_record.dart';
import 'package:reaprime/src/services/webserver/data_export/data_export_section.dart';
import 'package:reaprime/src/services/webserver/data_export/profile_export_section.dart';
// Use mock storage from existing test helpers if available, otherwise create inline

void main() {
  group('ProfileExportSection', () {
    test('filename is profiles.json', () {
      // Need a ProfileController with mock storage
      // Create section and verify filename
    });

    test('export returns list of profile JSON maps', () async {
      // Create controller with mock storage containing profiles
      // Call section.export()
      // Verify returns list of maps
    });

    test('import with skip strategy skips existing profiles', () async {
      // Pre-populate storage with a profile
      // Import same profile
      // Verify skipped count = 1
    });

    test('import with overwrite strategy replaces existing profiles', () async {
      // Pre-populate storage with a profile
      // Import same profile with overwrite
      // Verify imported count = 1
    });
  });
}
```

Exact test content depends on how the mock profile storage is set up — check existing profile controller tests for the mock pattern. The implementer should reference `test/profile_controller_test.dart` if it exists, or create a simple in-memory `ProfileStorageService` mock.

**Step 2: Run test to verify it fails**

Run: `flutter test test/data_export/profile_export_section_test.dart`
Expected: FAIL — `ProfileExportSection` doesn't exist.

**Step 3: Implement ProfileExportSection**

```dart
import 'package:reaprime/src/controllers/profile_controller.dart';
import 'package:reaprime/src/models/data/profile_record.dart';
import 'package:reaprime/src/services/webserver/data_export/data_export_section.dart';

class ProfileExportSection implements DataExportSection {
  final ProfileController _controller;

  ProfileExportSection({required ProfileController controller})
      : _controller = controller;

  @override
  String get filename => 'profiles.json';

  @override
  Future<dynamic> export() async {
    return await _controller.exportProfiles(
      includeHidden: true,
      includeDeleted: true,
    );
  }

  @override
  Future<SectionImportResult> import(
    dynamic data,
    ConflictStrategy strategy,
  ) async {
    if (data is! List) {
      return const SectionImportResult(
        errors: ['Expected JSON array of profile records'],
      );
    }

    final profilesJson = data.cast<Map<String, dynamic>>();

    if (strategy == ConflictStrategy.overwrite) {
      // For overwrite: import all, replacing existing
      int imported = 0;
      int errors = 0;
      final errorMessages = <String>[];

      for (final json in profilesJson) {
        try {
          final record = ProfileRecord.fromJson(json);
          final existing = await _controller.get(record.id);
          if (existing != null) {
            await _controller.update(record.id, profile: record.profile, metadata: record.metadata);
          } else {
            await _controller.importProfiles([json]);
          }
          imported++;
        } catch (e) {
          errors++;
          errorMessages.add('Failed to import profile: $e');
        }
      }

      return SectionImportResult(
        imported: imported,
        skipped: 0,
        errors: errorMessages,
      );
    }

    // Default: skip strategy — use existing importProfiles which already skips duplicates
    final result = await _controller.importProfiles(profilesJson);
    return SectionImportResult(
      imported: result['imported'] as int,
      skipped: result['skipped'] as int,
      errors: (result['errors'] as List?)?.cast<String>() ?? [],
    );
  }
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/data_export/profile_export_section_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/src/services/webserver/data_export/profile_export_section.dart test/data_export/profile_export_section_test.dart
git commit -m "feat: add ProfileExportSection for data export"
```

---

### Task 4: Implement ShotExportSection

**Files:**
- Create: `lib/src/services/webserver/data_export/shot_export_section.dart`
- Test: `test/data_export/shot_export_section_test.dart`

**Step 1: Write the failing test**

Test that export returns all shots as JSON array, and import with skip/overwrite works correctly.

**Step 2: Run test to verify it fails**

Run: `flutter test test/data_export/shot_export_section_test.dart`

**Step 3: Implement ShotExportSection**

```dart
import 'package:reaprime/src/controllers/persistence_controller.dart';
import 'package:reaprime/src/models/data/shot_record.dart';
import 'package:reaprime/src/services/webserver/data_export/data_export_section.dart';

class ShotExportSection implements DataExportSection {
  final PersistenceController _controller;

  ShotExportSection({required PersistenceController controller})
      : _controller = controller;

  @override
  String get filename => 'shots.json';

  @override
  Future<dynamic> export() async {
    final shots = await _controller.shots.first;
    return shots.map((s) => s.toJson()).toList();
  }

  @override
  Future<SectionImportResult> import(
    dynamic data,
    ConflictStrategy strategy,
  ) async {
    if (data is! List) {
      return const SectionImportResult(
        errors: ['Expected JSON array of shot records'],
      );
    }

    int imported = 0;
    int skipped = 0;
    final errors = <String>[];

    for (final item in data) {
      try {
        final record = ShotRecord.fromJson(item as Map<String, dynamic>);
        final existing = await _controller.storageService.getShot(record.id);

        if (existing != null) {
          if (strategy == ConflictStrategy.overwrite) {
            await _controller.updateShot(record);
            imported++;
          } else {
            skipped++;
          }
        } else {
          await _controller.persistShot(record);
          imported++;
        }
      } catch (e) {
        errors.add('Failed to import shot: $e');
      }
    }

    return SectionImportResult(
      imported: imported,
      skipped: skipped,
      errors: errors,
    );
  }
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/data_export/shot_export_section_test.dart`

**Step 5: Commit**

```bash
git add lib/src/services/webserver/data_export/shot_export_section.dart test/data_export/shot_export_section_test.dart
git commit -m "feat: add ShotExportSection for data export"
```

---

### Task 5: Implement WorkflowExportSection

**Files:**
- Create: `lib/src/services/webserver/data_export/workflow_export_section.dart`
- Test: `test/data_export/workflow_export_section_test.dart`

**Step 1: Write the failing test**

Test that export returns current workflow JSON, and import replaces it.

**Step 2: Run test to verify it fails**

**Step 3: Implement WorkflowExportSection**

```dart
import 'package:reaprime/src/controllers/workflow_controller.dart';
import 'package:reaprime/src/models/data/workflow.dart';
import 'package:reaprime/src/services/webserver/data_export/data_export_section.dart';

class WorkflowExportSection implements DataExportSection {
  final WorkflowController _controller;

  WorkflowExportSection({required WorkflowController controller})
      : _controller = controller;

  @override
  String get filename => 'workflow.json';

  @override
  Future<dynamic> export() async {
    return _controller.currentWorkflow.toJson();
  }

  @override
  Future<SectionImportResult> import(
    dynamic data,
    ConflictStrategy strategy,
  ) async {
    try {
      final workflow = Workflow.fromJson(data as Map<String, dynamic>);
      _controller.setWorkflow(workflow);
      return const SectionImportResult(imported: 1);
    } catch (e) {
      return SectionImportResult(errors: ['Failed to import workflow: $e']);
    }
  }
}
```

Note: Workflow is singular — `onConflict` doesn't apply (always overwrites). The `SectionImportResult` uses `imported: 1` to indicate success.

**Step 4: Run test, commit**

```bash
git add lib/src/services/webserver/data_export/workflow_export_section.dart test/data_export/workflow_export_section_test.dart
git commit -m "feat: add WorkflowExportSection for data export"
```

---

### Task 6: Implement SettingsExportSection

This exports settings, wake schedules, and device preferences. On import, warns about platform mismatch for device IDs.

**Files:**
- Create: `lib/src/services/webserver/data_export/settings_export_section.dart`
- Test: `test/data_export/settings_export_section_test.dart`

**Step 1: Write the failing test**

Test:
- Export produces correct JSON structure with settings, wakeSchedules, devicePreferences
- Import applies all settings
- Import from different platform produces warning about device preferences

**Step 2: Run test to verify it fails**

**Step 3: Implement SettingsExportSection**

The section needs `SettingsController` for reading/writing settings. It reads current values from the controller's getters and writes via the controller's update methods.

```dart
import 'dart:io';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:reaprime/src/services/webserver/data_export/data_export_section.dart';

class SettingsExportSection implements DataExportSection {
  final SettingsController _controller;

  SettingsExportSection({required SettingsController controller})
      : _controller = controller;

  @override
  String get filename => 'settings.json';

  @override
  Future<dynamic> export() async {
    return {
      'settings': {
        'gatewayMode': _controller.gatewayMode.name,
        'logLevel': _controller.logLevel,
        'weightFlowMultiplier': _controller.weightFlowMultiplier,
        'volumeFlowMultiplier': _controller.volumeFlowMultiplier,
        'scalePowerMode': _controller.scalePowerMode.name,
        'defaultSkinId': _controller.defaultSkinId,
        'automaticUpdateCheck': _controller.automaticUpdateCheck,
        'chargingMode': _controller.chargingMode.name,
        'nightModeEnabled': _controller.nightModeEnabled,
        'nightModeSleepTime': _controller.nightModeSleepTime,
        'nightModeMorningTime': _controller.nightModeMorningTime,
        'userPresenceEnabled': _controller.userPresenceEnabled,
        'sleepTimeoutMinutes': _controller.sleepTimeoutMinutes,
      },
      'wakeSchedules': _controller.wakeSchedules, // Already a JSON string
      'devicePreferences': {
        'preferredMachineId': _controller.preferredMachineId,
        'preferredScaleId': _controller.preferredScaleId,
      },
    };
  }

  @override
  Future<SectionImportResult> import(
    dynamic data,
    ConflictStrategy strategy,
  ) async {
    final warnings = <String>[];

    try {
      final map = data as Map<String, dynamic>;

      // Import settings
      if (map.containsKey('settings')) {
        final settings = map['settings'] as Map<String, dynamic>;
        // Apply each setting via the controller's update methods
        // (Reuse the same logic as POST /api/v1/settings)
        await _applySettings(settings);
      }

      // Import wake schedules
      if (map.containsKey('wakeSchedules')) {
        final schedules = map['wakeSchedules'];
        if (schedules is String) {
          await _controller.setWakeSchedules(schedules);
        }
      }

      // Import device preferences (with platform mismatch warning)
      if (map.containsKey('devicePreferences')) {
        final prefs = map['devicePreferences'] as Map<String, dynamic>;
        await _controller.setPreferredMachineId(prefs['preferredMachineId'] as String?);
        await _controller.setPreferredScaleId(prefs['preferredScaleId'] as String?);
      }

      return SectionImportResult(imported: 1, warnings: warnings);
    } catch (e) {
      return SectionImportResult(errors: ['Failed to import settings: $e']);
    }
  }

  Future<void> _applySettings(Map<String, dynamic> settings) async {
    // Apply each recognized setting key via controller methods.
    // Unknown keys are silently ignored for forward compatibility.
    // Implementation mirrors POST /api/v1/settings handler logic.
    // ... (apply each key)
  }
}
```

The platform mismatch warning is handled by the handler (Task 8) since it has access to metadata.json.

**Step 4: Run test, commit**

```bash
git add lib/src/services/webserver/data_export/settings_export_section.dart test/data_export/settings_export_section_test.dart
git commit -m "feat: add SettingsExportSection for data export"
```

---

### Task 7: Implement KvStoreExportSection

**Files:**
- Create: `lib/src/services/webserver/data_export/kv_store_export_section.dart`
- Test: `test/data_export/kv_store_export_section_test.dart`

**Step 1: Write the failing test**

Test:
- Export returns map of namespace → key/value pairs
- Import creates namespaces and sets all keys
- Import with skip strategy skips existing keys
- Import with overwrite strategy replaces existing keys

**Step 2: Run test to verify it fails**

**Step 3: Implement KvStoreExportSection**

```dart
import 'package:reaprime/src/services/storage/hive_store_service.dart';
import 'package:reaprime/src/services/webserver/data_export/data_export_section.dart';

class KvStoreExportSection implements DataExportSection {
  final HiveStoreService _store;

  KvStoreExportSection({required HiveStoreService store}) : _store = store;

  @override
  String get filename => 'store.json';

  @override
  Future<dynamic> export() async {
    final result = <String, dynamic>{};
    for (final namespace in _store.namespaces) {
      result[namespace] = await _store.getAll(namespace: namespace);
    }
    return {'namespaces': result};
  }

  @override
  Future<SectionImportResult> import(
    dynamic data,
    ConflictStrategy strategy,
  ) async {
    final map = data as Map<String, dynamic>;
    final namespaces = map['namespaces'] as Map<String, dynamic>?;
    if (namespaces == null) {
      return const SectionImportResult(
        errors: ['Expected "namespaces" key in store.json'],
      );
    }

    int imported = 0;
    int skipped = 0;
    final errors = <String>[];

    for (final entry in namespaces.entries) {
      final namespace = entry.key;
      final pairs = entry.value as Map<String, dynamic>;

      for (final kv in pairs.entries) {
        try {
          final existing = await _store.get(namespace: namespace, key: kv.key);
          if (existing != null && strategy == ConflictStrategy.skip) {
            skipped++;
          } else {
            await _store.set(
              namespace: namespace,
              key: kv.key,
              value: kv.value,
            );
            imported++;
          }
        } catch (e) {
          errors.add('Failed to import $namespace/${kv.key}: $e');
        }
      }
    }

    return SectionImportResult(
      imported: imported,
      skipped: skipped,
      errors: errors,
    );
  }
}
```

**Step 4: Run test, commit**

```bash
git add lib/src/services/webserver/data_export/kv_store_export_section.dart test/data_export/kv_store_export_section_test.dart
git commit -m "feat: add KvStoreExportSection for data export"
```

---

### Task 8: Implement DataExportHandler (the main handler)

This is the core handler that orchestrates export/import using the registered sections and the `archive` package.

**Files:**
- Create: `lib/src/services/webserver/data_export_handler.dart`
- Test: `test/data_export/data_export_handler_test.dart`

**Step 1: Write the failing test**

Test the handler via HTTP requests (same pattern as `test/devices_handler_test.dart`):
- `GET /api/v1/data/export` returns ZIP with correct content type and Content-Disposition
- ZIP contains metadata.json, profiles.json, shots.json, workflow.json, settings.json, store.json
- `POST /api/v1/data/import` with valid ZIP returns import summary
- `POST /api/v1/data/import?onConflict=overwrite` uses overwrite strategy
- `POST /api/v1/data/import` with invalid body returns 400
- Import with metadata.json containing higher formatVersion returns error
- Import with missing metadata.json still proceeds with warning

Use the existing test pattern:
```dart
final app = Router().plus;
handler.addRoutes(app);
final httpHandler = app.call;
// Send requests via Request('GET', Uri.parse('http://localhost/api/v1/data/export'))
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/data_export/data_export_handler_test.dart`

**Step 3: Implement DataExportHandler**

```dart
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/build_info.dart';
import 'package:reaprime/src/services/webserver/data_export/data_export_section.dart';
import 'package:reaprime/src/services/webserver/json_response.dart';
import 'package:shelf_plus/shelf_plus.dart';

class DataExportHandler {
  static const int _currentFormatVersion = 1;

  final List<DataExportSection> _sections;
  final Logger _log = Logger('DataExportHandler');

  DataExportHandler({required List<DataExportSection> sections})
      : _sections = sections;

  void addRoutes(RouterPlus app) {
    app.get('/api/v1/data/export', _handleExport);
    app.post('/api/v1/data/import', _handleImport);
  }

  Future<Response> _handleExport(Request request) async {
    try {
      final archive = Archive();

      // Add metadata.json
      final metadata = {
        'formatVersion': _currentFormatVersion,
        'appVersion': BuildInfo.version,
        'commitSha': BuildInfo.commitShort,
        'branch': BuildInfo.branch,
        'exportTimestamp': DateTime.now().toUtc().toIso8601String(),
        'platform': Platform.operatingSystem,
      };
      _addJsonToArchive(archive, 'metadata.json', metadata);

      // Export each registered section
      for (final section in _sections) {
        try {
          final data = await section.export();
          _addJsonToArchive(archive, section.filename, data);
        } catch (e, st) {
          _log.severe('Error exporting ${section.filename}', e, st);
          // Skip failed sections rather than failing entire export
        }
      }

      final zipBytes = ZipEncoder().encode(archive);
      if (zipBytes == null) {
        return jsonError({'error': 'Failed to create ZIP archive'});
      }

      final timestamp = DateTime.now().toUtc().toIso8601String()
          .replaceAll(':', '-').split('.').first;

      return Response.ok(
        zipBytes,
        headers: {
          'Content-Type': 'application/zip',
          'Content-Disposition':
              'attachment; filename="streamline_bridge_export_$timestamp.zip"',
        },
      );
    } catch (e, st) {
      _log.severe('Error in _handleExport', e, st);
      return jsonError({'error': 'Internal server error', 'message': '$e'});
    }
  }

  Future<Response> _handleImport(Request request) async {
    try {
      // Parse conflict strategy
      final onConflict = request.url.queryParameters['onConflict'] ?? 'skip';
      final ConflictStrategy strategy;
      switch (onConflict) {
        case 'skip':
          strategy = ConflictStrategy.skip;
          break;
        case 'overwrite':
          strategy = ConflictStrategy.overwrite;
          break;
        default:
          return jsonBadRequest({
            'error': 'Invalid onConflict value',
            'message': 'Valid values: skip, overwrite',
          });
      }

      // Read and decode ZIP
      final bytes = await request.read().expand((b) => b).toList();
      final archive = ZipDecoder().decodeBytes(bytes);

      // Parse metadata.json (optional but recommended)
      String? sourcePlatform;
      final metadataFile = archive.findFile('metadata.json');
      if (metadataFile != null) {
        final metadataJson = jsonDecode(utf8.decode(metadataFile.content));
        final formatVersion = metadataJson['formatVersion'] as int?;
        if (formatVersion != null && formatVersion > _currentFormatVersion) {
          return jsonBadRequest({
            'error': 'Unsupported export format',
            'message':
                'This archive was created with format version $formatVersion, '
                'but this app only supports up to version $_currentFormatVersion. '
                'Please update the app.',
          });
        }
        sourcePlatform = metadataJson['platform'] as String?;
      } else {
        _log.warning('Import archive missing metadata.json');
      }

      // Import each section
      final results = <String, dynamic>{};

      for (final section in _sections) {
        final file = archive.findFile(section.filename);
        if (file == null) continue;

        try {
          final data = jsonDecode(utf8.decode(file.content));
          final result = await section.import(data, strategy);

          // Add platform mismatch warning for settings
          if (section.filename == 'settings.json' &&
              sourcePlatform != null &&
              sourcePlatform != Platform.operatingSystem) {
            final warnings = List<String>.from(result.warnings);
            warnings.add(
              'Device preferences imported from \'$sourcePlatform\' may not '
              'work on \'${Platform.operatingSystem}\' — device IDs are '
              'platform-specific. Devices will need to be re-paired.',
            );
            results[_sectionKey(section)] = SectionImportResult(
              imported: result.imported,
              skipped: result.skipped,
              errors: result.errors,
              warnings: warnings,
            ).toJson();
          } else {
            results[_sectionKey(section)] = result.toJson();
          }
        } catch (e, st) {
          _log.severe('Error importing ${section.filename}', e, st);
          results[_sectionKey(section)] = {
            'errors': ['Failed to process ${section.filename}: $e'],
          };
        }
      }

      return jsonOk(results);
    } on ArchiveException catch (e) {
      return jsonBadRequest({
        'error': 'Invalid archive',
        'message': 'Could not read ZIP file: $e',
      });
    } catch (e, st) {
      _log.severe('Error in _handleImport', e, st);
      return jsonError({'error': 'Internal server error', 'message': '$e'});
    }
  }

  void _addJsonToArchive(Archive archive, String filename, dynamic data) {
    final jsonBytes = utf8.encode(jsonEncode(data));
    archive.addFile(ArchiveFile(filename, jsonBytes.length, jsonBytes));
  }

  /// Derive a result key from the section filename (e.g., 'profiles.json' -> 'profiles').
  String _sectionKey(DataExportSection section) =>
      section.filename.replaceAll('.json', '');
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/data_export/data_export_handler_test.dart`

**Step 5: Commit**

```bash
git add lib/src/services/webserver/data_export_handler.dart test/data_export/data_export_handler_test.dart
git commit -m "feat: add DataExportHandler with ZIP-based export and import"
```

---

### Task 9: Wire DataExportHandler into WebServer

Register the handler in `webserver_service.dart`.

**Files:**
- Modify: `lib/src/services/webserver_service.dart`

**Step 1: Add import**

`ShotsHandler` and `WorkflowHandler` are standalone files (not `part of`), so `DataExportHandler` follows the same pattern. Add to the imports at the top of `webserver_service.dart`:

```dart
import 'package:reaprime/src/services/webserver/data_export_handler.dart';
import 'package:reaprime/src/services/webserver/data_export/data_export_section.dart';
import 'package:reaprime/src/services/webserver/data_export/profile_export_section.dart';
import 'package:reaprime/src/services/webserver/data_export/shot_export_section.dart';
import 'package:reaprime/src/services/webserver/data_export/workflow_export_section.dart';
import 'package:reaprime/src/services/webserver/data_export/settings_export_section.dart';
import 'package:reaprime/src/services/webserver/data_export/kv_store_export_section.dart';
```

**Step 2: Instantiate handler in `startWebServer()`**

After the existing handler instantiations (around line 151, after `kvStoreHandler`), add:

```dart
final dataExportHandler = DataExportHandler(
  sections: [
    ProfileExportSection(controller: profileController),
    ShotExportSection(controller: persistenceController),
    WorkflowExportSection(controller: workflowController),
    SettingsExportSection(controller: settingsController),
    KvStoreExportSection(store: kvStoreHandler.store),
  ],
);
```

**Step 3: Add to `_init()` function signature and body**

Add `DataExportHandler dataExportHandler` parameter to `_init()`, and add `dataExportHandler.addRoutes(app);` in the route registration block (after existing handlers).

**Step 4: Pass handler in `startWebServer()`'s call to `_init()`**

Add `dataExportHandler` to the argument list where `_init()` is called (around line 155).

**Step 5: Run analyzer**

Run: `flutter analyze`
Expected: No new issues.

**Step 6: Run all tests**

Run: `flutter test`
Expected: All tests pass.

**Step 7: Commit**

```bash
git add lib/src/services/webserver_service.dart
git commit -m "feat: wire DataExportHandler into web server"
```

---

### Task 10: Update OpenAPI spec

Add the export/import endpoints to the API documentation.

**Files:**
- Modify: `assets/api/rest_v1.yml`

**Step 1: Add Data Management tag**

In the `tags` section of the YAML, add:

```yaml
- name: Data Management
  description: Full data export and import operations
```

**Step 2: Add export endpoint**

```yaml
/api/v1/data/export:
  get:
    summary: Export all app data
    description: >
      Exports all persistent app data as a ZIP archive containing separate JSON
      files for each data type. Includes profiles, shots, workflow, settings,
      and KV store data. The archive also contains a metadata.json with export
      information (format version, app version, timestamp, platform).
    tags: [Data Management]
    responses:
      200:
        description: ZIP archive containing all app data
        content:
          application/zip:
            schema:
              type: string
              format: binary
        headers:
          Content-Disposition:
            schema:
              type: string
            description: 'attachment; filename="streamline_bridge_export_{timestamp}.zip"'
      500:
        description: Internal server error
```

**Step 3: Add import endpoint**

```yaml
/api/v1/data/import:
  post:
    summary: Import app data from archive
    description: >
      Imports app data from a ZIP archive previously created by the export
      endpoint. Each JSON file in the archive is processed independently —
      missing files are skipped. Use the onConflict parameter to control
      how duplicate records are handled.
    tags: [Data Management]
    parameters:
      - in: query
        name: onConflict
        schema:
          type: string
          enum: [skip, overwrite]
          default: skip
        description: >
          How to handle records that already exist.
          'skip' keeps existing records (default).
          'overwrite' replaces existing records with imported ones.
    requestBody:
      required: true
      content:
        application/zip:
          schema:
            type: string
            format: binary
    responses:
      200:
        description: Import completed
        content:
          application/json:
            schema:
              type: object
              properties:
                profiles:
                  $ref: '#/components/schemas/SectionImportResult'
                shots:
                  $ref: '#/components/schemas/SectionImportResult'
                workflow:
                  $ref: '#/components/schemas/SectionImportResult'
                settings:
                  $ref: '#/components/schemas/SectionImportResult'
                store:
                  $ref: '#/components/schemas/SectionImportResult'
      400:
        description: Invalid archive or unsupported format version
      500:
        description: Internal server error
```

**Step 4: Add SectionImportResult schema**

In the `components/schemas` section:

```yaml
SectionImportResult:
  type: object
  properties:
    imported:
      type: integer
      description: Number of records successfully imported
    skipped:
      type: integer
      description: Number of records skipped (duplicates)
    errors:
      type: array
      items:
        type: string
      description: Error messages for failed records
    warnings:
      type: array
      items:
        type: string
      description: Warning messages (e.g., platform mismatch)
```

**Step 5: Commit**

```bash
git add assets/api/rest_v1.yml
git commit -m "docs: add data export/import endpoints to OpenAPI spec"
```

---

### Task 11: Integration test — full round-trip

Write a test that does a full export → import cycle to verify everything works end-to-end.

**Files:**
- Create: `test/data_export/data_export_integration_test.dart`

**Step 1: Write the integration test**

1. Set up all mock dependencies (mock storage with profiles, shots, workflow, settings, KV data)
2. Create the handler with all sections
3. Call `GET /api/v1/data/export`
4. Verify ZIP is returned with all expected files
5. Clear/reset mock storage
6. Call `POST /api/v1/data/import` with the exported ZIP
7. Verify all data was restored
8. Verify import response has correct counts

Also test:
- Import with `?onConflict=overwrite` when data already exists
- Import of ZIP with some files missing (partial import)

**Step 2: Run test**

Run: `flutter test test/data_export/data_export_integration_test.dart`

**Step 3: Run full test suite**

Run: `flutter test`
Expected: All pass.

**Step 4: Commit**

```bash
git add test/data_export/data_export_integration_test.dart
git commit -m "test: add integration test for data export/import round-trip"
```

---

### Task 12: Final verification

**Step 1: Run full test suite**

Run: `flutter test`

**Step 2: Run analyzer**

Run: `flutter analyze`

**Step 3: Verify app runs**

Run: `flutter run --dart-define=simulate=1`

Test manually:
- `curl http://localhost:8080/api/v1/data/export -o export.zip`
- Unzip and inspect contents
- `curl -X POST http://localhost:8080/api/v1/data/import -H 'Content-Type: application/zip' --data-binary @export.zip`
- Verify response JSON

**Step 4: Final commit if any cleanup needed**
