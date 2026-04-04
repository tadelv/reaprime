# PersistenceController Memory Optimization — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the in-memory shot cache in PersistenceController, replacing it with a lightweight notification stream so consumers query only what they need from the database.

**Architecture:** PersistenceController's `BehaviorSubject<List<ShotRecord>>` becomes a `PublishSubject<void>` that fires on mutations. Consumers switch from listening to the full shot list to listening for change notifications and querying the DB. Search is moved from client-side to a new `search` parameter on `getShotsPaginated`. Autocomplete uses Bean/Grinder storage services instead of scanning shot history.

**Tech Stack:** Flutter/Dart, Drift/SQLite, RxDart, shadcn_ui

**Design spec:** `doc/plans/2026-04-04-persistence-controller-memory.md`

---

## File Structure

### Modified Files

| File | Change |
|------|--------|
| `lib/src/controllers/persistence_controller.dart` | Replace in-memory cache with notification stream |
| `lib/src/services/storage/storage_service.dart` | Add `search` parameter to `getShotsPaginated` and `countShots` |
| `lib/src/services/storage/drift_storage_service.dart` | Pass `search` through to DAO |
| `lib/src/services/database/daos/shot_dao.dart` | Implement search filtering in `getShotsPaginated` and `countShots` |
| `lib/src/history_feature/history_feature.dart` | Switch from stream to query-on-notify pattern |
| `lib/src/home_feature/tiles/history_tile.dart` | Switch from stream to query-on-notify, load single shot |
| `lib/src/home_feature/home_feature.dart` | Replace StreamBuilder with simpler approach |
| `lib/src/home_feature/tiles/profile_tile.dart` | Use Bean/GrinderStorageService for autocomplete |
| `lib/src/services/webserver/shots_handler.dart` | Add `search` param, remove stream usage in legacy endpoints |
| `lib/src/services/webserver/data_export/shot_export_section.dart` | Use storageService directly for export |
| `lib/main.dart` | Remove `loadShots()` call |
| `lib/src/onboarding_feature/steps/import_step.dart` | Remove `loadShots()` calls |
| `lib/src/settings/data_management_page.dart` | Remove `loadShots()` calls |
| `lib/src/app.dart` | Thread Bean/GrinderStorageService to profile tile |
| `assets/api/rest_v1.yml` | Add `search` query parameter to GET /api/v1/shots |
| `test/helpers/mock_settings_service.dart` | Update if PersistenceController API changes affect it |
| `test/data_export/shot_export_section_test.dart` | Update for new PersistenceController API |

---

## Task 1: Add `search` to ShotDao, StorageService, DriftStorageService

The foundation — add full-text search across metadata columns.

**Files:**
- Modify: `lib/src/services/database/daos/shot_dao.dart`
- Modify: `lib/src/services/storage/storage_service.dart`
- Modify: `lib/src/services/storage/drift_storage_service.dart`

- [ ] **Step 1: Add `search` parameter to `StorageService.getShotsPaginated` and `countShots`**

In `lib/src/services/storage/storage_service.dart`, add `String? search` to both methods:

```dart
Future<List<ShotRecord>> getShotsPaginated({
  int limit = 20,
  int offset = 0,
  String? grinderId,
  String? grinderModel,
  String? beanBatchId,
  String? coffeeName,
  String? coffeeRoaster,
  String? profileTitle,
  String? search,
});

Future<int> countShots({
  String? grinderId,
  String? grinderModel,
  String? beanBatchId,
  String? coffeeName,
  String? coffeeRoaster,
  String? profileTitle,
  String? search,
});
```

- [ ] **Step 2: Add `search` to `ShotDao.getShotsPaginated` and `countShots`**

In `lib/src/services/database/daos/shot_dao.dart`, add `String? search` parameter to both methods. When non-null, add a where clause that does LIKE matching across the denormalized columns:

```dart
Future<List<ShotRecord>> getShotsPaginated({
  // ... existing params ...
  String? search,
}) {
  final query = select(shotRecords);

  // ... existing filters ...

  if (search != null && search.isNotEmpty) {
    final pattern = '%$search%';
    query.where((s) =>
        s.coffeeName.like(pattern) |
        s.coffeeRoaster.like(pattern) |
        s.profileTitle.like(pattern) |
        s.grinderModel.like(pattern) |
        s.espressoNotes.like(pattern));
  }

  query
    ..orderBy([(s) => OrderingTerm.desc(s.timestamp)])
    ..limit(limit, offset: offset);

  return query.get();
}
```

Same for `countShots` — add the same `search` where clause before the count.

