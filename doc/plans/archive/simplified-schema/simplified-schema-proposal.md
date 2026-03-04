# Simplified Coffee Metadata Schema Proposal

**Version:** Draft 2.0
**Date:** 2026-03-03
**Context:** Simplification of `beans-equipment-shot-data-schema-proposal.md` (the "full proposal"), informed by critical review of complexity, scaling concerns, and progressive adoption requirements
**Companion:** `persistence-layer-proposal.md` covers Drift (SQLite) storage layer design — to be updated to reflect the revised table set

---

## Executive Summary

The full schema proposal introduces 6 new entities, 4 snapshot types, 2 component types, junction tables, and ~50 new classes. This simplified proposal keeps the high-value entities (Bean, BeanBatch, Grinder) as first-class core data with Drift tables and REST API, but eliminates the complexity overhead (snapshot objects, component wrappers, junction tables) and defers lower-value entities (Equipment, Water) to the plugin system.

**Key architectural pattern: Core = data layer, plugins/skins = UI layer.** The core app owns entity tables and exposes CRUD APIs. Plugins (primarily Streamline/DYE2) and skins provide entity management UI, pickers, and selection flows. The core app has no bean/grinder management screens.

**Core entities (Drift tables + API):**
- `Bean` — coffee identity (roaster, name, origin, variety, processing, species, decaf) — full fields from original proposal
- `BeanBatch` — specific bag/purchase (roast date, weight tracking, dates, price) — full fields from original proposal
- `Grinder` — model info + Streamline/DYE2 UI configuration (setting types, step sizes, burrs) — merged from original Grinder + GrinderConfig

**Core composites (embedded in Workflow/ShotRecord):**
- `WorkflowContext` — replaces `DoseData`/`GrinderData`/`CoffeeData` with flat fields: entity IDs for linking + display strings for history + per-shot parameters
- `ShotAnnotations` — replaces unused `metadata` field with typed post-shot data

**What's eliminated vs the full proposal:**
- No snapshot objects (GrinderSnapshot, BeanSnapshot, WaterSnapshot, EquipmentSnapshot) — display strings on WorkflowContext serve as the historical record
- No component wrappers (BeanBatchComponent, EquipmentComponent) — flat `beanBatchId` field instead
- No junction tables (ShotBeanBatches, ShotEquipment) — single bean batch per shot
- No Equipment entity — deferred to plugin
- No Water entity — deferred to plugin
- No BlendComponent — deferred
- No tasting attribute breakdowns — deferred to plugin (annotations.extras)
- No photo attachments — deferred to plugin (annotations.extras)

**Table count:** 6 (down from 11). **New file count:** ~25 (down from ~50+).

---

## Design Principles

1. **Core = data, plugins/skins = UI** — The core app provides Drift tables and REST API for entity CRUD. Plugins and skins provide the management UI. The core app has no entity management screens. This lets any plugin or skin (Streamline/DYE2, a simple skin, a third-party plugin) share one entity library.
2. **ID + strings pattern** — WorkflowContext stores both entity IDs (for relational linking) and display strings (for history and compatibility). When a skin selects a bean batch, it writes both. If the entity is later deleted, the strings survive on historical shots. No snapshot objects needed.
3. **Unambiguous field names** — Pre-shot targets use `target*` prefixes; post-shot actuals use `actual*` prefixes. No fallback logic.
4. **Derived values are not stored** — `targetDoseYieldRatio` is computed from `targetDoseWeight / targetYield`. Not persisted.
5. **Lazy measurements** — Shot list queries return records without measurement data. Detail queries load the full record.
6. **Extras as plugin channels** — `extras` maps on WorkflowContext and ShotAnnotations are designated data channels for plugins. The core app treats them as opaque.
7. **Soft entity references** — Entity IDs on WorkflowContext and ShotRecords are nullable strings with no FK constraints. Archived/deleted entities leave dangling refs — the display strings preserve what was used.
8. **Full field sets from day one** — Bean, BeanBatch, and Grinder use the complete field sets from the full proposal. Skins choose which fields to expose in their UI. No second migration to add fields later.

---

## Entity Schema

### 1. Bean (Coffee Identity)

The coffee itself — origin, producer, variety. Immutable identity; batches track individual bags. Full field set from the original proposal.

