# Data Sync Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a `POST /api/v1/data/sync` endpoint that synchronizes data between two Bridge instances using the existing export/import infrastructure.

**Architecture:** Refactor `DataExportHandler` to expose `exportToBytes()` and `importFromBytes()` as public methods. Create a new `DataSyncHandler` that uses these methods plus an `http.Client` to pull/push data to/from a target Bridge instance. Section filtering happens at export time.

**Tech Stack:** Dart, shelf_plus, http package, archive package, flutter_test

**Design doc:** `doc/plans/2026-03-14-data-sync-design.md`

---

### Task 1: Refactor `DataExportHandler` — extract `exportToBytes()`

**Files:**
- Modify: `lib/src/services/webserver/data_export_handler.dart`
- Test: `test/data_export/data_export_handler_test.dart`

**Step 1: Write the failing test**

Add to `test/data_export/data_export_handler_test.dart`, inside the existing `group('DataExportHandler', ...)`:

```dart
group('exportToBytes()', () {
  test('returns ZIP bytes containing all sections', () async {
    final bytes = await handler.exportToBytes();

    final archive = ZipDecoder().decodeBytes(bytes);
    expect(archive.findFile('metadata.json'), isNotNull);
    expect(archive.findFile('profiles.json'), isNotNull);
    expect(archive.findFile('shots.json'), isNotNull);
  });

  test('filters sections when specified', () async {
    final bytes = await handler.exportToBytes(sections: ['profiles']);

    final archive = ZipDecoder().decodeBytes(bytes);
    expect(archive.findFile('metadata.json'), isNotNull);
    expect(archive.findFile('profiles.json'), isNotNull);
    expect(archive.findFile('shots.json'), isNull);
  });
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/data_export/data_export_handler_test.dart`
Expected: Compile error — `exportToBytes` does not exist on `DataExportHandler`.

**Step 3: Implement `exportToBytes()`**

In `data_export_handler.dart`, add this public method and refactor `_handleExport` to use it:

```dart
/// Exports data as ZIP bytes.
///
/// If [sections] is provided, only sections whose filename (without .json)
/// matches an entry in the list are included.
Future<List<int>> exportToBytes({List<String>? sections}) async {
  final archive = Archive();

  final metadata = {
    'formatVersion': _currentFormatVersion,
    'appVersion': BuildInfo.version,
    'buildNumber': BuildInfo.buildNumber,
    'commitSha': BuildInfo.commitShort,
    'branch': BuildInfo.branch,
    'exportTimestamp': DateTime.now().toUtc().toIso8601String(),
    'platform': Platform.operatingSystem,
  };
  _addJsonToArchive(archive, 'metadata.json', metadata);

  for (final section in _sections) {
    if (sections != null && !sections.contains(_sectionKey(section))) {
      continue;
    }
    try {
      final data = await section.export();
      _addJsonToArchive(archive, section.filename, data);
    } catch (e, st) {
      _log.severe('Error exporting ${section.filename}', e, st);
    }
  }

  return ZipEncoder().encode(archive);
}
```

Then simplify `_handleExport`:

```dart
Future<Response> _handleExport(Request request) async {
  try {
    final zipBytes = await exportToBytes();

    final timestamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;

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
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/data_export/data_export_handler_test.dart`
Expected: All tests PASS (existing + new).

**Step 5: Commit**

```bash
git add lib/src/services/webserver/data_export_handler.dart test/data_export/data_export_handler_test.dart
git commit -m "refactor: extract exportToBytes() from DataExportHandler"
```

---

### Task 2: Refactor `DataExportHandler` — extract `importFromBytes()`

**Files:**
- Modify: `lib/src/services/webserver/data_export_handler.dart`
- Test: `test/data_export/data_export_handler_test.dart`

**Step 1: Write the failing test**

Add to test file, inside `group('DataExportHandler', ...)`:

