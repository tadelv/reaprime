# Implementation Plan: Simplified Schema Proposal

## Context

The app currently stores shots as individual JSON files and profiles in Hive. The data model uses `DoseData`, `GrinderData`, and `CoffeeData` as simple embedded objects on `Workflow`, with no entity management, no relational queries, and no post-shot annotation support. This plan implements the simplified schema proposal (`doc/plans/simplified-schema-proposal.md`), which:

- Adds Bean, BeanBatch, Grinder as first-class entities with Drift tables and REST API
- Replaces `DoseData`/`GrinderData`/`CoffeeData` with `WorkflowContext`
- Replaces `ShotRecord.metadata`/`shotNotes` with typed `ShotAnnotations`
- Migrates all persistence to Drift (SQLite)
- Adds shot pagination and filtering

---

## Phase 0: New Domain Models (Additive — Zero Risk)

Create new pure Dart domain models. No existing code changes.

### Files to Create

| File | Contents |
|------|----------|
| `lib/src/models/data/workflow_context.dart` | `WorkflowContext` — 12 fields, `toJson()`/`fromJson()`/`copyWith()`. **Critical:** `fromJson()` handles both new format (`context` key) and legacy format (maps `doseData.doseIn`→`targetDoseWeight`, `doseData.doseOut`→`targetYield`, `grinderData.setting`→`grinderSetting`, `grinderData.model`→`grinderModel`, `coffeeData.name`→`coffeeName`, `coffeeData.roaster`→`coffeeRoaster`) |
| `lib/src/models/data/shot_annotations.dart` | `ShotAnnotations` — 7 fields. `fromJson()` handles legacy format (`shotNotes`→`espressoNotes`, `metadata`→`extras`) |
| `lib/src/models/data/bean.dart` | `Bean` + `BeanBatch` — full field sets from proposal. `toJson()`/`fromJson()`/`copyWith()` |
| `lib/src/models/data/grinder.dart` | `Grinder` + `GrinderSettingType` enum. `toJson()`/`fromJson()`/`copyWith()` |

### Tests to Create

| File | Covers |
|------|--------|
| `test/models/workflow_context_test.dart` | Round-trip serialization, backward-compat from old JSON format |
| `test/models/shot_annotations_test.dart` | Round-trip serialization, backward-compat from shotNotes/metadata |
| `test/models/bean_test.dart` | Serialization, nullable fields, extras |
| `test/models/grinder_test.dart` | Serialization, settingType enum, DYE2 config fields |

### Verify

```bash
flutter test test/models/ && flutter analyze
```

---

## Phase 1: Model Migration — Workflow + ShotRecord (HIGH RISK)

Replace old model fields with new ones across the entire codebase. This is the most disruptive phase.

### Strategy: Deprecated Bridge

1. Add `context: WorkflowContext?` to `Workflow`, keep old fields as `@Deprecated` getters that synthesize from `context`
2. `toJson()` writes **only** new format. `fromJson()` reads **both** formats.
3. Update all consumers to use new fields
4. Remove deprecated fields once all consumers migrated

### Files to Modify

**Core models:**

| File | Change |
|------|--------|
| `lib/src/models/data/workflow.dart` | Add `context: WorkflowContext?` field. Deprecated getters: `doseData` synthesizes `DoseData(doseIn: context?.targetDoseWeight ?? 16, doseOut: context?.targetYield ?? 36)`. `fromJson()` reads both formats. `toJson()` writes `context`. `copyWith()` gains `context` param. `updateWorkflow()` signature changes. Keep `DoseData`/`GrinderData`/`CoffeeData` class definitions until all consumers migrated. |
| `lib/src/models/data/shot_record.dart` | Add `annotations: ShotAnnotations?`. Make `measurements: List<ShotSnapshot>?` nullable. `fromJson()` reads both formats. `toJson()` writes `annotations`. Deprecated getters for `shotNotes` and `metadata`. |

**Controllers:**