| Field | Type | Notes | DE1 Alias |
|-------|------|-------|-----------|
| `id` | UUID | Primary key | — |
| `roaster` | String | Company/brand that roasted it | `bean_brand` |
| `name` | String | Coffee name/blend name | `bean_type` |
| `species` | String? | Arabica, Robusta, Liberica | *(new)* |
| `decaf` | bool | Default false | *(new)* |
| `decafProcess` | String? | Swiss Water, EA/Sugarcane, CO2, etc. | *(new)* |
| `country` | String? | Country of origin | `bean_country` |
| `region` | String? | Region/state/province | `bean_region` |
| `producer` | String? | Farm/estate/cooperative | `bean_producer` |
| `variety` | List\<String\>? | Geisha, SL28, Pink Bourbon, etc. | `bean_variety` |
| `altitude` | List\<int\>? | Elevation in masl — `[1800]` or `[1800, 2000]` | `bean_altitude` |
| `processing` | String? | Washed, Natural, Honey, etc. | `bean_processing` |
| `notes` | String? | General notes about this coffee | `bean_notes` |
| `archived` | bool | Soft delete / hide from active lists | — |
| `createdAt` | DateTime | | — |
| `updatedAt` | DateTime | | — |
| `extras` | Map\<String, dynamic\>? | Future fields (density, SCA score, etc.) | — |

#### Notes
- `variety` is a List because multi-variety single-origin lots are common (e.g., SL28 + SL34)
- `species` is a String (not List) — multi-species coffees are blends, and blends are expressed through separate Bean entries, not a species list
- **Commercial blends:** A Bean that is a blend (e.g., a house espresso mix) stores its composition in `extras` under a known key. The Streamline/DYE2 plugin manages this. Convention: `extras.blendComponents: [{description: "Ethiopian Yirgacheffe", percentage: 60, beanId: "uuid-or-null"}, ...]`. Each component has a text description (always present), an optional percentage, and an optional `beanId` FK if the component bean exists in the user's library. A Bean with non-empty `blendComponents` in extras is a blend; without is single-origin. The full proposal's typed `BlendComponent` class is not needed — the JSON structure in extras is sufficient and keeps the core Bean model simple

### 2. BeanBatch (Specific Bag/Purchase)

A physical bag of a specific Bean. Tracks inventory, dates, and batch-specific attributes. Full field set from the original proposal.

| Field | Type | Notes | DE1 Alias |
|-------|------|-------|-----------|
| `id` | UUID | Primary key | — |
| `beanId` | UUID | FK → Bean | — |
| `roastDate` | DateTime? | When this batch was roasted | `roast_date` |
| `roastLevel` | String? | Light, Medium, Dark, or numeric | `roast_level` |
| `harvestDate` | String? | Harvest season/year | `bean_harvest` |
| `qualityScore` | double? | SCA cupping score (0-100) | `bean_quality_score` |
| `price` | double? | Price paid | `bean_price` |
| `currency` | String? | ISO 4217 code (EUR, USD, etc.) | — |
| `weight` | double? | Bag weight in grams | — |
| `weightRemaining` | double? | Tracked, decremented per shot | — |
| `buyDate` | DateTime? | When purchased | — |
| `openDate` | DateTime? | When bag was first opened | `bean_open_date` |
| `bestBeforeDate` | DateTime? | Best by date | — |
| `freezeDate` | DateTime? | When frozen | `bean_freeze_date` |
| `unfreezeDate` | DateTime? | When thawed | `bean_unfreeze_date` |
| `frozen` | bool | Currently frozen? | — |
| `archived` | bool | Bag finished / hidden | — |
| `notes` | String? | Batch-specific notes | — |
| `createdAt` | DateTime | | — |
| `updatedAt` | DateTime | | — |
| `extras` | Map\<String, dynamic\>? | Future fields (CO2e, FOB price, etc.) | — |

#### Notes
- Bean↔BeanBatch split: buying the same coffee twice creates two BeanBatch entries pointing to the same Bean. Enables "all shots with this coffee regardless of bag."
- `weightRemaining` decremented by dose weight after each shot (if batch weight tracking is enabled). This is a core persistence concern — it must happen atomically with shot storage.

### 3. Grinder

Model info + Streamline/DYE2 UI configuration. Merges the original proposal's Grinder entity with the Streamline/DYE2 config fields from #62.