- [ ] **Step 3: Pass `search` through DriftStorageService**

In `lib/src/services/storage/drift_storage_service.dart`, add `search` to both `getShotsPaginated` and `countShots` methods, passing it through to the DAO.

- [ ] **Step 4: Run `flutter analyze`**

- [ ] **Step 5: Run `flutter test`** to verify nothing broke

- [ ] **Step 6: Commit**

```bash
git commit -m "feat: add search parameter to shot queries"
```

---

## Task 2: Refactor PersistenceController

Remove the in-memory cache, replace with notification stream.

**Files:**
- Modify: `lib/src/controllers/persistence_controller.dart`

- [ ] **Step 1: Rewrite PersistenceController**

Replace the entire file content with:

```dart
import 'package:logging/logging.dart';
import 'package:reaprime/src/models/data/shot_record.dart';
import 'package:reaprime/src/models/data/workflow.dart';
import 'package:reaprime/src/services/storage/storage_service.dart';
import 'package:rxdart/rxdart.dart';

class PersistenceController {
  final StorageService storageService;
  final _log = Logger("PersistenceController");

  PersistenceController({required this.storageService});

  /// Fires whenever shots are added, updated, or deleted.
  /// Consumers should re-query what they need from [storageService].
  final _shotsChangedSubject = PublishSubject<void>();
  Stream<void> get shotsChanged => _shotsChangedSubject.stream;

  Future<void> persistShot(ShotRecord record) async {
    _log.info("Storing shot");
    try {
      await storageService.storeShot(record);
      _shotsChangedSubject.add(null);
    } catch (e, st) {
      _log.severe("Error saving shot:", e, st);
    }
  }

  Future<void> updateShot(ShotRecord record) async {
    _log.info("Updating shot: ${record.id}");
    try {
      await storageService.updateShot(record);
      _shotsChangedSubject.add(null);
    } catch (e, st) {
      _log.severe("Error updating shot:", e, st);
      rethrow;
    }
  }

  Future<void> deleteShot(String id) async {
    _log.info("Deleting shot: $id");
    try {
      await storageService.deleteShot(id);
      _shotsChangedSubject.add(null);
    } catch (e, st) {
      _log.severe("Error deleting shot:", e, st);
      rethrow;
    }
  }

  Future<void> saveWorkflow(Workflow workflow) async {
    await storageService.storeCurrentWorkflow(workflow);
  }

  Future<Workflow?> loadWorkflow() async {
    return storageService.loadCurrentWorkflow();
  }

  void dispose() {
    _shotsChangedSubject.close();
  }
}
```

Removed: `_shots` list, `_shotsController` BehaviorSubject, `shots` stream, `loadShots()`, `grinderOptions()`, `coffeeOptions()`.

- [ ] **Step 2: Run `flutter analyze`** — expect errors from consumers still referencing removed API. That's fine, we'll fix them in subsequent tasks.

- [ ] **Step 3: Commit**

```bash
git commit -m "refactor: replace in-memory shot cache with notification stream"
```

---