| File | Change |
|------|--------|
| `lib/src/controllers/shot_controller.dart` | Replace `final DoseData doseData` constructor param → `final double targetYield`. Line 248: `doseData.doseOut` → `targetYield`. Line 250: same. |
| `lib/src/controllers/de1_state_manager.dart` | Line 535: `doseData: _workflowController.currentWorkflow.doseData` → `targetYield: _workflowController.currentWorkflow.context?.targetYield ?? 0` |
| `lib/src/controllers/workflow_controller.dart` | Default workflow uses `context: WorkflowContext(targetDoseWeight: 18.0, targetYield: 36.0)`. `updateWorkflow()` replaces `doseData`/`grinderData`/`coffeeData` params with `context`. |
| `lib/src/controllers/persistence_controller.dart` | `grinderOptions()` → extract `context?.grinderModel` strings. `coffeeOptions()` → extract `context?.coffeeName`/`coffeeRoaster` strings. Return types change to simple string records. |

**UI:**

| File | Change |
|------|--------|
| `lib/src/home_feature/tiles/profile_tile.dart` | **Largest refactor.** Replace all `.doseData.doseIn`/`.doseOut`/`.ratio` with `context?.targetDoseWeight`/`targetYield`/derived ratio. Replace mutation pattern (`doseData.doseIn = x`) with immutable `copyWith()` calls. Replace `.grinderData?.setting`/`.model`/`.manufacturer` with `context?.grinderSetting`/`grinderModel`. Replace `.coffeeData?.name`/`.roaster` with `context?.coffeeName`/`coffeeRoaster`. |
| `lib/src/realtime_shot_feature/realtime_shot_feature.dart` | Line ~209: `_shotController.doseData.doseOut` → `_shotController.targetYield` |
| `lib/src/history_feature/history_feature.dart` | Replace all old field reads with context/annotations equivalents |

**Plugin:**

| File | Change |
|------|--------|
| `assets/plugins/visualizer.reaplugin/plugin.js` | `doseData.doseIn` → `context?.targetDoseWeight`, `grinderData?.model` → `context?.grinderModel`, etc. |

**API & export handlers:** No structural changes needed — `toJson()`/`fromJson()` handle the format change transparently via deep merge.

**Tests:** Update all test helpers constructing `Workflow` or `ShotRecord` to use new fields.

### Risk: DoseData Mutation Pattern

`profile_tile.dart` directly mutates `DoseData` fields:
```dart
widget.workflowController.currentWorkflow.doseData.doseIn = double.parse(val);
```
Must become:
```dart
final ctx = widget.workflowController.currentWorkflow.context;
widget.workflowController.updateWorkflow(
  context: ctx?.copyWith(targetDoseWeight: double.parse(val)) ??
    WorkflowContext(targetDoseWeight: double.parse(val)),
);
```

### Risk: ShotController Target Weight

`shot_controller.dart` line 248 is **safety-critical** — controls when the machine stops pouring. The change from `doseData.doseOut` to `targetYield` must be exact.

### Cleanup (end of phase)

Remove `@Deprecated` getters. Remove `DoseData`, `GrinderData`, `CoffeeData` class definitions from `workflow.dart`.

### Verify

```bash
flutter test && flutter analyze
# Then run app with simulate=1, verify:
# - Default workflow loads
# - Dose/grinder/coffee display correctly in profile tile
# - History shows old shots with new model (backward-compat fromJson)
# - Workflow API returns new format
```

---

## Phase 2: Drift Foundation (MEDIUM RISK — Build System Change)

Add Drift to the project, define all 6 tables, create AppDatabase, DAOs, mappers.

### Dependencies to Add (`pubspec.yaml`)

```yaml
dependencies:
  drift: ^2.24.0
  drift_flutter: ^0.2.4
  sqlite3_flutter_libs: ^0.5.0

dev_dependencies:
  drift_dev: ^2.24.0
  build_runner: ^2.4.0
```

### Files to Create

**Database core:**

| File | Contents |
|------|----------|
| `lib/src/services/database/database.dart` | `AppDatabase` — registers all tables, schema version 1, `PRAGMA foreign_keys = ON` |
| `build.yaml` | Drift builder options: `store_date_time_values_as_text: true` |

**Tables:**

| File | Tables |
|------|--------|
| `lib/src/services/database/tables/bean_tables.dart` | `Beans`, `BeanBatches` (FK → Beans) |
| `lib/src/services/database/tables/grinder_tables.dart` | `Grinders` |
| `lib/src/services/database/tables/shot_tables.dart` | `ShotRecords` (denormalized columns + JSON columns) |
| `lib/src/services/database/tables/workflow_tables.dart` | `Workflows` |
| `lib/src/services/database/tables/profile_tables.dart` | `ProfileRecords` |