| Field | Type | Notes | DE1 Alias |
|-------|------|-------|-----------|
| `id` | UUID | Primary key | — |
| `model` | String | Grinder make/model | `grinder_model` |
| `burrs` | String? | Burr set description | `grinder_burrs` |
| `burrSize` | double? | Burr diameter in mm | — |
| `burrType` | String? | Flat, Conical, Ghost, Hybrid | — |
| `notes` | String? | | — |
| `archived` | bool | | — |
| **Streamline/DYE2 UI Configuration** | | | |
| `settingType` | enum | `numeric` or `values` | — |
| `settingValues` | List\<String\>? | When settingType=values: valid positions | — |
| `settingSmallStep` | double? | +/- button increment | — |
| `settingBigStep` | double? | ++/-- button increment | — |
| `rpmSmallStep` | double? | RPM +/- increment | — |
| `rpmBigStep` | double? | RPM ++/-- increment | — |
| `createdAt` | DateTime | | — |
| `updatedAt` | DateTime | | — |
| `extras` | Map\<String, dynamic\>? | Future fields | — |

#### Notes
- `settingType` drives UI behavior: `numeric` shows +/- with configurable steps; `values` shows a picker with the defined positions
- Per-shot grinder *settings* (the actual grind size, RPM used) live on WorkflowContext, not here
- "Slow feeding" and other shot prep techniques belong in WorkflowContext.extras, not on the grinder entity

---

## Composite Schema

### 4. WorkflowContext

Replaces `DoseData`, `GrinderData`, and `CoffeeData` on Workflow. The existing `Profile`, `SteamSettings`, `HotWaterData`, and `RinseData` remain as separate fields on Workflow alongside it.

```dart
class WorkflowContext {
  // === Dose & Yield ===
  double? targetDoseWeight;       // target dry coffee in grams (DE1: grinder_dose_weight)
  double? targetYield;            // target espresso yield in grams

  // === Grinder (ID for linking + string for display/history) ===
  String? grinderId;              // FK → Grinder (nullable — not everyone uses entity management)
  String? grinderModel;           // display string, survives entity deletion (DE1: grinder_model)
  String? grinderSetting;         // per-shot setting value (DE1: grinder_setting)

  // === Coffee (ID for linking + strings for display/history) ===
  String? beanBatchId;            // FK → BeanBatch (nullable)
  String? coffeeName;             // display string, survives entity deletion (DE1: bean_type)
  String? coffeeRoaster;          // display string, survives entity deletion (DE1: bean_brand)

  // === Beverage ===
  String? finalBeverageType;      // "espresso", "flat white", "cappuccino", etc.

  // === People ===
  String? baristaName;            // DE1: my_name
  String? drinkerName;            // DE1: drinker_name

  // === Plugin Data Channel ===
  Map<String, dynamic>? extras;   // shot prep, tasting config, equipment refs, etc.
}
```

**12 fields.** Everything nullable. Three usage tiers:

1. **Minimal:** Set `targetDoseWeight` + `targetYield`. Everything else null.
2. **Standard:** Add `grinderModel` + `grinderSetting` + `coffeeName` + `coffeeRoaster` as strings. No entity IDs needed.
3. **Full:** Streamline/DYE2 plugin sets entity IDs (`grinderId`, `beanBatchId`) alongside the display strings. Entity management via API.

#### The ID + Strings Pattern

Every entity reference follows the same pattern on WorkflowContext:

| Purpose | Grinder | Coffee |
|---------|---------|--------|
| **Relational linking** | `grinderId` | `beanBatchId` |
| **Display / history** | `grinderModel` | `coffeeName` + `coffeeRoaster` |
| **Per-shot parameter** | `grinderSetting` | — |

When a skin selects an entity, it writes both the ID and the display strings. If the entity is later archived/deleted, the strings survive on historical shots — the ID becomes a dangling ref (harmless; no FK constraint). This eliminates the need for snapshot objects.

**Why both?** The ID enables "all shots with this grinder" as a proper indexed query. The strings enable display without entity resolution and DE1/Visualizer compatibility. Neither alone is sufficient.

#### Migration from Current Fields

| Old Field | New Field |
|---|---|
| `DoseData.doseIn` | `WorkflowContext.targetDoseWeight` |
| `DoseData.doseOut` | `WorkflowContext.targetYield` |
| `GrinderData.setting` | `WorkflowContext.grinderSetting` |
| `GrinderData.manufacturer` + `.model` | `WorkflowContext.grinderModel` (concatenated) |
| `CoffeeData.roaster` | `WorkflowContext.coffeeRoaster` |
| `CoffeeData.name` | `WorkflowContext.coffeeName` |

Entity IDs (`grinderId`, `beanBatchId`) are null on migrated shots — users build their entity library going forward.