## Task 3: Update main.dart and import flows (remove `loadShots` calls)

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/src/onboarding_feature/steps/import_step.dart`
- Modify: `lib/src/settings/data_management_page.dart`

- [ ] **Step 1: Remove `loadShots()` from main.dart**

In `lib/main.dart`, find and remove line `persistenceController.loadShots();` (around line 236).

- [ ] **Step 2: Remove `loadShots()` from import_step.dart**

Find the two `await widget.persistenceController.loadShots();` calls (lines 146 and 228) and remove them. The `persistShot()` calls in the importer already fire `shotsChanged`.

For the ZIP import path, the REST endpoint internally stores shots which bypasses PersistenceController — so we need to fire the notification manually. After the ZIP import response is received (around line 146), add:

```dart
// Notify listeners that shots may have changed from ZIP import
widget.persistenceController.notifyShotsChanged();
```

Add a `notifyShotsChanged()` method to PersistenceController:

```dart
/// Manually fire a shots-changed notification.
/// Used after external mutations (e.g., ZIP import via REST endpoint).
void notifyShotsChanged() {
  _shotsChangedSubject.add(null);
}
```

- [ ] **Step 3: Remove `loadShots()` from data_management_page.dart**

Find and remove all `persistenceController.loadShots()` / `widget.persistenceController.loadShots()` calls (lines 480, 533, 688). Replace with `widget.persistenceController.notifyShotsChanged()` where the mutation was done via REST API (the full backup import at line 480 and de1app import at line 688). The legacy shot import at line 533 uses `persistenceController.persistShot()` which auto-notifies.

- [ ] **Step 4: Run `flutter analyze`**

- [ ] **Step 5: Commit**

```bash
git commit -m "refactor: remove loadShots calls, use notification stream"
```

---

## Task 4: Update ShotExportSection

**Files:**
- Modify: `lib/src/services/webserver/data_export/shot_export_section.dart`
- Modify: `test/data_export/shot_export_section_test.dart`

- [ ] **Step 1: Change export to use storageService directly**

In `shot_export_section.dart`, change the `export()` method:

```dart
@override
Future<dynamic> export() async {
  final shots = await _controller.storageService.getAllShots();
  return shots.map((s) => s.toJson()).toList();
}
```

The import methods (`persistShot`, `updateShot`) stay on `_controller` since they need to fire notifications.

- [ ] **Step 2: Update tests if needed**

Read `test/data_export/shot_export_section_test.dart`. If the test creates a mock PersistenceController that stubs the `shots` stream, update it to stub `storageService.getAllShots()` instead.

- [ ] **Step 3: Run `flutter test test/data_export/shot_export_section_test.dart`**

- [ ] **Step 4: Commit**

```bash
git commit -m "refactor: shot export uses storageService directly"
```

---

## Task 5: Update ShotsHandler (REST API)

**Files:**
- Modify: `lib/src/services/webserver/shots_handler.dart`
- Modify: `assets/api/rest_v1.yml`

- [ ] **Step 1: Add `search` query param and remove legacy stream usage**

In `shots_handler.dart`:

1. Add `search` to the paginated path (around line 40):
```dart
final search = params['search'];
```

2. Pass `search` to both `getShotsPaginated` and `countShots` calls.

3. Replace the legacy `?ids=` path (lines 52-66) that uses `_controller.shots.first` with direct DB lookups:
```dart
if (ids != null && ids.isNotEmpty && !hasFilters) {
  final shots = <ShotRecord>[];
  for (final id in ids) {
    final shot = await _controller.storageService.getShot(id);
    if (shot != null) shots.add(shot);
  }
  // ... sort and return as before ...
}
```

4. Replace `_getIds` method (lines 105-124) that uses `_controller.shots.first` with a direct DB call:
```dart
Future<Response> _getIds(Request req) async {
  final ids = await _controller.storageService.getShotIds();
  // ... sort logic stays the same ...
  return jsonOk(ids);
}
```

Note: `getShotIds()` returns `List<String>` (IDs only). The current implementation sorts by timestamp, but IDs alone don't carry timestamps. Either add a `getShotIdsSorted()` method to the DAO, or use `getShotsPaginated(limit: very_large)` and extract IDs. The simplest fix: use `getShotsPaginated` with a large limit and map to IDs. Or accept that the `/ids` endpoint returns unsorted IDs (check if any consumer depends on the order).

- [ ] **Step 2: Update OpenAPI spec**

In `assets/api/rest_v1.yml`, find the `GET /api/v1/shots` parameters section and add:

```yaml
        - in: query
          name: search
          description: |
            Free-text search across shot metadata. Matches against coffee name,
            coffee roaster, profile title, grinder model, and espresso notes.
            Case-insensitive substring match.
          required: false
          schema:
            type: string
```

- [ ] **Step 3: Run `flutter analyze`**

- [ ] **Step 4: Commit**

```bash
git commit -m "feat: add search param to shots REST endpoint, remove stream usage"
```

---

## Task 6: Update HistoryFeature

Switch from stream-of-all-shots to query-on-notify with server-side search.

**Files:**
- Modify: `lib/src/history_feature/history_feature.dart`

- [ ] **Step 1: Rewrite state management**

Replace the stream subscription with a `shotsChanged` listener and DB queries:

```dart
class _HistoryFeatureState extends State<HistoryFeature> {
  final Logger _log = Logger("HistoryFeature");
  final TextEditingController _searchController = TextEditingController();

  List<ShotRecord> _shots = [];
  late StreamSubscription<void> _shotsSubscription;

  ShotRecord? _selectedShot;

  @override
  void initState() {
    super.initState();
    _shotsSubscription = widget.persistenceController.shotsChanged.listen((_) {
      _loadShots();
    });
    _searchController.addListener(_onSearchChanged);
    _loadShots();
    // Handle selectedShot from navigation arguments
    if (widget.selectedShot != null) {
      setSelectedShot("");
    }
  }