```dart
group('importFromBytes()', () {
  test('imports all sections from ZIP bytes', () async {
    final zipBytes = buildZip({
      'metadata.json': {'formatVersion': 1, 'platform': 'macos'},
      'profiles.json': {'profiles': [{'id': 'p1'}]},
      'shots.json': {'shots': [{'id': 's1'}]},
    });

    final results = await handler.importFromBytes(
      zipBytes,
      ConflictStrategy.skip,
    );

    expect(results, contains('profiles'));
    expect(results, contains('shots'));
    expect(profileSection.importCalled, isTrue);
    expect(shotsSection.importCalled, isTrue);
  });

  test('filters sections when specified', () async {
    final zipBytes = buildZip({
      'metadata.json': {'formatVersion': 1, 'platform': 'macos'},
      'profiles.json': {'profiles': [{'id': 'p1'}]},
      'shots.json': {'shots': [{'id': 's1'}]},
    });

    final results = await handler.importFromBytes(
      zipBytes,
      ConflictStrategy.skip,
      sections: ['profiles'],
    );

    expect(results, contains('profiles'));
    expect(results, isNot(contains('shots')));
    expect(profileSection.importCalled, isTrue);
    expect(shotsSection.importCalled, isFalse);
  });

  test('throws FormatException for unsupported format version', () async {
    final zipBytes = buildZip({
      'metadata.json': {'formatVersion': 99},
    });

    expect(
      () => handler.importFromBytes(zipBytes, ConflictStrategy.skip),
      throwsA(isA<FormatException>()),
    );
  });
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/data_export/data_export_handler_test.dart`
Expected: Compile error — `importFromBytes` does not exist.

**Step 3: Implement `importFromBytes()`**

In `data_export_handler.dart`, add:

```dart
/// Imports data from ZIP bytes.
///
/// If [sections] is provided, only sections whose filename (without .json)
/// matches an entry in the list are processed.
///
/// Throws [FormatException] if the archive format version is unsupported.
/// Throws [ArchiveException] if the ZIP is invalid.
Future<Map<String, dynamic>> importFromBytes(
  List<int> zipBytes,
  ConflictStrategy strategy, {
  List<String>? sections,
}) async {
  final archive = ZipDecoder().decodeBytes(zipBytes);

  // Parse metadata
  String? sourcePlatform;
  final metadataFile = archive.findFile('metadata.json');
  if (metadataFile != null) {
    final metadataJson = jsonDecode(utf8.decode(metadataFile.content));
    final formatVersion = metadataJson['formatVersion'] as int?;
    if (formatVersion != null && formatVersion > _currentFormatVersion) {
      throw FormatException(
        'This archive was created with format version $formatVersion, '
        'but this app only supports up to version $_currentFormatVersion. '
        'Please update the app.',
      );
    }
    sourcePlatform = metadataJson['platform'] as String?;
  } else {
    _log.warning('Import archive missing metadata.json');
  }

  final results = <String, dynamic>{};

  for (final section in _sections) {
    final key = _sectionKey(section);
    if (sections != null && !sections.contains(key)) continue;

    final file = archive.findFile(section.filename);
    if (file == null) continue;

    try {
      final data = jsonDecode(utf8.decode(file.content));
      final result = await section.import(data, strategy);

      if (section.filename == 'settings.json' &&
          sourcePlatform != null &&
          sourcePlatform != Platform.operatingSystem) {
        final warnings = List<String>.from(result.warnings);
        warnings.add(
          'Device preferences imported from \'$sourcePlatform\' may not '
          'work on \'${Platform.operatingSystem}\' — device IDs are '
          'platform-specific. Devices will need to be re-paired.',
        );
        results[key] = SectionImportResult(
          imported: result.imported,
          skipped: result.skipped,
          errors: result.errors,
          warnings: warnings,
        ).toJson();
      } else {
        results[key] = result.toJson();
      }
    } catch (e, st) {
      _log.severe('Error importing ${section.filename}', e, st);
      results[key] = {
        'errors': ['Failed to process ${section.filename}: $e'],
      };
    }
  }

  return results;
}
```

Then simplify `_handleImport`:

