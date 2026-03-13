# Drop Legacy Workflow Fields Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove `DoseData`, `GrinderData`, and `CoffeeData` legacy classes from the `Workflow` model, preserving migration-on-read so stored shots with only legacy fields still deserialize correctly.

**Architecture:** The migration-on-read path lives entirely in `Workflow.fromJson()` — it reads `doseData`/`grinderData`/`coffeeData` from JSON and synthesizes a `WorkflowContext`, then discards the raw fields. Write path (`toJson`) stops emitting legacy fields. `WorkflowContext.fromLegacyJson()` is inlined into `Workflow.fromJson()` and removed. All other callers of the deprecated getters/params are updated to use `context` directly.

**Tech Stack:** Flutter/Dart, `flutter test`, `flutter analyze`

**Test Tiers:** Unit only. Per the tier selection guide, model/DAO logic → Unit: Yes, Integration: Rarely, MCP: No. No REST endpoints change behaviour and no multi-controller flows are affected, so integration and MCP tiers are not needed. `flutter analyze` is non-negotiable after every task.

**TDD note for a removal task:** The "RED" signal comes in two forms: (1) protection tests that PASS now and must continue to pass — these guard migration-on-read; (2) tests that reference deleted types/methods and will fail to compile or fail at runtime after removal — those are the expected RED for the removal steps. Always verify the correct failure mode before implementing the fix.

---

### Task 1: Add migration-on-read protection test

This test locks in the behavior we must not break: a workflow JSON with only legacy fields (no `context`) deserializes to a `Workflow` with a valid `WorkflowContext`. Run it first — it should PASS now and must still pass after all changes.

**Files:**
- Modify: `test/models/workflow_context_test.dart`

**Step 1: Add the migration-on-read test group**

At the bottom of `test/models/workflow_context_test.dart`, before the closing `}` of `main()`, add:

```dart
  group('Workflow.fromJson - migration-on-read', () {
    test('legacy-only JSON (no context) synthesizes WorkflowContext', () {
      final json = {
        'id': 'wf-1',
        'name': 'Legacy Workflow',
        'description': '',
        'profile': {
          'title': 'Test',
          'author': 'Test',
          'notes': '',
          'beverage_type': 'espresso',
          'steps': [],
          'tank_temperature': 0.0,
          'target_weight': 36.0,
          'target_volume': 0,
          'target_volume_count_start': 0,
          'legacy_profile_type': '',
          'type': 'advanced',
          'lang': 'en',
          'hidden': false,
          'reference_file': '',
          'changes_since_last_espresso': '',
          'version': '2',
        },
        'doseData': {'doseIn': 18.0, 'doseOut': 36.0},
        'grinderData': {'setting': '15', 'manufacturer': 'Niche', 'model': 'Zero'},
        'coffeeData': {'name': 'Gesha Village', 'roaster': 'Sey'},
        'steamSettings': {'targetTemperature': 150, 'duration': 50, 'flow': 0.8},
        'hotWaterData': {'targetTemperature': 75, 'duration': 30, 'volume': 50, 'flow': 10.0},
        'rinseData': {'targetTemperature': 90, 'duration': 10, 'flow': 6.0},
      };

      final workflow = Workflow.fromJson(json);

      expect(workflow.context, isNotNull);
      expect(workflow.context!.targetDoseWeight, 18.0);
      expect(workflow.context!.targetYield, 36.0);
      expect(workflow.context!.grinderSetting, '15');
      expect(workflow.context!.grinderModel, 'Zero');
      expect(workflow.context!.coffeeName, 'Gesha Village');
      expect(workflow.context!.coffeeRoaster, 'Sey');
    });

    test('legacy doseData-only JSON (no grinder/coffee) synthesizes partial context', () {
      final json = {
        'id': 'wf-2',
        'name': 'Dose Only',
        'description': '',
        'profile': {
          'title': 'Test',
          'author': 'Test',
          'notes': '',
          'beverage_type': 'espresso',
          'steps': [],
          'tank_temperature': 0.0,
          'target_volume': 0,
          'target_volume_count_start': 0,
          'legacy_profile_type': '',
          'type': 'advanced',
          'lang': 'en',
          'hidden': false,
          'reference_file': '',
          'changes_since_last_espresso': '',
          'version': '2',
        },
        'doseData': {'doseIn': 16, 'doseOut': 32},
        'steamSettings': {'targetTemperature': 150, 'duration': 50, 'flow': 0.8},
        'hotWaterData': {'targetTemperature': 75, 'duration': 30, 'volume': 50, 'flow': 10.0},
        'rinseData': {'targetTemperature': 90, 'duration': 10, 'flow': 6.0},
      };

      final workflow = Workflow.fromJson(json);

      expect(workflow.context, isNotNull);
      expect(workflow.context!.targetDoseWeight, 16.0);
      expect(workflow.context!.targetYield, 32.0);
      expect(workflow.context!.grinderSetting, isNull);
      expect(workflow.context!.coffeeName, isNull);
    });
  });
```

