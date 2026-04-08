# settings.tdb Import Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Import user settings from de1app's `settings.tdb` file during de1app folder import, mapping applicable settings to Bridge's settings, wake schedules, and workflow context.

**Architecture:** Add a `SettingsTdbParser` that reads the flat TCL key-value file via the existing `TclParser`, maps ~10 keys to Bridge equivalents, and returns a typed result. The `De1appScanner` detects the file, the `De1appImporter` applies the parsed settings to `SettingsController` and `StorageService` (workflow). The import summary UI shows a "Settings" row when detected.

**Tech Stack:** Dart, Flutter, existing `TclParser`, `SettingsController`, `WakeSchedule`, `Workflow`/`WorkflowContext`

---

## Mapping Reference

| de1app key | Bridge target | Conversion |
|---|---|---|
| `scheduler_enable` + `scheduler_wake` + `scheduler_sleep` | `WakeSchedule` | `hour`/`minute` from wake (seconds÷3600, remainder÷60); `keepAwakeFor` = `(sleep - wake) / 60` minutes; `daysOfWeek: {}`; `enabled: scheduler_enable == "1"` |
| `keep_scale_on` | `scalePowerMode` | `"1"` → `always_on`, else `disconnect` |
| `screen_saver_delay` | `sleepTimeoutMinutes` | seconds÷60, clamped to ≥1 |
| `grinder_dose_weight` | Workflow `targetDoseWeight` | parse as double, skip if 0 |
| `grinder_setting` | Workflow `grinderSetting` | string, skip if "0" or empty |
| `grinder_model` | Workflow `grinderModel` | string, skip if empty |
| `final_desired_shot_weight_advanced` | Workflow `targetYield` | parse as double, skip if 0 |
| `steam_temperature` | Workflow `steamSettings.targetTemperature` | parse as int |
| `steam_max_time` | Workflow `steamSettings.duration` | parse as int |
| `water_temperature` | Workflow `hotWaterData.targetTemperature` | parse as int |
| `water_volume` | Workflow `hotWaterData.volume` | parse as int |
| `flush_flow` | Workflow `rinseData.flow` | parse as double |
| `flush_seconds` | Workflow `rinseData.duration` | parse as int |

---

### Task 1: SettingsTdbParser — parsed result model and parser

**Files:**
- Create: `lib/src/import/parsers/settings_tdb_parser.dart`
- Test: `test/import/settings_tdb_parser_test.dart`

**Step 1: Write the failing test**

```dart
// test/import/settings_tdb_parser_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/import/parsers/settings_tdb_parser.dart';

void main() {
  group('SettingsTdbParser', () {
    test('parses scheduler settings into wake schedule fields', () {
      final content = '''
scheduler_enable 1
scheduler_wake 25200
scheduler_sleep 28800
''';
      final result = SettingsTdbParser.parse(content);
      expect(result.wakeScheduleEnabled, true);
      expect(result.wakeHour, 7);
      expect(result.wakeMinute, 0);
      expect(result.keepAwakeForMinutes, 60);
    });

    test('parses scale and sleep settings', () {
      final content = '''
keep_scale_on 1
screen_saver_delay 300
''';
      final result = SettingsTdbParser.parse(content);
      expect(result.keepScaleOn, true);
      expect(result.sleepTimeoutMinutes, 5);
    });

    test('parses workflow-related settings', () {
      final content = '''
grinder_dose_weight 18.5
grinder_setting 2.5
grinder_model {Niche Zero}
final_desired_shot_weight_advanced 36
''';
      final result = SettingsTdbParser.parse(content);
      expect(result.doseWeight, 18.5);
      expect(result.grinderSetting, '2.5');
      expect(result.grinderModel, 'Niche Zero');
      expect(result.targetYield, 36.0);
    });

    test('parses steam, water, and rinse settings', () {
      final content = '''
steam_temperature 160
steam_max_time 90
water_temperature 85
water_volume 200
flush_flow 6.0
flush_seconds 4
''';
      final result = SettingsTdbParser.parse(content);
      expect(result.steamTemperature, 160);
      expect(result.steamDuration, 90);
      expect(result.hotWaterTemperature, 85);
      expect(result.hotWaterVolume, 200);
      expect(result.rinseFlow, 6.0);
      expect(result.rinseDuration, 4);
    });

    test('handles missing keys gracefully', () {
      final content = '''
some_unrelated_key value
''';
      final result = SettingsTdbParser.parse(content);
      expect(result.wakeScheduleEnabled, isNull);
      expect(result.doseWeight, isNull);
      expect(result.grinderModel, isNull);
      expect(result.isEmpty, true);
    });

    test('skips zero dose/yield values', () {
      final content = '''
grinder_dose_weight 0
final_desired_shot_weight_advanced 0
grinder_setting 0
''';
      final result = SettingsTdbParser.parse(content);
      expect(result.doseWeight, isNull);
      expect(result.targetYield, isNull);
      expect(result.grinderSetting, isNull);
    });

    test('handles negative keepAwakeFor (sleep before wake)', () {
      // sleep at 3600 (1:00), wake at 25200 (7:00) — wraps around midnight
      final content = '''
scheduler_enable 1
scheduler_wake 25200
scheduler_sleep 3600
''';
      final result = SettingsTdbParser.parse(content);
      expect(result.wakeScheduleEnabled, true);
      // Negative delta means sleep is next day — (3600 + 86400 - 25200) / 60 = 1020 min
      expect(result.keepAwakeForMinutes, 1020);
    });
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/import/settings_tdb_parser_test.dart`
Expected: FAIL — `settings_tdb_parser.dart` doesn't exist yet

