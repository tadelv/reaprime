# Persistence Layer Proposal: Drift Migration

**Version:** Draft 1.0
**Date:** 2026-03-02
**Companion to:** `beans-equipment-shot-data-schema-proposal.md`
**Context:** Migrating from file-based + Hive storage to Drift (SQLite) for relational entity management

---

## Executive Summary

This proposal introduces [Drift](https://drift.simonbinder.eu/) as the persistence layer for the new coffee equipment and metadata entities (Bean, BeanBatch, Grinder, Equipment, Water) and the modified Workflow/ShotRecord structures. Drift provides type-safe SQLite with reactive queries, relational integrity, and proper migration support — things the current file-based + Hive approach can't deliver as the data model grows relational.

**Scope:**
- New entity tables (Bean, BeanBatch, Grinder, Equipment, Water)
- Modified ShotRecord storage (with ShotAnnotations and WorkflowContext)
- Migration of existing shots from JSON files to Drift
- Migration of existing profiles from Hive to Drift
- Workflow persistence in Drift
- Plugin KV store and SharedPreferences settings remain unchanged (no benefit from moving)

**What stays as-is:**
- `SharedPreferencesSettingsService` — flat key-value, no relational needs
- `HiveStoreService` for plugin KV — plugins own their namespace, schema-free by design

---

## 1. Why Drift

### Current Storage Problems

| Problem | Current Impact |
|---------|---------------|
| No relational queries | Can't efficiently query "all shots with this grinder" or "all batches of this bean" — would require loading all shots into memory and filtering |
| No referential integrity | Entity references (grinderId, beanBatchId) are just strings with no validation |
| No reactive queries | Controllers manually maintain in-memory caches + BehaviorSubjects; no way to watch a query result |
| No schema migrations | Adding fields requires defensive `fromJson()` with null fallbacks; no versioned migration path |
| Scattered storage engines | Profiles in Hive, shots as JSON files, settings in SharedPreferences — three different systems with different patterns |
| Full-collection loading | `getAllShots()` loads every shot JSON file into memory on startup; doesn't scale |

### What Drift Solves

| Capability | Benefit |
|-----------|---------|
| Relational queries with JOINs | "All shots using Bean X" is a simple JOIN, not a full scan |
| Foreign key constraints | Invalid entity references caught at insert time (with `PRAGMA foreign_keys = ON`) |
| `.watch()` reactive streams | Replace manual BehaviorSubject caching — UI rebuilds when underlying data changes |
| `stepByStep` migrations | Schema changes are versioned and testable; no fragile `fromJson()` fallbacks |
| Type converters | Complex objects (snapshots, extras Map, tasting attributes) stored as JSON columns |
| Single database file | One `.sqlite` file replaces hundreds of shot JSON files + Hive boxes |
| Indexed queries | Timestamp ranges, text search on bean names, etc. without loading everything |

---

## 2. Database Architecture

### 2.1 Two-Layer Model Architecture

**Hard rule: domain models are pure Dart with zero framework annotations.** Controllers, UI, API handlers, and plugins only ever see domain model objects. Drift table definitions, generated row classes, and TypeConverters are internal to the persistence service — invisible to the rest of the app.

This means there are two parallel representations of each entity:

| Layer | Location | Purpose | Dependencies |
|-------|----------|---------|-------------|
| **Domain models** | `lib/src/models/data/` | App-wide data objects | Pure Dart only (+ Equatable, UUID) |
| **Drift tables** | `lib/src/services/database/tables/` | SQLite schema definition | Drift framework |

The DAO layer is the **translation boundary** — it accepts and returns domain model objects, and internally maps to/from Drift row classes. No Drift types leak beyond the `services/database/` directory.

```
┌─────────────────────────────────────────────────┐
│  App Layer (controllers, UI, API, plugins)       │
│  Uses: Bean, BeanBatch, Grinder, ShotRecord...   │
│  Location: lib/src/models/data/                  │
│  Dependencies: pure Dart                         │
└──────────────────┬──────────────────────────────┘
                   │ domain objects only
                   ▼
┌─────────────────────────────────────────────────┐
│  Persistence Service Interface                   │
│  (abstract classes in lib/src/services/storage/) │
│  Dependencies: domain models only                │
└──────────────────┬──────────────────────────────┘
                   │ implemented by
                   ▼
┌─────────────────────────────────────────────────┐
│  Drift Implementation (internal)                 │
│  Location: lib/src/services/database/            │
│  Contains: Table definitions, DAOs, converters   │
│  Dependencies: Drift + domain models             │
│  Mapping: DriftBeanRow ↔ Bean (domain)           │
└─────────────────────────────────────────────────┘
```

**Why duplicate the structure?** If we ever replace Drift (or move to a server-hosted DB, or need a different storage engine per platform), only the `services/database/` layer changes. Controllers, UI, tests, and API handlers are unaffected. The existing pattern of `StorageService` → `FileStorageService` already follows this principle — we're extending it consistently.

### 2.2 Directory Structure

```
lib/src/models/data/
  bean.dart                  # Bean, BeanBatch domain models (pure Dart)
  grinder.dart               # Grinder domain model (pure Dart)
  equipment.dart             # Equipment, EquipmentType domain model (pure Dart)
  water.dart                 # Water domain model (pure Dart)
  workflow_context.dart      # WorkflowContext + snapshot classes (pure Dart)
  shot_annotations.dart      # ShotAnnotations, TastingAnnotation (pure Dart)
  workflow.dart              # Workflow (modified, uses WorkflowContext)
  shot_record.dart           # ShotRecord (modified, uses ShotAnnotations)
  profile.dart               # Profile (unchanged)
  profile_record.dart        # ProfileRecord (unchanged)
  ...

lib/src/services/database/
  database.dart              # AppDatabase class, table registrations
  database.g.dart            # Generated code (build_runner)
  tables/
    bean_tables.dart         # Beans, BeanBatches table definitions
    grinder_tables.dart      # Grinders table definition
    equipment_tables.dart    # Equipments table definition
    water_tables.dart        # Waters table definition
    shot_tables.dart         # ShotRecords, ShotEquipment table definitions
    workflow_tables.dart     # Workflows table definition
    profile_tables.dart      # ProfileRecords table definition
  daos/
    bean_dao.dart            # Bean + BeanBatch CRUD & queries
    grinder_dao.dart         # Grinder CRUD & queries
    equipment_dao.dart       # Equipment CRUD & queries
    water_dao.dart           # Water CRUD & queries
    shot_dao.dart            # ShotRecord CRUD, annotation updates
    workflow_dao.dart        # Workflow CRUD
    profile_dao.dart         # ProfileRecord CRUD, visibility, dedup
  mappers/
    bean_mapper.dart         # DriftBeanRow ↔ Bean, DriftBeanBatchRow ↔ BeanBatch
    grinder_mapper.dart      # DriftGrinderRow ↔ Grinder
    equipment_mapper.dart    # DriftEquipmentRow ↔ Equipment
    water_mapper.dart        # DriftWaterRow ↔ Water
    shot_mapper.dart         # DriftShotRecordRow ↔ ShotRecord
    workflow_mapper.dart     # DriftWorkflowRow ↔ Workflow
    profile_mapper.dart      # DriftProfileRecordRow ↔ ProfileRecord
  converters/
    json_converters.dart     # TypeConverters for JSON text columns
  migration/
    migration.dart           # stepByStep migration definitions
    legacy_import.dart       # One-time JSON/Hive → SQLite migration

lib/src/services/storage/
  storage_service.dart       # Abstract interface (unchanged)
  profile_storage_service.dart # Abstract interface (unchanged)
  bean_storage_service.dart  # NEW abstract interface for Bean/BeanBatch ops
  grinder_storage_service.dart # NEW abstract interface for Grinder ops
  equipment_storage_service.dart # NEW abstract interface for Equipment ops
  water_storage_service.dart # NEW abstract interface for Water ops
  # Implementations:
  drift_storage_service.dart # implements StorageService (shots + workflows)
  drift_profile_storage.dart # implements ProfileStorageService
  drift_bean_storage.dart    # implements BeanStorageService
  drift_grinder_storage.dart # implements GrinderStorageService
  drift_equipment_storage.dart # implements EquipmentStorageService
  drift_water_storage.dart   # implements WaterStorageService
  # Legacy (kept until migration proven stable):
  file_storage_service.dart  # existing file-based implementation
  hive_profile_storage.dart  # existing Hive implementation
```

### 2.3 Mapper Pattern

Each mapper is a simple stateless translation between domain ↔ Drift row:

```dart
// lib/src/services/database/mappers/bean_mapper.dart
// This file is INTERNAL to the database service — not imported by controllers/UI

extension BeanMapper on Bean {
  /// Domain → Drift companion (for inserts/updates)
  BeansCompanion toDriftCompanion() => BeansCompanion(
    id: Value(id),
    roaster: Value(roaster),
    name: Value(name),
    species: Value(species),
    // ...
  );
}

extension DriftBeanMapper on DriftBeanRow {
  /// Drift row → Domain
  Bean toDomain() => Bean(
    id: id,
    roaster: roaster,
    name: name,
    species: species,
    // ...
  );
}
```

DAOs use mappers internally — the mapping never leaks to callers:

```dart
// Inside BeanDao
Future<Bean?> getBean(String id) async {
  final row = await (select(beans)..where((t) => t.id.equals(id)))
      .getSingleOrNull();
  return row?.toDomain();  // Drift row → domain object
}

Future<void> insertBean(Bean bean) async {
  await into(beans).insert(bean.toDriftCompanion());  // domain → Drift
}
```

### 2.4 Design Principles

1. **Domain models are framework-free** — No Drift annotations, no `extends Table`, no generated classes in `lib/src/models/`. Pure Dart with `toJson()`/`fromJson()` for API/export use.
2. **Drift is an implementation detail** — Table definitions, row classes, and converters are private to `lib/src/services/database/`. If we swap Drift for another storage engine, only this directory changes.
3. **Service interfaces as the boundary** — Controllers depend on abstract storage service interfaces, not DAOs directly. Drift implementations sit behind these interfaces.
4. **Relational where it matters** — Entity tables are normalized with foreign keys. Cross-entity queries use JOINs.
5. **JSON columns for embedded objects** — Snapshots, extras maps, tasting attributes, and shot measurements are stored as JSON columns via Drift TypeConverters. These are written once and read as a unit.
6. **Reactive where useful** — Entity lists and shot history use `.watch()` streams (exposed as `Stream` on the service interface). Single-entity reads can be one-shot.

---

## 3. Table Definitions

### 3.1 Entity Tables

#### Beans

```dart
class Beans extends Table {
  TextColumn get id => text()();                          // UUID PK
  TextColumn get roaster => text()();
  TextColumn get name => text()();
  TextColumn get species => text().nullable()();
  TextColumn get country => text().nullable()();
  TextColumn get region => text().nullable()();
  TextColumn get producer => text().nullable()();
  TextColumn get variety => text().map(const StringListConverter()).nullable()();
  TextColumn get altitude => text().nullable()();
  TextColumn get processing => text().nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get extras => text().map(const JsonMapConverter()).nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

#### BeanBatches

```dart
class BeanBatches extends Table {
  TextColumn get id => text()();                          // UUID PK
  TextColumn get beanId => text().references(Beans, #id)();  // FK → Beans
  DateTimeColumn get roastDate => dateTime().nullable()();
  TextColumn get roastLevel => text().nullable()();
  TextColumn get harvestDate => text().nullable()();
  RealColumn get qualityScore => real().nullable()();
  RealColumn get price => real().nullable()();
  TextColumn get currency => text().nullable()();
  RealColumn get weight => real().nullable()();
  RealColumn get weightRemaining => real().nullable()();
  DateTimeColumn get buyDate => dateTime().nullable()();
  DateTimeColumn get openDate => dateTime().nullable()();
  DateTimeColumn get bestBeforeDate => dateTime().nullable()();
  DateTimeColumn get freezeDate => dateTime().nullable()();
  DateTimeColumn get unfreezeDate => dateTime().nullable()();
  BoolColumn get frozen => boolean().withDefault(const Constant(false))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get extras => text().map(const JsonMapConverter()).nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

#### Grinders

```dart
class Grinders extends Table {
  TextColumn get id => text()();
  TextColumn get model => text()();
  TextColumn get burrs => text().nullable()();
  RealColumn get burrSize => real().nullable()();
  TextColumn get burrType => text().nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  // UI Configuration (DYE2)
  TextColumn get settingType => textEnum<GrinderSettingType>()();
  TextColumn get settingValues => text().map(const StringListConverter()).nullable()();
  RealColumn get settingSmallStep => real().nullable()();
  RealColumn get settingBigStep => real().nullable()();
  RealColumn get rpmSmallStep => real().nullable()();
  RealColumn get rpmBigStep => real().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get extras => text().map(const JsonMapConverter()).nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

#### Equipments

```dart
class Equipments extends Table {
  TextColumn get id => text()();
  TextColumn get type => textEnum<EquipmentType>()();
  TextColumn get name => text()();
  TextColumn get brand => text().nullable()();
  TextColumn get model => text().nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get extras => text().map(const JsonMapConverter()).nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

#### Waters

```dart
class Waters extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  RealColumn get generalHardness => real().nullable()();
  RealColumn get carbonateHardness => real().nullable()();
  RealColumn get calcium => real().nullable()();
  RealColumn get magnesium => real().nullable()();
  RealColumn get sodium => real().nullable()();
  RealColumn get potassium => real().nullable()();
  RealColumn get tds => real().nullable()();
  RealColumn get ph => real().nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get extras => text().map(const JsonMapConverter()).nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

### 3.2 Shot & Workflow Tables

#### ShotRecords

The shot table stores the header row. Measurements and embedded workflow are JSON columns (they're written once as a unit, never queried by individual measurement fields).

```dart
class ShotRecords extends Table {
  TextColumn get id => text()();                          // UUID PK
  DateTimeColumn get timestamp => dateTime()();
  TextColumn get profileTitle => text().nullable()();     // denormalized for quick listing
  // Embedded workflow (full JSON — profile, steam, hot water, rinse, context)
  TextColumn get workflow => text().map(const WorkflowConverter())();
  // Measurements as JSON array (high-frequency time-series, not worth normalizing)
  TextColumn get measurements => text().map(const MeasurementsConverter())();
  // Typed annotations (replaces metadata + shotNotes)
  TextColumn get annotations => text().map(const ShotAnnotationsConverter()).nullable()();

  // Denormalized entity references for indexed querying
  // (also present inside workflow.context, but pulled up for SQL WHERE/JOIN)
  TextColumn get grinderId => text().nullable()();
  TextColumn get beanBatchId => text().nullable()();
  TextColumn get waterId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

**Why denormalize entity IDs on the shot row?**

The canonical references live inside `workflow.context.grinderId` etc. (a JSON column). But SQL can't efficiently index into JSON for queries like "all shots with grinder X." Pulling these IDs up to real columns enables indexed queries while the JSON column remains the source of truth for the full workflow snapshot.

#### Workflows (Current/Active)

```dart
class Workflows extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get profile => text().map(const ProfileConverter())();
  TextColumn get context => text().map(const WorkflowContextConverter()).nullable()();
  TextColumn get steamSettings => text().map(const SteamSettingsConverter())();
  TextColumn get hotWaterData => text().map(const HotWaterDataConverter())();
  TextColumn get rinseData => text().map(const RinseDataConverter())();

  @override
  Set<Column> get primaryKey => {id};
}
```

#### ProfileRecords

```dart
class ProfileRecords extends Table {
  TextColumn get id => text()();                          // content-hash based
  TextColumn get profile => text().map(const ProfileConverter())();
  TextColumn get metadataHash => text()();
  TextColumn get compoundHash => text()();
  TextColumn get parentId => text().nullable()();
  TextColumn get visibility => textEnum<Visibility>()();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get metadata => text().map(const JsonMapConverter()).nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

### 3.3 Junction Table

#### ShotEquipment (many-to-many: shots ↔ equipment)

```dart
class ShotEquipment extends Table {
  TextColumn get shotId => text().references(ShotRecords, #id)();
  TextColumn get equipmentId => text().references(Equipments, #id)();

  @override
  Set<Column> get primaryKey => {shotId, equipmentId};
}
```

### 3.4 Indexes

```dart
// Shot queries by time range
@TableIndex(name: 'idx_shots_timestamp', columns: {#timestamp})

// Shot queries by entity
@TableIndex(name: 'idx_shots_grinder', columns: {#grinderId})
@TableIndex(name: 'idx_shots_bean_batch', columns: {#beanBatchId})
@TableIndex(name: 'idx_shots_water', columns: {#waterId})

// Bean batch lookup by parent bean
@TableIndex(name: 'idx_bean_batches_bean', columns: {#beanId})

// Profile visibility filtering
@TableIndex(name: 'idx_profiles_visibility', columns: {#visibility})

// Archived filtering on entities
@TableIndex(name: 'idx_beans_archived', columns: {#archived})
@TableIndex(name: 'idx_grinders_archived', columns: {#archived})
@TableIndex(name: 'idx_equipments_archived', columns: {#archived})
@TableIndex(name: 'idx_waters_archived', columns: {#archived})
```

---

## 4. Type Converters

Complex objects that are always read/written as a unit use Drift TypeConverters to map between Dart domain objects and JSON text columns.

### 4.1 Converter Strategy

| Data | Storage | Rationale |
|------|---------|-----------|
| Entity scalar fields | Native columns | Queryable, indexable |
| `extras` Map | JSON text column | Schema-free by design |
| `variety` (List\<String\>) | JSON text column | Simple list, no need for junction table |
| `WorkflowContext` | JSON text column | Composite embedded object, written as unit |
| `ShotAnnotations` | JSON text column | Composite embedded object, written as unit |
| `Profile` | JSON text column | Complex nested structure (steps array), already has JSON serialization |
| `ShotSnapshot[]` measurements | JSON text column | High-frequency time-series, hundreds of entries per shot — not worth normalizing |
| `SteamSettings` / `HotWaterData` / `RinseData` | JSON text columns | Small embedded objects |
| Snapshots (Grinder/Bean/Water/Equipment) | Inside WorkflowContext JSON | Part of the composite context |

### 4.2 Core Converters

```dart
/// Stores Map<String, dynamic> as JSON text
class JsonMapConverter extends TypeConverter<Map<String, dynamic>, String>
    with JsonTypeConverter2<Map<String, dynamic>, String, Map<String, Object?>> {
  const JsonMapConverter();

  @override
  Map<String, dynamic> fromSql(String fromDb) => json.decode(fromDb) as Map<String, dynamic>;

  @override
  String toSql(Map<String, dynamic> value) => json.encode(value);

  @override
  Map<String, dynamic> fromJson(Map<String, Object?> json) => Map<String, dynamic>.from(json);

  @override
  Map<String, Object?> toJson(Map<String, dynamic> value) => value;
}

/// Stores List<String> as JSON text
class StringListConverter extends TypeConverter<List<String>, String>
    with JsonTypeConverter2<List<String>, String, List<Object?>> {
  const StringListConverter();

  @override
  List<String> fromSql(String fromDb) => (json.decode(fromDb) as List).cast<String>();

  @override
  String toSql(List<String> value) => json.encode(value);

  @override
  List<String> fromJson(List<Object?> json) => json.cast<String>();

  @override
  List<Object?> toJson(List<String> value) => value;
}

/// Stores domain objects that have toJson/fromJson
/// One converter per domain type: WorkflowContextConverter, ShotAnnotationsConverter,
/// ProfileConverter, MeasurementsConverter, etc.
```

---

## 5. Service Interfaces & DAO Design

### 5.1 Two Layers: Interface → Implementation

Controllers depend on **abstract service interfaces** (pure Dart, in `lib/src/services/storage/`). The Drift DAOs are internal implementation details behind those interfaces.

```
Controller → BeanStorageService (abstract) → DriftBeanStorageService → BeanDao → Drift tables
```

This means:
- Controllers never import anything from `lib/src/services/database/`
- Service interfaces use only domain model types
- Tests can mock the service interface without knowing about Drift

### 5.2 New Storage Service Interfaces

#### BeanStorageService

```dart
// lib/src/services/storage/bean_storage_service.dart
// Pure Dart — no Drift imports

abstract class BeanStorageService {
  Future<void> initialize();

  // === Bean CRUD ===
  Future<Bean> createBean(Bean bean);
  Future<Bean?> getBean(String id);
  Future<void> updateBean(Bean bean);
  Future<void> archiveBean(String id);
  Stream<List<Bean>> watchBeans({bool includeArchived = false});

  // === BeanBatch CRUD ===
  Future<BeanBatch> createBatch(BeanBatch batch);
  Future<BeanBatch?> getBatch(String id);
  Future<void> updateBatch(BeanBatch batch);
  Future<void> archiveBatch(String id);
  Stream<List<BeanBatch>> watchBatchesForBean(String beanId, {bool includeArchived = false});
  Future<void> decrementBatchWeight(String batchId, double grams);

  // === Composite queries ===
  Stream<BeanWithBatches> watchBeanWithBatches(String beanId);
  Stream<List<BeanWithBatches>> watchActiveBeans();
}
```

Similar interfaces for `GrinderStorageService`, `EquipmentStorageService`, `WaterStorageService`.

#### Extended StorageService (shots)

The existing `StorageService` interface is extended with entity-filtered queries:

```dart
// Additions to existing StorageService or a new ShotStorageService
Future<void> updateAnnotations(String shotId, ShotAnnotations annotations);
Stream<List<ShotRecord>> watchShots({int limit = 50, int offset = 0});
Future<List<ShotRecord>> getShotsForGrinder(String grinderId);
Future<List<ShotRecord>> getShotsForBeanBatch(String batchId);
Future<List<ShotRecord>> getShotsForBean(String beanId);
```

### 5.3 Drift Implementation (Internal)

Behind the interfaces, each Drift-backed service delegates to a DAO:

```dart
// lib/src/services/storage/drift_bean_storage.dart
class DriftBeanStorageService implements BeanStorageService {
  final BeanDao _dao;
  DriftBeanStorageService(this._dao);

  @override
  Future<Bean?> getBean(String id) => _dao.getBean(id);

  @override
  Stream<List<Bean>> watchBeans({bool includeArchived = false}) =>
      _dao.watchBeans(includeArchived: includeArchived);
  // ...
}
```

The DAOs themselves are internal to `lib/src/services/database/` and use mappers to convert between Drift row classes and domain objects:

```dart
// lib/src/services/database/daos/bean_dao.dart (INTERNAL — not imported by controllers)
@DriftAccessor(tables: [Beans, BeanBatches])
class BeanDao extends DatabaseAccessor<AppDatabase> with _$BeanDaoMixin {
  BeanDao(super.db);

  Future<Bean?> getBean(String id) async {
    final row = await (select(beans)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row?.toDomain();  // mapper: Drift row → domain Bean
  }

  Future<void> insertBean(Bean bean) async {
    await into(beans).insert(bean.toDriftCompanion());  // mapper: domain → Drift
  }

  Stream<List<Bean>> watchBeans({bool includeArchived = false}) {
    final query = select(beans);
    if (!includeArchived) {
      query.where((t) => t.archived.equals(false));
    }
    return query.watch().map((rows) => rows.map((r) => r.toDomain()).toList());
  }
  // ...
}
```

### 5.4 All Service Interfaces & DAOs

| Service Interface | DAO (internal) | Tables | Key Operations |
|---|---|---|---|
| `BeanStorageService` | `BeanDao` | Beans, BeanBatches | CRUD, watch active beans with batches, batch weight tracking |
| `GrinderStorageService` | `GrinderDao` | Grinders | CRUD, watch active grinders |
| `EquipmentStorageService` | `EquipmentDao` | Equipments | CRUD by type, watch active equipment |
| `WaterStorageService` | `WaterDao` | Waters | CRUD, watch active waters |
| `StorageService` (extended) | `ShotDao` | ShotRecords, ShotEquipment | CRUD, paginated history, filter by entity, annotation updates |
| `StorageService` | `WorkflowDao` | Workflows | Load/save current workflow |
| `ProfileStorageService` | `ProfileDao` | ProfileRecords | CRUD, visibility filtering, parent chain, dedup check |

---

## 6. Integration with Existing Architecture

### 6.1 Controller Layer — No Changes to Injection Pattern

The existing pattern is preserved exactly: controllers depend on **abstract service interfaces** injected via constructors. The only change is which implementation gets wired in at `main.dart`.

```
Before:  PersistenceController → StorageService (interface) → FileStorageService
After:   PersistenceController → StorageService (interface) → DriftStorageService → ShotDao → Drift
```

Controllers never see Drift. They never import from `lib/src/services/database/`. They receive service interfaces, same as today.

### 6.2 New Entity Controllers

The new entities (Bean, Grinder, Equipment, Water) need controllers that don't exist yet. These follow the same pattern — inject a storage service interface:

```dart
class BeanController {
  final BeanStorageService _storage;  // abstract interface, not DAO
  BeanController(this._storage);

  Stream<List<BeanWithBatches>> get activeBeans => _storage.watchActiveBeans();
  // CRUD methods...
}
```

### 6.3 Snapshot Population

When a shot finishes, the `ShotController` / `PersistenceController` needs to:

1. Resolve entity references from the current WorkflowContext (grinderId → Grinder, beanBatchId → BeanBatch + Bean, etc.)
2. Build snapshot objects (GrinderSnapshot, BeanSnapshot, etc.)
3. Populate them on the WorkflowContext before embedding in the ShotRecord
4. Store the ShotRecord with the fully-populated context

This is controller logic, not storage logic. The storage service just persists the result.

### 6.4 Initialization

```dart
// main.dart
final database = AppDatabase();  // opens/creates SQLite file

// Wire Drift implementations behind abstract interfaces
final beanStorage = DriftBeanStorageService(database.beanDao);
final grinderStorage = DriftGrinderStorageService(database.grinderDao);
final equipmentStorage = DriftEquipmentStorageService(database.equipmentDao);
final waterStorage = DriftWaterStorageService(database.waterDao);

// New entity controllers — receive abstract interfaces
final beanController = BeanController(beanStorage);
final grinderController = GrinderController(grinderStorage);
// ...

// Existing controllers — same interfaces, new implementation
final persistenceController = PersistenceController(
  storageService: DriftStorageService(database.shotDao, database.workflowDao),
);
final profileController = ProfileController(
  storage: DriftProfileStorageService(database.profileDao),
);
```

The `AppDatabase` instance is created in `main.dart` and never passed to controllers. Only the abstract service wrappers are injected.

---

## 7. Migration Strategy

### 7.1 Drift Schema Versioning

```dart
@override
int get schemaVersion => 1;  // start at 1 for initial release

@override
MigrationStrategy get migration {
  return MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: _schemaUpgrade,
    beforeOpen: (details) async {
      // Enable foreign keys
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
```

### 7.2 Data Migration from Legacy Storage

This is a **one-time migration** that runs when the app first launches with Drift. It imports existing data from JSON files and Hive into the SQLite database, then marks the migration as complete.

#### Migration Flow

```
App launch
  → Open Drift database (creates tables if needed)
  → Check migration flag in SharedPreferences
  → If not migrated:
      1. Import shots from JSON files → ShotRecords table
      2. Import profiles from Hive → ProfileRecords table
      3. Import current workflow from JSON → Workflows table
      4. Extract grinder/coffee entities from shot history → Beans, Grinders tables
      5. Set migration flag
      6. (Optionally) archive old JSON/Hive files, don't delete
  → Continue normal startup
```

#### Shot Migration Details

Each existing shot JSON file maps to a ShotRecord row:

| Old Field | New Location |
|-----------|-------------|
| `id`, `timestamp`, `measurements` | Direct mapping to ShotRecords columns |
| `workflow` | Full workflow JSON stored in `workflow` column |
| `workflow.doseData` | Extracted into `WorkflowContext.doseWeight` / `targetYield` |
| `workflow.grinderData` | Extracted into `WorkflowContext.grinderSetting` + `GrinderSnapshot` |
| `workflow.coffeeData` | Extracted into `WorkflowContext.beanSnapshot` (no entity reference — legacy) |
| `shotNotes` | Moved to `ShotAnnotations.espressoNotes` |
| `metadata` | Moved to `ShotAnnotations.extras` (if non-null) |

#### Entity Extraction from History

During migration, scan all shots to auto-create entity entries:

1. **Grinders:** Unique `(manufacturer, model)` pairs from `GrinderData` → create Grinder entries. Link shots via `grinderId`.
2. **Beans:** Unique `(roaster, name)` pairs from `CoffeeData` → create Bean entries + a single BeanBatch per Bean. Link shots via `beanBatchId`.

This is best-effort — the legacy data is sparse (just grinder model + coffee name/roaster). Users can enrich entities later.

### 7.3 Profile Migration

ProfileRecords move from Hive to the ProfileRecords table:

| Hive Field | Drift Column |
|-----------|-------------|
| All fields | Direct 1:1 mapping — same data model, different storage |

The Profile JSON structure stored inside the `profile` column is identical to what Hive stores today. The `ProfileConverter` TypeConverter handles serialization.

### 7.4 Rollback Safety

- Old JSON shot files and Hive boxes are **not deleted** after migration
- A SharedPreferences flag (`driftMigrationVersion`) tracks migration state
- If migration fails partway, it can be re-run (idempotent — check for existing IDs before insert)
- Users can manually recover by deleting the SQLite file and re-running migration

---

## 8. Foreign Key Strategy

SQLite foreign keys are **not enforced by default**. We enable them via `PRAGMA foreign_keys = ON` in the `beforeOpen` callback.

### Soft References vs Hard References

| Reference | Enforcement | Rationale |
|-----------|-------------|-----------|
| BeanBatch → Bean | Hard FK | Batch always belongs to a bean; cascade on bean delete |
| ShotRecord → Grinder | **Soft** (nullable, no FK constraint) | Archived/deleted grinders should not cascade-delete shot history |
| ShotRecord → BeanBatch | **Soft** (nullable, no FK constraint) | Same reasoning — snapshots preserve historical data |
| ShotRecord → Water | **Soft** (nullable, no FK constraint) | Same |
| ShotEquipment → Equipment | **Soft** (nullable, no FK constraint) | Same |
| ShotEquipment → ShotRecord | Hard FK with CASCADE delete | Deleting a shot removes junction rows |

**Why soft references for shots?** Per the schema proposal: "Archived/deleted entities leave dangling refs — snapshots preserve historical data." If a user deletes a grinder, we don't want to lose 500 shots. The snapshot embedded in the WorkflowContext preserves what was used.

---

## 9. Reactive Query Patterns

Drift's `.watch()` replaces the manual BehaviorSubject pattern used today.

### Before (current pattern)
```dart
class PersistenceController {
  final _shotsController = BehaviorSubject<List<ShotRecord>>.seeded([]);
  List<ShotRecord> _shots = [];

  Future<void> persistShot(ShotRecord record) async {
    await storageService.storeShot(record);
    _shots.add(record);
    _shotsController.add(_shots);  // manual broadcast
  }

  Stream<List<ShotRecord>> get shots => _shotsController.stream;
}
```

### After (Drift reactive)
```dart
class ShotDao extends DatabaseAccessor<AppDatabase> with _$ShotDaoMixin {
  Stream<List<ShotRecord>> watchShots({int limit = 50, int offset = 0}) {
    final query = select(shotRecords)
      ..orderBy([(t) => OrderingTerm.desc(t.timestamp)])
      ..limit(limit, offset: offset);
    return query.watch().map((rows) => rows.map(_toDomain).toList());
  }
}
```

The controller can expose the DAO's stream directly — no in-memory cache needed. Any insert/update/delete automatically triggers stream updates for all active watchers.

---

## 10. Open Questions

1. **DateTime storage format:** Drift supports both Unix timestamps (INTEGER) and ISO-8601 strings (TEXT). The Drift docs recommend `store_date_time_values_as_text: true` for human readability. Existing JSON data uses ISO-8601 strings. **Proposal: use TEXT (ISO-8601) for consistency with existing data and readability.**

2. **Measurement storage:** Shot measurements are the bulk of data (hundreds of ShotSnapshots per shot, each with machine + scale readings). Current proposal stores them as a single JSON text column. Alternative: a separate `shot_measurements` table with one row per snapshot. **Proposal: JSON column — measurements are always read as a complete set, never queried individually, and normalizing would create millions of rows with no query benefit.**

3. **build_runner integration:** Drift requires `build_runner` for code generation. The project doesn't currently use `build_runner`. Need to add `build_runner` and `drift_dev` to dev dependencies and document the generation workflow.

4. **Database file location:** Should use the app's documents directory (same location as current JSON files). Path resolution via `path_provider`.

5. **Testing approach:** Drift supports in-memory databases for testing (`NativeDatabase.memory()`). This replaces the current mock service pattern for storage tests, or can complement it.

---

## 11. Dependencies to Add

```yaml
dependencies:
  drift: ^2.24.0
  drift_flutter: ^0.2.4       # Flutter-specific database opener
  sqlite3_flutter_libs: ^0.5.0 # SQLite native libraries

dev_dependencies:
  drift_dev: ^2.24.0
  build_runner: ^2.4.0
```

---

## 12. Implementation Phases

### Phase 1: Foundation
- Add Drift dependencies
- Define table classes + type converters
- Create AppDatabase with schema version 1
- Generate code with `build_runner`
- Implement DAOs for new entities (Bean, BeanBatch, Grinder, Equipment, Water)
- Add `beforeOpen` PRAGMA for foreign keys
- Unit test DAOs with in-memory database

### Phase 2: Shot & Workflow Migration
- Add ShotRecords + Workflows tables
- Implement ShotDao + WorkflowDao
- Create `DriftStorageService implements StorageService`
- Write one-time data migration (JSON files → SQLite)
- Integration test migration with sample data

### Phase 3: Profile Migration
- Add ProfileRecords table
- Implement ProfileDao
- Create `DriftProfileStorageService implements ProfileStorageService`
- Write one-time profile migration (Hive → SQLite)
- Verify content-hash deduplication works with Drift

### Phase 4: New Entity Controllers + WorkflowContext
- Implement WorkflowContext model + converter
- Implement ShotAnnotations model + converter
- Create new entity controllers (BeanController, GrinderController, etc.)
- Wire snapshot population into shot recording flow
- Update Workflow model to use WorkflowContext instead of DoseData/GrinderData/CoffeeData

### Phase 5: Cleanup
- Remove FileStorageService (after migration proven stable)
- Remove HiveProfileStorageService
- Remove Hive dependencies (hive_ce, hive_ce_flutter) if plugin KV is also migrated or stays on Hive
- Update API handlers to use new model structures
- Update WebSocket broadcasts

---

## 13. Summary of Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Storage engine | Drift (SQLite) | Relational queries, reactive streams, migrations, type safety |
| Database count | Single AppDatabase | Simpler transactions, single file backup |
| Entity storage | Normalized tables with native columns | Queryable, indexable, FK-capable |
| Complex object storage | JSON text columns via TypeConverters | Snapshots, extras, measurements are written/read as units |
| Measurement storage | JSON column on ShotRecords | Always read as complete set; normalizing = millions of rows with no query benefit |
| Domain model purity | Domain models in `models/data/` are pure Dart — zero framework annotations | Storage engine is swappable; controllers/UI/API never see Drift |
| Two-layer model | Drift tables mirror domain models; mappers translate between them | Duplication is deliberate — decouples app from persistence framework |
| DAO pattern | One DAO per domain, returns domain objects via mappers | Translation boundary; Drift row classes never leak |
| Controller integration | Abstract service interfaces backed by Drift implementations | Same DI pattern as today; controllers never import Drift |
| Entity references on shots | Denormalized columns + JSON context | Indexed queries on real columns; full context in JSON |
| FK enforcement | Hard for parent-child (Bean→BeanBatch), soft for shot→entity | Don't cascade-delete shot history when archiving entities |
| DateTime format | ISO-8601 text | Matches existing JSON data, human-readable, Drift-recommended |
| Legacy data migration | One-time import on first launch, idempotent, non-destructive | Old files preserved as backup |
| Plugin KV store | Stays on Hive | Schema-free by design, no relational needs |
| Settings | Stays on SharedPreferences | Flat key-value, no benefit from SQL |