Add the `Workflow` import at the top of the file:
```dart
import 'package:reaprime/src/models/data/workflow.dart';
```

**Step 2: Run the test**

```bash
flutter test test/models/workflow_context_test.dart
```

Expected: All tests PASS (these protect existing behavior).

---

### Task 2: Rewrite `workflow.dart` — remove legacy classes and update Workflow

**Files:**
- Modify: `lib/src/models/data/workflow.dart`

**Step 1: Replace the entire `Workflow` class**

Replace the `Workflow` class (lines 6–161) with the following. Note: `DoseData`, `GrinderData`, `CoffeeData` are deleted; the legacy-field read logic from `fromLegacyJson` is inlined into `fromJson`.

```dart
class Workflow {
  final String id;
  final String name;
  final String description;
  final Profile profile;
  final WorkflowContext? context;
  final SteamSettings steamSettings;
  final HotWaterData hotWaterData;
  final RinseData rinseData;

  Workflow({
    required this.id,
    required this.name,
    this.description = '',
    required this.profile,
    this.context,
    required this.steamSettings,
    required this.hotWaterData,
    required this.rinseData,
  });

  factory Workflow.fromJson(Map<String, dynamic> json) {
    WorkflowContext? ctx;
    if (json['context'] != null) {
      ctx = WorkflowContext.fromJson(json['context'] as Map<String, dynamic>);
    }

    // Migration-on-read: synthesize WorkflowContext from legacy fields present
    // in shots stored before v0.5.2. These fields are no longer written by toJson.
    final dose = json['doseData'] as Map<String, dynamic>?;
    final grinder = json['grinderData'] as Map<String, dynamic>?;
    final coffee = json['coffeeData'] as Map<String, dynamic>?;

    if (ctx != null && (grinder != null || coffee != null || dose != null)) {
      ctx = ctx.copyWith(
        targetDoseWeight:
            ctx.targetDoseWeight ?? parseOptionalDouble(dose?['doseIn']),
        targetYield: ctx.targetYield ?? parseOptionalDouble(dose?['doseOut']),
        grinderSetting: ctx.grinderSetting ?? grinder?['setting'] as String?,
        grinderModel: ctx.grinderModel ?? grinder?['model'] as String?,
        coffeeName: ctx.coffeeName ?? coffee?['name'] as String?,
        coffeeRoaster: ctx.coffeeRoaster ?? coffee?['roaster'] as String?,
      );
    } else if (ctx == null && (dose != null || grinder != null || coffee != null)) {
      ctx = WorkflowContext(
        targetDoseWeight:
            dose != null ? parseOptionalDouble(dose['doseIn']) : null,
        targetYield: dose != null ? parseOptionalDouble(dose['doseOut']) : null,
        grinderSetting: grinder?['setting'] as String?,
        grinderModel: grinder?['model'] as String?,
        coffeeName: coffee?['name'] as String?,
        coffeeRoaster: coffee?['roaster'] as String?,
      );
    }

    return Workflow(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      profile: Profile.fromJson(json['profile']),
      context: ctx,
      steamSettings: json['steamSettings'] != null
          ? SteamSettings.fromJson(json['steamSettings'])
          : SteamSettings.defaults(),
      hotWaterData: json['hotWaterData'] != null
          ? HotWaterData.fromJson(json['hotWaterData'])
          : HotWaterData.defaults(),
      rinseData: json['rinseData'] != null
          ? RinseData.fromJson(json['rinseData'])
          : RinseData.defaults(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'profile': profile.toJson(),
      if (context != null) 'context': context!.toJson(),
      'steamSettings': steamSettings.toJson(),
      'hotWaterData': hotWaterData.toJson(),
      'rinseData': rinseData.toJson(),
    };
  }

  Workflow copyWith({
    String? name,
    String? description,
    Profile? profile,
    WorkflowContext? context,
    SteamSettings? steamSettings,
    HotWaterData? hotWaterData,
    RinseData? rinseData,
  }) {
    return Workflow(
      id: Uuid().v4(),
      name: name ?? this.name,
      description: description ?? this.description,
      profile: profile ?? this.profile,
      context: context ?? this.context,
      steamSettings: steamSettings ?? this.steamSettings,
      hotWaterData: hotWaterData ?? this.hotWaterData,
      rinseData: rinseData ?? this.rinseData,
    );
  }
}
```