#### Notes
- `grinderSetting` is a String, not a number. Stepped grinders use click notation ("28 clicks", "7.2.1"), some use letters. The `Grinder` entity's `settingType` and `settingValues` define how the UI interprets this value.
- `finalBeverageType` is a free-form String. Since the ShotRecord embeds the full Workflow, this value is captured automatically. On "repeat shot," the entire Workflow (including `finalBeverageType`) is copied.
- `extras` serves as the plugin data channel for: shot prep techniques (distribution, tamping, RDT, slow feeding), equipment references, water profile references, and any other per-shot data that plugins want to attach.

### 5. ShotAnnotations

Replaces the unused `ShotRecord.metadata: Map<String, dynamic>?` field and `ShotRecord.shotNotes: String?`. User-entered after the shot.

```dart
class ShotAnnotations {
  // === Actuals (unambiguous names — no overlap with WorkflowContext) ===
  double? actualDoseWeight;              // measured dose in grams
  double? actualYield;                   // measured yield in grams (DE1: drink_weight)

  // === Extraction ===
  double? drinkTds;                      // Total Dissolved Solids (%)
  double? drinkEy;                       // Extraction Yield (%)

  // === Rating ===
  double? enjoyment;                     // 0.0–10.0 scale
  String? espressoNotes;                 // DE1: espresso_notes

  // === Plugin Data Channel ===
  Map<String, dynamic>? extras;          // tasting breakdown, photos, beverage details, people overrides
}
```

**7 typed fields.** Tasting attribute breakdowns (acidity, sweetness, body), photo attachments, beverage details (added liquid type/weight/temperature), and per-shot people overrides all live in `extras` when a plugin provides them.

#### Field Naming: No Ambiguity

| Concept | WorkflowContext (pre-shot) | ShotAnnotations (post-shot) |
|---|---|---|
| Dose | `targetDoseWeight` | `actualDoseWeight` |
| Yield | `targetYield` | `actualYield` |

Different names. No fallback logic. The UI can show "target: 18.0g → actual: 18.2g" without confusion.

#### Enjoyment Scale

Single **0.0–10.0 scale**. For DE1 `.shot` file export compatibility, multiply by 10 at the serialization boundary.

### 6. Modified ShotRecord

```dart
class ShotRecord {
  String id;                              // UUID
  DateTime timestamp;
  Workflow workflow;                      // embeds WorkflowContext + profile + steam/hotwater/rinse
  List<ShotSnapshot>? measurements;       // NULLABLE — null when loaded as summary
  ShotAnnotations? annotations;           // replaces metadata + shotNotes
}
```

Key changes:
- `shotNotes` → `annotations.espressoNotes`
- `metadata` → `annotations.extras` (if non-null during migration)
- `measurements` is now **nullable** — enables lazy loading

### 7. Modified Workflow

```dart
class Workflow {
  String id;
  String name;
  String description;
  Profile profile;                        // unchanged
  WorkflowContext? context;               // NEW — replaces doseData, grinderData, coffeeData
  SteamSettings steamSettings;            // unchanged
  HotWaterData hotWaterData;              // unchanged
  RinseData rinseData;                    // unchanged
}
```

`DoseData`, `GrinderData`, and `CoffeeData` classes are removed.

---

## Drift Schema

### Tables

6 tables. No junction tables.

#### Beans

```dart
class Beans extends Table {
  TextColumn get id => text()();
  TextColumn get roaster => text()();
  TextColumn get name => text()();
  TextColumn get species => text().nullable()();
  BoolColumn get decaf => boolean().withDefault(const Constant(false))();
  TextColumn get decafProcess => text().nullable()();
  TextColumn get country => text().nullable()();
  TextColumn get region => text().nullable()();
  TextColumn get producer => text().nullable()();
  TextColumn get variety => text().map(const StringListConverter()).nullable()();
  TextColumn get altitude => text().map(const IntListConverter()).nullable()();
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
  TextColumn get id => text()();
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
  // Streamline/DYE2 UI Configuration
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

#### ShotRecords

```dart
class ShotRecords extends Table {
  TextColumn get id => text()();
  DateTimeColumn get timestamp => dateTime()();

  // Denormalized for indexed filtering — populated from workflow.context at write time
  TextColumn get profileTitle => text().nullable()();
  TextColumn get grinderId => text().nullable()();
  TextColumn get grinderModel => text().nullable()();
  TextColumn get beanBatchId => text().nullable()();
  TextColumn get coffeeName => text().nullable()();
  TextColumn get coffeeRoaster => text().nullable()();

