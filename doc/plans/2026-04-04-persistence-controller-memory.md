# PersistenceController Memory Optimization — Design Spec

## Problem

`PersistenceController` loads ALL shots (with full measurement arrays) into an in-memory `List<ShotRecord>`. Each shot contains hundreds of `ShotSnapshot` measurement points. At 10k shots this creates millions of objects in RAM. The in-memory cache exists to serve a reactive `BehaviorSubject<List<ShotRecord>>` stream, plus `grinderOptions()` and `coffeeOptions()` helper methods that scan the full list.

## Solution

Replace the in-memory shot cache with a lightweight notification stream. Consumers query exactly what they need from the database. No shots are held in memory beyond what's actively displayed.

## New PersistenceController

The controller becomes a thin write coordinator:

```
PersistenceController
  storageService: StorageService (injected)
  
  shotsChanged: Stream<void>     ← PublishSubject<void>, fires on any mutation
  
  persistShot(ShotRecord)        → store in DB → fire shotsChanged
  updateShot(ShotRecord)         → update in DB → fire shotsChanged
  deleteShot(String id)          → delete in DB → fire shotsChanged
  
  saveWorkflow(Workflow)         → unchanged
  loadWorkflow(): Workflow?      → unchanged
```

**Removed:**
- `_shots` in-memory list
- `_shotsController` BehaviorSubject
- `shots` stream (replaced by `shotsChanged`)
- `loadShots()`
- `grinderOptions()` → consumers use GrinderStorageService directly
- `coffeeOptions()` → consumers use BeanStorageService directly

## New DB Queries

### StorageService interface additions

```dart
/// Search shots by text across metadata fields.
/// Returns shots WITHOUT measurement data.
Future<List<ShotRecord>> getShotsPaginated({
  int limit = 20,
  int offset = 0,
  String? profileTitle,
  String? coffeeRoaster,
  String? search,  // NEW: filters across coffee_name, coffee_roaster,
                   //       profile_title, grinder_model, espresso_notes
});
```

`getShotsPaginated` already exists with `profileTitle` and `coffeeRoaster` filters. Add a `search` parameter that does a LIKE match across multiple columns (matching the current client-side search in history_feature.dart).

### ShotDao additions

```sql
-- Search query (conceptual)
SELECT * FROM shot_records 
WHERE coffee_name LIKE '%search%' 
   OR coffee_roaster LIKE '%search%'
   OR profile_title LIKE '%search%'
   OR grinder_model LIKE '%search%'
   OR espresso_notes LIKE '%search%'
ORDER BY timestamp DESC
LIMIT ? OFFSET ?
```

No new tables or columns needed — the denormalized columns already exist in `shot_records`.

## Consumer Changes

### History Feature (list view)
- **Before:** Listens to `shots` stream, holds all shots in `_shots`, filters client-side
- **After:** Listens to `shotsChanged`. On change (or on search text change), calls `storageService.getShotsPaginated(search: text)`. Implements pagination or infinite scroll. Shots returned without measurements.

### History Feature (detail view)
- **Before:** Uses shot from in-memory `_shots` list (already has measurements)
- **After:** Calls `storageService.getShot(id)` to load full shot with measurements on demand

### History Tile (home screen)
- **Before:** Listens to `shots` stream, picks one shot, renders chart
- **After:** Listens to `shotsChanged`. Loads current shot via `storageService.getShot(id)`. For prev/next navigation, uses `getShotsPaginated(limit: 1, offset: currentIndex)` or maintains a list of shot IDs.

### Profile Tile (autocomplete)
- **Before:** `persistenceController.grinderOptions()` / `.coffeeOptions()` scanning full shot list
- **After:** `grinderStorageService.getAllGrinders()` / `beanStorageService.getAllBeans()` for autocomplete data. Profile tile needs these services injected (or passed from parent).

### Shot Export Section
- **Before:** `persistenceController.shots.first` to get all shots
- **After:** `storageService.getAllShots()` directly (the controller reference on ShotExportSection is already `PersistenceController`, which exposes `storageService`)

### Shot Import (export section + de1app importer)
- **Before:** `persistenceController.persistShot()` + `loadShots()` after import
- **After:** `persistenceController.persistShot()` (still fires `shotsChanged`). Remove all `loadShots()` calls.

### Shots Handler (REST API)
- **Before:** Legacy `?ids=` endpoint uses `persistenceController.shots.first` to get all shots and filter by ID
- **After:** Use `storageService.getShot(id)` per ID, or add a batch query. Update/delete already go through PersistenceController (unchanged).

### main.dart
- **Before:** `persistenceController.loadShots()` at startup
- **After:** Remove (no cache to populate)

### Import Step + Data Management
- **Before:** Call `persistenceController.loadShots()` after import
- **After:** Remove these calls. Writes already fire `shotsChanged`.

## What Stays the Same

- `persistShot()`, `updateShot()`, `deleteShot()` API (just the internal implementation changes)
- `saveWorkflow()`, `loadWorkflow()`
- StorageService interface (additive change only — new `search` param)
- All existing paginated/filtered REST endpoints
- Shot data model (ShotRecord, ShotSnapshot, etc.)