**Step 2: Delete `DoseData`, `GrinderData`, `CoffeeData` classes**

Remove lines 163–241 (the three legacy classes). Keep everything from `SteamSettings` onward unchanged.

**Step 3: Verify the file compiles in isolation**

```bash
flutter analyze lib/src/models/data/workflow.dart
```

Expected: Errors only in *other* files that still reference the deleted classes — not in `workflow.dart` itself.

---

### Task 3: Remove `WorkflowContext.fromLegacyJson()`

**Files:**
- Modify: `lib/src/models/data/workflow_context.dart`

**Step 1: Delete `fromLegacyJson`**

Remove the entire `fromLegacyJson` static method (the block starting with `/// (DoseData/GrinderData/CoffeeData...` through its closing `}`). It spans from the `///` doc comment to the closing brace of the method body.

**Step 2: Run analyze**

```bash
flutter analyze lib/src/models/data/workflow_context.dart
```

Expected: No errors in this file. Errors will appear in `workflow_context_test.dart` — fix those in Task 5.

---

### Task 4: Update `workflow_controller.dart`

Remove the null-context backfill in `setWorkflow()` and the deprecated params from `updateWorkflow()`.

**Files:**
- Modify: `lib/src/controllers/workflow_controller.dart`

**Step 1: Replace `setWorkflow()`**

Replace:
```dart
void setWorkflow(Workflow newWorkflow) {
  _currentWorkflow = newWorkflow;
  if (newWorkflow.context != null) {
    notifyListeners();
    return;
  }
  final ctx = WorkflowContext(
    targetDoseWeight: newWorkflow.doseData.doseIn,
    targetYield: newWorkflow.doseData.doseOut,
    grinderSetting: newWorkflow.grinderData?.setting,
    grinderModel: newWorkflow.grinderData?.model,
    coffeeName: newWorkflow.coffeeData?.name,
    coffeeRoaster: newWorkflow.coffeeData?.roaster,
  );
  _currentWorkflow = _currentWorkflow.copyWith(context: ctx);
  notifyListeners();
}
```

With:
```dart
void setWorkflow(Workflow newWorkflow) {
  _currentWorkflow = newWorkflow;
  notifyListeners();
}
```

**Step 2: Replace `updateWorkflow()`**

Replace the entire `updateWorkflow()` method with:
```dart
void updateWorkflow({
  String? name,
  String? description,
  Profile? profile,
  WorkflowContext? context,
  SteamSettings? steamSettings,
  HotWaterData? hotWaterData,
  RinseData? rinseData,
}) {
  _currentWorkflow = _currentWorkflow.copyWith(
    name: name,
    description: description,
    profile: profile,
    context: context,
    steamSettings: steamSettings,
    hotWaterData: hotWaterData,
    rinseData: rinseData,
  );
  notifyListeners();
}
```

**Step 3: Run analyze**