  Future<void> _loadShots() async {
    final search = _searchController.text.isEmpty ? null : _searchController.text;
    final shots = await widget.persistenceController.storageService.getShotsPaginated(
      limit: 200,
      search: search,
    );
    if (mounted) {
      setState(() {
        _shots = shots;
      });
    }
  }

  void _onSearchChanged() {
    _loadShots();
  }

  @override
  void dispose() {
    _shotsSubscription.cancel();
    _searchController.removeListener(_onSearchChanged);
    super.dispose();
  }
```

Remove the old `searchTextUpdate()` method and `_filteredShots` — the DB does the filtering now.

Replace all references to `_filteredShots` with `_shots` in the build method.

Remove the `_searchInMetadata` helper method (the DB search replaces it).

Note: The list view currently accesses `record.measurements.isNotEmpty` and `record.measurements.last.machine.timestamp` to compute shot duration. Since `getShotsPaginated` returns shots without measurements, this needs to change. Options:
- Compute duration from the denormalized timestamp column (already on the table) — but we don't currently store shot end time. 
- Keep showing just the shot timestamp without duration in the list.
- Add a `duration` denormalized column (future improvement).

For now, guard the duration computation: if `measurements.isEmpty`, show duration as `Duration.zero` (which the existing code already handles as a fallback).

- [ ] **Step 2: Load full shot on selection**

When a shot is selected for detail view, load it with measurements:

```dart
Future<void> setSelectedShot(String shotId) async {
  if (shotId.isEmpty) {
    // Handle navigation argument
    // ... existing logic for widget.selectedShot ...
    return;
  }
  final fullShot = await widget.persistenceController.storageService.getShot(shotId);
  if (mounted && fullShot != null) {
    setState(() {
      _selectedShot = fullShot;
    });
  }
}
```

- [ ] **Step 3: Run `flutter analyze`**

- [ ] **Step 4: Commit**

```bash
git commit -m "refactor: history feature uses paginated DB queries with search"
```

---

## Task 7: Update HistoryTile

Switch from holding all shots to loading single shots on demand.

**Files:**
- Modify: `lib/src/home_feature/tiles/history_tile.dart`
- Modify: `lib/src/home_feature/home_feature.dart`

- [ ] **Step 1: Rewrite HistoryTile state management**

The tile shows one shot at a time with prev/next navigation. New approach:
- Listen to `shotsChanged`
- Load shot count and current shot from DB
- Navigate by offset

```dart
class _HistoryTileState extends State<HistoryTile> {
  late StreamSubscription<void> _subscription;

  ShotRecord? _currentShot;
  int _totalShots = 0;
  int _currentIndex = 0; // 0 = most recent

  @override
  void initState() {
    super.initState();
    _subscription = widget.persistenceController.shotsChanged.listen((_) {
      _loadCurrentShot();
    });
    _loadCurrentShot();
  }