```dart
Future<Response> _handleImport(Request request) async {
  try {
    final onConflict = request.url.queryParameters['onConflict'] ?? 'skip';
    final ConflictStrategy strategy;
    switch (onConflict) {
      case 'skip':
        strategy = ConflictStrategy.skip;
      case 'overwrite':
        strategy = ConflictStrategy.overwrite;
      default:
        return jsonBadRequest({
          'error': 'Invalid onConflict value',
          'message': 'Valid values: skip, overwrite',
        });
    }

    final bytes = await request.read().expand((b) => b).toList();
    final results = await importFromBytes(bytes, strategy);
    return jsonOk(results);
  } on FormatException catch (e) {
    return jsonBadRequest({
      'error': 'Unsupported export format',
      'message': e.message,
    });
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
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/data_export/data_export_handler_test.dart`
Expected: All tests PASS.

**Step 5: Commit**

```bash
git add lib/src/services/webserver/data_export_handler.dart test/data_export/data_export_handler_test.dart
git commit -m "refactor: extract importFromBytes() from DataExportHandler"
```

---

### Task 3: Create `DataSyncHandler` — pull mode

**Files:**
- Create: `lib/src/services/webserver/data_sync_handler.dart`
- Create: `test/data_export/data_sync_handler_test.dart`

**Step 1: Write the failing test**

Create `test/data_export/data_sync_handler_test.dart`:

```dart
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:reaprime/src/services/webserver/data_export/data_export_section.dart';
import 'package:reaprime/src/services/webserver/data_export_handler.dart';
import 'package:reaprime/src/services/webserver/data_sync_handler.dart';
import 'package:shelf_plus/shelf_plus.dart';

/// Reuse mock section from data_export_handler_test pattern.
class MockExportSection implements DataExportSection {
  @override
  final String filename;
  final dynamic exportData;
  final SectionImportResult importResult;
  dynamic lastImportedData;
  ConflictStrategy? lastStrategy;
  bool importCalled = false;

  MockExportSection({
    required this.filename,
    this.exportData = const {'mock': true},
    this.importResult = const SectionImportResult(imported: 1),
  });

  @override
  Future<dynamic> export() async => exportData;

  @override
  Future<SectionImportResult> import(
    dynamic data,
    ConflictStrategy strategy,
  ) async {
    importCalled = true;
    lastImportedData = data;
    lastStrategy = strategy;
    return importResult;
  }
}

/// Helper: build ZIP bytes from a map of filename → JSON data.
List<int> buildZip(Map<String, dynamic> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile.string(entry.key, jsonEncode(entry.value)));
  }
  return ZipEncoder().encode(archive);
}

void main() {
  late DataExportHandler exportHandler;
  late MockExportSection profileSection;
  late Handler httpHandler;

  setUp(() {
    profileSection = MockExportSection(
      filename: 'profiles.json',
      exportData: {'profiles': [{'id': 'p1', 'name': 'Default'}]},
      importResult: const SectionImportResult(imported: 1),
    );
  });

  /// Helper to create sync handler + shelf handler with a given mock HTTP client.
  Handler buildSyncHandler(http.Client client) {
    exportHandler = DataExportHandler(
      sections: [profileSection],
    );
    final syncHandler = DataSyncHandler(
      exportHandler: exportHandler,
      httpClient: client,
    );
    final app = Router().plus;
    syncHandler.addRoutes(app);
    return app.call;
  }

  Future<Response> sendSync(Handler handler, Map<String, dynamic> body) async {
    return await handler(
      Request(
        'POST',
        Uri.parse('http://localhost/api/v1/data/sync'),
        body: jsonEncode(body),
        headers: {'content-type': 'application/json'},
      ),
    );
  }

  group('DataSyncHandler', () {
    group('pull mode', () {
      test('pulls data from target and imports locally', () async {
        final targetZip = buildZip({
          'metadata.json': {'formatVersion': 1, 'platform': 'android'},
          'profiles.json': {'profiles': [{'id': 'remote1'}]},
        });

        final client = http_testing.MockClient((request) async {
          expect(request.method, 'GET');
          expect(
            request.url.toString(),
            'http://192.168.1.50:8080/api/v1/data/export',
          );
          return http.Response.bytes(targetZip, 200);
        });

        httpHandler = buildSyncHandler(client);
        final response = await sendSync(httpHandler, {
          'target': 'http://192.168.1.50:8080',
          'mode': 'pull',
        });

        expect(response.statusCode, 200);
        final body = jsonDecode(await response.readAsString());
        expect(body['pull'], contains('profiles'));
        expect(profileSection.importCalled, isTrue);
      });
    });
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/data_export/data_sync_handler_test.dart`
Expected: Compile error — `data_sync_handler.dart` does not exist.

