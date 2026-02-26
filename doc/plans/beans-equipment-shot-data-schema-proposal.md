# ReaPrime Coffee Equipment & Metadata Schema Proposal

**Version:** Draft 1.0  
**Date:** 2026-02-26  
**Context:** Based on Beanconqueror analysis, DE1/DYE legacy field review, and GitHub discussions #61–#66

---

## Design Principles

1. **First-class entities** — Beans, Grinders, Equipment, Water each have their own tables/stores with UUIDs and full CRUD lifecycle
2. **Typed core + extras map** — Every entity and context object has strongly-typed fields for known properties, plus a `Map<String, dynamic> extras` for future/custom fields
3. **Reference + snapshot** — Workflows and shot records store entity IDs for live resolution *and* snapshot key fields for historical accuracy
4. **Better names internally** — Use clear, modern field names (e.g., `roaster` not `bean_brand`); handle DE1 legacy name mapping only at the serialization/import boundary
5. **Espresso-first, extensible** — No preparation method abstraction now, but entity shapes don't preclude adding one later

---

## Entity Relationship Overview

```
┌─────────┐       ┌─────────────┐
│  Bean    │ 1───* │  BeanBatch  │
└─────────┘       └──────┬──────┘
                         │ ref
┌─────────┐              │
│ Grinder │──ref─┐       │
└─────────┘      │       │
                 ▼       ▼
┌─────────┐   ┌──────────────────┐     ┌─────────────────┐
│  Water  │──▶│    Workflow       │────▶│   ShotRecord     │
└─────────┘   │  .context {      │     │  .annotations {  │
              │    grinder: ref  │     │    extraction     │
┌─────────┐   │    beanBatch:ref │     │    beverage       │
│Equipment│──▶│    water: ref    │     │    tasting        │
│ (generic)│  │    equipment:refs│     │    people          │
└─────────┘   │    shotPrep      │     │  }               │
              │  }               │     │  .extras: Map     │
              │  .extras: Map    │     └─────────────────┘
              └──────────────────┘
```

---

## 1. Bean (Coffee Identity)

The coffee itself — origin, producer, variety. Immutable identity; batches track individual bags.

| Field | Type | Notes | DE1 Alias |
|-------|------|-------|-----------|
| `id` | UUID | Primary key | — |
| `roaster` | String | Company/brand that roasted it | `bean_brand` |
| `name` | String | Coffee name/blend name | `bean_type` |
| `species` | String? | Arabica, Robusta, Liberica | *(new)* |
| `country` | String? | Country of origin | `bean_country` |
| `region` | String? | Region/state/province | `bean_region` |
| `producer` | String? | Farm/estate/cooperative | `bean_producer` |
| `variety` | List\<String\>? | Geisha, SL28, Pink Bourbon, etc. | `bean_variety` |
| `altitude` | String? | Elevation (e.g., "1800-2000 masl") | `bean_altitude` |
| `processing` | String? | Washed, Natural, Honey, Anaerobic, etc. | `bean_processing` |
| `notes` | String? | General notes about this coffee | `bean_notes` |
| `decaf` | bool | Default false | *(new, from BC)* |
| `archived` | bool | Soft delete / hide from active lists | *(new, from BC)* |
| `createdAt` | DateTime | | — |
| `updatedAt` | DateTime | | — |
| `extras` | Map\<String, dynamic\> | Future fields (density, SCA score, etc.) | — |

### Notes
- `variety` is a List because blends or multi-variety lots are common
- `species` separated from `variety` per apaperclip's clarification in #61
- Enrique's concern about renaming: handled at serialization boundary. Internal model uses `roaster`; DE1 .shot file export maps to `bean_brand`

---

## 2. BeanBatch (Specific Bag/Purchase)

A physical bag of a specific Bean. Tracks inventory, dates, and batch-specific attributes.

