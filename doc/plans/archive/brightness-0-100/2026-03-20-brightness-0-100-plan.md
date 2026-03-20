# Brightness 0-100 Range + Battery-Aware Cap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the binary `dim`/`normal` brightness model with a 0-100 integer range, add a battery-aware brightness cap setting, and update all API surfaces.

**Architecture:** `DisplayController` gains `setBrightness(int)` replacing `dim()`/`restore()`, tracks requested vs actual brightness (for battery capping), and listens to a `Stream<ChargingState>?` (from `BatteryController`) + `SettingsController` for low-battery cap. Handler replaces two endpoints with `PUT /api/v1/display/brightness`. Tests are written before implementation (TDD).

**Validation strategy:** REST rejects out-of-range brightness values with 400. WebSocket silently ignores invalid values (existing error-handling pattern). Controller clamps as a safety net. This is intentional defense-in-depth — the API boundary validates, the controller is lenient.

**Tech Stack:** Flutter/Dart, `screen_brightness`, `wakelock_plus`, `rxdart`, `shelf_plus`, `fake_async`

**Design doc:** `doc/plans/2026-03-20-brightness-0-100-design.md`

---

### Task 1: Create branch and add `lowBatteryBrightnessLimit` setting

**Files:**
- Modify: `lib/src/settings/settings_service.dart:60-62` (abstract interface), `lib/src/settings/settings_service.dart:351-377` (SettingsKeys enum)
- Modify: `lib/src/settings/settings_controller.dart:59-61` (fields), `lib/src/settings/settings_controller.dart:85-87` (getters), `lib/src/settings/settings_controller.dart:115-116` (loadSettings), `lib/src/settings/settings_controller.dart:332-337` (setter)
- Modify: `test/helpers/mock_settings_service.dart:34` (MockSettingsService)

- [ ] **Step 1: Create feature branch**

```bash
git checkout -b feature/brightness-0-100
```

- [ ] **Step 2: Add abstract interface methods to SettingsService**

In `lib/src/settings/settings_service.dart`, after line 61 (`Future<void> setWakeSchedules(String json);`), add:

```dart
  Future<bool> lowBatteryBrightnessLimit();
  Future<void> setLowBatteryBrightnessLimit(bool value);
```

- [ ] **Step 3: Add to SettingsKeys enum**

In `lib/src/settings/settings_service.dart`, after `wakeSchedules,` (line 376), add:

```dart
  lowBatteryBrightnessLimit,
```

- [ ] **Step 4: Add implementation to SharedPreferencesSettingsService**

In `lib/src/settings/settings_service.dart`, after the `setWakeSchedules` method (after line 348), add:

```dart
  @override
  Future<bool> lowBatteryBrightnessLimit() async {
    return await prefs.getBool(SettingsKeys.lowBatteryBrightnessLimit.name) ?? false;
  }

  @override
  Future<void> setLowBatteryBrightnessLimit(bool value) async {
    await prefs.setBool(SettingsKeys.lowBatteryBrightnessLimit.name, value);
  }
```

- [ ] **Step 5: Add field, getter, loader, and setter to SettingsController**

In `lib/src/settings/settings_controller.dart`:

After `late String _wakeSchedules;` (line 61), add:
```dart
  late bool _lowBatteryBrightnessLimit;
```

After `String get wakeSchedules => _wakeSchedules;` (line 87), add:
```dart
  bool get lowBatteryBrightnessLimit => _lowBatteryBrightnessLimit;
```

In `loadSettings()`, after `_wakeSchedules = await _settingsService.wakeSchedules();` (line 116), add:
```dart
    _lowBatteryBrightnessLimit = await _settingsService.lowBatteryBrightnessLimit();
```

After the `setWakeSchedules` method (after line 337), add:
```dart
  Future<void> setLowBatteryBrightnessLimit(bool value) async {
    if (value == _lowBatteryBrightnessLimit) return;
    _lowBatteryBrightnessLimit = value;
    await _settingsService.setLowBatteryBrightnessLimit(value);
    notifyListeners();
  }
```

- [ ] **Step 6: Add to MockSettingsService**

In `test/helpers/mock_settings_service.dart`, after `String _wakeSchedules = '[]';` (line 34), add:
```dart
  bool _lowBatteryBrightnessLimit = false;
```

After the `setWakeSchedules` method (after line 137), add:
```dart
  @override
  Future<bool> lowBatteryBrightnessLimit() async => _lowBatteryBrightnessLimit;
  @override
  Future<void> setLowBatteryBrightnessLimit(bool value) async => _lowBatteryBrightnessLimit = value;
```

- [ ] **Step 7: Verify it compiles**

Run: `flutter analyze lib/src/settings/ test/helpers/mock_settings_service.dart`
Expected: No issues found.

- [ ] **Step 8: Commit**

```bash
git add lib/src/settings/settings_service.dart lib/src/settings/settings_controller.dart test/helpers/mock_settings_service.dart
git commit -m "feat: add lowBatteryBrightnessLimit setting"
```

---

### Task 2: Write failing DisplayController tests for 0-100 brightness

**Files:**
- Modify: `test/controllers/display_controller_test.dart`

This task rewrites the existing brightness tests and adds new ones. The tests will fail because the controller still uses the old `dim()`/`restore()` API.

- [ ] **Step 1: Add a `_TestBatteryController` to the test file**

In `test/controllers/display_controller_test.dart`, after the `_TestDe1Controller` class (after line 195), add:

```dart
/// A minimal BatteryController substitute for testing.
/// Real BatteryController needs Battery plugin, so we mock the stream.
class _TestBatteryController {
  final BehaviorSubject<ChargingState> _stateSubject =
      BehaviorSubject<ChargingState>();

  Stream<ChargingState> get chargingState => _stateSubject.stream;
  ChargingState? get currentChargingState => _stateSubject.valueOrNull;

  void emitBattery(int percent) {
    _stateSubject.add(ChargingState(
      mode: ChargingMode.balanced,
      nightModeEnabled: false,
      currentPhase: NightPhase.inactive,
      batteryPercent: percent,
      usbChargerOn: false,
      isEmergency: percent <= 15,
    ));
  }

  void dispose() {
    _stateSubject.close();
  }
}
```