**Type converters:**

| File | Converters |
|------|------------|
| `lib/src/services/database/converters/json_converters.dart` | `JsonMapConverter`, `StringListConverter`, `IntListConverter`, `WorkflowConverter`, `MeasurementsConverter`, `ShotAnnotationsConverter`, `ProfileConverter`, `WorkflowContextConverter`, `SteamSettingsConverter`, `HotWaterDataConverter`, `RinseDataConverter` |

**DAOs:**

| File | DAO |
|------|-----|
| `lib/src/services/database/daos/bean_dao.dart` | `BeanDao` — CRUD, watch, batch weight decrement |
| `lib/src/services/database/daos/grinder_dao.dart` | `GrinderDao` — CRUD, watch |
| `lib/src/services/database/daos/shot_dao.dart` | `ShotDao` — CRUD, paginated + filtered queries, lazy measurement loading |
| `lib/src/services/database/daos/workflow_dao.dart` | `WorkflowDao` — load/save current workflow |
| `lib/src/services/database/daos/profile_dao.dart` | `ProfileDao` — full CRUD, visibility filtering, parent chain |

**Mappers:**

| File | Maps |
|------|------|
| `lib/src/services/database/mappers/bean_mapper.dart` | `Bean`/`BeanBatch` ↔ Drift rows |
| `lib/src/services/database/mappers/grinder_mapper.dart` | `Grinder` ↔ Drift rows |
| `lib/src/services/database/mappers/shot_mapper.dart` | `ShotRecord` ↔ Drift rows (handles denormalized columns) |
| `lib/src/services/database/mappers/workflow_mapper.dart` | `Workflow` ↔ Drift rows |
| `lib/src/services/database/mappers/profile_mapper.dart` | `ProfileRecord` ↔ Drift rows |

### Tests

| File | Tests |
|------|-------|
| `test/database/bean_dao_test.dart` | CRUD, watch, archived filtering, batch FK, weight decrement |
| `test/database/grinder_dao_test.dart` | CRUD, watch, archived filtering |
| `test/database/shot_dao_test.dart` | CRUD, pagination, filtering, lazy measurement loading |
| `test/database/workflow_dao_test.dart` | Load/save |
| `test/database/profile_dao_test.dart` | CRUD, visibility, parent chain |

All tests use `NativeDatabase.memory()`.

### Verify

```bash
dart run build_runner build --delete-conflicting-outputs
flutter test && flutter analyze
```

### Risk

- `build_runner` is new to this project — document the workflow
- Platform-specific SQLite build issues possible (test on Android first)

---

## Phase 3: Storage Service Interfaces + Entity API (LOW RISK)

### Storage Interfaces to Create

| File | Interface |
|------|-----------|
| `lib/src/services/storage/bean_storage_service.dart` | `BeanStorageService` — Bean + BeanBatch CRUD, watch, batch weight tracking |
| `lib/src/services/storage/grinder_storage_service.dart` | `GrinderStorageService` — Grinder CRUD, watch |

### API Handlers to Create

| File | Handler |
|------|---------|
| `lib/src/services/webserver/beans_handler.dart` | `BeansHandler(BeanStorageService)` — CRUD for `/api/v1/beans`, `/api/v1/beans/<id>/batches`, `/api/v1/bean-batches/<id>` |
| `lib/src/services/webserver/grinders_handler.dart` | `GrindersHandler(GrinderStorageService)` — CRUD for `/api/v1/grinders` |

### Files to Modify

| File | Change |
|------|--------|
| `lib/src/services/webserver/webserver_service.dart` | Register new handlers in `startWebServer()` and `_init()` |

### Tests

| File | Tests |
|------|-------|
| `test/webserver/beans_handler_test.dart` | CRUD operations with mock storage |
| `test/webserver/grinders_handler_test.dart` | CRUD operations with mock storage |

### Verify

```bash
flutter test && flutter analyze
```

---

## Phase 4: Drift Storage Implementations + Migration (MEDIUM RISK)