| Field | Type | Notes | DE1 Alias |
|-------|------|-------|-----------|
| `id` | UUID | Primary key | — |
| `beanId` | UUID | FK → Bean | — |
| `roastDate` | DateTime? | When this batch was roasted | `roast_date` |
| `roastLevel` | String? | Light, Medium, Dark, or numeric | `roast_level` |
| `harvestDate` | String? | Harvest season/year | `bean_harvest` |
| `qualityScore` | double? | SCA cupping score (0-100) | `bean_quality_score` |
| `price` | double? | Price paid | `bean_price` |
| `currency` | String? | ISO 4217 code (EUR, USD, etc.) | *(new, from BC)* |
| `weight` | double? | Bag weight in grams | *(new, from BC)* |
| `weightRemaining` | double? | Tracked, decremented per shot | *(new, from BC)* |
| `buyDate` | DateTime? | When purchased | *(new, from BC)* |
| `openDate` | DateTime? | When bag was first opened | `bean_open_date` |
| `bestBeforeDate` | DateTime? | Best by date | *(new, from BC)* |
| `freezeDate` | DateTime? | When frozen | `bean_freeze_date` |
| `unfreezeDate` | DateTime? | When thawed | `bean_unfreeze_date` |
| `frozen` | bool | Currently frozen? | *(new)* |
| `archived` | bool | Bag finished / hidden | — |
| `notes` | String? | Batch-specific notes | — |
| `createdAt` | DateTime | | — |
| `updatedAt` | DateTime | | — |
| `extras` | Map\<String, dynamic\> | Future fields (CO2e, FOB price, etc.) | — |

### Notes
- Unlike BC's flat model, the Bean↔BeanBatch split means buying the same coffee twice creates two BeanBatch entries pointing to the same Bean. This enables "show me all shots with Ethiopian Yirgacheffe regardless of which bag."
- `weightRemaining` decremented by `grinder_dose_weight` after each shot (optional feature)
- Frozen bean portioning (à la BC 8.x) can be modeled as child BeanBatch entries with a `parentBatchId` in extras if needed later

---

## 3. Grinder

Rich entity with model info and UI configuration per Enrique's DYE2 requirements (#62).