Add the required imports at the top of the file:
```dart
import 'package:reaprime/src/controllers/charging_logic.dart';
import 'package:reaprime/src/settings/charging_mode.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import '../helpers/mock_settings_service.dart';
```

Note: `DisplayController` accepts `Stream<ChargingState>?` (not `BatteryController?`), so `_TestBatteryController` just provides a controllable stream — no type-system gymnastics needed.

- [ ] **Step 2: Create shared SettingsController fixture and update `_createController`**

Add a shared `SettingsController` variable to `main()`:

```dart
  late SettingsController settingsCtrl;
```

In the existing `setUp`, add:
```dart
    final mockSettings = MockSettingsService();
    settingsCtrl = SettingsController(mockSettings);
    // loadSettings is async but MockSettingsService is synchronous in-memory,
    // so the late fields are initialized immediately after this call
    settingsCtrl.loadSettings();
```

Replace the existing `_createController` function (lines 198-207) with:

```dart
/// Creates a DisplayController with no-op platform operations for testing.
DisplayController _createController(
  _TestDe1Controller de1Controller, {
  required SettingsController settingsController,
  _TestBatteryController? batteryController,
}) {
  return DisplayController(
    de1Controller: de1Controller,
    settingsController: settingsController,
    batteryStateStream: batteryController?.chargingState,
    setBrightness: (_) async {},
    resetBrightness: () async {},
    enableWakeLock: () async {},
    disableWakeLock: () async {},
  );
}
```

Update ALL existing calls from `_createController(de1Controller)` to `_createController(de1Controller, settingsController: settingsCtrl)` throughout the test file.

- [ ] **Step 3: Rewrite the `brightness` test group**

Replace the entire `group('brightness', ...)` block (lines 413-469) with:

```dart
  group('brightness', () {
    test('initial state has brightness 100', () {
      fakeAsync((async) {
        final controller = _createController(de1Controller);
        controller.initialize();
        async.flushMicrotasks();

        expect(controller.currentState.brightness, 100);
        expect(controller.currentState.requestedBrightness, 100);

        controller.dispose();
      });
    });

    test('setBrightness(50) sets brightness to 50', () {
      fakeAsync((async) {
        final controller = _createController(de1Controller);
        controller.initialize();
        async.flushMicrotasks();

        controller.setBrightness(50);
        async.flushMicrotasks();

        expect(controller.currentState.brightness, 50);
        expect(controller.currentState.requestedBrightness, 50);

        controller.dispose();
      });
    });

    test('setBrightness clamps values above 100', () {
      fakeAsync((async) {
        final controller = _createController(de1Controller);
        controller.initialize();
        async.flushMicrotasks();

        controller.setBrightness(150);
        async.flushMicrotasks();

        expect(controller.currentState.brightness, 100);
        expect(controller.currentState.requestedBrightness, 100);

        controller.dispose();
      });
    });

    test('setBrightness clamps values below 0', () {
      fakeAsync((async) {
        final controller = _createController(de1Controller);
        controller.initialize();
        async.flushMicrotasks();

        controller.setBrightness(-5);
        async.flushMicrotasks();

        expect(controller.currentState.brightness, 0);
        expect(controller.currentState.requestedBrightness, 0);

        controller.dispose();
      });
    });

    test('setBrightness(100) uses resetBrightness', () {
      fakeAsync((async) {
        bool resetCalled = false;
        bool setCalled = false;
        final controller = DisplayController(
          de1Controller: de1Controller,
          settingsController: settingsCtrl,
          setBrightness: (_) async { setCalled = true; },
          resetBrightness: () async { resetCalled = true; },
          enableWakeLock: () async {},
          disableWakeLock: () async {},
        );
        controller.initialize();
        async.flushMicrotasks();

        // First set to something other than 100
        controller.setBrightness(50);
        async.flushMicrotasks();
        setCalled = false;
        resetCalled = false;

        // Now set to 100 — should call reset, not set
        controller.setBrightness(100);
        async.flushMicrotasks();

        expect(resetCalled, isTrue);
        expect(setCalled, isFalse);

        controller.dispose();
      });
    });

    test('saves brightness on sleep and restores on wake', () {
      fakeAsync((async) {
        final controller = _createController(de1Controller);
        controller.initialize();
        async.flushMicrotasks();

        de1Controller.setDe1(testDe1);
        async.flushMicrotasks();

        controller.setBrightness(75);
        async.flushMicrotasks();
        expect(controller.currentState.brightness, 75);

        // Machine goes to sleep — brightness is saved
        testDe1.emitState(MachineState.sleeping);
        async.flushMicrotasks();

        // Skin dims screen while sleeping
        controller.setBrightness(5);
        async.flushMicrotasks();
        expect(controller.currentState.brightness, 5);

        // Machine wakes — should restore to pre-sleep value (75)
        testDe1.emitState(MachineState.idle);
        async.flushMicrotasks();
        expect(controller.currentState.brightness, 75);

        controller.dispose();
      });
    });
  });
```

- [ ] **Step 4: Add a new `battery brightness cap` test group**

After the `brightness` group, add:

```dart
  group('battery brightness cap', () {
    late _TestBatteryController batteryCtrl;

    setUp(() {
      batteryCtrl = _TestBatteryController();
    });

    test('caps brightness when battery low and setting enabled', () {
      fakeAsync((async) {
        // Enable the setting
        settingsCtrl.setLowBatteryBrightnessLimit(true);
        async.flushMicrotasks();

        final controller = _createController(
          de1Controller,
          settingsController: settingsCtrl,
          batteryController: batteryCtrl,
        );
        controller.initialize();
        async.flushMicrotasks();

        controller.setBrightness(80);
        async.flushMicrotasks();

        // Battery drops below 30%
        batteryCtrl.emitBattery(25);
        async.flushMicrotasks();

        expect(controller.currentState.brightness, 20);
        expect(controller.currentState.requestedBrightness, 80);
        expect(controller.currentState.lowBatteryBrightnessActive, isTrue);

        controller.dispose();
      });
    });

    test('does not cap when setting is disabled', () {
      fakeAsync((async) {
        // Setting defaults to false
        final controller = _createController(
          de1Controller,
          settingsController: settingsCtrl,
          batteryController: batteryCtrl,
        );
        controller.initialize();
        async.flushMicrotasks();

        controller.setBrightness(80);
        async.flushMicrotasks();

        batteryCtrl.emitBattery(25);
        async.flushMicrotasks();

        expect(controller.currentState.brightness, 80);
        expect(controller.currentState.lowBatteryBrightnessActive, isFalse);

        controller.dispose();
      });
    });

    test('allows brightness below cap', () {
      fakeAsync((async) {
        settingsCtrl.setLowBatteryBrightnessLimit(true);
        async.flushMicrotasks();

        final controller = _createController(
          de1Controller,
          settingsController: settingsCtrl,
          batteryController: batteryCtrl,
        );
        controller.initialize();
        async.flushMicrotasks();

        batteryCtrl.emitBattery(25);
        async.flushMicrotasks();

        controller.setBrightness(15);
        async.flushMicrotasks();

        // 15 is below cap of 20, so actual = 15
        expect(controller.currentState.brightness, 15);
        expect(controller.currentState.requestedBrightness, 15);

        controller.dispose();
      });
    });

    test('restores brightness when battery recovers', () {
      fakeAsync((async) {
        settingsCtrl.setLowBatteryBrightnessLimit(true);
        async.flushMicrotasks();

        final controller = _createController(
          de1Controller,
          settingsController: settingsCtrl,
          batteryController: batteryCtrl,
        );
        controller.initialize();
        async.flushMicrotasks();

        controller.setBrightness(80);
        async.flushMicrotasks();

        batteryCtrl.emitBattery(25);
        async.flushMicrotasks();
        expect(controller.currentState.brightness, 20);

        batteryCtrl.emitBattery(35);
        async.flushMicrotasks();
        expect(controller.currentState.brightness, 80);
        expect(controller.currentState.lowBatteryBrightnessActive, isFalse);

        controller.dispose();
      });
    });

    test('toggling setting off restores requested brightness immediately', () {
      fakeAsync((async) {
        settingsCtrl.setLowBatteryBrightnessLimit(true);
        async.flushMicrotasks();

        final controller = _createController(
          de1Controller,
          settingsController: settingsCtrl,
          batteryController: batteryCtrl,
        );
        controller.initialize();
        async.flushMicrotasks();

        controller.setBrightness(80);
        async.flushMicrotasks();

        batteryCtrl.emitBattery(25);
        async.flushMicrotasks();
        expect(controller.currentState.brightness, 20);

        // Toggle off
        settingsCtrl.setLowBatteryBrightnessLimit(false);
        async.flushMicrotasks();

        expect(controller.currentState.brightness, 80);
        expect(controller.currentState.lowBatteryBrightnessActive, isFalse);

        controller.dispose();
      });
    });

    test('toggling setting on when battery already low applies cap immediately', () {
      fakeAsync((async) {
        final controller = _createController(
          de1Controller,
          settingsController: settingsCtrl,
          batteryController: batteryCtrl,
        );
        controller.initialize();
        async.flushMicrotasks();

        controller.setBrightness(80);
        async.flushMicrotasks();

        batteryCtrl.emitBattery(25);
        async.flushMicrotasks();
        // Setting is off, no cap
        expect(controller.currentState.brightness, 80);

        // Toggle on — should immediately cap
        settingsCtrl.setLowBatteryBrightnessLimit(true);
        async.flushMicrotasks();

        expect(controller.currentState.brightness, 20);
        expect(controller.currentState.lowBatteryBrightnessActive, isTrue);

        controller.dispose();
      });
    });

    test('no battery controller means no cap (desktop)', () {
      fakeAsync((async) {
        settingsCtrl.setLowBatteryBrightnessLimit(true);
        async.flushMicrotasks();

        final controller = _createController(
          de1Controller,
          settingsController: settingsCtrl,
        );
        controller.initialize();
        async.flushMicrotasks();

        controller.setBrightness(80);
        async.flushMicrotasks();

        expect(controller.currentState.brightness, 80);
        expect(controller.currentState.lowBatteryBrightnessActive, isFalse);

        controller.dispose();
      });
    });

    test('sleep/wake with battery cap active restores capped value', () {
      fakeAsync((async) {
        settingsCtrl.setLowBatteryBrightnessLimit(true);
        async.flushMicrotasks();

        final controller = _createController(
          de1Controller,
          settingsController: settingsCtrl,
          batteryController: batteryCtrl,
        );
        controller.initialize();
        async.flushMicrotasks();

        de1Controller.setDe1(testDe1);
        async.flushMicrotasks();

        controller.setBrightness(80);
        async.flushMicrotasks();

        batteryCtrl.emitBattery(25);
        async.flushMicrotasks();
        expect(controller.currentState.brightness, 20);

        // Machine sleeps
        testDe1.emitState(MachineState.sleeping);
        async.flushMicrotasks();

        // Machine wakes — should restore to pre-sleep (80) but capped to 20
        testDe1.emitState(MachineState.idle);
        async.flushMicrotasks();

        expect(controller.currentState.brightness, 20);
        expect(controller.currentState.requestedBrightness, 80);

        controller.dispose();
      });
    });
  });
```

- [ ] **Step 5: Update existing test assertions that reference the old enum**

In the `DisplayState` test group (lines 606-671), update all references:
- Replace `DisplayBrightness.dimmed` → integer brightness values
- Replace `DisplayBrightness.normal` → integer brightness values
- Replace `brightness: DisplayBrightness.dimmed` → `brightness: 5`
- Replace `brightness: DisplayBrightness.normal` → `brightness: 100`
- Add `requestedBrightness` and `lowBatteryBrightnessActive` fields to `DisplayState` constructors

In the `initial state` group, update:
- `expect(state.brightness, DisplayBrightness.normal)` → `expect(state.brightness, 100)`

