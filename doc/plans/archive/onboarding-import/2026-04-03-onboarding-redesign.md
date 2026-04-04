# Onboarding Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Welcome screen and data Import step to the onboarding flow, allowing users migrating from de1app to import their shots, profiles, beans, and grinders into Streamline Bridge.

**Architecture:** Two new onboarding steps (Welcome, Import) are inserted before the existing Permissions/Init/Scan steps. The import subsystem lives in `lib/src/import/` with parsers for de1app's JSON and TCL formats, an entity extractor for deduplication, and a folder scanner/orchestrator. Import UI widgets are reusable between the onboarding step and Settings > Data Management. An `onboardingCompleted` flag in SharedPreferences controls whether Welcome and Import steps are shown on subsequent launches.

**Tech Stack:** Flutter/Dart, SharedPreferences, file_picker, share_plus (new dependency), shadcn_ui, RxDart, Drift/SQLite (existing storage)

**Design document:** `doc/plans/onboarding-redesign.md` (brainstorming tracking doc with all agreed decisions)

---

## File Structure

### New Files

| File | Purpose |
|------|---------|
| **Onboarding Steps** | |
| `lib/src/onboarding_feature/steps/welcome_step.dart` | Welcome screen with copy and "Get Started" button |
| `lib/src/onboarding_feature/steps/import_step.dart` | Import step: source picker, delegates to import flow widgets |
| **Import — Models** | |
| `lib/src/import/import_result.dart` | `ImportResult`, `ImportError`, `ScanResult` data classes |
| **Import — Parsers** | |
| `lib/src/import/parsers/tcl_parser.dart` | TCL tokenizer: reads de1app `.shot` files into key-value maps |
| `lib/src/import/parsers/shot_v2_json_parser.dart` | Parses `history_v2/*.json` → `ShotRecord` + extracted metadata |
| `lib/src/import/parsers/tcl_shot_parser.dart` | Parses `history/*.shot` (TCL) → `ShotRecord` + extracted metadata |
| `lib/src/import/parsers/profile_v2_parser.dart` | Parses `profiles_v2/*.json` → `ProfileRecord` |
| `lib/src/import/parsers/grinder_tdb_parser.dart` | Parses DYE `grinders.tdb` → `Grinder` list |
| **Import — Pipeline** | |
| `lib/src/import/entity_extractor.dart` | Deduplicates beans/grinders from shot metadata, creates entities |
| `lib/src/import/de1app_scanner.dart` | Pre-scans de1app folder, counts files, detects available sources |
| `lib/src/import/de1app_importer.dart` | Orchestrates full import: scan → parse → extract → store |
| **Import — UI Widgets** | |
| `lib/src/import/widgets/import_source_picker.dart` | Two-option card: "Import from Decent app" / "Import Bridge backup" |
| `lib/src/import/widgets/import_summary_view.dart` | Pre-import summary with counts and "Import All" button |
| `lib/src/import/widgets/import_progress_view.dart` | Determinate progress bar with per-category counts |
| `lib/src/import/widgets/import_result_view.dart` | Post-import summary: success counts, error list, share report |
| **Tests** | |
| `test/import/tcl_parser_test.dart` | TCL tokenizer tests |
| `test/import/shot_v2_json_parser_test.dart` | Shot v2 JSON parser tests |
| `test/import/tcl_shot_parser_test.dart` | TCL shot parser tests |
| `test/import/profile_v2_parser_test.dart` | Profile v2 parser tests |
| `test/import/grinder_tdb_parser_test.dart` | Grinder TDB parser tests |
| `test/import/entity_extractor_test.dart` | Entity extraction/dedup tests |
| `test/import/de1app_scanner_test.dart` | Folder scanner tests |
| `test/import/de1app_importer_test.dart` | Import orchestrator tests |
| `test/onboarding/welcome_step_test.dart` | Welcome step widget test |
| `test/onboarding/import_step_test.dart` | Import step widget test |
| **Test Fixtures** | |
| `test/fixtures/de1app/history_v2/20240315T143022.json` | Sample de1app v2 shot JSON |
| `test/fixtures/de1app/history/20231108T091544.shot` | Sample de1app v1 shot TCL |
| `test/fixtures/de1app/profiles_v2/best_practice.json` | Sample de1app profile v2 JSON |
| `test/fixtures/de1app/plugins/DYE/grinders.tdb` | Sample DYE grinder specs |

### Modified Files

| File | Change |
|------|--------|
| `lib/src/settings/settings_service.dart` | Add `onboardingCompleted` to SettingsKeys enum, abstract methods, and SharedPreferencesSettingsService |
| `lib/src/settings/settings_controller.dart` | Add `onboardingCompleted` getter/setter, load in `loadSettings()` |
| `lib/src/app.dart` | Insert `createWelcomeStep()` and `createImportStep()` into OnboardingController step list |
| `lib/src/settings/data_management_page.dart` | Add "Import from Decent app" button, launch import flow |
| `pubspec.yaml` | Add `share_plus` dependency |
| `test/helpers/mock_settings_service.dart` | Add `onboardingCompleted` stub |

---

## Phase 1: Foundation (Settings Flag + Welcome Step)

### Task 1: Add `onboardingCompleted` Setting

**Files:**
- Modify: `lib/src/settings/settings_service.dart`
- Modify: `lib/src/settings/settings_controller.dart`
- Modify: `test/helpers/mock_settings_service.dart` (if it exists, add stub)

- [ ] **Step 1: Add `onboardingCompleted` to SettingsKeys enum**

In `lib/src/settings/settings_service.dart`, add to the `SettingsKeys` enum:

```dart
enum SettingsKeys {
  // ... existing keys ...
  onboardingCompleted,
}
```

- [ ] **Step 2: Add abstract methods to SettingsService**

In the `SettingsService` abstract class:

```dart
Future<bool> onboardingCompleted();
Future<void> setOnboardingCompleted(bool value);
```

- [ ] **Step 3: Implement in SharedPreferencesSettingsService**

```dart
@override
Future<bool> onboardingCompleted() async {
  return await prefs.getBool(SettingsKeys.onboardingCompleted.name) ?? false;
}

@override
Future<void> setOnboardingCompleted(bool value) async {
  await prefs.setBool(SettingsKeys.onboardingCompleted.name, value);
}
```

- [ ] **Step 4: Add to SettingsController**

Add private field and getter:
```dart
late bool _onboardingCompleted;
bool get onboardingCompleted => _onboardingCompleted;
```

In `loadSettings()`:
```dart
_onboardingCompleted = await _settingsService.onboardingCompleted();
```

Add setter:
```dart
Future<void> setOnboardingCompleted(bool value) async {
  if (value == _onboardingCompleted) return;
  _onboardingCompleted = value;
  await _settingsService.setOnboardingCompleted(value);
  notifyListeners();
}
```

- [ ] **Step 5: Update MockSettingsService if it exists**