**Step 3: Implement `DataSyncHandler` with pull mode**

Create `lib/src/services/webserver/data_sync_handler.dart`:

```dart
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:reaprime/src/services/webserver/data_export/data_export_section.dart';
import 'package:reaprime/src/services/webserver/data_export_handler.dart';
import 'package:reaprime/src/services/webserver/json_response.dart';
import 'package:shelf_plus/shelf_plus.dart';

class DataSyncHandler {
  final DataExportHandler _exportHandler;
  final http.Client _httpClient;
  final Logger _log = Logger('DataSyncHandler');

  DataSyncHandler({
    required DataExportHandler exportHandler,
    required http.Client httpClient,
  })  : _exportHandler = exportHandler,
        _httpClient = httpClient;

  void addRoutes(RouterPlus app) {
    app.post('/api/v1/data/sync', _handleSync);
  }

  Future<Response> _handleSync(Request request) async {
    // Parse request body
    final String bodyStr;
    try {
      bodyStr = await request.readAsString();
    } catch (e) {
      return jsonBadRequest({'error': 'Could not read request body'});
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(bodyStr) as Map<String, dynamic>;
    } catch (e) {
      return jsonBadRequest({'error': 'Invalid JSON'});
    }

    // Validate required fields
    final target = body['target'] as String?;
    if (target == null || target.isEmpty) {
      return jsonBadRequest({
        'error': 'Missing required field',
        'message': '"target" is required',
      });
    }

    final modeStr = body['mode'] as String?;
    if (modeStr == null) {
      return jsonBadRequest({
        'error': 'Missing required field',
        'message': '"mode" is required. Valid values: pull, push, two_way',
      });
    }

    final SyncMode mode;
    switch (modeStr) {
      case 'pull':
        mode = SyncMode.pull;
      case 'push':
        mode = SyncMode.push;
      case 'two_way':
        mode = SyncMode.twoWay;
      default:
        return jsonBadRequest({
          'error': 'Invalid mode',
          'message': 'Valid values: pull, push, two_way',
        });
    }

    final onConflict = body['onConflict'] as String? ?? 'skip';
    final ConflictStrategy strategy;
    switch (onConflict) {
      case 'skip':
        strategy = ConflictStrategy.skip;
      case 'overwrite':
        strategy = ConflictStrategy.overwrite;
      default:
        return jsonBadRequest({
          'error': 'Invalid onConflict value',
          'message': 'Valid values: skip, overwrite',
        });
    }

    final sections = (body['sections'] as List<dynamic>?)
        ?.cast<String>();

    // Execute sync
    final results = <String, dynamic>{};
    bool pullFailed = false;
    bool pushFailed = false;

    // Pull phase
    if (mode == SyncMode.pull || mode == SyncMode.twoWay) {
      try {
        final pullResult = await _pull(target, strategy, sections);
        results['pull'] = pullResult;
      } catch (e) {
        pullFailed = true;
        results['pull'] = _errorResult(e);
      }
    }

    // Push phase
    if (mode == SyncMode.push || mode == SyncMode.twoWay) {
      try {
        final pushResult = await _push(target, strategy, sections);
        results['push'] = pushResult;
      } catch (e) {
        pushFailed = true;
        results['push'] = _errorResult(e);
      }
    }

    // Determine response status
    if (mode == SyncMode.twoWay && (pullFailed != pushFailed)) {
      // Partial failure in two-way sync
      return Response(207,
        body: jsonEncode(results),
        headers: {'Content-Type': 'application/json'},
      );
    }

    if (pullFailed || pushFailed) {
      return Response(502,
        body: jsonEncode(results),
        headers: {'Content-Type': 'application/json'},
      );
    }

    return jsonOk(results);
  }

  Future<Map<String, dynamic>> _pull(
    String target,
    ConflictStrategy strategy,
    List<String>? sections,
  ) async {
    _log.info('Pulling data from $target');

    final uri = Uri.parse('$target/api/v1/data/export');
    final response = await _httpClient.get(uri);

    if (response.statusCode != 200) {
      throw SyncTargetException(
        'Target returned status ${response.statusCode}',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }

    return await _exportHandler.importFromBytes(
      response.bodyBytes,
      strategy,
      sections: sections,
    );
  }

  Map<String, dynamic> _errorResult(Object error) {
    if (error is SyncTargetException) {
      return {
        'error': 'Target error',
        'status': error.statusCode,
        'message': error.message,
      };
    }
    if (error is http.ClientException) {
      return {
        'error': 'Target unreachable',
        'message': error.message,
      };
    }
    return {
      'error': 'Sync failed',
      'message': '$error',
    };
  }
}

enum SyncMode { pull, push, twoWay }

class SyncTargetException implements Exception {
  final String message;
  final int? statusCode;
  final String? responseBody;

  SyncTargetException(this.message, {this.statusCode, this.responseBody});

  @override
  String toString() => 'SyncTargetException: $message';
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/data_export/data_sync_handler_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/src/services/webserver/data_sync_handler.dart test/data_export/data_sync_handler_test.dart
git commit -m "feat: add DataSyncHandler with pull mode"
```