| Field | Type | Notes | DE1 Alias |
|-------|------|-------|-----------|
| `id` | UUID | Primary key | — |
| `model` | String | Grinder make/model | `grinder_model` |
| `burrs` | String? | Burr set description (e.g., "98mm SSP Multipurpose") | `grinder_burrs` |
| `burrSize` | double? | Burr diameter in mm | *(new)* |
| `burrType` | String? | Flat, Conical, Ghost, Hybrid | *(new)* |
| `notes` | String? | | — |
| `archived` | bool | | — |
| **UI Configuration (DYE2)** | | | |
| `settingType` | enum | `numeric` or `values` | *(new, from #62)* |
| `settingValues` | List\<String\>? | When settingType=values, valid positions | *(new, from #62)* |
| `settingSmallStep` | double? | +/- button increment | *(new, from #62)* |
| `settingBigStep` | double? | ++/-- button increment | *(new, from #62)* |
| `rpmSmallStep` | double? | RPM +/- increment | *(new, from #62)* |
| `rpmBigStep` | double? | RPM ++/-- increment | *(new, from #62)* |
| `createdAt` | DateTime | | — |
| `updatedAt` | DateTime | | — |
| `extras` | Map\<String, dynamic\> | Future fields | — |

### Notes
- `settingType` drives UI behavior: `numeric` shows +/- with configurable steps; `values` shows a picker with the defined positions
- Per-shot grinder *settings* (the actual grind size, RPM used) live on the WorkflowContext, not here
- "Slow feeding" (from your question in #62) belongs in WorkflowContext.shotPrep or extras, not on the grinder entity
- BC's Mill entity is just name + notes + archived. This is substantially richer.

---

## 4. Equipment (Generic Accessories)

Covers everything that isn't a grinder or the machine itself. Type-discriminated.

| Field | Type | Notes |
|-------|------|-------|
| `id` | UUID | Primary key |
| `type` | enum | See EquipmentType below |
| `name` | String | User-facing name (e.g., "IMS Nanotech 18g") |
| `brand` | String? | Manufacturer |
| `model` | String? | Model name/number |
| `notes` | String? | |
| `archived` | bool | |
| `createdAt` | DateTime | |
| `updatedAt` | DateTime | |
| `extras` | Map\<String, dynamic\> | Type-specific details |

### EquipmentType Enum

```dart
enum EquipmentType {
  portafilter,
  basket,
  filterTop,       // paper/mesh filter on top (for e.g. Decent basket)
  filterBottom,    // paper/mesh filter below puck
  tamper,
  distributionTool,
  wdtTool,
  scale,
  refractometer,
  other,
}
```

### Notes
- The espresso machine itself is already known via BLE connection and not stored here
- `extras` allows type-specific data: a basket might have `{diameter: 58.5, capacity: "18g"}`, a refractometer might have `{model: "DiFluid R2"}`
- Techniques (tamping technique, distribution technique, RDT) are per-shot actions, so they belong in WorkflowContext, not on the equipment entity

---

## 5. Water

Full mineral profile matching Beanconqueror's level of detail.

| Field | Type | Notes |
|-------|------|-------|
| `id` | UUID | Primary key |
| `name` | String | e.g., "Third Wave Water Classic", "Home Tap" |
| `generalHardness` | double? | GH (°dH or ppm, note unit) |
| `carbonateHardness` | double? | KH (°dH or ppm) |
| `calcium` | double? | Ca (mg/L) |
| `magnesium` | double? | Mg (mg/L) |
| `sodium` | double? | Na (mg/L) |
| `potassium` | double? | K (mg/L) |
| `tds` | double? | Total Dissolved Solids (ppm) |
| `ph` | double? | pH value |
| `notes` | String? | Recipe instructions, source info |
| `archived` | bool | |
| `createdAt` | DateTime | |
| `updatedAt` | DateTime | |
| `extras` | Map\<String, dynamic\> | Future fields (chloride, sulfate, bicarbonate, etc.) |

### Notes
- Users who don't care about water chemistry simply create one entry called "Tap Water" with no details filled in
- Units should be documented and consistent. Suggest mg/L (ppm) for minerals, °dH for hardness
- BC also stores named water presets (Pure Coffee Water, Empirical Water) — the name field handles this

---

## 6. WorkflowContext (Pre-Shot Data on Workflow)

Nested object on the existing Workflow entity. Contains references to entities plus per-shot preparation parameters.

```dart
class WorkflowContext {
  // === Entity References (live-resolvable) ===
  String? grinderId;
  String? beanBatchId;
  String? waterId;
  List<String>? equipmentIds;  // multiple accessories per shot

  // === Snapshots (historical accuracy) ===
  GrinderSnapshot? grinderSnapshot;
  BeanSnapshot? beanSnapshot;

  // === Per-Shot Grinder Settings ===
  String? grinderSetting;     // DE1: grinder_setting (String to support stepped/click/named positions)
  double? grinderRpm;         // grinder_rpm
  double? doseWeight;         // DE1: grinder_dose_weight

  // === Target / Intent ===
  double? targetYield;        // target beverage weight in grams (pre-shot intent)
  double? targetDoseYieldRatio; // ratio of output to input, e.g., 2.0 means 1:2 (18g in → 36g out)

  // === Shot Preparation Technique ===
  String? distributionTechnique;
  String? tampingTechnique;
  bool? rdt;                   // Ross Droplet Technique
  bool? slowFeeding;
  String? puckPrepNotes;

  // === Equipment Snapshot (which accessories used) ===
  String? portafilterModel;    // snapshot from equipment
  String? basketName;          // snapshot from equipment
  String? filterTop;           // snapshot from equipment
  String? filterBottom;        // snapshot from equipment
  String? tamperName;          // snapshot from equipment
  String? distributionToolName;// snapshot from equipment

  // === Extras ===
  Map<String, dynamic>? extras;
}
```

### Snapshot Objects

```dart
class GrinderSnapshot {
  String model;
  String? burrs;
}

class BeanSnapshot {
  String roaster;        // from Bean
  String name;           // from Bean
  String? roastLevel;    // from BeanBatch
  DateTime? roastDate;   // from BeanBatch
}
```

### Notes
- `grinderSetting` is a **String**, not a number. Stepped grinders use click notation ("28 clicks", "7.2.1"), some use letters, and even numeric grinders can have decimal formats that vary. The Grinder entity's `settingType` and `settingValues` define how the UI interprets and presents this value.
- `targetYield` is the pre-shot *intent* ("I want 36g out"). The post-shot *actual* `drinkWeight` lives in ShotAnnotations. Comparing these is useful for tracking how consistently you hit your target.
- `targetDoseYieldRatio` is the output-to-input multiplier as a double — a value of `2.0` means "1:2" (e.g., 18g dose → 36g yield). Using a double avoids string parsing and makes calculation trivial: `targetYield = doseWeight * targetDoseYieldRatio`. The UI can display it as "1:2" for readability.
- `doseWeight` lives here (pre-shot) because it's a setting you decide before pulling the shot. It also appears on the ShotRecord as `grinder_dose_weight` for DE1 compatibility — same value, just accessible from both sides.
- Equipment snapshots are simple name strings. We don't need the full Equipment object frozen in time — just enough to know what was used.
- Techniques (distribution, tamping, RDT, slow feeding) are per-shot actions. These are what apaperclip requested a home for in #63.

---

## 7. ShotRecord Annotations (Post-Shot Data)

Extended typed fields on the existing ShotRecord entity. These are user-entered after the shot.

### 7a. Extraction

| Field | Type | Notes | DE1 Alias |
|-------|------|-------|-----------|
| `doseWeight` | double? | Dry coffee in (grams) | `grinder_dose_weight` |
| `drinkWeight` | double? | Beverage out (grams) | `drink_weight` |
| `drinkTds` | double? | Total Dissolved Solids (%) | `drink_tds` |
| `drinkEy` | double? | Extraction Yield (%) | `drink_ey` |
| `calcEyFromTds` | bool? | Whether EY was calculated from TDS | `calc_ey_from_tds` |
| `drinkBrix` | double? | Brix reading | `drink_brix` |
| `refractometerModel` | String? | Which refractometer used | `refractometer_model` |
| `refractometerTemperature` | double? | Sample temp at measurement | `refractometer_temperature` |
| `refractometerTechnique` | String? | Measurement method | `refractometer_technique` |
| `pourQuality` | String? | Visual assessment of pour | `pour_quality` |

### 7b. People

| Field | Type | Notes | DE1 Alias |
|-------|------|-------|-----------|
| `baristaName` | String? | Who made it | `my_name` |
| `drinkerName` | String? | Who drank it | `drinker_name` |

### 7c. Beverage

| Field | Type | Notes | DE1 Alias |
|-------|------|-------|-----------|
| `beverageType` | String? | From profile (espresso, lungo, etc.) | `beverage_type` |
| `finalBeverageType` | String? | User-defined drink (cappuccino, latte, americano) | `final_beverage_type` |
| `addedLiquidType` | String? | Milk, water, oat milk, etc. | `added_liquid_type` |
| `addedLiquidWeight` | double? | Grams | `added_liquid_weight` |
| `addedLiquidTemperature` | double? | °C | `added_liquid_temperature` |
| `addedLiquidQuality` | String? | Steaming quality assessment | `added_liquid_quality` |

**Note from Enrique (#66):** `finalBeverageType` is critical for DYE2 auto-favorites. Should map to GHC machine functions (espresso, steam, hot water). Consider making this an enum or at least maintaining a recommended values list.

### 7d. Tasting

Structured tasting notes with quality/intensity/notes triples per attribute.

```dart
class TastingAttribute {
  double? quality;     // 0-10 or 0-100 scale
  double? intensity;   // 0-10 or 0-100 scale
  String? notes;       // free text
}

class TastingAnnotation {
  double? enjoyment;           // DE1: enjoyment (overall score)
  List<String>? scentone;      // flavour wheel descriptors (DE1: scentone)

  TastingAttribute? aroma;
  TastingAttribute? acidity;
  TastingAttribute? sweetness;
  TastingAttribute? body;
  TastingAttribute? bitterness;
  TastingAttribute? astringency;
  TastingAttribute? finish;
  TastingAttribute? flavour;
  TastingAttribute? overall;
}
```

### 7e. Notes & Media

| Field | Type | Notes | DE1 Alias |
|-------|------|-------|-----------|
| `espressoNotes` | String? | General shot notes | `espresso_notes` |
| `photoAttachments` | List\<String\>? | File paths / URIs to photos (stored on disk, not inline). Base64 encoding used only for import/export serialization, not at rest. | *(new)* |

### 7f. Top-level ShotRecord Annotations Object

```dart
class ShotAnnotations {
  // Extraction
  double? doseWeight;
  double? drinkWeight;
  double? drinkTds;
  double? drinkEy;
  bool? calcEyFromTds;
  double? drinkBrix;
  String? refractometerModel;
  double? refractometerTemperature;
  String? refractometerTechnique;
  String? pourQuality;

  // People
  String? baristaName;
  String? drinkerName;

  // Beverage
  String? beverageType;
  String? finalBeverageType;
  String? addedLiquidType;
  double? addedLiquidWeight;
  double? addedLiquidTemperature;
  String? addedLiquidQuality;

  // Tasting
  TastingAnnotation? tasting;

  // Notes & Media
  String? espressoNotes;
  List<String>? photoAttachments; // file paths at rest; base64 only for import/export

  // Extras
  Map<String, dynamic>? extras;
}
```

---

## 11. DE1 Legacy Field Mapping

For import/export compatibility with .shot files and the Tcl app history.

| ReaPrime Field | DE1 / .shot File Name |
|---|---|
| `Bean.roaster` | `bean_brand` |
| `Bean.name` | `bean_type` |
| `Bean.notes` | `bean_notes` |
| `BeanBatch.roastDate` | `roast_date` |
| `BeanBatch.roastLevel` | `roast_level` |
| `Grinder.model` | `grinder_model` |
| `WorkflowContext.grinderSetting` | `grinder_setting` |
| `WorkflowContext.doseWeight` | `grinder_dose_weight` |
| `ShotAnnotations.drinkWeight` | `drink_weight` |
| `ShotAnnotations.drinkTds` | `drink_tds` |
| `ShotAnnotations.drinkEy` | `drink_ey` |
| `ShotAnnotations.espressoNotes` | `espresso_notes` |
| `ShotAnnotations.beverageType` | `beverage_type` |
| `ShotAnnotations.enjoyment` → `tasting.enjoyment` | `enjoyment` |
| `ShotAnnotations.baristaName` | `my_name` |
| `ShotAnnotations.drinkerName` | `drinker_name` |
| `ShotAnnotations.scentone` → `tasting.scentone` | `scentone` |

---

## 9. Visualizer Cross-Reference

[Visualizer](https://visualizer.coffee) (by Miha Rekar) is the primary cloud platform for Decent Espresso shot sharing and analysis (~7,000 users, 3.6M+ shots). ReaPrime already uploads shots to Visualizer, so schema compatibility is important.

### Visualizer's Shot Export Schema (CSV meta fields)

From the profile CSV export format, Visualizer stores these metadata fields per shot:

| Visualizer Field | ReaPrime Mapping | Notes |
|---|---|---|
| `Name` | Profile name (already on ShotRecord) | Shot profile title |
| `Date` | ShotRecord timestamp | ISO8601 |
| `Roasting Date` | `BeanSnapshot.roastDate` / `BeanBatch.roastDate` | |
| `Roastery` | `BeanSnapshot.roaster` / `Bean.roaster` | DE1: `bean_brand` |
| `Beans` | `BeanSnapshot.name` / `Bean.name` | DE1: `bean_type` |
| `Description` | Free text — bean notes | Maps to `Bean.notes` or extras |
| `Roast Color` | `BeanSnapshot.roastLevel` / `BeanBatch.roastLevel` | DE1: `roast_level` |
| `Operator` | `ShotAnnotations.baristaName` | DE1: `my_name` |
| `Grinder Brand` | `GrinderSnapshot.model` / `Grinder.model` | Often brand+model combined |
| `Grinder Model` | `GrinderSnapshot.model` / `Grinder.model` | Often same as Brand |
| `Grinder Setting` | `WorkflowContext.grinderSetting` | DE1: `grinder_setting` |
| `Weight` | `ShotAnnotations.drinkWeight` | DE1: `drink_weight` |
| `Tds` | `ShotAnnotations.drinkTds` | DE1: `drink_tds` |

### Visualizer's Coffee Management (Premium)

Visualizer recently added a two-level coffee management model similar to our Bean + BeanBatch:
- **Roasters** — the roasting company (maps to our `Bean.roaster`)
- **Coffee Bags** — specific bags with archiving support (maps to our `BeanBatch`)

This validates our two-level approach. Miha himself described the evolution: the original flat model (just roaster + bean name strings on each shot) was replaced with proper entities and bag-level tracking in the Premium tier.

### Visualizer's Custom Fields

Visualizer solved the "everyone wants different fields" problem with user-defined Custom Fields (Premium). This is analogous to our `extras` Map — both are escape hatches for per-user customization. Our approach is slightly more structured since the `extras` Map is per-entity rather than a flat custom fields list on shots.

### Key Insights from Visualizer for ReaPrime

1. **Grinder Brand vs Model split**: Visualizer has both `Grinder Brand` and `Grinder Model` as separate fields, but in practice users almost always set them to the same value (e.g., "DF64 SSP MP" for both). Our single `Grinder.model` field is cleaner. If a brand/model distinction is ever needed, it can go in `extras` or we add `Grinder.brand` later.

2. **The `Description` field**: Visualizer uses a free-text Description that often contains structured bean data (origin, variety, elevation, processing) as unstructured text. Our schema captures all of these as typed fields on Bean — a strict improvement. For Visualizer upload, we can compose this Description from our structured fields.

3. **Upload compatibility**: When uploading to Visualizer, ReaPrime needs to map its structured data back to Visualizer's flat field set. The snapshot fields (`GrinderSnapshot`, `BeanSnapshot`) serve exactly this purpose — they contain the denormalized data that Visualizer expects.

4. **Loffee Labs Bean Base integration**: Visualizer recently added search against Loffee Labs' Bean Base (a community coffee database). Our Bean entity fields (roaster, name, country, region, variety, processing, elevation) are a superset of what Loffee Labs provides, making future integration straightforward.

5. **Time-series data format**: Visualizer's CSV uses `moment` rows with columns for elapsed, pressure, weight, flow_in, flow_out, and three temperature readings (boiler, in, basket). ReaPrime's existing ShotRecord time-series should map to this format for upload.

---

## 10. Beanconqueror Compatibility Notes (Future)

For future BC import/export support:

| BC Entity | ReaPrime Mapping | Migration Notes |
|---|---|---|
| BC Bean | Bean + BeanBatch | BC's flat bean splits into identity (Bean) + batch data (BeanBatch). Weight, dates, cost → BeanBatch. Origin, variety, roaster → Bean. |
| BC Mill | Grinder | BC Mill is minimal (name + notes). Import creates Grinder with just `model` = BC mill name. |
| BC Water | Water | Direct mapping. BC water fields are a subset of ours. |
| BC Preparation | *(no direct equivalent)* | BC preparation type can map to extras or a future PreparationMethod entity. |
| BC Brew | Workflow + ShotRecord | BC brew's pre-shot fields → WorkflowContext. BC brew's post-shot fields → ShotAnnotations. BC brew's graph data → ShotRecord time-series. |

Bean field mapping:

| BC Field | ReaPrime Field |
|---|---|
| `name` | `Bean.name` |
| `roaster` | `Bean.roaster` |
| `variety` | `Bean.variety` |
| `country` | `Bean.country` |
| `region` | `Bean.region` |
| `farm` | `Bean.producer` |
| `elevation` | `Bean.altitude` |
| `processing` | `Bean.processing` |
| `roast_range` | `BeanBatch.roastLevel` |
| `roastingDate` | `BeanBatch.roastDate` |
| `weight` | `BeanBatch.weight` |
| `cost` | `BeanBatch.price` |
| `openDate` | `BeanBatch.openDate` |
| `buyDate` | `BeanBatch.buyDate` |

---

## 12. Summary of Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Entity architecture | First-class with own tables | CRUD, lifecycle, independence from shots (#64 Enrique) |
| Bean model | Two-level Bean + BeanBatch | Same coffee, multiple bags. Correlation across purchases. |
| Grinder model | Rich entity with UI config | DYE2 needs setting_type/step sizes (#62 Enrique) |
| Equipment model | Generic typed entity | Type enum covers baskets, tampers, WDT, etc. |
| Water model | Full mineral profile | Match BC level; simple users ignore optional fields |
| Field flexibility | Typed core + extras Map | Queryable known fields + open extensibility |
| Naming | Modern names internally | DE1 aliases at serialization boundary only |
| Workflow integration | Nested context object | `workflow.context.grinder`, `.beans`, etc. |
| Shot annotations | Typed fields on ShotRecord | All post-shot data as explicit `ShotAnnotations` object |
| Historical accuracy | Reference IDs + snapshots | Edit entity → change propagates. Snapshot preserves shot-time state. |
| Preparation method | Not needed now | Espresso-only; entity shape allows adding later |
| BC compatibility | Deferred, schema-compatible | Field superset enables future import/export |
| Visualizer compatibility | Schema-aligned | Snapshots provide flat fields needed for upload; CSV meta format maps cleanly |
