# Design: Drop Legacy Workflow Fields (v0.5.2)

## Context

`WorkflowContext` was introduced to replace three legacy data classes (`DoseData`, `GrinderData`, `CoffeeData`) that were embedded in `Workflow`. Both representations were written to JSON and kept in sync during the migration period (v0.5.1). v0.5.2 drops the legacy fields entirely.

**Key constraint:** Shots already stored in the database (and exports/archives) may contain only legacy fields with no `context`. These must be migrated on read — not left as context-less records.

## What Changes

### Model layer

**`Workflow.fromJson()`** — keep reading `doseData`, `grinderData`, `coffeeData` from JSON *solely* to synthesize `WorkflowContext`. This is the migration-on-read path. After context is built, the legacy fields are discarded (not stored on the object).

**`Workflow.toJson()`** — stop emitting `doseData`, `grinderData`, `coffeeData`.

**`Workflow` class** — remove:
- Private fields `_doseData`, `_grinderData`, `_coffeeData`
- Deprecated getters `doseData`, `grinderData`, `coffeeData`
- Constructor params `doseData`, `grinderData`, `coffeeData`
- `copyWith` params `doseData`, `grinderData`, `coffeeData`

**`DoseData`, `GrinderData`, `CoffeeData`** — delete entirely.

**`WorkflowContext.fromLegacyJson()`** — inline into `Workflow.fromJson()` and remove.

### Controller layer

**`WorkflowController.setWorkflow()`** — remove the null-context backfill block. After this change, any workflow coming from JSON will always have `context` (synthesized in `fromJson`), so the backfill is unreachable.

**`WorkflowController.updateWorkflow()`** — remove deprecated `doseData`, `grinderData`, `coffeeData` params.

**`PersistenceController.grinderOptions()`** — rewritten to return `List<({String setting, String? model})>`, sourcing data from `shot.workflow.context?.grinderSetting` and `shot.workflow.context?.grinderModel`.

**`PersistenceController.coffeeOptions()`** — rewritten to return `List<({String name, String? roaster})>`, sourcing data from `shot.workflow.context?.coffeeName` and `shot.workflow.context?.coffeeRoaster`.

### UI

**`profile_tile.dart`** — update autocomplete `optionsBuilder` lambdas to use the new record tuple types. Field names (`setting`, `model`, `name`, `roaster`) are unchanged so changes are minimal.

### API + docs

**`rest_v1.yml`** — remove `doseData`, `grinderData`, `coffeeData` from the `PUT /api/v1/workflow` request schema. Add a note that `context` is the only accepted format as of v0.5.2.

## What Does NOT Change

- `Workflow.fromJson()` read-path for legacy fields (migration-on-read must be preserved)
- `WorkflowContext` itself — no changes to its fields or serialization
- Database schema — no migration needed; stored JSON is migrated on read

## Tests

- **Keep** at least one test in `shot_importer_test.dart` (or a new unit test) covering migration-on-read: a workflow JSON with only legacy fields and no `context` deserializes to a `Workflow` with a valid `WorkflowContext`.
- **Remove** `WorkflowContext.fromLegacyJson()` tests from `workflow_context_test.dart`.
- **Update** `workflow_export_section_test.dart` to remove assertions checking for `doseData` in serialized output.
- **Update** any `shot_importer_test.dart` cases that construct workflows with legacy fields to use `context` instead, except the one migration-on-read case above.

## Files Affected

| File | Change |
|------|--------|
| `lib/src/models/data/workflow.dart` | Remove classes + fields + getters + params; update fromJson/toJson |
| `lib/src/models/data/workflow_context.dart` | Remove `fromLegacyJson()` |
| `lib/src/controllers/workflow_controller.dart` | Remove backfill + deprecated params |
| `lib/src/controllers/persistence_controller.dart` | Rewrite `grinderOptions()`/`coffeeOptions()` |
| `lib/src/home_feature/tiles/profile_tile.dart` | Update autocomplete to use record tuples |
| `assets/api/rest_v1.yml` | Remove legacy field docs from workflow PUT |
| `test/shot_importer_test.dart` | Update/remove legacy-field test cases; keep migration-on-read test |
| `test/data_export/workflow_export_section_test.dart` | Remove `doseData` output assertions |
| `test/models/workflow_context_test.dart` | Remove `fromLegacyJson` tests |