Wire Drift behind the existing abstract interfaces. Build one-time migration.

### Files to Create

| File | Contents |
|------|----------|
| `lib/src/services/storage/drift_bean_storage.dart` | `DriftBeanStorageService implements BeanStorageService` → delegates to `BeanDao` |
| `lib/src/services/storage/drift_grinder_storage.dart` | `DriftGrinderStorageService implements GrinderStorageService` → delegates to `GrinderDao` |
| `lib/src/services/storage/drift_storage_service.dart` | `DriftStorageService implements StorageService` → delegates to `ShotDao` + `WorkflowDao` |
| `lib/src/services/storage/drift_profile_storage.dart` | `DriftProfileStorageService implements ProfileStorageService` → delegates to `ProfileDao` |
| `lib/src/services/database/migration/legacy_import.dart` | One-time migration: read JSON shot files + Hive profiles → insert into SQLite. Idempotent (check existing IDs). Non-destructive (don't delete old files). Migration flag in SharedPreferences. |

### Files to Modify

| File | Change |
|------|--------|
| `lib/main.dart` | Create `AppDatabase` instance. Replace `FileStorageService` with `DriftStorageService`. Replace `HiveProfileStorageService` with `DriftProfileStorageService`. Wire `DriftBeanStorageService` + `DriftGrinderStorageService` to entity handlers. Run migration on first launch. |
| `lib/src/services/webserver/webserver_service.dart` | `startWebServer()` gains `BeanStorageService` and `GrinderStorageService` params |

### Tests

| File | Tests |
|------|-------|
| `test/database/legacy_import_test.dart` | Migration with sample JSON + in-memory DB |
| `test/storage/drift_storage_service_test.dart` | Interface compliance with in-memory DB |

### Verify

```bash
flutter test && flutter analyze
# Run app with simulate=1:
# - Old shots load from SQLite after migration
# - New shots persist to SQLite
# - Workflow loads/saves to SQLite
# - Profiles load from SQLite
# - Bean/Grinder CRUD via curl
```

---

## Phase 5: Shot Filtering + Cleanup (LOW RISK)

### Files to Modify

| File | Change |
|------|--------|
| `lib/src/services/webserver/shots_handler.dart` | Add query params: `limit`, `offset`, `grinderId`, `grinderModel`, `beanBatchId`, `coffeeName`, `coffeeRoaster`, `profileTitle`. Paginated response: `{items, total, limit, offset}`. List excludes measurements. |
| `lib/src/services/storage/storage_service.dart` | Add `watchShots(limit, offset)` and filtering methods if needed |
| `lib/src/controllers/persistence_controller.dart` | `grinderOptions()`/`coffeeOptions()` can be simplified or removed — entity endpoints replace them |

### Files to Remove (after migration proven stable)

- `lib/src/services/storage/file_storage_service.dart`
- Consider removing Hive profile storage (keep `HiveStoreService` for plugin KV)

### Verify

```bash
flutter test && flutter analyze
# API smoke test:
curl localhost:8080/api/v1/shots?limit=10&coffeeRoaster=Sey
curl localhost:8080/api/v1/shots/<id>  # includes measurements
curl localhost:8080/api/v1/beans
curl localhost:8080/api/v1/grinders
```

---

## Phase Dependencies

```
Phase 0 (models) → Phase 1 (migration) → Phase 2 (Drift) → Phase 3 (entity API)
                                                    ↓
                                              Phase 4 (Drift storage) → Phase 5 (cleanup)
```

Each phase leaves the app in a working state. Phase 1 is the only phase that touches existing behavior.

## Summary

| Phase | Risk | New Files | Modified Files |
|-------|------|-----------|----------------|
| 0: Domain models | None | 4 models + 4 tests | 0 |
| 1: Model migration | **HIGH** | 0 | ~12-15 source + tests |
| 2: Drift foundation | Medium | ~17 + generated | 2 (pubspec, build.yaml) |
| 3: Entity API | Low | 4 + 2 tests | 1 (webserver_service) |
| 4: Drift storage + migration | Medium | 5 + 2 tests | 2 (main.dart, webserver_service) |
| 5: Shot filtering + cleanup | Low | 0 | 3 + delete legacy |