**Step 3: Write minimal implementation**

```dart
// lib/src/import/parsers/settings_tdb_parser.dart
import 'package:reaprime/src/import/parsers/tcl_parser.dart';

/// Result of parsing de1app's settings.tdb file.
/// All fields are nullable — only present if the key existed in the file.
class SettingsTdbResult {
  // Wake schedule
  final bool? wakeScheduleEnabled;
  final int? wakeHour;
  final int? wakeMinute;
  final int? keepAwakeForMinutes;

  // Settings
  final bool? keepScaleOn;
  final int? sleepTimeoutMinutes;

  // Workflow context
  final double? doseWeight;
  final String? grinderSetting;
  final String? grinderModel;
  final double? targetYield;

  // Steam
  final int? steamTemperature;
  final int? steamDuration;

  // Hot water
  final int? hotWaterTemperature;
  final int? hotWaterVolume;

  // Rinse
  final double? rinseFlow;
  final int? rinseDuration;

  const SettingsTdbResult({
    this.wakeScheduleEnabled,
    this.wakeHour,
    this.wakeMinute,
    this.keepAwakeForMinutes,
    this.keepScaleOn,
    this.sleepTimeoutMinutes,
    this.doseWeight,
    this.grinderSetting,
    this.grinderModel,
    this.targetYield,
    this.steamTemperature,
    this.steamDuration,
    this.hotWaterTemperature,
    this.hotWaterVolume,
    this.rinseFlow,
    this.rinseDuration,
  });

  /// True if no meaningful settings were found.
  bool get isEmpty =>
      wakeScheduleEnabled == null &&
      keepScaleOn == null &&
      sleepTimeoutMinutes == null &&
      doseWeight == null &&
      grinderSetting == null &&
      grinderModel == null &&
      targetYield == null &&
      steamTemperature == null &&
      steamDuration == null &&
      hotWaterTemperature == null &&
      hotWaterVolume == null &&
      rinseFlow == null &&
      rinseDuration == null;
}

class SettingsTdbParser {
  static SettingsTdbResult parse(String content) {
    final data = TclParser.parse(content);

    // Wake schedule
    final schedulerEnable = data['scheduler_enable']?.toString();
    final schedulerWake = int.tryParse(data['scheduler_wake']?.toString() ?? '');
    final schedulerSleep = int.tryParse(data['scheduler_sleep']?.toString() ?? '');

    bool? wakeEnabled;
    int? wakeHour;
    int? wakeMinute;
    int? keepAwakeFor;

    if (schedulerEnable != null) {
      wakeEnabled = schedulerEnable == '1';
    }
    if (schedulerWake != null) {
      wakeHour = schedulerWake ~/ 3600;
      wakeMinute = (schedulerWake % 3600) ~/ 60;
    }
    if (schedulerWake != null && schedulerSleep != null) {
      var delta = schedulerSleep - schedulerWake;
      if (delta < 0) delta += 86400; // wrap around midnight
      keepAwakeFor = delta ~/ 60;
    }

    // Scale / sleep
    final keepScaleOnRaw = data['keep_scale_on']?.toString();
    final screenSaverDelay = int.tryParse(data['screen_saver_delay']?.toString() ?? '');

    // Workflow context
    final doseRaw = double.tryParse(data['grinder_dose_weight']?.toString() ?? '');
    final yieldRaw = double.tryParse(data['final_desired_shot_weight_advanced']?.toString() ?? '');
    final grinderSettingRaw = data['grinder_setting']?.toString();
    final grinderModelRaw = data['grinder_model']?.toString();

    // Steam
    final steamTemp = int.tryParse(data['steam_temperature']?.toString() ?? '');
    final steamTime = int.tryParse(data['steam_max_time']?.toString() ?? '');

    // Hot water
    final waterTemp = int.tryParse(data['water_temperature']?.toString() ?? '');
    final waterVol = int.tryParse(data['water_volume']?.toString() ?? '');

    // Rinse
    final flushFlow = double.tryParse(data['flush_flow']?.toString() ?? '');
    final flushSec = int.tryParse(data['flush_seconds']?.toString() ?? '');

    return SettingsTdbResult(
      wakeScheduleEnabled: wakeEnabled,
      wakeHour: wakeHour,
      wakeMinute: wakeMinute,
      keepAwakeForMinutes: keepAwakeFor,
      keepScaleOn: keepScaleOnRaw != null ? keepScaleOnRaw == '1' : null,
      sleepTimeoutMinutes: screenSaverDelay != null
          ? (screenSaverDelay / 60).ceil().clamp(1, 9999)
          : null,
      doseWeight: (doseRaw != null && doseRaw > 0) ? doseRaw : null,
      grinderSetting: (grinderSettingRaw != null &&
              grinderSettingRaw.isNotEmpty &&
              grinderSettingRaw != '0')
          ? grinderSettingRaw
          : null,
      grinderModel: (grinderModelRaw != null && grinderModelRaw.isNotEmpty)
          ? grinderModelRaw
          : null,
      targetYield: (yieldRaw != null && yieldRaw > 0) ? yieldRaw : null,
      steamTemperature: steamTemp,
      steamDuration: steamTime,
      hotWaterTemperature: waterTemp,
      hotWaterVolume: waterVol,
      rinseFlow: flushFlow,
      rinseDuration: flushSec,
    );
  }
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/import/settings_tdb_parser_test.dart`
Expected: PASS (all 7 tests)