  Future<void> _loadCurrentShot() async {
    final storage = widget.persistenceController.storageService;
    final total = await storage.countShots();
    if (total == 0) {
      if (mounted) setState(() { _totalShots = 0; _currentShot = null; });
      return;
    }
    // Offset from newest: index 0 = newest shot
    final shots = await storage.getShotsPaginated(limit: 1, offset: _currentIndex);
    final fullShot = shots.isNotEmpty
        ? await storage.getShot(shots.first.id)
        : null;
    if (mounted) {
      setState(() {
        _totalShots = total;
        _currentShot = fullShot;
      });
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
```

Update navigation buttons:
```dart
var canGoBack = _currentIndex < _totalShots - 1; // older
var canGoForward = _currentIndex > 0; // newer

// Back button (older):
onPressed: () {
  _currentIndex++;
  _loadCurrentShot();
}

// Forward button (newer):
onPressed: () {
  _currentIndex--;
  _loadCurrentShot();
}
```

Update the build method to use `_currentShot` instead of `_shotHistory[_selectedShotIndex]`. Show "No shots yet." when `_currentShot == null`.

- [ ] **Step 2: Update home_feature.dart**

Replace the `StreamBuilder` that wraps HistoryTile (around line 232-244):

```dart
// Before: StreamBuilder on persistenceController.shots
// After: Just render the tile directly — it manages its own state
HistoryTile(
  persistenceController: widget.persistenceController,
  workflowController: widget.workflowController,
),
```

The StreamBuilder was only there to show a loading indicator while shots loaded. Since the tile now loads its own data, it can show its own loading state internally.

- [ ] **Step 3: Run `flutter analyze`**

- [ ] **Step 4: Commit**

```bash
git commit -m "refactor: history tile loads single shot on demand"
```

---

## Task 8: Update ProfileTile autocomplete

Switch from `persistenceController.grinderOptions()/coffeeOptions()` to entity storage services.

**Files:**
- Modify: `lib/src/home_feature/tiles/profile_tile.dart`
- Modify: `lib/src/app.dart` (thread services to profile tile)
- Modify: `lib/src/home_feature/home_feature.dart` (pass services through)

- [ ] **Step 1: Add storage services to ProfileTile**

The profile tile currently receives `PersistenceController` and calls `grinderOptions()`/`coffeeOptions()`. It needs `BeanStorageService` and `GrinderStorageService` instead.

Add parameters to ProfileTile:
```dart
final BeanStorageService? beanStorageService;
final GrinderStorageService? grinderStorageService;
```

- [ ] **Step 2: Replace grinderOptions() calls**

Replace the 4 autocomplete builders (lines 620-638, 660-680, 840-860, 885-900) that call `persistenceController.grinderOptions()` and `coffeeOptions()`.

For grinder setting autocomplete (line 620):
```dart
optionsBuilder: (TextEditingValue val) async {
  if (val.text.isEmpty || widget.grinderStorageService == null) return const [];
  final grinders = await widget.grinderStorageService!.getAllGrinders();
  // Grinder settings are per-shot, not on the entity.
  // For now, return empty — user types their setting.
  // The grinder model autocomplete is more useful.
  return <String>[];
},
```

Actually, grinder setting is a freeform field (the user's dial position). It's not stored on the Grinder entity. The old `grinderOptions()` scanned all shots for unique settings. We can either:
- Drop setting autocomplete (users type it)
- Keep it from WorkflowContext (the current workflow has the last setting)

The simplest: just show the current workflow's grinder setting as a suggestion if it matches. But for a clean break, just return `[]` — the user already knows their grinder setting.

For grinder model autocomplete (line 660):
```dart
optionsBuilder: (TextEditingValue val) async {
  if (val.text.isEmpty || widget.grinderStorageService == null) return const [];
  final grinders = await widget.grinderStorageService!.getAllGrinders();
  return grinders
      .where((g) => g.model.toLowerCase().contains(val.text.toLowerCase()))
      .map((g) => g.model)
      .toSet()
      .toList();
},
```

For coffee name autocomplete (line 840):
```dart
optionsBuilder: (TextEditingValue val) async {
  if (val.text.isEmpty || widget.beanStorageService == null) return const [];
  final beans = await widget.beanStorageService!.getAllBeans();
  return beans
      .where((b) => b.name.toLowerCase().contains(val.text.toLowerCase()))
      .map((b) => b.name)
      .toSet()
      .toList();
},
```

For coffee roaster autocomplete (line 885):
```dart
optionsBuilder: (TextEditingValue val) async {
  if (val.text.isEmpty || widget.beanStorageService == null) return const [];
  final beans = await widget.beanStorageService!.getAllBeans();
  return beans
      .where((b) => b.roaster.toLowerCase().contains(val.text.toLowerCase()))
      .map((b) => b.roaster)
      .toSet()
      .toList();
},
```

Note: `Autocomplete.optionsBuilder` expects a `FutureOr<Iterable<String>>`. Making it `async` returns a `Future<List<String>>` which satisfies `FutureOr`.

- [ ] **Step 3: Thread services from app.dart → home_feature → profile_tile**

In `home_feature.dart`, add `BeanStorageService?` and `GrinderStorageService?` as params and pass to ProfileTile.

In `app.dart`, pass `widget.beanStorage` and `widget.grinderStorage` to HomeScreen/HomeFeature (find where HomeFeature is constructed and add the params).

- [ ] **Step 4: Run `flutter analyze`**

- [ ] **Step 5: Commit**

```bash
git commit -m "refactor: profile tile uses entity storage for autocomplete"
```

---

## Task 9: Final cleanup and verification

- [ ] **Step 1: Run `flutter analyze`** — fix any remaining issues

- [ ] **Step 2: Run `flutter test`** — all tests must pass

- [ ] **Step 3: Search for any remaining references to removed API**

```bash
grep -r "\.shots\b" lib/ --include="*.dart" | grep -v "shotsChanged"
grep -r "loadShots" lib/ --include="*.dart"
grep -r "grinderOptions\|coffeeOptions" lib/ --include="*.dart"
```

Fix any remaining references.

- [ ] **Step 4: Commit any fixes**

- [ ] **Step 5: Commit**

```bash
git commit -m "chore: clean up remaining references to removed PersistenceController API"
```