---

### Task 4: Add push mode to `DataSyncHandler`

**Files:**
- Modify: `lib/src/services/webserver/data_sync_handler.dart`
- Modify: `test/data_export/data_sync_handler_test.dart`

**Step 1: Write the failing test**

Add to `test/data_export/data_sync_handler_test.dart`, inside `group('DataSyncHandler', ...)`:

```dart
group('push mode', () {
  test('exports local data and sends to target', () async {
    Uri? capturedUri;
    List<int>? capturedBody;

    final client = http_testing.MockClient((request) async {
      capturedUri = request.url;
      capturedBody = request.bodyBytes;
      expect(request.method, 'POST');
      return http.Response('{"profiles":{"imported":1,"skipped":0}}', 200);
    });

    httpHandler = buildSyncHandler(client);
    final response = await sendSync(httpHandler, {
      'target': 'http://192.168.1.50:8080',
      'mode': 'push',
      'onConflict': 'overwrite',
    });

    expect(response.statusCode, 200);
    expect(
      capturedUri.toString(),
      'http://192.168.1.50:8080/api/v1/data/import?onConflict=overwrite',
    );

    // Verify ZIP was sent
    final archive = ZipDecoder().decodeBytes(capturedBody!);
    expect(archive.findFile('profiles.json'), isNotNull);

    final body = jsonDecode(await response.readAsString());
    expect(body['push'], isNotNull);
  });
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/data_export/data_sync_handler_test.dart`
Expected: FAIL — push mode not implemented (missing `_push` method body).

**Step 3: Implement `_push()` method**

Add to `data_sync_handler.dart`:

```dart
Future<Map<String, dynamic>> _push(
  String target,
  ConflictStrategy strategy,
  List<String>? sections,
) async {
  _log.info('Pushing data to $target');

  final zipBytes = await _exportHandler.exportToBytes(sections: sections);

  final uri = Uri.parse(
    '$target/api/v1/data/import?onConflict=${strategy.name}',
  );
  final response = await _httpClient.post(
    uri,
    body: zipBytes,
    headers: {'Content-Type': 'application/octet-stream'},
  );

  if (response.statusCode != 200) {
    throw SyncTargetException(
      'Target returned status ${response.statusCode}',
      statusCode: response.statusCode,
      responseBody: response.body,
    );
  }

  return jsonDecode(response.body) as Map<String, dynamic>;
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/data_export/data_sync_handler_test.dart`
Expected: All tests PASS.