In `state broadcasting` group, update:
- `expect(emissions.first.brightness, DisplayBrightness.normal)` → `expect(emissions.first.brightness, 100)`

- [ ] **Step 6: Run tests to verify they fail**

Run: `flutter test test/controllers/display_controller_test.dart`
Expected: Compilation errors — `DisplayBrightness` enum still exists, `setBrightness` doesn't exist yet, `requestedBrightness`/`lowBatteryBrightnessActive` not on `DisplayState`, constructor doesn't accept `settingsController`/`batteryController`.

- [ ] **Step 7: Commit failing tests**

```bash
git add test/controllers/display_controller_test.dart
git commit -m "test: rewrite brightness tests for 0-100 range and battery cap (failing)"
```

---

### Task 3: Implement DisplayController brightness refactor

**Files:**
- Modify: `lib/src/controllers/display_controller.dart`

- [ ] **Step 1: Replace DisplayBrightness enum and update DisplayState**

In `lib/src/controllers/display_controller.dart`:

Remove the `DisplayBrightness` enum (line 12).

Replace the `DisplayState` class (lines 29-61) with:

```dart
class DisplayState {
  final bool wakeLockEnabled;
  final bool wakeLockOverride;
  final int brightness;
  final int requestedBrightness;
  final bool lowBatteryBrightnessActive;
  final DisplayPlatformSupport platformSupported;

  const DisplayState({
    required this.wakeLockEnabled,
    required this.wakeLockOverride,
    required this.brightness,
    required this.requestedBrightness,
    required this.lowBatteryBrightnessActive,
    required this.platformSupported,
  });

  DisplayState copyWith({
    bool? wakeLockEnabled,
    bool? wakeLockOverride,
    int? brightness,
    int? requestedBrightness,
    bool? lowBatteryBrightnessActive,
    DisplayPlatformSupport? platformSupported,
  }) =>
      DisplayState(
        wakeLockEnabled: wakeLockEnabled ?? this.wakeLockEnabled,
        wakeLockOverride: wakeLockOverride ?? this.wakeLockOverride,
        brightness: brightness ?? this.brightness,
        requestedBrightness: requestedBrightness ?? this.requestedBrightness,
        lowBatteryBrightnessActive: lowBatteryBrightnessActive ?? this.lowBatteryBrightnessActive,
        platformSupported: platformSupported ?? this.platformSupported,
      );

  Map<String, dynamic> toJson() => {
        'wakeLockEnabled': wakeLockEnabled,
        'wakeLockOverride': wakeLockOverride,
        'brightness': brightness,
        'requestedBrightness': requestedBrightness,
        'lowBatteryBrightnessActive': lowBatteryBrightnessActive,
        'platformSupported': platformSupported.toJson(),
      };
}
```

- [ ] **Step 2: Add new imports and update constructor**

Add imports at the top:
```dart
import 'package:reaprime/src/controllers/battery_controller.dart';
import 'package:reaprime/src/controllers/charging_logic.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
```

Replace the constructor and field declarations in `DisplayController` with:

```dart
class DisplayController {
  final De1Controller _de1Controller;
  final Stream<ChargingState>? _batteryStateStream;
  final SettingsController _settingsController;
  final Logger _log = Logger('DisplayController');

  static const int _lowBatteryThreshold = 30;
  static const int _lowBatteryBrightnessCap = 20;

  static final ScreenBrightness _defaultScreenBrightness = ScreenBrightness();

  // --- Injectable platform operations (for testability) ---
  final Future<void> Function(double) _setBrightness;
  final Future<void> Function() _resetBrightness;
  final Future<void> Function() _enableWakeLock;
  final Future<void> Function() _disableWakeLock;

  // --- Platform support detection ---
  late final DisplayPlatformSupport _platformSupport;

  // --- State broadcasting ---
  late final BehaviorSubject<DisplayState> _stateSubject;
  Stream<DisplayState> get state => _stateSubject.stream;
  DisplayState get currentState => _stateSubject.value;

  // --- Internal state ---
  De1Interface? _de1;
  MachineState? _currentMachineState;
  StreamSubscription<De1Interface?>? _de1Subscription;
  StreamSubscription<MachineSnapshot>? _snapshotSubscription;
  StreamSubscription<ChargingState>? _batterySubscription;
  bool _wakeLockOverride = false;
  int _requestedBrightness = 100;
  int _preSleepBrightness = 100;
  bool _lowBatteryCapping = false;
  int? _lastBatteryPercent;

  DisplayController({
    required De1Controller de1Controller,
    BatteryController? batteryController,
    Stream<ChargingState>? batteryStateStream,
    required SettingsController settingsController,
    Future<void> Function(double)? setBrightness,
    Future<void> Function()? resetBrightness,
    Future<void> Function()? enableWakeLock,
    Future<void> Function()? disableWakeLock,
  })  : _de1Controller = de1Controller,
        _batteryStateStream = batteryStateStream ?? batteryController?.chargingState,
        _settingsController = settingsController,
        _setBrightness = setBrightness ??
            _defaultScreenBrightness.setApplicationScreenBrightness,
        _resetBrightness = resetBrightness ??
            _defaultScreenBrightness.resetApplicationScreenBrightness,
        _enableWakeLock = enableWakeLock ?? WakelockPlus.enable,
        _disableWakeLock = disableWakeLock ?? WakelockPlus.disable {
    _platformSupport = DisplayPlatformSupport(
      brightness: Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isWindows,
      wakeLock: true,
    );

    _stateSubject = BehaviorSubject.seeded(DisplayState(
      wakeLockEnabled: false,
      wakeLockOverride: false,
      brightness: 100,
      requestedBrightness: 100,
      lowBatteryBrightnessActive: false,
      platformSupported: _platformSupport,
    ));
  }
```

- [ ] **Step 3: Update initialize() and dispose()**

Replace `initialize()` and `dispose()`:

```dart
  void initialize() {
    _de1Subscription = _de1Controller.de1.listen(_onDe1Changed);
    _batterySubscription = _batteryStateStream?.listen(_onBatteryChanged);
    _settingsController.addListener(_onSettingsChanged);
  }

  void dispose() {
    _de1Subscription?.cancel();
    _de1Subscription = null;
    _snapshotSubscription?.cancel();
    _snapshotSubscription = null;
    _batterySubscription?.cancel();
    _batterySubscription = null;
    _settingsController.removeListener(_onSettingsChanged);
    _stateSubject.close();
  }
```

- [ ] **Step 4: Replace dim()/restore() with setBrightness()**

Remove `dim()` and `restore()` methods (lines 141-163). Replace with:

```dart
  /// Set screen brightness to a value between 0 and 100.
  /// Values are clamped to the 0-100 range.
  /// Setting 100 returns to OS-managed brightness (respects auto-brightness).
  Future<void> setBrightness(int value) async {
    final clamped = value.clamp(0, 100);
    _requestedBrightness = clamped;
    await _applyBrightness();
  }
```

- [ ] **Step 5: Add _applyBrightness() and battery/settings handlers**

Add after `setBrightness`:

```dart
  /// Applies the effective brightness, considering battery cap.
  Future<void> _applyBrightness() async {
    final effectiveBrightness = _computeEffectiveBrightness();
    _lowBatteryCapping = effectiveBrightness < _requestedBrightness;

    if (!_platformSupport.brightness) {
      _updateState(
        brightness: effectiveBrightness,
        requestedBrightness: _requestedBrightness,
        lowBatteryBrightnessActive: _lowBatteryCapping,
      );
      return;
    }

    try {
      if (effectiveBrightness == 100) {
        await _resetBrightness();
      } else {
        await _setBrightness(effectiveBrightness / 100.0);
      }
      _updateState(
        brightness: effectiveBrightness,
        requestedBrightness: _requestedBrightness,
        lowBatteryBrightnessActive: _lowBatteryCapping,
      );
      _log.fine('Screen brightness set to $effectiveBrightness (requested: $_requestedBrightness)');
    } catch (e) {
      _log.warning('Failed to set brightness: $e');
    }
  }

  int _computeEffectiveBrightness() {
    if (_batteryStateStream == null ||
        !_settingsController.lowBatteryBrightnessLimit) {
      return _requestedBrightness;
    }
    final batteryPercent = _lastBatteryPercent;
    if (batteryPercent != null && batteryPercent < _lowBatteryThreshold) {
      return _requestedBrightness.clamp(0, _lowBatteryBrightnessCap);
    }
    return _requestedBrightness;
  }

  void _onBatteryChanged(ChargingState state) {
    _lastBatteryPercent = state.batteryPercent;
    unawaited(_applyBrightness());
  }

  void _onSettingsChanged() {
    unawaited(_applyBrightness());
  }
```

- [ ] **Step 6: Update _onSnapshot for sleep/wake with new brightness model**

Replace the `_onSnapshot` method:

```dart
  void _onSnapshot(MachineSnapshot snapshot) {
    final previousState = _currentMachineState;
    _currentMachineState = snapshot.state.state;

    if (previousState == _currentMachineState) return;

    // Save brightness when machine enters sleep (before skin can dim)
    if (_currentMachineState == MachineState.sleeping) {
      _preSleepBrightness = _requestedBrightness;
      _log.fine('Machine sleeping, saved pre-sleep brightness: $_preSleepBrightness');
    }

    // Auto-restore brightness when machine wakes from sleep
    if (previousState == MachineState.sleeping &&
        (_currentMachineState == MachineState.idle ||
            _currentMachineState == MachineState.schedIdle)) {
      _log.info('Machine woke from sleep, restoring brightness to $_preSleepBrightness');
      unawaited(setBrightness(_preSleepBrightness));
    }

    unawaited(_evaluateWakeLock());
  }
```

- [ ] **Step 7: Update _updateState to include new fields**

Replace the `_updateState` method:

```dart
  void _updateState({
    bool? wakeLockEnabled,
    bool? wakeLockOverride,
    int? brightness,
    int? requestedBrightness,
    bool? lowBatteryBrightnessActive,
  }) {
    _stateSubject.add(currentState.copyWith(
      wakeLockEnabled: wakeLockEnabled,
      wakeLockOverride: wakeLockOverride,
      brightness: brightness,
      requestedBrightness: requestedBrightness,
      lowBatteryBrightnessActive: lowBatteryBrightnessActive,
    ));
  }
```

- [ ] **Step 8: Run tests**

Run: `flutter test test/controllers/display_controller_test.dart`
Expected: All tests pass. If compilation errors remain, fix them.

- [ ] **Step 9: Run full test suite and analyze**

Run: `flutter test && flutter analyze`
Expected: All tests pass, no analysis issues.

- [ ] **Step 10: Commit**

```bash
git add lib/src/controllers/display_controller.dart test/controllers/display_controller_test.dart
git commit -m "feat: replace dim/restore with setBrightness(0-100) and battery-aware cap"
```

---

### Task 4: Update DisplayHandler for new brightness API

**Files:**
- Modify: `lib/src/services/webserver/display_handler.dart`

- [ ] **Step 1: Replace dim/restore routes with PUT brightness**

In `lib/src/services/webserver/display_handler.dart`, replace the `addRoutes` method:

```dart
  void addRoutes(RouterPlus app) {
    app.get('/api/v1/display', _getState);
    app.put('/api/v1/display/brightness', _setBrightness);
    app.post('/api/v1/display/wakelock', _requestWakeLock);
    app.delete('/api/v1/display/wakelock', _releaseWakeLock);
    app.get('/ws/v1/display', _handleWebSocket);
  }
```

- [ ] **Step 2: Replace _dim and _restore handlers with _setBrightness**

Remove `_dim` and `_restore` methods. Add:

```dart
  /// PUT /api/v1/display/brightness
  Future<Response> _setBrightness(Request request) async {
    try {
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final brightness = json['brightness'];
      if (brightness == null || brightness is! int || brightness < 0 || brightness > 100) {
        return Response.badRequest(
          body: jsonEncode({'error': 'brightness must be an integer 0-100'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      await _displayController.setBrightness(brightness);
      return jsonOk(_displayController.currentState.toJson());
    } catch (e, st) {
      log.severe('Error in setBrightness handler', e, st);
      return jsonError({'error': e.toString()});
    }
  }
```