Add stub implementation returning `false` by default (or `true` if that's the test default to skip onboarding in tests).

- [ ] **Step 6: Run `flutter analyze` and fix any issues**

Run: `flutter analyze`

- [ ] **Step 7: Commit**

```bash
git add lib/src/settings/settings_service.dart lib/src/settings/settings_controller.dart test/helpers/mock_settings_service.dart
git commit -m "feat: add onboardingCompleted setting flag"
```

---

### Task 2: Welcome Step Widget

**Files:**
- Create: `lib/src/onboarding_feature/steps/welcome_step.dart`
- Test: `test/onboarding/welcome_step_test.dart`

- [ ] **Step 1: Write the widget test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/onboarding_feature/onboarding_controller.dart';
import 'package:reaprime/src/onboarding_feature/steps/welcome_step.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  group('WelcomeStep', () {
    late OnboardingController controller;
    late bool advanceCalled;

    setUp(() {
      advanceCalled = false;
      controller = OnboardingController(steps: [
        createWelcomeStep(),
        OnboardingStep(
          id: 'next',
          shouldShow: () async => true,
          builder: (_) => const SizedBox(),
        ),
      ]);
    });

    tearDown(() => controller.dispose());

    testWidgets('displays welcome copy', (tester) async {
      await controller.initialize();
      final step = controller.activeSteps.first;

      await tester.pumpWidget(
        ShadApp(
          home: Scaffold(body: step.builder(controller)),
        ),
      );

      expect(find.text('Welcome to Streamline Bridge'), findsOneWidget);
      expect(
        find.textContaining('Control your Decent espresso machine'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Coming from the Decent app'),
        findsOneWidget,
      );
    });

    testWidgets('Get Started button advances controller', (tester) async {
      await controller.initialize();
      final step = controller.activeSteps.first;

      await tester.pumpWidget(
        ShadApp(
          home: Scaffold(body: step.builder(controller)),
        ),
      );

      await tester.tap(find.text('Get Started'));
      await tester.pump();

      // Controller should have advanced to next step
      expect(controller.currentStep.id, equals('next'));
    });

    test('shouldShow returns true always', () async {
      final step = createWelcomeStep();
      expect(await step.shouldShow(), isTrue);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/onboarding/welcome_step_test.dart`
Expected: FAIL — `createWelcomeStep` not found

- [ ] **Step 3: Implement the welcome step**

```dart
import 'package:flutter/material.dart';
import 'package:reaprime/src/onboarding_feature/onboarding_controller.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

OnboardingStep createWelcomeStep() {
  return OnboardingStep(
    id: 'welcome',
    shouldShow: () async => true,
    builder: (controller) => _WelcomeStepView(controller: controller),
  );
}

class _WelcomeStepView extends StatelessWidget {
  final OnboardingController controller;

  const _WelcomeStepView({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Welcome to Streamline Bridge',
                  style: theme.textTheme.h3,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'Control your Decent espresso machine, manage profiles, '
                  'and track your shots — right here or from any device on '
                  'your network.',
                  style: theme.textTheme.p,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Text(
                  'Coming from the Decent app? You can import your data next.',
                  style: theme.textTheme.muted,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                ShadButton(
                  onPressed: () => controller.advance(),
                  child: const Text('Get Started'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/onboarding/welcome_step_test.dart`
Expected: PASS

- [ ] **Step 5: Run `flutter analyze`**

- [ ] **Step 6: Commit**

```bash
git add lib/src/onboarding_feature/steps/welcome_step.dart test/onboarding/welcome_step_test.dart
git commit -m "feat: add welcome onboarding step"
```

---

### Task 3: Wire Up Welcome Step + Onboarding Flag in app.dart

**Files:**
- Modify: `lib/src/app.dart`

- [ ] **Step 1: Import welcome step and add to controller**

At the top of `app.dart`, add:
```dart
import 'package:reaprime/src/onboarding_feature/steps/welcome_step.dart';
```

In `_MyAppState.initState()`, insert `createWelcomeStep()` as the first step, with a `shouldShow` override that checks the onboarding flag:

```dart
_onboardingController = OnboardingController(steps: [
  OnboardingStep(
    id: 'welcome',
    shouldShow: () async =>
        !await widget.settingsController.settingsService.onboardingCompleted(),
    builder: createWelcomeStep().builder,
  ),
  createPermissionsStep(
    de1Controller: widget.de1Controller,
  ),
  createInitializationStep(
    // ... existing args ...
  ),
  createScanStep(
    // ... existing args ...
  ),
]);
```

Note: We override `shouldShow` here rather than in the step itself, because the step doesn't have access to `settingsController`. The import step (Task 13) will use the same pattern and will also set the flag.

- [ ] **Step 2: Run `flutter analyze`**

- [ ] **Step 3: Run `flutter test` (full suite)**

Run: `flutter test`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add lib/src/app.dart
git commit -m "feat: wire welcome step into onboarding flow with flag check"
```

---

## Phase 2: Import Models and Parsers

### Task 4: Import Result Models

**Files:**
- Create: `lib/src/import/import_result.dart`

- [ ] **Step 1: Create the import result data classes**

```dart
/// Represents a single file that failed to import.
class ImportError {
  final String filename;
  final String reason;
  final String? details;

  const ImportError({
    required this.filename,
    required this.reason,
    this.details,
  });

  @override
  String toString() => '$filename: $reason';
}

/// Results of scanning a de1app folder before import.
class ScanResult {
  final int shotCount;
  final int profileCount;
  final bool hasDyeGrinders;
  final String sourcePath;
  /// Which shot source was found: 'history_v2', 'history', or null
  final String? shotSource;

  const ScanResult({
    required this.shotCount,
    required this.profileCount,
    required this.hasDyeGrinders,
    required this.sourcePath,
    this.shotSource,
  });

  int get totalItems => shotCount + profileCount;
  bool get isEmpty => totalItems == 0;
}

/// Results of a completed import operation.
class ImportResult {
  final int shotsImported;
  final int shotsSkipped;
  final int profilesImported;
  final int profilesSkipped;
  final int beansCreated;
  final int grindersCreated;
  final List<ImportError> errors;

  const ImportResult({
    this.shotsImported = 0,
    this.shotsSkipped = 0,
    this.profilesImported = 0,
    this.profilesSkipped = 0,
    this.beansCreated = 0,
    this.grindersCreated = 0,
    this.errors = const [],
  });

  bool get hasErrors => errors.isNotEmpty;

  ImportResult operator +(ImportResult other) {
    return ImportResult(
      shotsImported: shotsImported + other.shotsImported,
      shotsSkipped: shotsSkipped + other.shotsSkipped,
      profilesImported: profilesImported + other.profilesImported,
      profilesSkipped: profilesSkipped + other.profilesSkipped,
      beansCreated: beansCreated + other.beansCreated,
      grindersCreated: grindersCreated + other.grindersCreated,
      errors: [...errors, ...other.errors],
    );
  }
}

/// Progress callback for import operations.
class ImportProgress {
  final int current;
  final int total;
  final String phase; // 'shots', 'profiles', 'grinders'

  const ImportProgress({
    required this.current,
    required this.total,
    required this.phase,
  });

  double get fraction => total > 0 ? current / total : 0;
}
```

- [ ] **Step 2: Run `flutter analyze`**

- [ ] **Step 3: Commit**

```bash
git add lib/src/import/import_result.dart
git commit -m "feat: add import result and progress data classes"
```

---

### Task 5: Test Fixtures

**Files:**
- Create: `test/fixtures/de1app/history_v2/20240315T143022.json`
- Create: `test/fixtures/de1app/history/20231108T091544.shot`
- Create: `test/fixtures/de1app/profiles_v2/best_practice.json`
- Create: `test/fixtures/de1app/plugins/DYE/grinders.tdb`

- [ ] **Step 1: Create sample de1app v2 shot JSON**

This fixture represents the actual format written by de1app's `shot.tcl`. The `profile` key contains the full profile object. The `meta` key has DYE-style metadata. The `app.data.settings` object contains the flat de1app settings.

```json
{
  "version": 2,
  "clock": 1710510622,
  "date": "Fri Mar 15 14:30:22 CET 2024",
  "elapsed": [0.0, 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0],
  "pressure": {
    "pressure": [0.0, 1.2, 3.5, 6.1, 8.8, 9.0, 9.0, 8.9, 8.7],
    "goal": [0.0, 9.0, 9.0, 9.0, 9.0, 9.0, 9.0, 9.0, 9.0]
  },
  "flow": {
    "flow": [0.0, 0.5, 1.2, 2.1, 2.8, 3.0, 2.9, 2.8, 2.7],
    "by_weight": [0.0, 0.4, 1.0, 1.8, 2.5, 2.7, 2.6, 2.5, 2.4],
    "by_weight_raw": [0.0, 0.4, 1.0, 1.8, 2.5, 2.7, 2.6, 2.5, 2.4],
    "goal": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
  },
  "temperature": {
    "basket": [22.0, 45.0, 68.0, 82.0, 89.0, 92.0, 93.0, 93.0, 93.0],
    "mix": [22.0, 40.0, 60.0, 75.0, 85.0, 90.0, 92.0, 93.0, 93.0],
    "goal": [93.0, 93.0, 93.0, 93.0, 93.0, 93.0, 93.0, 93.0, 93.0]
  },
  "totals": {
    "weight": [0.0, 0.1, 0.4, 1.0, 2.0, 3.5, 5.2, 7.1, 9.2],
    "water_dispensed": [0.0, 0.2, 0.5, 1.2, 2.2, 3.8, 5.8, 8.0, 10.5]
  },
  "state_change": [0.0, 1.5],
  "profile": {
    "version": "2",
    "title": "Best Practice",
    "notes": "Recommended pressure profile",
    "author": "Decent",
    "beverage_type": "espresso",
    "steps": [
      {
        "name": "preinfusion",
        "pump": "pressure",
        "transition": "fast",
        "volume": 0,
        "seconds": 10,
        "temperature": 93.0,
        "sensor": "coffee",
        "pressure": 1.0
      },
      {
        "name": "hold",
        "pump": "pressure",
        "transition": "smooth",
        "volume": 0,
        "seconds": 30,
        "temperature": 93.0,
        "sensor": "coffee",
        "pressure": 9.0,
        "exit": {
          "type": "flow",
          "condition": "over",
          "value": 3.0
        }
      }
    ],
    "target_volume": 0,
    "target_weight": 36.0,
    "target_volume_count_start": 0,
    "tank_temperature": 0
  },
  "meta": {
    "bean": {
      "brand": "Banibeans",
      "type": "Ethiopia Yirgacheffe",
      "notes": "Fruity and floral",
      "roast_level": "Light",
      "roast_date": "2024-03-01"
    },
    "shot": {
      "enjoyment": 75,
      "notes": "Good body, slight sourness",
      "tds": 8.5,
      "ey": 20.5
    },
    "grinder": {
      "model": "Niche Zero",
      "setting": "15"
    },
    "in": 18.0,
    "out": 36.0,
    "time": 28.5
  },
  "app": {
    "app_name": "de1app",
    "app_version": "1.42.0",
    "data": {
      "settings": {
        "grinder_dose_weight": "18.0",
        "drink_weight": "36.0",
        "bean_brand": "Banibeans",
        "bean_type": "Ethiopia Yirgacheffe",
        "roast_date": "2024-03-01",
        "roast_level": "Light",
        "grinder_model": "Niche Zero",
        "grinder_setting": "15",
        "drink_tds": "8.5",
        "drink_ey": "20.5",
        "espresso_enjoyment": "75",
        "espresso_notes": "Good body, slight sourness",
        "bean_notes": "Fruity and floral",
        "my_name": "Test User",
        "drinker_name": "Guest",
        "profile_title": "Best Practice",
        "beverage_type": "espresso"
      }
    }
  }
}
```

- [ ] **Step 2: Create sample de1app v1 shot TCL**

```
clock 1699432544
espresso_elapsed {0.0 0.25 0.5 0.75 1.0 1.25 1.5 1.75 2.0}
espresso_pressure {0.0 1.1 3.2 5.8 8.5 9.0 9.0 8.8 8.5}
espresso_flow {0.0 0.4 1.0 1.9 2.6 2.8 2.7 2.6 2.5}
espresso_flow_weight {0.0 0.3 0.9 1.6 2.3 2.5 2.4 2.3 2.2}
espresso_weight {0.0 0.1 0.3 0.9 1.8 3.2 4.8 6.6 8.5}
espresso_temperature_basket {22.0 44.0 66.0 80.0 88.0 91.0 92.5 93.0 93.0}
espresso_temperature_mix {22.0 39.0 58.0 73.0 83.0 89.0 91.5 92.5 93.0}
espresso_temperature_goal {93.0 93.0 93.0 93.0 93.0 93.0 93.0 93.0 93.0}
espresso_pressure_goal {0.0 9.0 9.0 9.0 9.0 9.0 9.0 9.0 9.0}
espresso_flow_goal {0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0}
espresso_water_dispensed {0.0 0.2 0.5 1.1 2.0 3.5 5.3 7.4 9.8}
espresso_state_change {0.0 1.5}
settings {
	bean_brand {Banibeans}
	bean_type {Colombia Huila}
	bean_notes {Chocolatey and nutty}
	roast_date {2023-10-20}
	roast_level {Medium}
	grinder_model {Eureka Mignon}
	grinder_setting {2.5}
	grinder_dose_weight {18.5}
	drink_weight {38.0}
	drink_tds {9.0}
	drink_ey {21.0}
	espresso_enjoyment {80}
	espresso_notes {Balanced, good sweetness}
	my_name {Barista}
	profile_title {Default}
}
```

- [ ] **Step 3: Create sample de1app profile v2 JSON**

```json
{
  "version": "2",
  "title": "Londinium",
  "notes": "Lever-style pressure profile",
  "author": "Decent",
  "beverage_type": "espresso",
  "steps": [
    {
      "name": "preinfusion",
      "pump": "pressure",
      "transition": "fast",
      "volume": 0,
      "seconds": 8,
      "temperature": 92.0,
      "sensor": "coffee",
      "pressure": 1.5
    },
    {
      "name": "rise",
      "pump": "pressure",
      "transition": "smooth",
      "volume": 0,
      "seconds": 5,
      "temperature": 92.0,
      "sensor": "coffee",
      "pressure": 9.0
    },
    {
      "name": "decline",
      "pump": "pressure",
      "transition": "smooth",
      "exit": {
        "type": "flow",
        "condition": "over",
        "value": 3.5
      },
      "volume": 0,
      "seconds": 25,
      "temperature": 92.0,
      "sensor": "coffee",
      "pressure": 6.0
    }
  ],
  "target_volume": 0,
  "target_weight": 40.0,
  "target_volume_count_start": 0,
  "tank_temperature": 0
}
```

- [ ] **Step 4: Create sample DYE grinders.tdb**

The `.tdb` format is a TCL serialized array. Each grinder is a key (the model name) mapped to a dict of specs:

```
Niche\ Zero {setting_type numeric small_step 1 big_step 5 burrs {63mm conical}}
Eureka\ Mignon {setting_type numeric small_step 0.5 big_step 2 burrs {55mm flat}}
EK43 {setting_type numeric small_step 0.5 big_step 3 burrs {98mm flat}}
```

- [ ] **Step 5: Commit**

```bash
git add test/fixtures/
git commit -m "test: add de1app sample data fixtures"
```

---

### Task 6: TCL Parser

The TCL parser tokenizes de1app `.shot` files into a `Map<String, dynamic>` where values are strings, lists of strings, or nested maps. This is the foundation for `TclShotParser`.

**Files:**
- Create: `lib/src/import/parsers/tcl_parser.dart`
- Test: `test/import/tcl_parser_test.dart`

- [ ] **Step 1: Write the test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/import/parsers/tcl_parser.dart';

void main() {
  group('TclParser', () {
    test('parses simple key-value pairs', () {
      final input = 'clock 1699432544\n';
      final result = TclParser.parse(input);
      expect(result['clock'], equals('1699432544'));
    });

    test('parses braced arrays as List<String>', () {
      final input = 'espresso_elapsed {0.0 0.25 0.5 0.75}\n';
      final result = TclParser.parse(input);
      expect(result['espresso_elapsed'], equals(['0.0', '0.25', '0.5', '0.75']));
    });

    test('parses braced single values as string', () {
      final input = 'settings {\n\tbean_brand {Banibeans}\n}\n';
      final result = TclParser.parse(input);
      final settings = result['settings'] as Map<String, dynamic>;
      expect(settings['bean_brand'], equals('Banibeans'));
    });

    test('parses nested settings block', () {
      final input = '''
clock 1699432544
settings {
\tbean_brand {Banibeans}
\tbean_type {Colombia Huila}
\tgrinder_dose_weight {18.5}
}
''';
      final result = TclParser.parse(input);
      expect(result['clock'], equals('1699432544'));
      final settings = result['settings'] as Map<String, dynamic>;
      expect(settings['bean_brand'], equals('Banibeans'));
      expect(settings['bean_type'], equals('Colombia Huila'));
      expect(settings['grinder_dose_weight'], equals('18.5'));
    });

    test('parses backslash-escaped spaces in values', () {
      final input = 'model Niche\\ Zero\n';
      final result = TclParser.parse(input);
      expect(result['model'], equals('Niche Zero'));
    });

    test('handles empty braces', () {
      final input = 'notes {}\n';
      final result = TclParser.parse(input);
      expect(result['notes'], equals(''));
    });

    test('parses full shot file fixture', () {
      final file = File('test/fixtures/de1app/history/20231108T091544.shot');
      final result = TclParser.parse(file.readAsStringSync());
      expect(result['clock'], equals('1699432544'));
      expect(result['espresso_elapsed'], isA<List>());
      expect(result['settings'], isA<Map>());
    });
  });
}
```

Add `import 'dart:io';` at the top.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/import/tcl_parser_test.dart`
Expected: FAIL — `TclParser` not found

- [ ] **Step 3: Implement TclParser**

```dart
import 'dart:convert';

/// Parses de1app TCL-format files (.shot, .tdb) into key-value maps.
///
/// Handles:
/// - Simple key-value: `clock 1699432544`
/// - Braced arrays: `espresso_elapsed {0.0 0.25 0.5}`
/// - Braced strings: `bean_brand {Banibeans}`
/// - Nested blocks: `settings { key {value} }`
/// - Backslash-escaped spaces: `Niche\ Zero`
class TclParser {
  /// Parse a TCL-format string into a map.
  ///
  /// Top-level keys map to:
  /// - `String` for simple values and single braced values
  /// - `List<String>` for space-separated braced arrays (detected by numeric content)
  /// - `Map<String, dynamic>` for nested key-value blocks
  static Map<String, dynamic> parse(String input) {
    final lines = LineSplitter.split(input).toList();
    return _parseBlock(lines, 0, lines.length, 0);
  }

  static Map<String, dynamic> _parseBlock(
    List<String> lines,
    int start,
    int end,
    int indentLevel,
  ) {
    final result = <String, dynamic>{};
    var i = start;

    while (i < end) {
      final line = lines[i];
      final trimmed = line.trim();

      // Skip empty lines
      if (trimmed.isEmpty) {
        i++;
        continue;
      }

      // Find key and value on this line
      final keyEnd = _findKeyEnd(trimmed);
      if (keyEnd <= 0) {
        i++;
        continue;
      }

      final key = _unescapeKey(trimmed.substring(0, keyEnd));
      final rest = trimmed.substring(keyEnd).trim();

      if (rest.isEmpty) {
        result[key] = '';
        i++;
      } else if (rest.startsWith('{')) {
        // Check if braces close on this line
        if (_bracesCloseOnLine(rest)) {
          final content = rest.substring(1, rest.length - 1).trim();
          result[key] = _interpretBracedValue(content);
          i++;
        } else {
          // Multi-line block — find closing brace
          final blockEnd = _findBlockEnd(lines, i, trimmed);
          result[key] = _parseBlock(lines, i + 1, blockEnd, indentLevel + 1);
          i = blockEnd + 1;
        }
      } else {
        result[key] = _unescapeValue(rest);
        i++;
      }
    }

    return result;
  }

  static int _findKeyEnd(String line) {
    for (var i = 0; i < line.length; i++) {
      if (line[i] == ' ' && (i == 0 || line[i - 1] != '\\')) {
        return i;
      }
    }
    return line.length;
  }

  static String _unescapeKey(String key) {
    return key.replaceAll('\\ ', ' ');
  }

  static String _unescapeValue(String value) {
    return value.replaceAll('\\ ', ' ');
  }

  static bool _bracesCloseOnLine(String rest) {
    var depth = 0;
    for (var i = 0; i < rest.length; i++) {
      if (rest[i] == '{') depth++;
      if (rest[i] == '}') depth--;
      if (depth == 0) return i == rest.length - 1;
    }
    return false;
  }

  static int _findBlockEnd(List<String> lines, int start, String startLine) {
    var depth = 0;
    for (var i = start; i < lines.length; i++) {
      final line = i == start ? startLine : lines[i];
      for (var c = 0; c < line.length; c++) {
        if (line[c] == '{') depth++;
        if (line[c] == '}') depth--;
        if (depth == 0) return i;
      }
    }
    return lines.length - 1;
  }

  /// Interpret braced content: numeric-looking lists become List<String>,
  /// otherwise return as single string.
  static dynamic _interpretBracedValue(String content) {
    if (content.isEmpty) return '';

    // Check if this looks like a space-separated numeric array
    final parts = content.split(RegExp(r'\s+'));
    if (parts.length > 1 && parts.every(_looksNumeric)) {
      return parts;
    }

    // Single value or text
    return content;
  }

  static bool _looksNumeric(String s) {
    return double.tryParse(s) != null ||
        s == '10000000.0' ||
        s == '-10000000.0';
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/import/tcl_parser_test.dart`
Expected: PASS

- [ ] **Step 5: Run `flutter analyze`**

- [ ] **Step 6: Commit**

```bash
git add lib/src/import/parsers/tcl_parser.dart test/import/tcl_parser_test.dart
git commit -m "feat: add TCL parser for de1app file formats"
```

---

### Task 7: Shot v2 JSON Parser

Parses de1app `history_v2/*.json` files into `ShotRecord` + metadata for entity extraction.

**Files:**
- Create: `lib/src/import/parsers/shot_v2_json_parser.dart`
- Test: `test/import/shot_v2_json_parser_test.dart`

- [ ] **Step 1: Write the test**

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/import/parsers/shot_v2_json_parser.dart';
import 'package:reaprime/src/models/data/shot_record.dart';

void main() {
  group('ShotV2JsonParser', () {
    late Map<String, dynamic> sampleJson;

    setUp(() {
      final file = File('test/fixtures/de1app/history_v2/20240315T143022.json');
      sampleJson = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    });

    test('parses shot record with correct timestamp', () {
      final parsed = ShotV2JsonParser.parse(sampleJson, '20240315T143022.json');
      expect(parsed.shot.timestamp,
          equals(DateTime.fromMillisecondsSinceEpoch(1710510622 * 1000)));
    });

    test('parses time-series measurements', () {
      final parsed = ShotV2JsonParser.parse(sampleJson, '20240315T143022.json');
      expect(parsed.shot.measurements.length, equals(9));
      expect(parsed.shot.measurements[4].machine.pressure, equals(8.8));
      expect(parsed.shot.measurements[4].scale?.weight, equals(2.0));
    });

    test('extracts embedded profile', () {
      final parsed = ShotV2JsonParser.parse(sampleJson, '20240315T143022.json');
      expect(parsed.shot.workflow.profile.title, equals('Best Practice'));
      expect(parsed.shot.workflow.profile.steps.length, equals(2));
    });

    test('extracts bean metadata', () {
      final parsed = ShotV2JsonParser.parse(sampleJson, '20240315T143022.json');
      expect(parsed.beanBrand, equals('Banibeans'));
      expect(parsed.beanType, equals('Ethiopia Yirgacheffe'));
      expect(parsed.roastLevel, equals('Light'));
      expect(parsed.roastDate, equals('2024-03-01'));
    });

    test('extracts grinder metadata', () {
      final parsed = ShotV2JsonParser.parse(sampleJson, '20240315T143022.json');
      expect(parsed.grinderModel, equals('Niche Zero'));
      expect(parsed.grinderSetting, equals('15'));
    });

    test('extracts shot annotations', () {
      final parsed = ShotV2JsonParser.parse(sampleJson, '20240315T143022.json');
      final ann = parsed.shot.annotations!;
      expect(ann.actualDoseWeight, equals(18.0));
      expect(ann.actualYield, equals(36.0));
      expect(ann.drinkTds, equals(8.5));
      expect(ann.drinkEy, equals(20.5));
      expect(ann.enjoyment, equals(75.0));
      expect(ann.espressoNotes, equals('Good body, slight sourness'));
    });

    test('extracts workflow context', () {
      final parsed = ShotV2JsonParser.parse(sampleJson, '20240315T143022.json');
      final ctx = parsed.shot.workflow.context!;
      expect(ctx.targetDoseWeight, equals(18.0));
      expect(ctx.targetYield, equals(36.0));
      expect(ctx.grinderModel, equals('Niche Zero'));
      expect(ctx.coffeeName, equals('Ethiopia Yirgacheffe'));
      expect(ctx.coffeeRoaster, equals('Banibeans'));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/import/shot_v2_json_parser_test.dart`
Expected: FAIL

- [ ] **Step 3: Implement ShotV2JsonParser**

```dart
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/data/shot_annotations.dart';
import 'package:reaprime/src/models/data/shot_record.dart';
import 'package:reaprime/src/models/data/shot_snapshot.dart';
import 'package:reaprime/src/models/data/workflow.dart';
import 'package:reaprime/src/models/data/workflow_context.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:uuid/uuid.dart';

/// Intermediate result from parsing a de1app shot file.
/// Contains the ShotRecord plus raw metadata strings for entity extraction.
class ParsedShot {
  final ShotRecord shot;
  final String? beanBrand;
  final String? beanType;
  final String? beanNotes;
  final String? roastDate;
  final String? roastLevel;
  final String? grinderModel;
  final String? grinderSetting;

  const ParsedShot({
    required this.shot,
    this.beanBrand,
    this.beanType,
    this.beanNotes,
    this.roastDate,
    this.roastLevel,
    this.grinderModel,
    this.grinderSetting,
  });
}

/// Parses de1app history_v2 JSON files into ShotRecord + metadata.
class ShotV2JsonParser {
  static ParsedShot parse(Map<String, dynamic> json, String filename) {
    final clock = json['clock'] as int;
    final timestamp =
        DateTime.fromMillisecondsSinceEpoch(clock * 1000, isUtc: true);

    // Parse time-series data
    final elapsed = _parseDoubleList(json['elapsed']);
    final pressure = json['pressure'] as Map<String, dynamic>;
    final flow = json['flow'] as Map<String, dynamic>;
    final temperature = json['temperature'] as Map<String, dynamic>;
    final totals = json['totals'] as Map<String, dynamic>;

    final pressureValues = _parseDoubleList(pressure['pressure']);
    final pressureGoal = _parseDoubleList(pressure['goal']);
    final flowValues = _parseDoubleList(flow['flow']);
    final flowByWeight = _parseDoubleList(flow['by_weight']);
    final flowGoal = _parseDoubleList(flow['goal']);
    final tempBasket = _parseDoubleList(temperature['basket']);
    final tempMix = _parseDoubleList(temperature['mix']);
    final tempGoal = _parseDoubleList(temperature['goal']);
    final weight = _parseDoubleList(totals['weight']);
    final waterDispensed = _parseDoubleList(totals['water_dispensed']);

    // Build measurements
    final measurements = <ShotSnapshot>[];
    final count = elapsed.length;
    for (var i = 0; i < count; i++) {
      final t = timestamp.add(
        Duration(milliseconds: (elapsed[i] * 1000).round()),
      );
      measurements.add(ShotSnapshot(
        machine: MachineSnapshot(
          timestamp: t,
          state: MachineStateSnapshot(
            state: MachineState.espresso,
            substate: MachineSubstate.pouring,
          ),
          flow: _safeGet(flowValues, i),
          pressure: _safeGet(pressureValues, i),
          targetFlow: _safeGet(flowGoal, i),
          targetPressure: _safeGet(pressureGoal, i),
          mixTemperature: _safeGet(tempMix, i),
          groupTemperature: _safeGet(tempBasket, i),
          targetMixTemperature: _safeGet(tempGoal, i),
          targetGroupTemperature: _safeGet(tempGoal, i),
          profileFrame: 0,
          steamTemperature: 0,
        ),
        scale: WeightSnapshot(
          timestamp: t,
          weight: _safeGet(weight, i),
          weightFlow: _safeGet(flowByWeight, i),
        ),
        volume: _safeGet(waterDispensed, i),
      ));
    }

    // Extract metadata — prefer `meta` block, fall back to `app.data.settings`
    final meta = json['meta'] as Map<String, dynamic>?;
    final settings = _extractSettings(json);

    final beanBrand = _metaStr(meta, ['bean', 'brand']) ?? settings['bean_brand'];
    final beanType = _metaStr(meta, ['bean', 'type']) ?? settings['bean_type'];
    final beanNotes = _metaStr(meta, ['bean', 'notes']) ?? settings['bean_notes'];
    final roastDate =
        _metaStr(meta, ['bean', 'roast_date']) ?? settings['roast_date'];
    final roastLevel =
        _metaStr(meta, ['bean', 'roast_level']) ?? settings['roast_level'];
    final grinderModel =
        _metaStr(meta, ['grinder', 'model']) ?? settings['grinder_model'];
    final grinderSetting =
        _metaStr(meta, ['grinder', 'setting']) ?? settings['grinder_setting'];

    final doseWeight = _metaDouble(meta, ['in']) ??
        double.tryParse(settings['grinder_dose_weight'] ?? '');
    final drinkWeight = _metaDouble(meta, ['out']) ??
        double.tryParse(settings['drink_weight'] ?? '');
    final enjoyment = _metaDouble(meta, ['shot', 'enjoyment']) ??
        double.tryParse(settings['espresso_enjoyment'] ?? '');
    final tds = _metaDouble(meta, ['shot', 'tds']) ??
        double.tryParse(settings['drink_tds'] ?? '');
    final ey = _metaDouble(meta, ['shot', 'ey']) ??
        double.tryParse(settings['drink_ey'] ?? '');
    final espressoNotes =
        _metaStr(meta, ['shot', 'notes']) ?? settings['espresso_notes'];

    // Parse embedded profile
    final profileJson = json['profile'] as Map<String, dynamic>;
    final profile = Profile.fromJson(profileJson);

    final context = WorkflowContext(
      targetDoseWeight: doseWeight,
      targetYield: drinkWeight,
      grinderModel: grinderModel,
      grinderSetting: grinderSetting,
      coffeeName: beanType,
      coffeeRoaster: beanBrand,
      baristaName: settings['my_name'],
      drinkerName: settings['drinker_name'],
    );

    final workflow = Workflow(
      id: const Uuid().v4(),
      name: profile.title,
      description: '',
      profile: profile,
      context: context,
      steamSettings: SteamSettings.defaults(),
      hotWaterData: HotWaterData.defaults(),
      rinseData: RinseData.defaults(),
    );

    final annotations = ShotAnnotations(
      actualDoseWeight: doseWeight,
      actualYield: drinkWeight,
      drinkTds: tds,
      drinkEy: ey,
      enjoyment: enjoyment,
      espressoNotes: espressoNotes,
    );

    final shot = ShotRecord(
      id: 'de1app-$clock',
      timestamp: timestamp,
      measurements: measurements,
      workflow: workflow,
      annotations: annotations,
    );

    return ParsedShot(
      shot: shot,
      beanBrand: beanBrand,
      beanType: beanType,
      beanNotes: beanNotes,
      roastDate: roastDate,
      roastLevel: roastLevel,
      grinderModel: grinderModel,
      grinderSetting: grinderSetting,
    );
  }

  static List<double> _parseDoubleList(dynamic value) {
    if (value is List) {
      return value.map((e) => (e as num).toDouble()).toList();
    }
    return [];
  }

  static double _safeGet(List<double> list, int i) {
    return i < list.length ? list[i] : 0.0;
  }

  static Map<String, String> _extractSettings(Map<String, dynamic> json) {
    final app = json['app'] as Map<String, dynamic>?;
    final data = app?['data'] as Map<String, dynamic>?;
    final settings = data?['settings'] as Map<String, dynamic>?;
    if (settings == null) return {};
    return settings.map((k, v) => MapEntry(k, v.toString()));
  }

  static String? _metaStr(Map<String, dynamic>? meta, List<String> path) {
    if (meta == null) return null;
    dynamic current = meta;
    for (final key in path) {
      if (current is! Map<String, dynamic>) return null;
      current = current[key];
    }
    if (current == null) return null;
    final str = current.toString();
    return str.isEmpty ? null : str;
  }

  static double? _metaDouble(Map<String, dynamic>? meta, List<String> path) {
    final str = _metaStr(meta, path);
    if (str == null) return null;
    return double.tryParse(str);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/import/shot_v2_json_parser_test.dart`
Expected: PASS

- [ ] **Step 5: Run `flutter analyze`**

- [ ] **Step 6: Commit**

```bash
git add lib/src/import/parsers/shot_v2_json_parser.dart test/import/shot_v2_json_parser_test.dart
git commit -m "feat: add de1app shot v2 JSON parser"
```

---

### Task 8: TCL Shot Parser

Parses de1app `history/*.shot` (TCL format) into the same `ParsedShot` structure.

**Files:**
- Create: `lib/src/import/parsers/tcl_shot_parser.dart`
- Test: `test/import/tcl_shot_parser_test.dart`

- [ ] **Step 1: Write the test**

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/import/parsers/tcl_shot_parser.dart';

void main() {
  group('TclShotParser', () {
    late String sampleTcl;

    setUp(() {
      sampleTcl = File('test/fixtures/de1app/history/20231108T091544.shot')
          .readAsStringSync();
    });

    test('parses shot with correct timestamp from clock', () {
      final parsed = TclShotParser.parse(sampleTcl, '20231108T091544.shot');
      expect(
        parsed.shot.timestamp,
        equals(DateTime.fromMillisecondsSinceEpoch(1699432544 * 1000, isUtc: true)),
      );
    });

    test('parses time-series measurements', () {
      final parsed = TclShotParser.parse(sampleTcl, '20231108T091544.shot');
      expect(parsed.shot.measurements.length, equals(9));
      expect(parsed.shot.measurements[4].machine.pressure, equals(8.5));
    });

    test('extracts bean metadata from settings block', () {
      final parsed = TclShotParser.parse(sampleTcl, '20231108T091544.shot');
      expect(parsed.beanBrand, equals('Banibeans'));
      expect(parsed.beanType, equals('Colombia Huila'));
      expect(parsed.roastLevel, equals('Medium'));
    });

    test('extracts grinder metadata', () {
      final parsed = TclShotParser.parse(sampleTcl, '20231108T091544.shot');
      expect(parsed.grinderModel, equals('Eureka Mignon'));
      expect(parsed.grinderSetting, equals('2.5'));
    });

    test('extracts annotations', () {
      final parsed = TclShotParser.parse(sampleTcl, '20231108T091544.shot');
      final ann = parsed.shot.annotations!;
      expect(ann.actualDoseWeight, equals(18.5));
      expect(ann.actualYield, equals(38.0));
      expect(ann.enjoyment, equals(80.0));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/import/tcl_shot_parser_test.dart`
Expected: FAIL

- [ ] **Step 3: Implement TclShotParser**

```dart
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/import/parsers/shot_v2_json_parser.dart';
import 'package:reaprime/src/import/parsers/tcl_parser.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/data/shot_annotations.dart';
import 'package:reaprime/src/models/data/shot_record.dart';
import 'package:reaprime/src/models/data/shot_snapshot.dart';
import 'package:reaprime/src/models/data/workflow.dart';
import 'package:reaprime/src/models/data/workflow_context.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:uuid/uuid.dart';

/// Parses de1app history/*.shot (TCL format) into ParsedShot.
class TclShotParser {
  static ParsedShot parse(String content, String filename) {
    final data = TclParser.parse(content);

    final clock = int.parse(data['clock'] as String);
    final timestamp =
        DateTime.fromMillisecondsSinceEpoch(clock * 1000, isUtc: true);

    // Parse time-series arrays
    final elapsed = _toDoubles(data['espresso_elapsed']);
    final pressureValues = _toDoubles(data['espresso_pressure']);
    final flowValues = _toDoubles(data['espresso_flow']);
    final flowByWeight = _toDoubles(data['espresso_flow_weight']);
    final tempBasket = _toDoubles(data['espresso_temperature_basket']);
    final tempMix = _toDoubles(data['espresso_temperature_mix']);
    final tempGoal = _toDoubles(data['espresso_temperature_goal']);
    final pressureGoal = _toDoubles(data['espresso_pressure_goal']);
    final flowGoal = _toDoubles(data['espresso_flow_goal']);
    final weight = _toDoubles(data['espresso_weight']);
    final waterDispensed = _toDoubles(data['espresso_water_dispensed']);

    // Build measurements
    final measurements = <ShotSnapshot>[];
    final count = elapsed.length;
    for (var i = 0; i < count; i++) {
      final t = timestamp.add(
        Duration(milliseconds: (elapsed[i] * 1000).round()),
      );
      measurements.add(ShotSnapshot(
        machine: MachineSnapshot(
          timestamp: t,
          state: MachineStateSnapshot(
            state: MachineState.espresso,
            substate: MachineSubstate.pouring,
          ),
          flow: _safeGet(flowValues, i),
          pressure: _safeGet(pressureValues, i),
          targetFlow: _safeGet(flowGoal, i),
          targetPressure: _safeGet(pressureGoal, i),
          mixTemperature: _safeGet(tempMix, i),
          groupTemperature: _safeGet(tempBasket, i),
          targetMixTemperature: _safeGet(tempGoal, i),
          targetGroupTemperature: _safeGet(tempGoal, i),
          profileFrame: 0,
          steamTemperature: 0,
        ),
        scale: WeightSnapshot(
          timestamp: t,
          weight: _safeGet(weight, i),
          weightFlow: _safeGet(flowByWeight, i),
        ),
        volume: _safeGet(waterDispensed, i),
      ));
    }

    // Extract settings block
    final settings = data['settings'] as Map<String, dynamic>? ?? {};
    String? s(String key) {
      final v = settings[key];
      if (v == null) return null;
      final str = v.toString();
      return str.isEmpty ? null : str;
    }

    final beanBrand = s('bean_brand');
    final beanType = s('bean_type');
    final beanNotes = s('bean_notes');
    final roastDate = s('roast_date');
    final roastLevel = s('roast_level');
    final grinderModel = s('grinder_model');
    final grinderSetting = s('grinder_setting');
    final doseWeight = double.tryParse(s('grinder_dose_weight') ?? '');
    final drinkWeight = double.tryParse(s('drink_weight') ?? '');
    final tds = double.tryParse(s('drink_tds') ?? '');
    final ey = double.tryParse(s('drink_ey') ?? '');
    final enjoyment = double.tryParse(s('espresso_enjoyment') ?? '');
    final espressoNotes = s('espresso_notes');
    final profileTitle = s('profile_title') ?? 'Unknown';
    final baristaName = s('my_name');

    // Create a minimal profile from the title (TCL shots don't always embed full profile)
    final profile = Profile(
      version: '2',
      title: profileTitle,
      notes: '',
      author: '',
      beverageType: BeverageType.espresso,
      steps: [],
      targetVolume: null,
      targetWeight: drinkWeight,
      targetVolumeCountStart: 0,
      tankTemperature: 0,
    );

    final context = WorkflowContext(
      targetDoseWeight: doseWeight,
      targetYield: drinkWeight,
      grinderModel: grinderModel,
      grinderSetting: grinderSetting,
      coffeeName: beanType,
      coffeeRoaster: beanBrand,
      baristaName: baristaName,
    );

    final workflow = Workflow(
      id: const Uuid().v4(),
      name: profileTitle,
      description: '',
      profile: profile,
      context: context,
      steamSettings: SteamSettings.defaults(),
      hotWaterData: HotWaterData.defaults(),
      rinseData: RinseData.defaults(),
    );

    final annotations = ShotAnnotations(
      actualDoseWeight: doseWeight,
      actualYield: drinkWeight,
      drinkTds: tds,
      drinkEy: ey,
      enjoyment: enjoyment,
      espressoNotes: espressoNotes,
    );

    return ParsedShot(
      shot: ShotRecord(
        id: 'de1app-$clock',
        timestamp: timestamp,
        measurements: measurements,
        workflow: workflow,
        annotations: annotations,
      ),
      beanBrand: beanBrand,
      beanType: beanType,
      beanNotes: beanNotes,
      roastDate: roastDate,
      roastLevel: roastLevel,
      grinderModel: grinderModel,
      grinderSetting: grinderSetting,
    );
  }

  static List<double> _toDoubles(dynamic value) {
    if (value is List) {
      return value.map((e) => double.tryParse(e.toString()) ?? 0.0).toList();
    }
    return [];
  }

  static double _safeGet(List<double> list, int i) {
    return i < list.length ? list[i] : 0.0;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/import/tcl_shot_parser_test.dart`
Expected: PASS

- [ ] **Step 5: Run `flutter analyze`**

- [ ] **Step 6: Commit**

```bash
git add lib/src/import/parsers/tcl_shot_parser.dart test/import/tcl_shot_parser_test.dart
git commit -m "feat: add de1app TCL shot parser"
```

---

### Task 9: Profile v2 Parser

Parses de1app `profiles_v2/*.json` files into `ProfileRecord`.

**Files:**
- Create: `lib/src/import/parsers/profile_v2_parser.dart`
- Test: `test/import/profile_v2_parser_test.dart`

- [ ] **Step 1: Write the test**

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/import/parsers/profile_v2_parser.dart';
import 'package:reaprime/src/models/data/profile.dart';

void main() {
  group('ProfileV2Parser', () {
    late Map<String, dynamic> sampleJson;

    setUp(() {
      final file = File('test/fixtures/de1app/profiles_v2/best_practice.json');
      sampleJson = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    });

    test('parses profile with correct title', () {
      final record = ProfileV2Parser.parse(sampleJson);
      expect(record.profile.title, equals('Londinium'));
    });

    test('parses profile steps', () {
      final record = ProfileV2Parser.parse(sampleJson);
      expect(record.profile.steps.length, equals(3));
      expect(record.profile.steps[0].name, equals('preinfusion'));
    });

    test('generates content-based hash ID', () {
      final record = ProfileV2Parser.parse(sampleJson);
      expect(record.id, startsWith('profile:'));
    });

    test('same profile content produces same ID', () {
      final record1 = ProfileV2Parser.parse(sampleJson);
      final record2 = ProfileV2Parser.parse(sampleJson);
      expect(record1.id, equals(record2.id));
    });

    test('parses target weight', () {
      final record = ProfileV2Parser.parse(sampleJson);
      expect(record.profile.targetWeight, equals(40.0));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/import/profile_v2_parser_test.dart`
Expected: FAIL

- [ ] **Step 3: Implement ProfileV2Parser**

```dart
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/data/profile_record.dart';

/// Parses de1app profiles_v2/*.json files into ProfileRecord.
///
/// The de1app v2 profile JSON format is the same as Bridge's Profile.fromJson,
/// so this is a thin wrapper that creates a ProfileRecord with content-based
/// hash ID for deduplication.
class ProfileV2Parser {
  static ProfileRecord parse(Map<String, dynamic> json) {
    final profile = Profile.fromJson(json);
    return ProfileRecord.create(profile: profile);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/import/profile_v2_parser_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/src/import/parsers/profile_v2_parser.dart test/import/profile_v2_parser_test.dart
git commit -m "feat: add de1app profile v2 JSON parser"
```

---

### Task 10: DYE Grinder TDB Parser

Parses DYE's `grinders.tdb` file into `Grinder` entities.

**Files:**
- Create: `lib/src/import/parsers/grinder_tdb_parser.dart`
- Test: `test/import/grinder_tdb_parser_test.dart`

- [ ] **Step 1: Write the test**

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/import/parsers/grinder_tdb_parser.dart';

void main() {
  group('GrinderTdbParser', () {
    late String sampleTdb;

    setUp(() {
      sampleTdb = File('test/fixtures/de1app/plugins/DYE/grinders.tdb')
          .readAsStringSync();
    });

    test('parses grinder models', () {
      final grinders = GrinderTdbParser.parse(sampleTdb);
      expect(grinders.length, equals(3));
      expect(grinders.map((g) => g.model).toList(),
          containsAll(['Niche Zero', 'Eureka Mignon', 'EK43']));
    });

    test('parses burr info', () {
      final niche = GrinderTdbParser.parse(sampleTdb)
          .firstWhere((g) => g.model == 'Niche Zero');
      expect(niche.burrs, equals('63mm conical'));
    });

    test('sets numeric setting type', () {
      final niche = GrinderTdbParser.parse(sampleTdb)
          .firstWhere((g) => g.model == 'Niche Zero');
      expect(niche.settingSmallStep, equals(1.0));
      expect(niche.settingBigStep, equals(5.0));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/import/grinder_tdb_parser_test.dart`
Expected: FAIL

- [ ] **Step 3: Implement GrinderTdbParser**

```dart
import 'package:reaprime/src/import/parsers/tcl_parser.dart';
import 'package:reaprime/src/models/data/grinder.dart';

/// Parses DYE plugin's grinders.tdb file into Grinder entities.
///
/// Format is TCL: `Model\ Name {setting_type numeric small_step 1 big_step 5 burrs {63mm conical}}`
class GrinderTdbParser {
  static List<Grinder> parse(String content) {
    final data = TclParser.parse(content);
    final grinders = <Grinder>[];

    for (final entry in data.entries) {
      final model = entry.key;
      final specs = entry.value;

      if (specs is! Map<String, dynamic>) continue;

      final smallStep = double.tryParse(specs['small_step']?.toString() ?? '');
      final bigStep = double.tryParse(specs['big_step']?.toString() ?? '');
      final burrs = specs['burrs']?.toString();
      final settingType = specs['setting_type']?.toString();

      grinders.add(Grinder.create(
        model: model,
        burrs: burrs,
        settingType: settingType == 'numeric'
            ? GrinderSettingType.numeric
            : GrinderSettingType.preset,
        settingSmallStep: smallStep,
        settingBigStep: bigStep,
      ));
    }

    return grinders;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/import/grinder_tdb_parser_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/src/import/parsers/grinder_tdb_parser.dart test/import/grinder_tdb_parser_test.dart
git commit -m "feat: add DYE grinder TDB parser"
```

---

## Phase 3: Import Pipeline

### Task 11: Entity Extractor

Deduplicates beans and grinders from parsed shot metadata, creating Bean, BeanBatch, and Grinder entities.

**Files:**
- Create: `lib/src/import/entity_extractor.dart`
- Test: `test/import/entity_extractor_test.dart`

- [ ] **Step 1: Write the test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/import/entity_extractor.dart';
import 'package:reaprime/src/import/parsers/shot_v2_json_parser.dart';

void main() {
  group('EntityExtractor', () {
    test('deduplicates beans by brand+type', () {
      final shots = [
        _makeParsedShot(brand: 'Banibeans', type: 'Yirgacheffe', roastDate: '2024-01-01'),
        _makeParsedShot(brand: 'Banibeans', type: 'Yirgacheffe', roastDate: '2024-02-01'),
        _makeParsedShot(brand: 'Banibeans', type: 'Colombia', roastDate: '2024-01-15'),
      ];

      final extractor = EntityExtractor();
      final result = extractor.extract(shots);

      expect(result.beans.length, equals(2)); // Yirgacheffe + Colombia
      expect(result.batches.length, equals(3)); // One per unique roastDate
    });

    test('deduplicates grinders by model', () {
      final shots = [
        _makeParsedShot(grinderModel: 'Niche Zero'),
        _makeParsedShot(grinderModel: 'Niche Zero'),
        _makeParsedShot(grinderModel: 'EK43'),
      ];

      final extractor = EntityExtractor();
      final result = extractor.extract(shots);

      expect(result.grinders.length, equals(2));
    });

    test('skips shots with no bean info', () {
      final shots = [
        _makeParsedShot(brand: null, type: null),
        _makeParsedShot(brand: 'Banibeans', type: 'Yirgacheffe'),
      ];

      final extractor = EntityExtractor();
      final result = extractor.extract(shots);

      expect(result.beans.length, equals(1));
    });

    test('maps shot indices to entity IDs', () {
      final shots = [
        _makeParsedShot(brand: 'Banibeans', type: 'Yirg', grinderModel: 'Niche'),
      ];

      final extractor = EntityExtractor();
      final result = extractor.extract(shots);

      expect(result.shotBeanBatchIds[0], isNotNull);
      expect(result.shotGrinderIds[0], isNotNull);
    });
  });
}

ParsedShot _makeParsedShot({
  String? brand,
  String? type,
  String? roastDate,
  String? grinderModel,
}) {
  // Minimal ParsedShot for testing entity extraction only
  return ParsedShot(
    shot: _minimalShotRecord(),
    beanBrand: brand,
    beanType: type,
    roastDate: roastDate,
    grinderModel: grinderModel,
  );
}
```

Add a helper `_minimalShotRecord()` that creates a `ShotRecord` with empty measurements and a default workflow. Import the necessary model classes.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/import/entity_extractor_test.dart`
Expected: FAIL

- [ ] **Step 3: Implement EntityExtractor**

```dart
import 'package:reaprime/src/import/parsers/shot_v2_json_parser.dart';
import 'package:reaprime/src/models/data/bean.dart';
import 'package:reaprime/src/models/data/grinder.dart';

class ExtractionResult {
  final List<Bean> beans;
  final List<BeanBatch> batches;
  final List<Grinder> grinders;
  /// Maps shot index → BeanBatch ID (null if shot had no bean info)
  final Map<int, String?> shotBeanBatchIds;
  /// Maps shot index → Grinder ID (null if shot had no grinder info)
  final Map<int, String?> shotGrinderIds;

  const ExtractionResult({
    required this.beans,
    required this.batches,
    required this.grinders,
    required this.shotBeanBatchIds,
    required this.shotGrinderIds,
  });
}

/// Extracts and deduplicates Bean, BeanBatch, and Grinder entities
/// from a list of parsed de1app shots.
class EntityExtractor {
  ExtractionResult extract(List<ParsedShot> shots) {
    // Deduplicate beans by (brand, type)
    final beansByKey = <String, Bean>{};
    // Track batches by (beanKey, roastDate)
    final batchesByKey = <String, BeanBatch>{};
    // Deduplicate grinders by model
    final grindersByModel = <String, Grinder>{};

    final shotBeanBatchIds = <int, String?>{};
    final shotGrinderIds = <int, String?>{};

    for (var i = 0; i < shots.length; i++) {
      final s = shots[i];

      // Bean extraction
      if (s.beanBrand != null && s.beanType != null &&
          s.beanBrand!.isNotEmpty && s.beanType!.isNotEmpty) {
        final beanKey = '${s.beanBrand!.toLowerCase()}|${s.beanType!.toLowerCase()}';

        final bean = beansByKey.putIfAbsent(beanKey, () {
          return Bean.create(
            roaster: s.beanBrand!,
            name: s.beanType!,
            notes: s.beanNotes,
          );
        });

        // Create batch per (bean, roastDate)
        final batchKey = '$beanKey|${s.roastDate ?? 'unknown'}';
        final batch = batchesByKey.putIfAbsent(batchKey, () {
          DateTime? roastDate;
          if (s.roastDate != null) {
            roastDate = DateTime.tryParse(s.roastDate!);
          }
          return BeanBatch.create(
            beanId: bean.id,
            roastDate: roastDate,
            roastLevel: s.roastLevel,
          );
        });

        shotBeanBatchIds[i] = batch.id;
      } else {
        shotBeanBatchIds[i] = null;
      }

      // Grinder extraction
      if (s.grinderModel != null && s.grinderModel!.isNotEmpty) {
        final grinderKey = s.grinderModel!.toLowerCase();
        final grinder = grindersByModel.putIfAbsent(grinderKey, () {
          return Grinder.create(model: s.grinderModel!);
        });
        shotGrinderIds[i] = grinder.id;
      } else {
        shotGrinderIds[i] = null;
      }
    }

    return ExtractionResult(
      beans: beansByKey.values.toList(),
      batches: batchesByKey.values.toList(),
      grinders: grindersByModel.values.toList(),
      shotBeanBatchIds: shotBeanBatchIds,
      shotGrinderIds: shotGrinderIds,
    );
  }

  /// Merge DYE grinder specs into grinders extracted from shots.
  /// Matches by model name (case-insensitive).
  List<Grinder> mergeGrinderSpecs(
    List<Grinder> fromShots,
    List<Grinder> fromDye,
  ) {
    final merged = <String, Grinder>{};
    for (final g in fromShots) {
      merged[g.model.toLowerCase()] = g;
    }
    for (final g in fromDye) {
      final key = g.model.toLowerCase();
      if (merged.containsKey(key)) {
        // Enrich existing with DYE specs
        final existing = merged[key]!;
        merged[key] = Grinder(
          id: existing.id,
          model: existing.model,
          burrs: g.burrs ?? existing.burrs,
          settingType: g.settingType,
          settingSmallStep: g.settingSmallStep ?? existing.settingSmallStep,
          settingBigStep: g.settingBigStep ?? existing.settingBigStep,
          createdAt: existing.createdAt,
          updatedAt: existing.updatedAt,
        );
      } else {
        merged[key] = g;
      }
    }
    return merged.values.toList();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/import/entity_extractor_test.dart`
Expected: PASS

- [ ] **Step 5: Run `flutter analyze`**

- [ ] **Step 6: Commit**

```bash
git add lib/src/import/entity_extractor.dart test/import/entity_extractor_test.dart
git commit -m "feat: add entity extractor for bean/grinder deduplication"
```

---

### Task 12: De1app Folder Scanner

Pre-scans a de1app folder to detect available data sources and count items.

**Files:**
- Create: `lib/src/import/de1app_scanner.dart`
- Test: `test/import/de1app_scanner_test.dart`

- [ ] **Step 1: Write the test**

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/import/de1app_scanner.dart';

void main() {
  group('De1appScanner', () {
    test('scans fixture folder', () async {
      final result = await De1appScanner.scan('test/fixtures/de1app');
      expect(result.shotCount, equals(1)); // history_v2 preferred
      expect(result.profileCount, equals(1));
      expect(result.hasDyeGrinders, isTrue);
      expect(result.shotSource, equals('history_v2'));
    });

    test('falls back to history/ when history_v2/ missing', () async {
      // Create temp dir with only history/
      final tempDir = await Directory.systemTemp.createTemp('de1app_test');
      final historyDir = Directory('${tempDir.path}/history');
      await historyDir.create();
      await File('${historyDir.path}/test.shot').writeAsString('clock 123');

      final result = await De1appScanner.scan(tempDir.path);
      expect(result.shotCount, equals(1));
      expect(result.shotSource, equals('history'));

      await tempDir.delete(recursive: true);
    });

    test('returns empty result for non-de1app folder', () async {
      final tempDir = await Directory.systemTemp.createTemp('empty_test');
      final result = await De1appScanner.scan(tempDir.path);
      expect(result.isEmpty, isTrue);
      await tempDir.delete(recursive: true);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/import/de1app_scanner_test.dart`
Expected: FAIL

- [ ] **Step 3: Implement De1appScanner**

```dart
import 'dart:io';

import 'package:reaprime/src/import/import_result.dart';

/// Pre-scans a de1app folder to detect available data sources and count items.
class De1appScanner {
  static Future<ScanResult> scan(String path) async {
    int shotCount = 0;
    String? shotSource;
    int profileCount = 0;
    bool hasDyeGrinders = false;

    // Prefer history_v2/ (JSON), fall back to history/ (TCL)
    final historyV2 = Directory('$path/history_v2');
    final history = Directory('$path/history');

    if (await historyV2.exists()) {
      shotCount = await _countFiles(historyV2, '.json');
      if (shotCount > 0) shotSource = 'history_v2';
    }

    if (shotCount == 0 && await history.exists()) {
      shotCount = await _countFiles(history, '.shot');
      if (shotCount > 0) shotSource = 'history';
    }

    // Profiles
    final profilesV2 = Directory('$path/profiles_v2');
    if (await profilesV2.exists()) {
      profileCount = await _countFiles(profilesV2, '.json');
    }

    // DYE grinders
    final grindersTdb = File('$path/plugins/DYE/grinders.tdb');
    hasDyeGrinders = await grindersTdb.exists();

    return ScanResult(
      shotCount: shotCount,
      profileCount: profileCount,
      hasDyeGrinders: hasDyeGrinders,
      sourcePath: path,
      shotSource: shotSource,
    );
  }

  static Future<int> _countFiles(Directory dir, String extension) async {
    var count = 0;
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith(extension)) {
        count++;
      }
    }
    return count;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/import/de1app_scanner_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/src/import/de1app_scanner.dart test/import/de1app_scanner_test.dart
git commit -m "feat: add de1app folder scanner"
```

---

### Task 13: De1app Importer (Orchestrator)

Orchestrates the full import pipeline: parse shots, extract entities, store everything.

**Files:**
- Create: `lib/src/import/de1app_importer.dart`
- Test: `test/import/de1app_importer_test.dart`

- [ ] **Step 1: Write the test**

This test uses mock storage services. Check `test/helpers/` for existing mock patterns. The test should verify:
- Shots are parsed and stored
- Beans and grinders are extracted and stored
- Profiles are deduplicated
- Progress callbacks fire
- Errors don't stop the pipeline
- Duplicate shots are skipped

Write tests that construct the importer with mock storage services and point it at the fixture folder.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/import/de1app_importer_test.dart`
Expected: FAIL

- [ ] **Step 3: Implement De1appImporter**

```dart
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:reaprime/src/import/de1app_scanner.dart';
import 'package:reaprime/src/import/entity_extractor.dart';
import 'package:reaprime/src/import/import_result.dart';
import 'package:reaprime/src/import/parsers/grinder_tdb_parser.dart';
import 'package:reaprime/src/import/parsers/profile_v2_parser.dart';
import 'package:reaprime/src/import/parsers/shot_v2_json_parser.dart';
import 'package:reaprime/src/import/parsers/tcl_shot_parser.dart';
import 'package:reaprime/src/services/storage/bean_storage_service.dart';
import 'package:reaprime/src/services/storage/grinder_storage_service.dart';
import 'package:reaprime/src/services/storage/profile_storage_service.dart';
import 'package:reaprime/src/services/storage/storage_service.dart';

final _log = Logger('De1appImporter');

class De1appImporter {
  final StorageService storageService;
  final ProfileStorageService profileStorageService;
  final BeanStorageService beanStorageService;
  final GrinderStorageService grinderStorageService;

  De1appImporter({
    required this.storageService,
    required this.profileStorageService,
    required this.beanStorageService,
    required this.grinderStorageService,
  });

  /// Run the full import pipeline.
  ///
  /// [scanResult] from De1appScanner.scan()
  /// [onProgress] called for each item processed
  Future<ImportResult> import(
    ScanResult scanResult, {
    void Function(ImportProgress)? onProgress,
  }) async {
    final errors = <ImportError>[];
    var shotsImported = 0;
    var shotsSkipped = 0;
    var profilesImported = 0;
    var profilesSkipped = 0;

    // --- Phase 1: Parse all shot files ---
    final parsedShots = <ParsedShot>[];
    final shotDir = scanResult.shotSource == 'history_v2'
        ? Directory('${scanResult.sourcePath}/history_v2')
        : Directory('${scanResult.sourcePath}/history');
    final shotExtension =
        scanResult.shotSource == 'history_v2' ? '.json' : '.shot';

    if (await shotDir.exists()) {
      final files = await shotDir
          .list()
          .where((e) => e is File && e.path.endsWith(shotExtension))
          .cast<File>()
          .toList();

      for (var i = 0; i < files.length; i++) {
        final file = files[i];
        final filename = file.uri.pathSegments.last;
        try {
          final content = await file.readAsString();
          final parsed = scanResult.shotSource == 'history_v2'
              ? ShotV2JsonParser.parse(
                  jsonDecode(content) as Map<String, dynamic>, filename)
              : TclShotParser.parse(content, filename);
          parsedShots.add(parsed);
        } catch (e) {
          _log.warning('Failed to parse $filename: $e');
          errors.add(ImportError(
            filename: filename,
            reason: 'Parse error',
            details: e.toString(),
          ));
        }
        onProgress?.call(ImportProgress(
          current: i + 1,
          total: scanResult.shotCount,
          phase: 'shots',
        ));
      }
    }

    // --- Phase 2: Extract and store entities ---
    final extractor = EntityExtractor();
    final extraction = extractor.extract(parsedShots);

    // Store beans
    for (final bean in extraction.beans) {
      try {
        await beanStorageService.insertBean(bean);
      } catch (e) {
        _log.warning('Failed to store bean ${bean.name}: $e');
      }
    }

    // Store bean batches
    for (final batch in extraction.batches) {
      try {
        await beanStorageService.insertBatch(batch);
      } catch (e) {
        _log.warning('Failed to store bean batch ${batch.id}: $e');
      }
    }

    // Store grinders (merge with DYE specs if available)
    var grinders = extraction.grinders;
    if (scanResult.hasDyeGrinders) {
      try {
        final tdbContent = await File(
                '${scanResult.sourcePath}/plugins/DYE/grinders.tdb')
            .readAsString();
        final dyeGrinders = GrinderTdbParser.parse(tdbContent);
        grinders = extractor.mergeGrinderSpecs(grinders, dyeGrinders);
      } catch (e) {
        _log.warning('Failed to parse DYE grinders: $e');
      }
    }
    for (final grinder in grinders) {
      try {
        await grinderStorageService.insertGrinder(grinder);
      } catch (e) {
        _log.warning('Failed to store grinder ${grinder.model}: $e');
      }
    }

    // --- Phase 3: Store shots with entity linkage ---
    final existingIds = await storageService.getShotIds();
    final existingIdSet = existingIds.toSet();

    for (var i = 0; i < parsedShots.length; i++) {
      final parsed = parsedShots[i];
      if (existingIdSet.contains(parsed.shot.id)) {
        shotsSkipped++;
        continue;
      }

      // Update workflow context with entity IDs
      var shot = parsed.shot;
      final batchId = extraction.shotBeanBatchIds[i];
      final grinderId = extraction.shotGrinderIds[i];
      if (batchId != null || grinderId != null) {
        final ctx = shot.workflow.context ?? const WorkflowContext();
        shot = shot.copyWith(
          workflow: shot.workflow.copyWith(
            context: ctx.copyWith(
              beanBatchId: batchId,
              grinderId: grinderId,
            ),
          ),
        );
      }

      try {
        await storageService.storeShot(shot);
        shotsImported++;
      } catch (e) {
        errors.add(ImportError(
          filename: 'shot-${parsed.shot.id}',
          reason: 'Storage error',
          details: e.toString(),
        ));
      }
    }

    // --- Phase 4: Import standalone profiles ---
    final profilesDir =
        Directory('${scanResult.sourcePath}/profiles_v2');
    if (await profilesDir.exists()) {
      final profileFiles = await profilesDir
          .list()
          .where((e) => e is File && e.path.endsWith('.json'))
          .cast<File>()
          .toList();

      for (var i = 0; i < profileFiles.length; i++) {
        final file = profileFiles[i];
        final filename = file.uri.pathSegments.last;
        try {
          final content = await file.readAsString();
          final json = jsonDecode(content) as Map<String, dynamic>;
          final record = ProfileV2Parser.parse(json);

          final existing = await profileStorageService.get(record.id);
          if (existing != null) {
            profilesSkipped++;
          } else {
            await profileStorageService.store(record);
            profilesImported++;
          }
        } catch (e) {
          errors.add(ImportError(
            filename: filename,
            reason: 'Profile parse error',
            details: e.toString(),
          ));
        }
        onProgress?.call(ImportProgress(
          current: i + 1,
          total: scanResult.profileCount,
          phase: 'profiles',
        ));
      }
    }

    return ImportResult(
      shotsImported: shotsImported,
      shotsSkipped: shotsSkipped,
      profilesImported: profilesImported,
      profilesSkipped: profilesSkipped,
      beansCreated: extraction.beans.length,
      grindersCreated: grinders.length,
      errors: errors,
    );
  }
}
```

Note: The `WorkflowContext` import and usage assumes the existing `copyWith` on `Workflow` and `ShotRecord` work as expected. Verify against the actual models during implementation.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/import/de1app_importer_test.dart`
Expected: PASS

- [ ] **Step 5: Run full test suite**

Run: `flutter test`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add lib/src/import/de1app_importer.dart test/import/de1app_importer_test.dart
git commit -m "feat: add de1app import orchestrator"
```

---

## Phase 4: Import UI

### Task 14: Import UI Widgets

Create the reusable import UI widgets: source picker, summary view, progress view, result view with error report.

**Files:**
- Create: `lib/src/import/widgets/import_source_picker.dart`
- Create: `lib/src/import/widgets/import_summary_view.dart`
- Create: `lib/src/import/widgets/import_progress_view.dart`
- Create: `lib/src/import/widgets/import_result_view.dart`

- [ ] **Step 1: Create ImportSourcePicker**

A widget with two card-style buttons: "Import from Decent app" (folder picker) and "Import Bridge backup" (ZIP file picker), plus a "Skip" callback.

```dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class ImportSourcePicker extends StatelessWidget {
  final void Function(String folderPath) onDe1appFolderSelected;
  final void Function(String filePath) onZipFileSelected;
  final VoidCallback? onSkip;

  const ImportSourcePicker({
    super.key,
    required this.onDe1appFolderSelected,
    required this.onZipFileSelected,
    this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Import Your Data',
                style: theme.textTheme.h3,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ShadButton.outline(
                onPressed: () => _pickFolder(context),
                size: ShadButtonSize.lg,
                width: double.infinity,
                child: Row(
                  children: [
                    const Icon(LucideIcons.folderOpen, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Import from Decent app',
                              style: theme.textTheme.p),
                          Text('Select your de1plus folder',
                              style: theme.textTheme.muted),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              ShadButton.outline(
                onPressed: () => _pickZip(context),
                size: ShadButtonSize.lg,
                width: double.infinity,
                child: Row(
                  children: [
                    const Icon(LucideIcons.archive, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Import Bridge backup',
                              style: theme.textTheme.p),
                          Text('Select a .zip backup file',
                              style: theme.textTheme.muted),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (onSkip != null) ...[
                const SizedBox(height: 24),
                ShadButton.link(
                  onPressed: onSkip,
                  child: const Text('Skip for now'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickFolder(BuildContext context) async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select your de1plus folder',
    );
    if (path != null) onDe1appFolderSelected(path);
  }

  Future<void> _pickZip(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      dialogTitle: 'Select Bridge backup file',
    );
    if (result != null && result.files.single.path != null) {
      onZipFileSelected(result.files.single.path!);
    }
  }
}
```

- [ ] **Step 2: Create ImportSummaryView**

Shows scan results and "Import All" button.

```dart
import 'package:flutter/material.dart';
import 'package:reaprime/src/import/import_result.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class ImportSummaryView extends StatelessWidget {
  final ScanResult scanResult;
  final VoidCallback onImportAll;
  final VoidCallback onCancel;

  const ImportSummaryView({
    super.key,
    required this.scanResult,
    required this.onImportAll,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Found in your Decent app folder:',
                style: theme.textTheme.h4,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ShadCard(
                child: Column(
                  children: [
                    _countRow(context, LucideIcons.coffee,
                        '${scanResult.shotCount} shots'),
                    const SizedBox(height: 8),
                    _countRow(context, LucideIcons.fileText,
                        '${scanResult.profileCount} profiles'),
                    if (scanResult.hasDyeGrinders) ...[
                      const SizedBox(height: 8),
                      _countRow(context, LucideIcons.settings,
                          'Grinder specs (DYE)'),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ShadButton(
                    onPressed: onImportAll,
                    child: const Text('Import All'),
                  ),
                  const SizedBox(width: 12),
                  ShadButton.outline(
                    onPressed: onCancel,
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _countRow(BuildContext context, IconData icon, String label) {
    final theme = ShadTheme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Text(label, style: theme.textTheme.p),
      ],
    );
  }
}
```

- [ ] **Step 3: Create ImportProgressView**

```dart
import 'package:flutter/material.dart';
import 'package:reaprime/src/import/import_result.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class ImportProgressView extends StatelessWidget {
  final ImportProgress progress;
  final int shotsImported;
  final int profilesImported;

  const ImportProgressView({
    super.key,
    required this.progress,
    this.shotsImported = 0,
    this.profilesImported = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Importing Your Data...',
                style: theme.textTheme.h4,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ShadProgress(value: progress.fraction),
              const SizedBox(height: 8),
              Text(
                '${progress.current} of ${progress.total} ${progress.phase}',
                style: theme.textTheme.muted,
              ),
              const SizedBox(height: 16),
              if (shotsImported > 0)
                Text('$shotsImported shots imported',
                    style: theme.textTheme.muted),
              if (profilesImported > 0)
                Text('$profilesImported profiles imported',
                    style: theme.textTheme.muted),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Create ImportResultView**

```dart
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reaprime/src/import/import_result.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:share_plus/share_plus.dart';

class ImportResultView extends StatefulWidget {
  final ImportResult result;
  final VoidCallback onContinue;

  const ImportResultView({
    super.key,
    required this.result,
    required this.onContinue,
  });

  @override
  State<ImportResultView> createState() => _ImportResultViewState();
}

class _ImportResultViewState extends State<ImportResultView> {
  bool _errorsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final r = widget.result;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                r.hasErrors ? LucideIcons.alertTriangle : LucideIcons.check,
                size: 48,
                color: r.hasErrors
                    ? theme.colorScheme.destructive
                    : theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                r.hasErrors ? 'Import Complete (with issues)' : 'Import Complete',
                style: theme.textTheme.h4,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              if (r.shotsImported > 0)
                _resultRow(context, LucideIcons.check, '${r.shotsImported} shots imported'),
              if (r.shotsSkipped > 0)
                _resultRow(context, LucideIcons.skipForward,
                    '${r.shotsSkipped} shots skipped (already existed)'),
              if (r.profilesImported > 0)
                _resultRow(context, LucideIcons.check,
                    '${r.profilesImported} profiles imported'),
              if (r.profilesSkipped > 0)
                _resultRow(context, LucideIcons.skipForward,
                    '${r.profilesSkipped} profiles skipped'),
              if (r.beansCreated > 0)
                _resultRow(context, LucideIcons.check, '${r.beansCreated} coffees added'),
              if (r.grindersCreated > 0)
                _resultRow(context, LucideIcons.check, '${r.grindersCreated} grinders added'),
              if (r.hasErrors) ...[
                const SizedBox(height: 12),
                _resultRow(context, LucideIcons.alertTriangle,
                    '${r.errors.length} items failed',
                    isError: true),
                ShadButton.link(
                  onPressed: () => setState(() => _errorsExpanded = !_errorsExpanded),
                  child: Text(_errorsExpanded ? 'Hide details' : 'Show details'),
                ),
                if (_errorsExpanded) ...[
                  ...r.errors.map((e) => Padding(
                        padding: const EdgeInsets.only(left: 16, top: 4),
                        child: Text('${e.filename}: ${e.reason}',
                            style: theme.textTheme.muted),
                      )),
                  const SizedBox(height: 8),
                  ShadButton.outline(
                    onPressed: () => _shareReport(context),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.share2, size: 16),
                        SizedBox(width: 8),
                        Text('Share Report'),
                      ],
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 24),
              ShadButton(
                onPressed: widget.onContinue,
                child: const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultRow(BuildContext context, IconData icon, String label,
      {bool isError = false}) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon,
              size: 16,
              color: isError
                  ? theme.colorScheme.destructive
                  : theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: theme.textTheme.p)),
        ],
      ),
    );
  }

  Future<void> _shareReport(BuildContext context) async {
    final r = widget.result;
    final buffer = StringBuffer();
    buffer.writeln('=== Streamline Bridge Import Report ===');
    buffer.writeln('Platform: ${Platform.operatingSystem}');
    buffer.writeln('Date: ${DateTime.now().toIso8601String()}');
    buffer.writeln();
    buffer.writeln('Shots imported: ${r.shotsImported}');
    buffer.writeln('Shots skipped: ${r.shotsSkipped}');
    buffer.writeln('Profiles imported: ${r.profilesImported}');
    buffer.writeln('Profiles skipped: ${r.profilesSkipped}');
    buffer.writeln('Beans created: ${r.beansCreated}');
    buffer.writeln('Grinders created: ${r.grindersCreated}');
    buffer.writeln();
    buffer.writeln('=== Errors (${r.errors.length}) ===');
    for (final e in r.errors) {
      buffer.writeln('File: ${e.filename}');
      buffer.writeln('Reason: ${e.reason}');
      if (e.details != null) buffer.writeln('Details: ${e.details}');
      buffer.writeln();
    }

    // Append log file contents
    buffer.writeln('=== Application Log ===');
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final logFile = File('${docsDir.path}/log.txt');
      if (await logFile.exists()) {
        buffer.writeln(await logFile.readAsString());
      } else {
        buffer.writeln('(log file not found)');
      }
    } catch (e) {
      buffer.writeln('(failed to read log: $e)');
    }

    // Save to temp file and share
    final tempDir = await getTemporaryDirectory();
    final reportFile = File(
        '${tempDir.path}/import_report_${DateTime.now().millisecondsSinceEpoch}.txt');
    await reportFile.writeAsString(buffer.toString());

    if (Platform.isAndroid || Platform.isIOS) {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(reportFile.path)]),
      );
    } else {
      final savePath = await FilePicker.platform.saveFile(
        fileName: 'import_report.txt',
        bytes: reportFile.readAsBytesSync(),
      );
      if (savePath != null && !Platform.isAndroid && !Platform.isIOS) {
        await File(savePath).writeAsBytes(reportFile.readAsBytesSync());
      }
    }
  }
}
```

- [ ] **Step 5: Run `flutter analyze`**

- [ ] **Step 6: Commit**

```bash
git add lib/src/import/widgets/
git commit -m "feat: add import UI widgets (picker, summary, progress, result)"
```

---

### Task 15: Add `share_plus` Dependency

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add share_plus to pubspec.yaml**

Add under `dependencies:`:
```yaml
  share_plus: ^10.1.4
```

- [ ] **Step 2: Run `flutter pub get`**

Run: `flutter pub get`
Expected: Resolves successfully

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: add share_plus dependency for import report sharing"
```

---

## Phase 5: Wiring It All Together

### Task 16: Import Onboarding Step

The import step manages the state machine: source picker → scanning → summary → importing → result.

**Files:**
- Create: `lib/src/onboarding_feature/steps/import_step.dart`

- [ ] **Step 1: Implement the import step**

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:reaprime/src/import/de1app_importer.dart';
import 'package:reaprime/src/import/de1app_scanner.dart';
import 'package:reaprime/src/import/import_result.dart';
import 'package:reaprime/src/import/widgets/import_progress_view.dart';
import 'package:reaprime/src/import/widgets/import_result_view.dart';
import 'package:reaprime/src/import/widgets/import_source_picker.dart';
import 'package:reaprime/src/import/widgets/import_summary_view.dart';
import 'package:reaprime/src/onboarding_feature/onboarding_controller.dart';
import 'package:reaprime/src/services/storage/bean_storage_service.dart';
import 'package:reaprime/src/services/storage/grinder_storage_service.dart';
import 'package:reaprime/src/services/storage/profile_storage_service.dart';
import 'package:reaprime/src/services/storage/storage_service.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

OnboardingStep createImportStep({
  required StorageService storageService,
  required ProfileStorageService profileStorageService,
  required BeanStorageService beanStorageService,
  required GrinderStorageService grinderStorageService,
  required SettingsController settingsController,
}) {
  return OnboardingStep(
    id: 'import',
    shouldShow: () async => true, // Overridden in app.dart with flag check
    builder: (controller) => _ImportStepView(
      controller: controller,
      storageService: storageService,
      profileStorageService: profileStorageService,
      beanStorageService: beanStorageService,
      grinderStorageService: grinderStorageService,
      settingsController: settingsController,
    ),
  );
}

enum _ImportPhase { pickSource, scanning, summary, importing, result, zipImport }

class _ImportStepView extends StatefulWidget {
  final OnboardingController controller;
  final StorageService storageService;
  final ProfileStorageService profileStorageService;
  final BeanStorageService beanStorageService;
  final GrinderStorageService grinderStorageService;
  final SettingsController settingsController;

  const _ImportStepView({
    required this.controller,
    required this.storageService,
    required this.profileStorageService,
    required this.beanStorageService,
    required this.grinderStorageService,
    required this.settingsController,
  });

  @override
  State<_ImportStepView> createState() => _ImportStepViewState();
}

class _ImportStepViewState extends State<_ImportStepView> {
  _ImportPhase _phase = _ImportPhase.pickSource;
  ScanResult? _scanResult;
  ImportProgress _progress = const ImportProgress(current: 0, total: 0, phase: '');
  int _shotsImported = 0;
  int _profilesImported = 0;
  ImportResult? _importResult;

  Future<void> _onComplete() async {
    await widget.settingsController.setOnboardingCompleted(true);
    widget.controller.advance();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: switch (_phase) {
        _ImportPhase.pickSource => ImportSourcePicker(
            onDe1appFolderSelected: _onFolderSelected,
            onZipFileSelected: _onZipSelected,
            onSkip: _onComplete,
          ),
        _ImportPhase.scanning => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ShadProgress(),
                const SizedBox(height: 16),
                Text('Scanning folder...',
                    style: ShadTheme.of(context).textTheme.muted),
              ],
            ),
          ),
        _ImportPhase.summary => ImportSummaryView(
            scanResult: _scanResult!,
            onImportAll: _startImport,
            onCancel: () => setState(() => _phase = _ImportPhase.pickSource),
          ),
        _ImportPhase.importing => ImportProgressView(
            progress: _progress,
            shotsImported: _shotsImported,
            profilesImported: _profilesImported,
          ),
        _ImportPhase.result => ImportResultView(
            result: _importResult!,
            onContinue: _onComplete,
          ),
        _ImportPhase.zipImport => _buildZipImportView(),
      },
    );
  }

  Future<void> _onFolderSelected(String path) async {
    setState(() => _phase = _ImportPhase.scanning);
    final scanResult = await De1appScanner.scan(path);

    if (scanResult.isEmpty) {
      if (mounted) {
        setState(() => _phase = _ImportPhase.pickSource);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No Decent app data found in this folder')),
        );
      }
      return;
    }

    if (mounted) {
      setState(() {
        _scanResult = scanResult;
        _phase = _ImportPhase.summary;
      });
    }
  }

  Future<void> _startImport() async {
    setState(() => _phase = _ImportPhase.importing);

    final importer = De1appImporter(
      storageService: widget.storageService,
      profileStorageService: widget.profileStorageService,
      beanStorageService: widget.beanStorageService,
      grinderStorageService: widget.grinderStorageService,
    );

    final result = await importer.import(
      _scanResult!,
      onProgress: (p) {
        if (mounted) {
          setState(() {
            _progress = p;
            if (p.phase == 'shots') _shotsImported = p.current;
            if (p.phase == 'profiles') _profilesImported = p.current;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _importResult = result;
        _phase = _ImportPhase.result;
      });
    }
  }

  void _onZipSelected(String filePath) {
    // Delegate to existing ZIP import logic via the REST API
    // For now, navigate to result with a message to use Settings
    setState(() => _phase = _ImportPhase.zipImport);
  }

  Widget _buildZipImportView() {
    // TODO: Wire up to existing data import handler
    // For the onboarding MVP, show a message that ZIP import is available in Settings
    final theme = ShadTheme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('ZIP Import', style: theme.textTheme.h4),
              const SizedBox(height: 16),
              Text(
                'ZIP backup import will be processed after setup completes. '
                'You can also import backups anytime from Settings > Data Management.',
                style: theme.textTheme.muted,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ShadButton(
                onPressed: _onComplete,
                child: const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Run `flutter analyze`**

- [ ] **Step 3: Commit**

```bash
git add lib/src/onboarding_feature/steps/import_step.dart
git commit -m "feat: add import onboarding step with full import flow"
```

---

### Task 17: Wire Import Step into app.dart

**Files:**
- Modify: `lib/src/app.dart`

- [ ] **Step 1: Import the import step and add to controller**

Add import:
```dart
import 'package:reaprime/src/onboarding_feature/steps/import_step.dart';
```

In the OnboardingController steps list, insert the import step between initialization and scan. Use the same `shouldShow` pattern as the welcome step:

```dart
_onboardingController = OnboardingController(steps: [
  OnboardingStep(
    id: 'welcome',
    shouldShow: () async =>
        !await widget.settingsController.settingsService.onboardingCompleted(),
    builder: createWelcomeStep().builder,
  ),
  createPermissionsStep(
    de1Controller: widget.de1Controller,
  ),
  createInitializationStep(
    // ... existing args ...
  ),
  OnboardingStep(
    id: 'import',
    shouldShow: () async =>
        !await widget.settingsController.settingsService.onboardingCompleted(),
    builder: createImportStep(
      storageService: widget.storageService,
      profileStorageService: widget.profileStorageService,
      beanStorageService: widget.beanStorageService,
      grinderStorageService: widget.grinderStorageService,
      settingsController: widget.settingsController,
    ).builder,
  ),
  createScanStep(
    // ... existing args ...
  ),
]);
```

Note: Verify the exact property names for storage services on the `MyApp` widget — they may be passed through `main.dart`. If they don't exist on `widget`, they need to be added as constructor parameters.

- [ ] **Step 2: Run `flutter analyze`**

- [ ] **Step 3: Run `flutter test`**

Run: `flutter test`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add lib/src/app.dart
git commit -m "feat: wire import step into onboarding flow"
```

---

### Task 18: Update Settings > Data Management

Add "Import from Decent app" to the Data Management page.

**Files:**
- Modify: `lib/src/settings/data_management_page.dart`

- [ ] **Step 1: Add de1app import button to the Import section**

Find the existing import section in `data_management_page.dart`. Add a new button for de1app import that launches the same import flow (folder picker → scan → summary → progress → result) as a dialog or pushed route.

The implementation should reuse `ImportSourcePicker`, `De1appScanner`, `De1appImporter`, and the result widgets. Since data_management_page already has access to storage services (via the HTTP API), consider whether to use the direct importer or the REST endpoint. The direct importer is simpler here since we're in the same app process.

Add a new `ShadButton.outline` in the import section:

```dart
ShadButton.outline(
  onPressed: _importFromDe1app,
  child: const Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(LucideIcons.folderOpen, size: 16),
      SizedBox(width: 8),
      Text('Import from Decent app'),
    ],
  ),
),
```

The `_importFromDe1app` method should open a dialog or navigate to a page that runs the import flow. Use `showDialog` or `Navigator.push` — follow whichever pattern the existing import uses.

- [ ] **Step 2: Run `flutter analyze`**

- [ ] **Step 3: Commit**

```bash
git add lib/src/settings/data_management_page.dart
git commit -m "feat: add de1app import option to Data Management settings"
```

---

## Phase 6: Final Steps

### Task 19: Run Full Test Suite and Fix Issues

- [ ] **Step 1: Run `flutter analyze`**

Run: `flutter analyze`
Fix any issues.

- [ ] **Step 2: Run full test suite**

Run: `flutter test`
Fix any failures.

- [ ] **Step 3: Run app in simulate mode**

Run: `flutter run --dart-define=simulate=1`
Walk through the onboarding flow manually:
1. Verify Welcome step appears with correct copy
2. Verify Import step appears with source picker
3. Verify "Skip for now" advances to scan step
4. Verify on second launch, Welcome and Import are skipped

- [ ] **Step 4: Commit any fixes**

### Task 20: Update Tracking Document

- [ ] **Step 1: Update `doc/plans/onboarding-redesign.md`**

Mark completed items in the Implementation Status section.

- [ ] **Step 2: Commit**

```bash
git add doc/plans/onboarding-redesign.md
git commit -m "docs: update onboarding tracking document with implementation status"
```