```bash
flutter analyze lib/src/controllers/workflow_controller.dart
```

Expected: No errors.

---

### Task 5: Rewrite `PersistenceController.grinderOptions()` and `coffeeOptions()`

**Files:**
- Modify: `lib/src/controllers/persistence_controller.dart`

**Step 1: Replace `grinderOptions()`**

Replace:
```dart
List<GrinderData> grinderOptions() {
  return _shots.fold(<GrinderData>[], (res, el) {
    if (el.workflow.grinderData != null) {
      res.add(el.workflow.grinderData!);
    }
    return res;
  }).toList();
}
```

With:
```dart
List<({String setting, String? model})> grinderOptions() {
  return _shots
      .where((el) => el.workflow.context?.grinderSetting != null)
      .map((el) => (
            setting: el.workflow.context!.grinderSetting!,
            model: el.workflow.context!.grinderModel,
          ))
      .toList();
}
```

**Step 2: Replace `coffeeOptions()`**

Replace:
```dart
List<CoffeeData> coffeeOptions() {
  return _shots.fold(<CoffeeData>[], (res, el) {
    if (el.workflow.coffeeData != null) {
      res.add(el.workflow.coffeeData!);
    }
    return res;
  }).toList();
}
```

With:
```dart
List<({String name, String? roaster})> coffeeOptions() {
  return _shots
      .where((el) => el.workflow.context?.coffeeName != null)
      .map((el) => (
            name: el.workflow.context!.coffeeName!,
            roaster: el.workflow.context!.coffeeRoaster,
          ))
      .toList();
}
```

**Step 3: Remove unused imports**

Remove any `import` lines for `workflow.dart` that were only needed for `GrinderData`/`CoffeeData`. Check if the `workflow.dart` import is still needed for other types — if `Workflow` is not directly referenced in this file, remove it. Keep imports for anything still used.

**Step 4: Run analyze**

```bash
flutter analyze lib/src/controllers/persistence_controller.dart
```

Expected: No errors. `profile_tile.dart` should also compile without changes since the record field names (`setting`, `model`, `name`, `roaster`) match what the autocomplete lambdas already access.

---

### Task 6: Verify `profile_tile.dart` compiles unchanged

The autocomplete lambdas in `profile_tile.dart` access `.setting`, `.model`, `.name`, `.roaster` on the elements from `grinderOptions()` / `coffeeOptions()`. Dart records with named fields use the same dot-access syntax as class fields, so no code changes are needed.

**Step 1: Run analyze on profile_tile**

```bash
flutter analyze lib/src/home_feature/tiles/profile_tile.dart
```

Expected: No errors. If any errors appear (e.g. type annotation mismatch), fix them now — but none are expected.

---

### Task 7: Update `workflow_context_test.dart` — remove `fromLegacyJson` tests

**Files:**
- Modify: `test/models/workflow_context_test.dart`

**Step 1: Remove the three `fromLegacyJson` tests**

Delete these three test cases (lines 56–101):
- `'fromLegacyJson maps DoseData/GrinderData/CoffeeData'`
- `'fromLegacyJson handles missing optional groups'`
- `'fromLegacyJson handles int dose values'`

Keep all other tests unchanged. The migration-on-read coverage is now in the group added in Task 1.

**Step 2: Run tests**

```bash
flutter test test/models/workflow_context_test.dart
```

Expected: All remaining tests PASS.

---

### Task 8: Update `workflow_export_section_test.dart`

**Files:**
- Modify: `test/data_export/workflow_export_section_test.dart`

**Step 1: Remove the `doseData` assertion**

In the `'exports the current workflow as JSON'` test, remove this line:
```dart
expect(map['doseData'], isA<Map<String, dynamic>>());
```

Optionally add an assertion confirming legacy fields are absent:
```dart
expect(map.containsKey('doseData'), isFalse);
```

**Step 2: Run tests**

```bash
flutter test test/data_export/workflow_export_section_test.dart
```

Expected: All tests PASS.

---

### Task 9: Update `shot_importer_test.dart`