  // Full objects as JSON columns
  TextColumn get workflow => text().map(const WorkflowConverter())();
  TextColumn get measurements => text().map(const MeasurementsConverter())();
  TextColumn get annotations => text().map(const ShotAnnotationsConverter()).nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

**Note:** `grinderId` and `beanBatchId` on ShotRecords are denormalized string columns — **not FK constraints**. They exist for indexed filtering only. The canonical references live inside the embedded `workflow.context`. Deleted entities leave dangling IDs here; the display strings (`grinderModel`, `coffeeName`, `coffeeRoaster`) preserve what was used.

#### Workflows

Unchanged from the persistence layer proposal, except `context` replaces `doseData`/`grinderData`/`coffeeData` in the JSON column.

#### ProfileRecords

Unchanged from the persistence layer proposal.

### Foreign Key Strategy

| Reference | Enforcement | Rationale |
|-----------|-------------|-----------|
| BeanBatch → Bean | **Hard FK** | Batch always belongs to a bean; cascade on bean delete |
| ShotRecords → Grinder | **None** (soft string column) | Don't cascade-delete shots when archiving grinders |
| ShotRecords → BeanBatch | **None** (soft string column) | Don't cascade-delete shots when archiving batches |

### Indexes

```dart
// Shot queries
@TableIndex(name: 'idx_shots_timestamp', columns: {#timestamp})
@TableIndex(name: 'idx_shots_grinder_id', columns: {#grinderId})
@TableIndex(name: 'idx_shots_grinder_model', columns: {#grinderModel})
@TableIndex(name: 'idx_shots_bean_batch_id', columns: {#beanBatchId})
@TableIndex(name: 'idx_shots_coffee_name', columns: {#coffeeName})
@TableIndex(name: 'idx_shots_coffee_roaster', columns: {#coffeeRoaster})
@TableIndex(name: 'idx_shots_profile', columns: {#profileTitle})

// Bean batch lookup by parent bean
@TableIndex(name: 'idx_bean_batches_bean', columns: {#beanId})

// Archived filtering
@TableIndex(name: 'idx_beans_archived', columns: {#archived})
@TableIndex(name: 'idx_grinders_archived', columns: {#archived})
```

### Lazy Measurements

The DAO provides two query depths:

```dart
/// List query — excludes measurements column. Returns ShotRecord with measurements = null.
Stream<List<ShotRecord>> watchShotSummaries({int limit = 50, int offset = 0});

/// Detail query — loads full record including measurements.
Future<ShotRecord> getShot(String id);
```

UI list views use `watchShotSummaries()`. Detail views use `getShot()`.

---

## API Surface

### Entity Endpoints

All entity list endpoints support `?archived=true` to include archived items.

| Endpoint | Purpose |
|----------|---------|
| `GET/POST /api/v1/beans` | List / create beans |
| `GET/PUT/DELETE /api/v1/beans/<id>` | Bean CRUD |
| `GET/POST /api/v1/beans/<id>/batches` | List / create batches for a bean |
| `GET/PUT/DELETE /api/v1/bean-batches/<id>` | BeanBatch CRUD |
| `GET/POST /api/v1/grinders` | List / create grinders |
| `GET/PUT/DELETE /api/v1/grinders/<id>` | Grinder CRUD |

### Shot Endpoints

```
GET /api/v1/shots?limit=50&offset=0&grinderId=uuid&coffeeRoaster=Sey
```

| Parameter | Type | Notes |
|-----------|------|-------|
| `limit` | int | Max items per page (default 50) |
| `offset` | int | Skip N items (default 0) |
| `orderBy` | string | `timestamp` (default, only option initially) |
| `order` | string | `asc` or `desc` (default `desc`) |
| `grinderId` | string | Filter by grinder entity ID |
| `grinderModel` | string | Filter by grinder model string |
| `beanBatchId` | string | Filter by bean batch entity ID |
| `coffeeName` | string | Filter by coffee name string |
| `coffeeRoaster` | string | Filter by coffee roaster string |
| `profileTitle` | string | Filter by profile title |

Shot list responses **exclude measurements** (lazy loading). Full record at `GET /api/v1/shots/<id>`.

Response:
```json
{
  "items": [ ... ],
  "total": 342,
  "limit": 50,
  "offset": 0
}
```

### Modified Endpoints

| Endpoint | What Changes |
|----------|-------------|
| `GET/PUT /api/v1/workflow` | `doseData`, `grinderData`, `coffeeData` replaced by `context` (WorkflowContext). Other fields unchanged. |
| `GET /api/v1/shots/<id>` | `shotNotes` and `metadata` replaced by `annotations`. Full measurements included. |
| `PUT /api/v1/shots/<id>` | Accepts `annotations` and `workflow` for partial update (deep merge). |

### Skin Complexity Tiers

#### Tier 1: Minimal (dose + profile only)

Endpoints: `GET/PUT /api/v1/workflow` (context.targetDoseWeight, context.targetYield, profile), machine state, latest shot.

```json
PUT /api/v1/workflow
{
  "context": { "targetDoseWeight": 18.0, "targetYield": 36.0 },
  "profile": { ... }
}
```

#### Tier 2: Standard (+ grinder & coffee strings)

Adds display strings to workflow. No entity management — user types grinder/coffee names.

```json
PUT /api/v1/workflow
{
  "context": {
    "grinderModel": "Niche Zero",
    "grinderSetting": "18.5",
    "coffeeName": "La Esperanza",
    "coffeeRoaster": "Sey",
    "targetDoseWeight": 18.0,
    "targetYield": 36.0,
    "finalBeverageType": "espresso"
  }
}
```

#### Tier 3: Full (entity management + annotations)

Streamline/DYE2 plugin manages entity library via API, sets entity IDs on workflow, records post-shot annotations.

```json
PUT /api/v1/workflow
{
  "context": {
    "grinderId": "uuid-abc",
    "grinderModel": "Niche Zero",
    "grinderSetting": "18.5",
    "beanBatchId": "uuid-def",
    "coffeeName": "La Esperanza",
    "coffeeRoaster": "Sey",
    "targetDoseWeight": 18.0,
    "targetYield": 36.0,
    "finalBeverageType": "espresso"
  }
}
```

---

## Plugin Data Channel

### Contract

Plugins communicate additional data through `extras` on WorkflowContext and ShotAnnotations. The core app guarantees:

1. **Serialization** — `extras` is serialized to JSON. All JSON-safe types preserved.
2. **Deep merge on update** — `PUT` endpoints deep-merge `extras`. A plugin can update its namespace without overwriting others.
3. **Namespace convention** — Plugins namespace under a key matching their plugin ID (e.g., `extras.equipmentTracker`).
4. **Opaqueness** — The core app never reads, validates, or indexes `extras` contents.

### What Lives in Extras

| Feature | Channel | Notes |
|---------|---------|-------|
| Commercial blend composition | `Bean.extras.blendComponents` | `[{description, percentage?, beanId?}, ...]` — plugin-managed |
| Equipment references | `context.extras` | Plugin tracks baskets, portafilters, tampers |
| Water profile references | `context.extras` | Plugin tracks water chemistry |
| Shot prep techniques | `context.extras` | Distribution, tamping, RDT, slow feeding |
| Tasting breakdowns | `annotations.extras` | Quality/intensity/notes per attribute |
| Photo attachments | `annotations.extras` | File paths; base64 only for import/export |
| Beverage details | `annotations.extras` | Added liquid type/weight/temperature |
| People overrides | `annotations.extras` | Per-shot barista/drinker if different from workflow defaults |

### Querying Plugin Data in Extras

Plugin data stored in `extras` is searchable via SQLite JSON functions. Since `extras` lives inside the `workflow` and `annotations` JSON columns on ShotRecords, queries use `json_extract()`:

```sql
-- Shots where Streamline/DYE2 plugin set a manual blend
SELECT * FROM shot_records
WHERE json_extract(workflow, '$.context.extras.dye2.manualBlend') IS NOT NULL;

-- Shots where Streamline/DYE2 plugin recorded acidity quality > 7
SELECT * FROM shot_records
WHERE json_extract(annotations, '$.extras.dye2.tasting.acidity.quality') > 7.0;
```

Drift supports this via custom expressions. **Tradeoffs:**
- **Not indexed** — each query scans the JSON column (no index on JSON paths)
- **Adequate at scale** — for a personal espresso journal (few thousand shots), full-scan JSON queries are fast enough
- **Promotion path** — if a specific extras query becomes frequent enough to need indexing, promote it to a denormalized column on ShotRecords in a future schema version (same pattern used for `grinderId`, `coffeeName`, etc.)

This means plugins can query their own data in extras without core schema changes, and the core app can promote high-traffic query patterns to indexed columns as usage patterns emerge.

### Plugin Storage

The current plugin KV store (`HiveStoreService`) provides flat key-value storage per plugin namespace. For an equipment/water tracking plugin with dozens of entities, this is adequate — store collections as JSON blobs, filter in JS.

**Future enhancement (separate proposal):** If plugin entity management needs relational queries, a richer plugin storage API would be the next step. Not needed initially.

---

## DE1 Legacy Field Mapping

| WorkflowContext Field | DE1 / .shot File Name |
|---|---|
| `coffeeRoaster` | `bean_brand` |
| `coffeeName` | `bean_type` |
| `grinderModel` | `grinder_model` |
| `grinderSetting` | `grinder_setting` |
| `targetDoseWeight` | `grinder_dose_weight` |
| `baristaName` | `my_name` |
| `drinkerName` | `drinker_name` |
| `finalBeverageType` | `final_beverage_type` |

| ShotAnnotations Field | DE1 / .shot File Name |
|---|---|
| `actualDoseWeight` | `grinder_dose_weight` (actual takes precedence) |
| `actualYield` | `drink_weight` |
| `drinkTds` | `drink_tds` |
| `drinkEy` | `drink_ey` |
| `enjoyment` | `enjoyment` (multiply by 10 for 0-100 scale) |
| `espressoNotes` | `espresso_notes` |

### Visualizer Compatibility

| Visualizer Field | Source |
|---|---|
| `bean_brand` | `WorkflowContext.coffeeRoaster` |
| `bean_type` | `WorkflowContext.coffeeName` |
| `grinder_model` | `WorkflowContext.grinderModel` |
| `grinder_setting` | `WorkflowContext.grinderSetting` |
| `bean_weight` | `WorkflowContext.targetDoseWeight` |
| `drink_weight` | `ShotAnnotations.actualYield` |
| `drink_tds` | `ShotAnnotations.drinkTds` |
| `drink_ey` | `ShotAnnotations.drinkEy` |
| `espresso_enjoyment` | `ShotAnnotations.enjoyment * 10` |
| `espresso_notes` | `ShotAnnotations.espressoNotes` |
| `barista` | `WorkflowContext.baristaName` |

No adapter layer needed. The display strings on WorkflowContext are the Visualizer fields.

---

## Data Migration

### Legacy → New Schema

One-time migration on first Drift launch.

| Source | Destination |
|---|---|
| Shot JSON files | `ShotRecords` table |
| Current workflow JSON | `Workflows` table |
| Hive profile records | `ProfileRecords` table |

#### Shot Field Mapping

| Old Shot Field | New Location |
|---|---|
| `id`, `timestamp` | Direct mapping |
| `workflow.doseData.doseIn` | `workflow.context.targetDoseWeight` |
| `workflow.doseData.doseOut` | `workflow.context.targetYield` |
| `workflow.grinderData.setting` | `workflow.context.grinderSetting` |
| `workflow.grinderData.manufacturer` + `.model` | `workflow.context.grinderModel` (+ denormalized column) |
| `workflow.coffeeData.roaster` | `workflow.context.coffeeRoaster` (+ denormalized column) |
| `workflow.coffeeData.name` | `workflow.context.coffeeName` (+ denormalized column) |
| `workflow.profile`, `.steamSettings`, etc. | Unchanged, alongside new `context` |
| `measurements` | Direct mapping |
| `shotNotes` | `annotations.espressoNotes` |
| `metadata` | `annotations.extras` (if non-null) |

Entity IDs (`grinderId`, `beanBatchId`) are null on migrated shots. No entity extraction from shot history — users build their entity library going forward via skins. The Beans, BeanBatches, and Grinders tables start empty.

---

## Persistence Layer Updates

The persistence layer proposal (`persistence-layer-proposal.md`) remains the reference for Drift architecture patterns. Changes:

| Persistence Proposal Section | Status |
|---|---|
| Two-layer model architecture (2.1) | **Unchanged** |
| Directory structure (2.2) | **Simplified** — no `equipment_tables.dart`, `water_tables.dart`, junction tables, or corresponding DAOs/mappers |
| Bean tables (3.1) | **Kept** — Beans + BeanBatches as defined in full proposal |
| Grinder table (3.1) | **Kept** — merged with Streamline/DYE2 config fields |
| Equipment/Water tables (3.1) | **Removed** — deferred to plugin |
| Shot table (3.2) | **Simplified** — denormalized string + ID columns instead of only FK columns; no junction tables |
| Junction tables (3.3) | **Removed** — ShotBeanBatches, ShotEquipment eliminated |
| Storage service interfaces (5.2) | **Reduced** — `BeanStorageService`, `GrinderStorageService` kept; `EquipmentStorageService`, `WaterStorageService` removed |
| Foreign key strategy (8) | **Simplified** — hard FK only for BeanBatch → Bean; soft refs for shots |
| Migration (7) | **Simplified** — no entity extraction from shot history |
| Everything else | **Unchanged** |

---

## Implementation Scope

### What's Built (Core App)

| Component | New Files | Notes |
|---|---|---|
| `Bean`, `BeanBatch` domain models | 1-2 | `lib/src/models/data/bean.dart` |
| `Grinder` domain model | 1 | `lib/src/models/data/grinder.dart` |
| `WorkflowContext` domain model | 1 | `lib/src/models/data/workflow_context.dart` |
| `ShotAnnotations` domain model | 1 | `lib/src/models/data/shot_annotations.dart` |
| Modified `Workflow` | 0 | Remove DoseData/GrinderData/CoffeeData, add context |
| Modified `ShotRecord` | 0 | annotations replaces metadata + shotNotes |
| Drift tables | ~3 | `bean_tables.dart`, `grinder_tables.dart`, `shot_tables.dart` (+ existing workflow/profile) |
| DAOs | ~3 | `bean_dao.dart`, `grinder_dao.dart`, `shot_dao.dart` |
| Mappers | ~3 | `bean_mapper.dart`, `grinder_mapper.dart`, `shot_mapper.dart` |
| Type converters | ~5 | WorkflowConverter, ShotAnnotationsConverter, etc. |
| Storage service interfaces | ~3 | `BeanStorageService`, `GrinderStorageService`, extended `StorageService` |
| Drift implementations | ~3 | `DriftBeanStorage`, `DriftGrinderStorage`, `DriftStorageService` |
| API handlers | ~3 | Bean/BeanBatch CRUD, Grinder CRUD, shot filtering |
| Migration logic | 1 | JSON/Hive → SQLite one-time import |
| **Total** | **~25 new files** | Plus modifications to ~5-8 existing files |

### What's Deferred (Plugin Territory)

| Feature | Plugin Approach |
|---|---|
| Equipment tracking | Plugin KV store + `context.extras` |
| Water chemistry profiles | Plugin KV store + `context.extras` |
| Tasting attribute breakdowns | `annotations.extras` |
| Photo attachments | `annotations.extras` (file paths) |
| Beverage details (added liquid) | `annotations.extras` |
| Shot prep techniques | `context.extras` |
| Per-shot people overrides | `annotations.extras` |
| Commercial blend components | `Bean.extras` |
| User-created blends (multi-batch per shot) | Plugin — single batch per shot in core |
| Beanconqueror import/export | Plugin |
| Enhanced plugin storage API | Separate proposal if needed |

---

## Summary of Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Architecture | Core = data layer, skins = UI layer | Shared entity library; no management screens in core app |
| Bean/BeanBatch | Core entity (Drift + API), full field set | High-value entities; avoid string-to-entity migration later; skins manage UI |
| Grinder | Core entity (merged model + Streamline/DYE2 config) | First-party Streamline/DYE2 requirement (#62); model info + UI config in one entity |
| Equipment | Deferred to plugin | Not earning its keep as a typed entity; type-specific data all in extras |
| Water | Deferred to plugin | Power-user feature; casual users don't track water |
| Entity references on shots | ID + display strings (no snapshots) | IDs for linking/querying, strings for display/history/compat. No snapshot objects. |
| Entity FK constraints | Soft (nullable, no FK on shots) | Don't cascade-delete shots when archiving entities |
| BeanBatch → Bean FK | Hard FK with cascade | Batch always belongs to a bean |
| Pre-shot/post-shot naming | `target*` vs `actual*` prefixes | No ambiguity, no fallback logic |
| Dose-yield ratio | Not stored (derived) | Eliminates three-way coupling |
| Enjoyment scale | 0.0–10.0 | Single intuitive scale; multiply by 10 for export |
| Tasting attributes | Plugin via annotations.extras | Power-user territory |
| Photo attachments | Deferred to plugin | Needs proper design later |
| Blends (commercial) | `Bean.extras.blendComponents` | Plugin-managed JSON list; convention documented; not worth a typed class in core |
| Blends (user-created) | Plugin | Single batch per shot in core |
| Shot filtering | Denormalized ID + string columns | Both entity-based and string-based queries supported |
| Measurement lazy loading | Nullable measurements on ShotRecord | List queries exclude; detail queries include |
| Extras | On WorkflowContext + ShotAnnotations | Plugin data channels; namespaced, deep-merged, opaque |
| Drift tables | 6 (down from 11) | Beans, BeanBatches, Grinders, ShotRecords, Workflows, ProfileRecords |
| Plugin storage | Current KV store initially | Adequate for dozens of entities |
| API break | Clean break on v1 | Developer preview |
| Batch weight tracking | Core persistence concern | Must happen atomically with shot storage |