**Step 5: Commit**

```bash
git add lib/src/services/webserver/data_sync_handler.dart test/data_export/data_sync_handler_test.dart
git commit -m "feat: add push mode to DataSyncHandler"
```

---

### Task 5: Add two-way mode and error handling tests

**Files:**
- Modify: `test/data_export/data_sync_handler_test.dart`

**Step 1: Write the tests**

Add to `group('DataSyncHandler', ...)`:

```dart
group('two_way mode', () {
  test('pulls then pushes', () async {
    final targetZip = buildZip({
      'metadata.json': {'formatVersion': 1, 'platform': 'android'},
      'profiles.json': {'profiles': [{'id': 'remote1'}]},
    });

    int callCount = 0;
    final client = http_testing.MockClient((request) async {
      callCount++;
      if (request.method == 'GET') {
        return http.Response.bytes(targetZip, 200);
      }
      // POST (push)
      return http.Response(
        '{"profiles":{"imported":1,"skipped":0}}',
        200,
      );
    });

    httpHandler = buildSyncHandler(client);
    final response = await sendSync(httpHandler, {
      'target': 'http://192.168.1.50:8080',
      'mode': 'two_way',
    });

    expect(response.statusCode, 200);
    final body = jsonDecode(await response.readAsString());
    expect(body['pull'], isNotNull);
    expect(body['push'], isNotNull);
    expect(callCount, 2);
  });
});

group('section filtering', () {
  test('filters sections in pull mode', () async {
    final targetZip = buildZip({
      'metadata.json': {'formatVersion': 1, 'platform': 'android'},
      'profiles.json': {'profiles': [{'id': 'remote1'}]},
    });

    final client = http_testing.MockClient((request) async {
      return http.Response.bytes(targetZip, 200);
    });

    httpHandler = buildSyncHandler(client);
    final response = await sendSync(httpHandler, {
      'target': 'http://192.168.1.50:8080',
      'mode': 'pull',
      'sections': ['profiles'],
    });

    expect(response.statusCode, 200);
    expect(profileSection.importCalled, isTrue);
  });
});

group('error handling', () {
  test('returns 400 for missing target', () async {
    final client = http_testing.MockClient((_) async =>
      http.Response('', 200));
    httpHandler = buildSyncHandler(client);

    final response = await sendSync(httpHandler, {
      'mode': 'pull',
    });
    expect(response.statusCode, 400);
  });

  test('returns 400 for invalid mode', () async {
    final client = http_testing.MockClient((_) async =>
      http.Response('', 200));
    httpHandler = buildSyncHandler(client);

    final response = await sendSync(httpHandler, {
      'target': 'http://192.168.1.50:8080',
      'mode': 'invalid',
    });
    expect(response.statusCode, 400);
  });

  test('returns 502 when target is unreachable', () async {
    final client = http_testing.MockClient((_) async {
      throw http.ClientException('Connection refused');
    });

    httpHandler = buildSyncHandler(client);
    final response = await sendSync(httpHandler, {
      'target': 'http://192.168.1.50:8080',
      'mode': 'pull',
    });

    expect(response.statusCode, 502);
    final body = jsonDecode(await response.readAsString());
    expect(body['pull']['error'], 'Target unreachable');
  });

  test('returns 502 when target returns error', () async {
    final client = http_testing.MockClient((_) async {
      return http.Response('Not found', 404);
    });

    httpHandler = buildSyncHandler(client);
    final response = await sendSync(httpHandler, {
      'target': 'http://192.168.1.50:8080',
      'mode': 'pull',
    });

    expect(response.statusCode, 502);
    final body = jsonDecode(await response.readAsString());
    expect(body['pull']['error'], 'Target error');
  });

  test('returns 207 for partial two-way failure', () async {
    final targetZip = buildZip({
      'metadata.json': {'formatVersion': 1, 'platform': 'android'},
      'profiles.json': {'profiles': [{'id': 'remote1'}]},
    });

    int callCount = 0;
    final client = http_testing.MockClient((request) async {
      callCount++;
      if (request.method == 'GET') {
        return http.Response.bytes(targetZip, 200);
      }
      // Push fails
      throw http.ClientException('Connection reset');
    });

    httpHandler = buildSyncHandler(client);
    final response = await sendSync(httpHandler, {
      'target': 'http://192.168.1.50:8080',
      'mode': 'two_way',
    });

    expect(response.statusCode, 207);
    final body = jsonDecode(await response.readAsString());
    expect(body['pull'], contains('profiles'));
    expect(body['push']['error'], 'Target unreachable');
  });
});
```