- [ ] **Step 3: Update WebSocket command handling**

In `_handleWebSocket`, replace the `switch` block for commands:

```dart
            switch (command) {
              case 'setBrightness':
                final brightness = data['brightness'];
                if (brightness is int && brightness >= 0 && brightness <= 100) {
                  _displayController.setBrightness(brightness);
                } else {
                  log.warning('Invalid setBrightness value: $brightness');
                }
                break;
              case 'requestWakeLock':
                overrideRequested = true;
                _displayController.requestWakeLock();
                break;
              case 'releaseWakeLock':
                overrideRequested = false;
                _displayController.releaseWakeLock();
                break;
            }
```

- [ ] **Step 4: Run tests and analyze**

Run: `flutter test && flutter analyze`
Expected: All tests pass, no analysis issues.

- [ ] **Step 5: Commit**

```bash
git add lib/src/services/webserver/display_handler.dart
git commit -m "feat: replace dim/restore endpoints with PUT brightness, update WS commands"
```

---

### Task 5: Add DisplayHandler tests

**Files:**
- Create: `test/services/webserver/display_handler_test.dart`

Note: Since `DisplayHandler` is `part of '../webserver_service.dart'`, handler tests may need to test through the full web server or use integration-style tests. If this proves too complex (the web server has many dependencies), test the handler logic indirectly through the controller tests + manual MCP verification in Task 9. At minimum, verify the handler compiles and routes are registered by running the app in simulate mode.

Alternatively, if the project has existing handler test patterns, follow those. Check `test/services/webserver/` for examples.

- [ ] **Step 1: Check for existing handler test patterns**

Run: `ls test/services/webserver/ 2>/dev/null || echo "no handler tests directory"`

If no handler tests exist in the project, skip creating a test file and rely on:
1. Controller unit tests (already comprehensive in Task 2)
2. MCP verification in Task 9 (manual smoke test)

If handler tests do exist, follow their pattern to test:
1. `PUT /api/v1/display/brightness` with body `{"brightness": 50}` → 200 + state JSON
2. `PUT /api/v1/display/brightness` with missing body → 400
3. `PUT /api/v1/display/brightness` with `{"brightness": 150}` → 400
4. `PUT /api/v1/display/brightness` with `{"brightness": -1}` → 400

- [ ] **Step 2: Commit if tests were added**

```bash
git add test/services/webserver/
git commit -m "test: add DisplayHandler tests for PUT brightness validation"
```

---

### Task 6: Wire up new dependencies in main.dart and settings handler

**Files:**
- Modify: `lib/main.dart:257-258`
- Modify: `lib/src/services/webserver/settings_handler.dart:43-47` (GET) and `:156-194` (POST)

- [ ] **Step 1: Update DisplayController construction in main.dart**

Replace lines 257-258 in `lib/main.dart`:

```dart
  final displayController = DisplayController(de1Controller: de1Controller);
  displayController.initialize();
```

With:

```dart
  final displayController = DisplayController(
    de1Controller: de1Controller,
    batteryController: batteryController,
    settingsController: settingsController,
  );
  displayController.initialize();
```

- [ ] **Step 2: Add lowBatteryBrightnessLimit to settings GET handler**

In `lib/src/services/webserver/settings_handler.dart`, in the GET handler, after the `'nightModeMorningTime'` entry (line 46), add:

```dart
        'lowBatteryBrightnessLimit': _controller.lowBatteryBrightnessLimit,
```

- [ ] **Step 3: Add lowBatteryBrightnessLimit to settings POST handler**

In `lib/src/services/webserver/settings_handler.dart`, after the `nightModeMorningTime` POST block (after line 193), add:

```dart
      if (json.containsKey('lowBatteryBrightnessLimit')) {
        final value = json['lowBatteryBrightnessLimit'];
        if (value is bool) {
          await _controller.setLowBatteryBrightnessLimit(value);
        } else {
          return Response.badRequest(
            body: {'message': 'lowBatteryBrightnessLimit must be a boolean'},
          );
        }
      }
```

- [ ] **Step 4: Run tests and analyze**

Run: `flutter test && flutter analyze`
Expected: All tests pass, no analysis issues.

- [ ] **Step 5: Commit**

```bash
git add lib/main.dart lib/src/services/webserver/settings_handler.dart
git commit -m "feat: wire DisplayController to BatteryController and SettingsController, expose lowBatteryBrightnessLimit in settings API"
```

---

### Task 7: Update settings plugin

**Files:**
- Modify: `assets/plugins/settings.reaplugin/manifest.json`
- Modify: `assets/plugins/settings.reaplugin/plugin.js:495-510`

- [ ] **Step 1: Bump manifest version**

In `assets/plugins/settings.reaplugin/manifest.json`, change:
```json
"version": "0.0.13",
```
to:
```json
"version": "0.0.14",
```

- [ ] **Step 2: Add toggle to Battery & Charging section**

In `assets/plugins/settings.reaplugin/plugin.js`, after the Night Mode Morning Time setting item (after line 495, before the `chargingState` conditional block), add:

```javascript
                    <div class="setting-item">
                        <label class="setting-label" for="lowBatteryBrightnessLimit">Low Battery Brightness Limit</label>
                        <div class="setting-control">
                            <select id="lowBatteryBrightnessLimit">
                                <option value="true" ${reaSettings.lowBatteryBrightnessLimit ? 'selected' : ''}>Enabled</option>
                                <option value="false" ${!reaSettings.lowBatteryBrightnessLimit ? 'selected' : ''}>Disabled</option>
                            </select>
                            <span id="lowBatteryBrightnessLimit-desc" class="visually-hidden">When enabled, limits screen brightness to 20% when battery is below 30%</span>
                            <button class="btn btn-primary" onclick="updateReaSetting('lowBatteryBrightnessLimit', document.getElementById('lowBatteryBrightnessLimit').value === 'true')" aria-label="Save low battery brightness limit setting">Save</button>
                        </div>
                    </div>
```