The existing test JSONs use `doseData` without a `context` field. They remain valid inputs (migration-on-read still handles them), but we should modernize the bulk of them and make the migration-on-read intent explicit in one case.

**Files:**
- Modify: `test/shot_importer_test.dart`

**Step 1: Convert the single-shot import test to use `context`**

In the `'should import a valid shot JSON string'` test (around line 100), change the workflow JSON from:
```json
"doseData": { "doseIn": 18.0, "doseOut": 36.0 }
```
To:
```json
"context": { "targetDoseWeight": 18.0, "targetYield": 36.0 }
```

**Step 2: Keep one test explicitly labelled as migration-on-read**

The multi-shot import test (around line 202) happens to use `doseData`-only JSON for both shots. Convert shot-2 to use `context`, but leave shot-1 with only `doseData` to serve as the explicit migration-on-read integration test. Add a comment:
```dart
// Shot 1 uses legacy doseData (no context) to verify migration-on-read.
```

Convert shot-2's workflow JSON to use `context`:
```json
"context": { "targetDoseWeight": 20.0, "targetYield": 40.0 }
```

**Step 3: Run tests**

```bash
flutter test test/shot_importer_test.dart
```

Expected: All tests PASS.

---

### Task 10: Update `rest_v1.yml`

**Files:**
- Modify: `assets/api/rest_v1.yml`

**Step 1: Remove legacy field documentation from workflow PUT**

Find the `PUT /api/v1/workflow` request schema. Remove the `doseData`, `grinderData`, `coffeeData` properties and their descriptions. Find the note at line ~498 that says legacy fields are "still accepted" and update it to say they are no longer accepted as of v0.5.2; only `context` is supported.

**Step 2: Verify the YAML is valid**

```bash
flutter analyze assets/
```

Or open the API docs in a browser at port 4001 if the app is running.

---

### Task 11: Self-review (Phase 4 — tdd-workflow)

Before committing, review all changed code. Cap at 3 passes; stop when a pass finds nothing to improve.

**Step 1: Re-run unit tests to confirm baseline**

```bash
flutter test
flutter analyze
```

Expected: All PASS, no errors.

**Step 2: Review each changed file**

Check for:
- Duplication: any repeated legacy-field read logic that could be a helper?
- Naming: are migration-on-read comments clear?
- SRP: does `Workflow.fromJson()` do more than one thing?
- Dead code: any remaining references to removed types (analyzer will catch most, but scan manually too)

**Step 3: Make improvements, re-run tests after each change**

```bash
flutter test && flutter analyze
```

If tests break: fix before continuing. Never move forward with a broken baseline.

**Step 4: Stop when a review pass finds nothing to improve**

---

### Task 12: Full test suite, analysis, and commit

**Step 1: Run all tests**

```bash
flutter test
```

Expected: All tests PASS. Zero failures.

**Step 2: Run static analysis**

```bash
flutter analyze
```

Expected: No errors, no warnings about deleted types.

**Step 3: Verify TDD checklist before committing**

- [ ] Every changed behaviour has a test that was verified RED before the change
- [ ] Migration-on-read protection tests pass
- [ ] `fromLegacyJson` tests removed (method deleted)
- [ ] `doseData` no longer appears in `toJson()` output (covered by export test)
- [ ] `grinderOptions()`/`coffeeOptions()` return record tuples (covered by compile + analyze)
- [ ] All tests pass, output pristine

**Step 5: Commit**

```bash
git add lib/src/models/data/workflow.dart \
        lib/src/models/data/workflow_context.dart \
        lib/src/controllers/workflow_controller.dart \
        lib/src/controllers/persistence_controller.dart \
        lib/src/home_feature/tiles/profile_tile.dart \
        assets/api/rest_v1.yml \
        test/models/workflow_context_test.dart \
        test/data_export/workflow_export_section_test.dart \
        test/shot_importer_test.dart
git commit -m "feat: drop legacy workflow fields (DoseData, GrinderData, CoffeeData)

Migration-on-read preserved in Workflow.fromJson for stored shots.
Closes v0.5.2 cleanup of deprecated workflow serialization fields."
```
