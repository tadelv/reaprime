# Full Data Export/Import Design

## Overview

A comprehensive data export/import solution for Streamline-Bridge that enables backup, restore, device migration, and interoperability. Exports all persistent app data as a ZIP archive via REST API.

## Use Cases

- **Backup & restore:** Protect against data loss (factory reset, device failure)
- **Device migration:** Move all data from one Streamline-Bridge instance to another
- **Interoperability:** Export data for use in other apps, spreadsheets, or sharing

## API Endpoints

### Export

```
GET /api/v1/data/export
```

Returns a ZIP file with `Content-Disposition: attachment; filename="streamline_bridge_export_{timestamp}.zip"`.

### Import

```
POST /api/v1/data/import?onConflict=skip|overwrite
```

Accepts a ZIP in the same format. Query parameter `onConflict` controls duplicate handling (default: `skip`).

**Response:**
```json
{
  "profiles": { "imported": 12, "skipped": 3, "errors": [] },
  "shots": { "imported": 45, "skipped": 2, "errors": [] },
  "workflow": { "imported": true },
  "settings": { "imported": true, "warnings": [] },
  "store": { "imported": 5, "skipped": 0, "errors": [] }
}
```

Missing files in the ZIP are silently skipped (supports partial imports).

## ZIP Archive Structure

| File | Contents |
|------|----------|
| `metadata.json` | Export format version, app version, commit SHA, branch, timestamp, platform |
| `profiles.json` | All profiles (same format as existing `/api/v1/profiles/export`) |
| `shots.json` | All shot records as JSON array |
| `workflow.json` | Current workflow/recipe |
| `settings.json` | All settings, wake schedules, device preferences |
| `store.json` | All KV store namespaces and key/value pairs |

### metadata.json

```json
{
  "formatVersion": 1,
  "appVersion": "1.2.3",
  "commitSha": "4b67d36",
  "branch": "main",
  "exportTimestamp": "2026-02-28T14:30:00Z",
  "platform": "android"
}
```

### settings.json

```json
{
  "settings": { "themeMode": "system", "gatewayMode": "full", "..." : "..." },
  "wakeSchedules": [{ "id": "...", "hour": 7, "minute": 0, "daysOfWeek": [1,2,3,4,5], "enabled": true }],
  "devicePreferences": {
    "preferredMachineId": "XX:XX:XX:XX",
    "preferredScaleId": "YY:YY:YY:YY"
  }
}
```

### store.json

```json
{
  "namespaces": {
    "kvStore": { "key1": "value1" },
    "plugins": { "pluginA_setting": "value" }
  }
}
```

## Conflict Resolution

- `?onConflict=skip` (default): Existing records kept, duplicates skipped. Skipped count reported.
- `?onConflict=overwrite`: Imported records replace existing ones with same ID.
- Settings import always overwrites (singular values, not collections).

## Implementation Architecture

### New File

`lib/src/services/webserver/data_export_handler.dart`

### Registry Pattern for Extensibility

Each data type implements a `DataExportSection` interface:

```dart
abstract class DataExportSection {
  String get filename;
  Future<dynamic> export();
  Future<SectionImportResult> import(dynamic data, ConflictStrategy strategy);
}
```

Sections are registered in the handler. Adding a new data type (e.g., databases) means:
1. Create a class implementing `DataExportSection`
2. Register it in the handler

No changes needed to the handler, endpoints, or existing sections.

### Dependencies

The handler needs access to:
- `ProfileController` — reuses existing `exportProfiles()` / `importProfiles()`
- `PersistenceController` — shot records via `getAllShots()`
- `WorkflowController` — current workflow
- `SettingsService` — all settings
- `HiveStoreService` — KV store data

### Export Flow

1. Iterate registered sections, call `export()` on each
2. Serialize each result to JSON
3. Build ZIP archive in memory using the `archive` package (already a dependency)
4. Add `metadata.json` with app version, commit SHA, branch, timestamp, platform
5. Return ZIP response with `Content-Disposition` header

### Import Flow

1. Read ZIP from request body
2. Decode archive, extract files
3. Parse `metadata.json` first for format version validation
4. For each recognized file, find matching registered section and call `import()`
5. Collect results per section, return summary response

## Edge Cases

### Platform Mismatch (Device Preferences)

BLE device IDs are platform-specific (Android uses MAC addresses, iOS uses UUIDs, serial ports are OS-specific). When `metadata.platform` differs from the importing device:

- Device preferences are still imported (harmless if wrong — app won't auto-connect)
- Response includes a warning: `"Device preferences imported from '{source_platform}' may not work on '{target_platform}' — device IDs are platform-specific. Devices will need to be re-paired."`

### Format Version Mismatch

- If `metadata.formatVersion` is higher than what the app understands, import is rejected with a clear error
- `formatVersion` only bumps for breaking changes to existing file schemas

### Unknown Files in ZIP

- Import ignores unrecognized files (logged at debug level, no errors)
- This enables forward compatibility: newer exports with additional data types can still be partially imported by older app versions

### Partial/Corrupt Archives

- Missing files in ZIP: silently skipped, other sections still import
- Malformed JSON in one file: that section fails, others continue
- Empty/corrupt ZIP: returns 400 with descriptive error
- Missing `metadata.json`: import still proceeds (for manually-assembled ZIPs), logs a warning

### Memory

- Export is built in memory. Espresso shot records are small; even a year of daily shots (~365 records) is well within reasonable limits.

## OpenAPI Spec

Add both endpoints to `assets/api/rest_v1.yml` under a new `Data Management` tag.