**Step 5: Commit**

```bash
git add lib/src/import/parsers/settings_tdb_parser.dart test/import/settings_tdb_parser_test.dart
git commit -m "feat: add SettingsTdbParser for de1app settings.tdb import"
```

---

### Task 2: Update De1appScanner to detect settings.tdb

**Files:**
- Modify: `lib/src/import/de1app_scanner.dart`
- Modify: `lib/src/import/import_result.dart` (add `hasSettings` to `ScanResult`)
- Modify: `test/import/de1app_scanner_test.dart`

**Step 1: Write the failing test**

Add to `test/import/de1app_scanner_test.dart`:

```dart
test('detects settings.tdb', () async {
  final dir = await Directory.systemTemp.createTemp('scanner_test');
  try {
    await File('${dir.path}/settings.tdb').writeAsString('scheduler_enable 1');
    final result = await De1appScanner.scan(dir.path);
    expect(result.hasSettings, true);
  } finally {
    await dir.delete(recursive: true);
  }
});

test('reports no settings when file missing', () async {
  final dir = await Directory.systemTemp.createTemp('scanner_test');
  try {
    final result = await De1appScanner.scan(dir.path);
    expect(result.hasSettings, false);
  } finally {
    await dir.delete(recursive: true);
  }
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/import/de1app_scanner_test.dart`
Expected: FAIL — `hasSettings` doesn't exist on `ScanResult`

**Step 3: Implement**

In `lib/src/import/import_result.dart`, add `hasSettings` to `ScanResult`:

```dart
class ScanResult {
  final int shotCount;
  final int profileCount;
  final bool hasDyeGrinders;
  final bool hasSettings;
  final String sourcePath;
  final String? shotSource;
  const ScanResult({
    required this.shotCount,
    required this.profileCount,
    required this.hasDyeGrinders,
    required this.hasSettings,
    required this.sourcePath,
    this.shotSource,
  });
  int get totalItems => shotCount + profileCount;
  bool get isEmpty => totalItems == 0 && !hasDyeGrinders && !hasSettings;
}
```

In `lib/src/import/de1app_scanner.dart`, add settings detection:

```dart
// Settings
final hasSettings = await File('$path/settings.tdb').exists();
```

And add `hasSettings: hasSettings` to the `ScanResult` constructor call.

**Step 4: Run tests**

Run: `flutter test test/import/de1app_scanner_test.dart`
Expected: PASS

**Step 5: Fix any other test files that construct `ScanResult` without `hasSettings`**