- [ ] **Step 3: Commit**

```bash
git add assets/plugins/settings.reaplugin/manifest.json assets/plugins/settings.reaplugin/plugin.js
git commit -m "feat: add low battery brightness limit toggle to settings plugin (v0.0.14)"
```

---

### Task 8: Update API documentation

**Files:**
- Modify: `assets/api/rest_v1.yml:2715-2763` (remove dim/restore, add brightness endpoint), `assets/api/rest_v1.yml:3921-3942` (DisplayState schema)
- Modify: `assets/api/websocket_v1.yml:92-106` (channel description), `assets/api/websocket_v1.yml:523-558` (schemas)

- [ ] **Step 1: Update REST API spec — remove dim/restore, add brightness endpoint**

In `assets/api/rest_v1.yml`, replace lines 2715-2739 (the `/api/v1/display/dim` and `/api/v1/display/restore` entries) with:

```yaml
  /api/v1/display/brightness:
    put:
      summary: Set screen brightness
      description: |
        Sets the screen brightness to a value between 0 and 100.
        Setting brightness to 100 returns to OS-managed brightness (respects auto-brightness settings).
        Values 0-99 set an explicit brightness level.
        If the low battery brightness limit is active (battery < 30% and setting enabled), the actual applied brightness may be capped at 20.
        The response includes both `brightness` (actual applied) and `requestedBrightness` (what was requested).
      tags: [Display]
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required: [brightness]
              properties:
                brightness:
                  type: integer
                  minimum: 0
                  maximum: 100
                  description: Brightness level (0-100). 100 returns to OS-managed brightness.
      responses:
        "200":
          description: Updated display state
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/DisplayState"
        "400":
          description: Invalid brightness value
```

- [ ] **Step 2: Update DisplayState schema in rest_v1.yml**

Replace the `DisplayState` schema (lines 3921-3942) with:

```yaml
    DisplayState:
      type: object
      properties:
        wakeLockEnabled:
          type: boolean
          description: Whether wake-lock is currently active
        wakeLockOverride:
          type: boolean
          description: Whether a skin has requested a wake-lock override
        brightness:
          type: integer
          minimum: 0
          maximum: 100
          description: Actual applied brightness level (0-100). May differ from requestedBrightness if battery cap is active.
        requestedBrightness:
          type: integer
          minimum: 0
          maximum: 100
          description: The brightness level that was requested. If no battery cap is active, this equals brightness.
        lowBatteryBrightnessActive:
          type: boolean
          description: Whether the low battery brightness cap is currently limiting brightness
        platformSupported:
          type: object
          properties:
            brightness:
              type: boolean
              description: Whether brightness control is supported on this platform
            wakeLock:
              type: boolean
              description: Whether wake-lock is supported on this platform
```

- [ ] **Step 3: Update WebSocket spec — channel description**

In `assets/api/websocket_v1.yml`, replace the Display channel description (lines 94-101) with:

```yaml
    description: |
      Streams display state changes (wake-lock and brightness) in real-time.
      Also accepts commands via WebSocket messages:
      - `{"command": "setBrightness", "brightness": 75}` — set brightness (0-100, where 100 returns to OS-managed)
      - `{"command": "requestWakeLock"}` — request wake-lock override
      - `{"command": "releaseWakeLock"}` — release wake-lock override
      Wake-lock overrides requested via this WebSocket are automatically released when the connection closes.
```

- [ ] **Step 4: Update WebSocket schemas**

Replace the `DisplayState` schema (lines 523-544) with:

```yaml
    DisplayState:
      type: object
      properties:
        wakeLockEnabled:
          type: boolean
          description: Whether wake-lock is currently active
        wakeLockOverride:
          type: boolean
          description: Whether a skin has requested a wake-lock override
        brightness:
          type: integer
          minimum: 0
          maximum: 100
          description: Actual applied brightness level (0-100)
        requestedBrightness:
          type: integer
          minimum: 0
          maximum: 100
          description: The brightness level that was requested
        lowBatteryBrightnessActive:
          type: boolean
          description: Whether the low battery brightness cap is currently limiting brightness
        platformSupported:
          type: object
          properties:
            brightness:
              type: boolean
              description: Whether brightness control is supported on this platform
            wakeLock:
              type: boolean
              description: Whether wake-lock is supported on this platform
```

Replace the `DisplayCommand` schema (lines 546-558) with:

```yaml
    DisplayCommand:
      type: object
      required:
        - command
      properties:
        command:
          type: string
          enum:
            - setBrightness
            - requestWakeLock
            - releaseWakeLock
          description: The display command to execute.
        brightness:
          type: integer
          minimum: 0
          maximum: 100
          description: Brightness value (required when command is setBrightness).
```

- [ ] **Step 5: Commit**

```bash
git add assets/api/rest_v1.yml assets/api/websocket_v1.yml
git commit -m "docs: update OpenAPI and AsyncAPI specs for brightness 0-100 API"
```

---

### Task 9: Update Skins.md documentation

**Files:**
- Modify: `doc/Skins.md:1341-1408` (Display Control REST section), `doc/Skins.md:1723-1778` (Display State Stream WebSocket section)

- [ ] **Step 1: Replace Display Control REST section**

In `doc/Skins.md`, replace lines 1341-1408 (from `### Display Control` through the Wake-Lock Auto-Management section) with:

```markdown
### Display Control

Control the tablet's screen brightness and wake-lock (keep-screen-on) behavior. Useful for skins that want to adjust brightness during idle periods or prevent the screen from turning off during active use.

#### Get Display State
```http
GET /api/v1/display
```

**Response:**
```json
{
  "wakeLockEnabled": true,
  "wakeLockOverride": false,
  "brightness": 75,
  "requestedBrightness": 75,
  "lowBatteryBrightnessActive": false,
  "platformSupported": {
    "brightness": true,
    "wakeLock": true
  }
}
```

**Fields:**
- `wakeLockEnabled` (boolean): Whether the screen is currently prevented from turning off
- `wakeLockOverride` (boolean): Whether a skin has manually requested wake-lock (overrides auto-management)
- `brightness` (integer, 0-100): Actual applied screen brightness. May differ from `requestedBrightness` if the low battery brightness cap is active.
- `requestedBrightness` (integer, 0-100): The brightness level that was requested by the skin. If no battery cap is active, this equals `brightness`.
- `lowBatteryBrightnessActive` (boolean): Whether the low battery brightness cap is currently limiting brightness (battery < 30% and setting enabled).
- `platformSupported.brightness` (boolean): Whether brightness control is available on this platform
- `platformSupported.wakeLock` (boolean): Whether wake-lock control is available on this platform

#### Set Brightness
```http
PUT /api/v1/display/brightness
Content-Type: application/json

{"brightness": 75}
```

Sets the screen brightness to a value between 0 and 100. Setting brightness to 100 returns to OS-managed brightness (respects auto-brightness settings on the device). Values 0-99 set an explicit brightness level.

Returns 400 if `brightness` is missing or outside the 0-100 range.

**Response:** Updated `DisplayState` JSON (same format as GET).

**Note:** If the low battery brightness limit setting is enabled and battery is below 30%, the actual applied brightness will be capped at 20 regardless of the requested value. The response will show the capped value in `brightness` and the original request in `requestedBrightness`.

#### Request Wake-Lock Override
```http
POST /api/v1/display/wakelock
```

Forces the screen to stay on regardless of machine state. Normally, wake-lock is auto-managed (on when machine is connected and awake, off when sleeping). This endpoint overrides that behavior.

**Response:** Updated `DisplayState` JSON.

#### Release Wake-Lock Override
```http
DELETE /api/v1/display/wakelock
```

Returns to auto-managed wake-lock behavior based on machine state.

**Response:** Updated `DisplayState` JSON.

**Wake-Lock Auto-Management:**
- When no override is active, wake-lock is automatically enabled when the machine is connected and not sleeping, and disabled when the machine sleeps or disconnects.
- Brightness is automatically restored to its pre-sleep value when the machine transitions from sleeping to idle.

**Low Battery Brightness Cap:**
- When the `lowBatteryBrightnessLimit` setting is enabled (via `POST /api/v1/settings`) and battery drops below 30%, screen brightness is capped at 20.
- When battery recovers above 30%, brightness is restored to the requested value.
- Battery level is polled every 60 seconds, so there may be up to a 60-second delay between charging state changes and brightness cap activation/deactivation.
- This feature is only available on platforms with battery monitoring (Android/iOS).
```

- [ ] **Step 2: Replace Display State Stream WebSocket section**

In `doc/Skins.md`, replace lines 1723-1778 (the `### 9. Display State Stream` section through the example code block) with:

```markdown
### 9. Display State Stream

**Endpoint:** `ws/v1/display`

**Purpose:** Real-time display state updates with bidirectional command support. Preferred over polling `GET /api/v1/display` for reactive UIs.

**Outgoing Messages (server → client):**

Sent whenever display state changes (brightness, wake-lock):

```json
{
  "wakeLockEnabled": true,
  "wakeLockOverride": false,
  "brightness": 75,
  "requestedBrightness": 75,
  "lowBatteryBrightnessActive": false,
  "platformSupported": {
    "brightness": true,
    "wakeLock": true
  }
}
```

**Incoming Commands (client → server):**

Send JSON commands to control the display:

```json
{"command": "setBrightness", "brightness": 75}
{"command": "requestWakeLock"}
{"command": "releaseWakeLock"}
```

**Auto-Cleanup:** If a client sends `requestWakeLock`, the wake-lock override is automatically released when the WebSocket connection closes. This prevents orphaned wake-locks if a skin disconnects unexpectedly.

**Example:**
```javascript
const displayWs = new WebSocket('ws://192.168.1.100:8080/ws/v1/display');

displayWs.onopen = () => {
  // Keep screen on while skin is active
  displayWs.send(JSON.stringify({ command: 'requestWakeLock' }));
  // Set brightness to 80%
  displayWs.send(JSON.stringify({ command: 'setBrightness', brightness: 80 }));
};

displayWs.onmessage = (event) => {
  const state = JSON.parse(event.data);
  console.log('Brightness:', state.brightness);
  console.log('Requested:', state.requestedBrightness);
  console.log('Battery-capped:', state.lowBatteryBrightnessActive);

  // Adapt UI based on platform support
  if (!state.platformSupported.brightness) {
    hideBrightnessControls();
  }
};

// Wake-lock is automatically released when this WebSocket closes
```
```

- [ ] **Step 3: Commit**

```bash
git add doc/Skins.md
git commit -m "docs: update Skins.md display control section for brightness 0-100 API"
```

---

### Task 10: Archive plans and open PR

**Files:**
- Move: `doc/plans/2026-03-20-brightness-0-100-design.md` and `doc/plans/2026-03-20-brightness-0-100-plan.md` to `doc/plans/archive/brightness-0-100/`

- [ ] **Step 1: Run full test suite one final time**

Run: `flutter test && flutter analyze`
Expected: All tests pass, no analysis issues.

- [ ] **Step 2: Archive plan documents**

```bash
mkdir -p doc/plans/archive/brightness-0-100
mv doc/plans/2026-03-20-brightness-0-100-design.md doc/plans/archive/brightness-0-100/
mv doc/plans/2026-03-20-brightness-0-100-plan.md doc/plans/archive/brightness-0-100/
```

- [ ] **Step 3: Commit archive**

```bash
git add doc/plans/
git commit -m "chore: archive brightness 0-100 design and plan docs"
```

- [ ] **Step 4: Push and open PR**

```bash
git push -u origin feature/brightness-0-100
```

Open PR with title and description summarizing:
- Breaking API change: `POST /dim` and `POST /restore` replaced with `PUT /brightness`
- New `DisplayState` fields: `brightness` (int), `requestedBrightness`, `lowBatteryBrightnessActive`
- New setting: `lowBatteryBrightnessLimit`
- Settings plugin bumped to 0.0.14