**Step 2: Run tests to verify they pass**

Run: `flutter test test/data_export/data_sync_handler_test.dart`
Expected: All tests PASS (two-way and error handling logic already implemented in Task 3).

**Step 3: Commit**

```bash
git add test/data_export/data_sync_handler_test.dart
git commit -m "test: add two-way sync, section filtering, and error handling tests"
```

---

### Task 6: Register `DataSyncHandler` in `webserver_service.dart`

**Files:**
- Modify: `lib/src/services/webserver_service.dart`

**Step 1: Add import and instantiation**

Add import at top of file:
```dart
import 'package:http/http.dart' as http;
import 'package:reaprime/src/services/webserver/data_sync_handler.dart';
```

After `dataExportHandler` is created (line ~192), add:
```dart
final dataSyncHandler = DataSyncHandler(
  exportHandler: dataExportHandler,
  httpClient: http.Client(),
);
```

**Step 2: Add to `_init()` signature and route registration**

Add `DataSyncHandler dataSyncHandler` parameter to `_init()`.

Add route registration near `dataExportHandler.addRoutes(app)`:
```dart
dataSyncHandler.addRoutes(app);
```

Pass `dataSyncHandler` in the `_init()` call.

**Step 3: Run analyze and full test suite**

Run: `flutter analyze && flutter test`
Expected: No issues, all tests pass.

**Step 4: Commit**

```bash
git add lib/src/services/webserver_service.dart
git commit -m "feat: register DataSyncHandler in web server"
```

---

### Task 7: Add MCP tool for data sync

**Files:**
- Modify or create: `packages/mcp-server/src/tools/data-tools.ts` (if exists) or create new file
- Modify: `packages/mcp-server/src/server.ts`

**Step 1: Check existing data tools in MCP server**

Look for existing data export/import tools in `packages/mcp-server/src/tools/` and follow the same pattern.

**Step 2: Create sync tool**

Register a `data_sync` tool with Zod schema matching the endpoint:
- `target`: string (required)
- `mode`: enum pull/push/two_way (required)
- `onConflict`: enum skip/overwrite (optional, default skip)
- `sections`: array of strings (optional)

Delegate to `POST /api/v1/data/sync` via REST client.

**Step 3: Register in server.ts**

Import and call the register function in `server.ts`.

**Step 4: Test via MCP**

Use MCP tools to call `data_sync` with a target device IP to verify real-world sync.

**Step 5: Commit**

```bash
git add packages/mcp-server/src/tools/ packages/mcp-server/src/server.ts
git commit -m "feat: add MCP tool for data sync"
```

---

### Task 8: Update API spec and documentation

**Files:**
- Modify: `assets/api/rest_v1.yml` — add `POST /api/v1/data/sync` endpoint spec
- Modify: `CLAUDE.md` — add sync endpoint to REST API table

**Step 1: Add OpenAPI spec**

Add the sync endpoint to `rest_v1.yml` near the existing `/api/v1/data/export` and `/api/v1/data/import` entries.

**Step 2: Update CLAUDE.md REST API table**

Add `Data Sync` row: `| Data Sync | /api/v1/data/sync | data_sync_handler.dart |`

**Step 3: Commit**

```bash
git add assets/api/rest_v1.yml CLAUDE.md
git commit -m "docs: add data sync endpoint to API spec and CLAUDE.md"
```