Search for `ScanResult(` in test files and add `hasSettings: false` where needed.

Run: `flutter test`
Expected: PASS (all tests)

**Step 6: Commit**

```bash
git add lib/src/import/import_result.dart lib/src/import/de1app_scanner.dart test/
git commit -m "feat: detect settings.tdb in De1appScanner"
```

---

### Task 3: Apply parsed settings in De1appImporter

**Files:**
- Modify: `lib/src/import/de1app_importer.dart` — add `SettingsController` and `StorageService` params, apply settings after other imports
- Test: `test/import/de1app_importer_test.dart` (add settings import test, or add to existing)

**Step 1: Write the failing test**

Add a test that verifies settings.tdb values are applied to SettingsController and workflow. Use `MockSettingsService` from `test/helpers/`.

The test should:
1. Create a temp directory with a `settings.tdb` file containing known values
2. Create a `ScanResult` with `hasSettings: true`
3. Run the importer
4. Verify `SettingsController` was updated (scalePowerMode, sleepTimeoutMinutes, wakeSchedules)
5. Verify the workflow stored via `StorageService` has the right context values

**Step 2: Implement**

Add to `De1appImporter`:
- New constructor params: `SettingsController? settingsController`
- New Phase 5 after profiles: if `scanResult.hasSettings`, read `settings.tdb`, parse via `SettingsTdbParser`, apply:
  - Wake schedule → create `WakeSchedule`, serialize to JSON, call `settingsController.setWakeSchedules()`
  - `keepScaleOn` → `settingsController.setScalePowerMode()`
  - `sleepTimeoutMinutes` → `settingsController.setSleepTimeoutMinutes()`
  - Workflow fields → load current workflow via `storageService.loadCurrentWorkflow()`, merge context/steam/water/rinse fields, store back

**Step 3: Run tests**

Run: `flutter test`
Expected: PASS

**Step 4: Update ImportResult to include settings import count**

Add `settingsApplied: bool` to `ImportResult` (default `false`). Set to `true` when settings are successfully applied.

**Step 5: Commit**

```bash
git add lib/src/import/de1app_importer.dart lib/src/import/import_result.dart test/
git commit -m "feat: apply settings.tdb values during de1app import"
```

---

### Task 4: Update import summary UI to show settings row

**Files:**
- Modify: `lib/src/import/widgets/import_summary_view.dart` — add settings row
- Modify: `lib/src/import/widgets/import_result_view.dart` — show "Settings applied" in result

**Step 1: Add settings row to import summary**

In `ImportSummaryView`, after the DYE grinders row, add:

```dart
if (scanResult.hasSettings) ...[
  const SizedBox(height: 12),
  const _CountRow(
    icon: LucideIcons.settings2,
    label: 'App settings',
  ),
],
```

**Step 2: Update import result view**

In `ImportResultView`, show "Settings applied" when `result.settingsApplied` is true.

**Step 3: Run analyze**

Run: `flutter analyze`
Expected: No issues

**Step 4: Commit**

```bash
git add lib/src/import/widgets/
git commit -m "feat: show settings in import summary and result views"
```

---

### Task 5: Wire SettingsController into import entry points

**Files:**
- Modify: `lib/src/onboarding_feature/steps/import_step.dart` — pass `settingsController` to `De1appImporter`
- Modify: `lib/src/settings/data_management_page.dart` — pass `settingsController` to `De1appImporter`

**Step 1: Update import_step.dart**

In `_onImportAll()`, pass `settingsController: widget.settingsController` to the `De1appImporter` constructor.

**Step 2: Update data_management_page.dart**

In `_importFromDe1app()`, pass `settingsController: widget.controller` to the `De1appImporter` constructor.

**Step 3: Run full test suite + analyze**

Run: `flutter test && flutter analyze`
Expected: PASS, no issues

**Step 4: Commit**

```bash
git add lib/src/onboarding_feature/steps/import_step.dart lib/src/settings/data_management_page.dart
git commit -m "feat: wire settings import into onboarding and data management"
```

---

### Task 6: Final verification

**Step 1: Run full test suite**

Run: `flutter test`
Expected: All tests pass

**Step 2: Run flutter analyze**

Run: `flutter analyze`
Expected: No issues

**Step 3: Manual smoke test (if app running)**

Use MCP tools to start app in simulate mode, then verify the import endpoint works:
1. Start app with `app_start` (simulate mode)
2. Check settings before import via `settings_get`
3. Place a test `settings.tdb` file and trigger import
4. Verify settings changed via `settings_get` and `workflow_get`
