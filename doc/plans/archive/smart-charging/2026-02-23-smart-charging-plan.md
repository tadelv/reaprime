# Smart Charging & Night Mode Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement smart battery charging with 4 modes, night mode scheduling, and API exposure for issue #12.

**Architecture:** Pure function `decide()` computes charging decisions from inputs (battery %, time, settings, previous state). `BatteryController` calls it every 60s and applies the result via DE1 USB charger MMR. State exposed as `BehaviorSubject<ChargingState>` to API and UI.

**Tech Stack:** Flutter/Dart, `battery_plus`, `rxdart` BehaviorSubject, SharedPreferences, Shelf web server.

**Design doc:** `doc/plans/2026-02-23-smart-charging-design.md`

---

### Task 1: ChargingMode enum

**Files:**
- Create: `lib/src/settings/charging_mode.dart`

**Step 1: Create the enum file**

Follow the `gateway_mode.dart` pattern (`lib/src/settings/gateway_mode.dart`):

```dart
import 'package:collection/collection.dart';

enum ChargingMode {
  disabled,
  longevity,
  balanced,
  highAvailability,
}

extension ChargingModeFromString on ChargingMode {
  static ChargingMode? fromString(String mode) {
    return ChargingMode.values.firstWhereOrNull((t) => t.name == mode);
  }
}
```

**Step 2: Verify**

Run: `flutter analyze lib/src/settings/charging_mode.dart`
Expected: No issues found.

**Step 3: Commit**

```bash
git add lib/src/settings/charging_mode.dart
git commit -m "feat: add ChargingMode enum for smart charging"
```

---

### Task 2: Pure function charging logic

**Files:**
- Create: `lib/src/controllers/charging_logic.dart`
- Create: `test/controllers/charging_logic_test.dart`

**Step 1: Write the charging logic file**

Create `lib/src/controllers/charging_logic.dart` with:

- `enum NightPhase { inactive, normal, hovering, chargingToMax, sleeping }`
- `class NightModeConfig { final int sleepTimeMinutes; final int morningTimeMinutes; }` (minutes-since-midnight)
- `class ChargingDecision { final bool shouldCharge; final NightPhase nightPhase; final String reason; }`
- `class ChargingState { final ChargingMode mode; final bool nightModeEnabled; final NightPhase currentPhase; final int batteryPercent; final bool usbChargerOn; final bool isEmergency; }` with `toJson()` method
- `ChargingDecision decide({required int batteryPercent, required DateTime currentTime, required ChargingMode chargingMode, required NightModeConfig? nightModeConfig, required bool wasCharging})`

The `decide()` function priority:
1. Emergency: `batteryPercent <= 15` → `shouldCharge: true`, reason: "emergency"
2. Disabled: `chargingMode == disabled` → `shouldCharge: true`, reason: "disabled"
3. Night mode (if `nightModeConfig != null`): determine phase from `currentTime`, then:
   - `sleeping` → `shouldCharge: false`
   - `chargingToMax` → charge if below 95%, stop at 95%
   - `hovering` → hysteresis 75-80%
   - `normal` / `inactive` → fall through to step 4
4. Charging mode ranges with hysteresis:
   - `longevity`: low=45, high=55
   - `balanced`: low=40, high=80
   - `highAvailability`: low=80, high=95

Hysteresis logic: `batteryPercent <= low` → charge; `batteryPercent >= high` → stop; in between → maintain `wasCharging` direction.

Time math helper: `int _minutesSinceMidnight(DateTime dt)` → `dt.hour * 60 + dt.minute`. Night phase determination: `NightPhase _determineNightPhase(int currentMinutes, NightModeConfig config)` handles wrapping by normalizing to sleep-relative offsets. Hover starts at `sleepTime - 120`, chargingToMax at `sleepTime - 30`.

**Step 2: Write comprehensive tests**

Create `test/controllers/charging_logic_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/charging_logic.dart';
import 'package:reaprime/src/settings/charging_mode.dart';
```

Test groups:

**group('emergency override')**
- battery at 15% → shouldCharge true, regardless of mode
- battery at 14% → shouldCharge true
- battery at 16% → follows mode rules
- emergency during night sleeping phase → shouldCharge true

**group('disabled mode')**
- always returns shouldCharge true
- nightPhase is inactive

**group('longevity mode 45-55%')**
- battery at 44% → shouldCharge true
- battery at 56% → shouldCharge false
- battery at 50%, wasCharging true → shouldCharge true (hysteresis)
- battery at 50%, wasCharging false → shouldCharge false (hysteresis)
- battery at 45% → shouldCharge true (boundary)
- battery at 55% → shouldCharge false (boundary)

**group('balanced mode 40-80%')**
- Same pattern as longevity but with 40/80 thresholds

**group('highAvailability mode 80-95%')**
- Same pattern but with 80/95 thresholds

**group('night mode phase determination')**
- 19:59 → normal (before hover window)
- 20:00 → hovering (exactly 2h before sleep)
- 21:29 → hovering
- 21:30 → chargingToMax (exactly 30min before sleep)
- 21:59 → chargingToMax
- 22:00 → sleeping (exactly sleep time)
- 06:59 → sleeping
- 07:00 → normal (exactly morning time)
- Use `DateTime(2026, 1, 15, hour, minute)` for test times

**group('night mode hovering phase')**
- battery at 74% → shouldCharge true
- battery at 81% → shouldCharge false
- battery at 77%, wasCharging true → shouldCharge true
- battery at 77%, wasCharging false → shouldCharge false

**group('night mode chargingToMax phase')**
- battery at 94% → shouldCharge true
- battery at 95% → shouldCharge false
- battery at 96% → shouldCharge false

**group('night mode sleeping phase')**
- battery at 50% → shouldCharge false
- battery at 15% → shouldCharge true (emergency overrides)

**group('midnight wrapping')**
- sleep=01:00, morning=08:00: hover starts at 23:00
- At 23:00 → hovering
- At 00:30 → chargingToMax
- At 01:00 → sleeping
- At 07:59 → sleeping
- At 08:00 → normal

**Step 3: Run tests to verify they fail**

Run: `flutter test test/controllers/charging_logic_test.dart`
Expected: FAIL (charging_logic.dart doesn't exist yet or functions not implemented)

**Step 4: Implement the charging logic**

Write the full implementation in `lib/src/controllers/charging_logic.dart`.

**Step 5: Run tests to verify they pass**

Run: `flutter test test/controllers/charging_logic_test.dart`
Expected: All tests PASS.

**Step 6: Run analyzer**

Run: `flutter analyze lib/src/controllers/charging_logic.dart`
Expected: No issues found.

**Step 7: Commit**

```bash
git add lib/src/controllers/charging_logic.dart test/controllers/charging_logic_test.dart
git commit -m "feat: add pure function charging logic with comprehensive tests"
```

---

### Task 3: Settings layer (service + controller + mock)

**Files:**
- Modify: `lib/src/settings/settings_service.dart` — add 4 new abstract methods + implementations + SettingsKeys
- Modify: `lib/src/settings/settings_controller.dart` — add fields, getters, setters, loadSettings
- Modify: `test/helpers/mock_settings_service.dart` — add mock implementations

**Step 1: Add to SettingsService abstract class**

In `lib/src/settings/settings_service.dart`, add to the abstract class (after `setSkippedVersion`):

```dart
Future<ChargingMode> chargingMode();
Future<void> setChargingMode(ChargingMode mode);
Future<bool> nightModeEnabled();
Future<void> setNightModeEnabled(bool value);
Future<int> nightModeSleepTime();  // minutes since midnight
Future<void> setNightModeSleepTime(int minutes);
Future<int> nightModeMorningTime();  // minutes since midnight
Future<void> setNightModeMorningTime(int minutes);
```

Add import: `import 'package:reaprime/src/settings/charging_mode.dart';`

Add to `SettingsKeys` enum: `chargingMode, nightModeEnabled, nightModeSleepTime, nightModeMorningTime`

Implement in `SharedPreferencesSettingsService` following the `scalePowerMode` pattern:
- `chargingMode` default: `ChargingMode.balanced`
- `nightModeEnabled` default: `false`
- `nightModeSleepTime` default: `1320` (22:00 = 22*60)
- `nightModeMorningTime` default: `420` (07:00 = 7*60)

**Step 2: Add to SettingsController**

In `lib/src/settings/settings_controller.dart`:

Add import: `import 'package:reaprime/src/settings/charging_mode.dart';`

Add private fields:
```dart
late ChargingMode _chargingMode;
late bool _nightModeEnabled;
late int _nightModeSleepTime;
late int _nightModeMorningTime;
```

Add getters:
```dart
ChargingMode get chargingMode => _chargingMode;
bool get nightModeEnabled => _nightModeEnabled;
int get nightModeSleepTime => _nightModeSleepTime;
int get nightModeMorningTime => _nightModeMorningTime;
```

Add to `loadSettings()`:
```dart
_chargingMode = await _settingsService.chargingMode();
_nightModeEnabled = await _settingsService.nightModeEnabled();
_nightModeSleepTime = await _settingsService.nightModeSleepTime();
_nightModeMorningTime = await _settingsService.nightModeMorningTime();
```

Add setters (follow `setScalePowerMode` pattern with early return on no change + `notifyListeners()`).

**Step 3: Add to MockSettingsService**

In `test/helpers/mock_settings_service.dart`:

Add import: `import 'package:reaprime/src/settings/charging_mode.dart';`

Add fields and methods:
```dart
ChargingMode _chargingMode = ChargingMode.balanced;
bool _nightModeEnabled = false;
int _nightModeSleepTime = 1320;
int _nightModeMorningTime = 420;

@override
Future<ChargingMode> chargingMode() async => _chargingMode;
@override
Future<void> setChargingMode(ChargingMode mode) async => _chargingMode = mode;
@override
Future<bool> nightModeEnabled() async => _nightModeEnabled;
@override
Future<void> setNightModeEnabled(bool value) async => _nightModeEnabled = value;
@override
Future<int> nightModeSleepTime() async => _nightModeSleepTime;
@override
Future<void> setNightModeSleepTime(int minutes) async => _nightModeSleepTime = minutes;
@override
Future<int> nightModeMorningTime() async => _nightModeMorningTime;
@override
Future<void> setNightModeMorningTime(int minutes) async => _nightModeMorningTime = minutes;
```

**Step 4: Verify**

Run: `flutter analyze lib/src/settings/ test/helpers/mock_settings_service.dart`
Run: `flutter test` (all tests — ensure nothing broke)
Expected: No issues, all tests pass.

**Step 5: Commit**

```bash
git add lib/src/settings/settings_service.dart lib/src/settings/settings_controller.dart test/helpers/mock_settings_service.dart
git commit -m "feat: add charging mode and night mode settings"
```

---

### Task 4: Rewrite BatteryController

**Files:**
- Modify: `lib/src/controllers/battery_controller.dart`
- Modify: `lib/main.dart` (line ~349-351)

**Step 1: Rewrite BatteryController**

Replace the contents of `lib/src/controllers/battery_controller.dart`:

```dart
import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/controllers/charging_logic.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:rxdart/rxdart.dart';

class BatteryController {
  final De1Controller _de1Controller;
  final SettingsController _settingsController;
  final Battery _battery = Battery();
  final Logger _log = Logger("Battery");

  late Timer _checkTimer;
  bool _wasCharging = false;

  final BehaviorSubject<ChargingState> _stateSubject =
      BehaviorSubject<ChargingState>();

  Stream<ChargingState> get chargingState => _stateSubject.stream;
  ChargingState? get currentChargingState => _stateSubject.valueOrNull;

  BatteryController({
    required De1Controller de1Controller,
    required SettingsController settingsController,
  })  : _de1Controller = de1Controller,
        _settingsController = settingsController {
    _checkTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _tick(),
    );
    // Run immediately on construction
    _tick();
  }

  Future<void> _tick() async {
    try {
      final batteryPercent = await _battery.batteryLevel;
      final now = DateTime.now();

      final chargingMode = _settingsController.chargingMode;
      final nightModeEnabled = _settingsController.nightModeEnabled;

      NightModeConfig? nightConfig;
      if (nightModeEnabled) {
        nightConfig = NightModeConfig(
          sleepTimeMinutes: _settingsController.nightModeSleepTime,
          morningTimeMinutes: _settingsController.nightModeMorningTime,
        );
      }

      final decision = decide(
        batteryPercent: batteryPercent,
        currentTime: now,
        chargingMode: chargingMode,
        nightModeConfig: nightConfig,
        wasCharging: _wasCharging,
      );

      _wasCharging = decision.shouldCharge;

      _log.fine(
        'Battery: $batteryPercent%, '
        'phase: ${decision.nightPhase.name}, '
        'charge: ${decision.shouldCharge}, '
        'reason: ${decision.reason}',
      );

      // Apply to DE1
      try {
        final de1 = _de1Controller.connectedDe1();
        await de1.setUsbChargerMode(decision.shouldCharge);
      } catch (e) {
        _log.warning('Failed to set USB charger mode', e);
      }

      // Emit state
      _stateSubject.add(ChargingState(
        mode: chargingMode,
        nightModeEnabled: nightModeEnabled,
        currentPhase: decision.nightPhase,
        batteryPercent: batteryPercent,
        usbChargerOn: decision.shouldCharge,
        isEmergency: decision.reason == 'emergency',
      ));
    } catch (e, st) {
      _log.warning('Battery check failed', e, st);
    }
  }

  void dispose() {
    _checkTimer.cancel();
    _stateSubject.close();
  }
}
```

**Step 2: Wire up in main.dart**

In `lib/main.dart`, around line 349-351, change:

```dart
// OLD:
if (Platform.isAndroid || Platform.isIOS) {
  final batteryController = BatteryController(de1Controller);
}
```

to:

```dart
// NEW:
BatteryController? batteryController;
if (Platform.isAndroid || Platform.isIOS) {
  batteryController = BatteryController(
    de1Controller: de1Controller,
    settingsController: settingsController,
  );
}
```

Note: `batteryController` must be declared outside the `if` block so it can be passed to the web server later (Task 6).

**Step 3: Verify**

Run: `flutter analyze lib/src/controllers/battery_controller.dart lib/main.dart`
Expected: No issues found.

**Step 4: Commit**

```bash
git add lib/src/controllers/battery_controller.dart lib/main.dart
git commit -m "feat: rewrite BatteryController with smart charging logic"
```

---

### Task 5: Settings UI — Battery & Charging sub-page

**Files:**
- Create: `lib/src/settings/battery_charging_settings_page.dart`
- Modify: `lib/src/settings/settings_view.dart`

**Step 1: Create the sub-page**

Create `lib/src/settings/battery_charging_settings_page.dart`.

The page should have:
- `ChargingMode` dropdown (Disabled / Longevity / Balanced / High Availability)
- Night mode toggle (`ShadSwitch`)
- When night mode is enabled, show:
  - Sleep time picker (use `showTimePicker` or a simple hour/minute dropdown)
  - Morning time picker
  - Warning banner if no-charge window > 10 hours
- Description text for each charging mode explaining the battery range

Follow the pattern of existing settings sections in `settings_view.dart` — use `_SettingsSection` style `ShadCard` with `Column` children, `DropdownButton`, `ShadSwitch`, etc.

Convert minutes-since-midnight ↔ `TimeOfDay` for the time pickers:
- `TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60)`
- `timeOfDay.hour * 60 + timeOfDay.minute`

Warning condition: calculate the no-charge window duration. If sleep < morning (e.g., 22:00→07:00), duration = `(1440 - sleep) + morning`. If sleep > morning (e.g., 01:00→08:00), duration = `morning - sleep`. Show warning if > 600 minutes (10 hours).

**Step 2: Add navigation in settings_view.dart**

In `lib/src/settings/settings_view.dart`, add a new section between `_buildGatewaySection()` and `_buildDeviceManagementSection()` in the `build` method's Column children (around line 77):

```dart
_buildBatterySection(),
```

Add the builder method:

```dart
Widget _buildBatterySection() {
  return _SettingsSection(
    title: 'Battery & Charging',
    icon: Icons.battery_charging_full_outlined,
    description: 'Smart charging and night mode settings',
    children: [
      Text(
        'Mode: ${widget.controller.chargingMode.name}',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 12),
      ShadButton.outline(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => BatteryChargingSettingsPage(
                controller: widget.controller,
              ),
            ),
          );
        },
        child: const Text('Configure'),
      ),
    ],
  );
}
```

Add import at top of `settings_view.dart`:
```dart
import 'package:reaprime/src/settings/battery_charging_settings_page.dart';
```

Only show this section on Android/iOS:
```dart
if (Platform.isAndroid || Platform.isIOS) _buildBatterySection(),
```

**Step 3: Verify**

Run: `flutter analyze lib/src/settings/battery_charging_settings_page.dart lib/src/settings/settings_view.dart`
Expected: No issues found.

**Step 4: Commit**

```bash
git add lib/src/settings/battery_charging_settings_page.dart lib/src/settings/settings_view.dart
git commit -m "feat: add Battery & Charging settings sub-page"
```

---

### Task 6: REST API — charging state in settings endpoints

**Files:**
- Modify: `lib/src/services/webserver/settings_handler.dart`
- Modify: `lib/src/services/webserver_service.dart`
- Modify: `lib/main.dart`

**Step 1: Pass BatteryController to web server**

In `lib/src/services/webserver_service.dart`:

Add import: `import 'package:reaprime/src/controllers/battery_controller.dart';`

Add `BatteryController? batteryController` parameter to `startWebServer()` (after `webViewLogService`).

Pass it to `SettingsHandler`:
```dart
final settingsHandler = SettingsHandler(
  controller: settingsController,
  service: webUIService,
  webUIStorage: webUIStorage,
  batteryController: batteryController,
);
```

In `lib/main.dart`, add `batteryController` to the `startWebServer(...)` call (after `webViewLogService`). Move the `BatteryController` creation to **before** the `startWebServer` call.

**Step 2: Update SettingsHandler**

In `lib/src/services/webserver/settings_handler.dart`:

Add `BatteryController?` field to `SettingsHandler`:
```dart
final BatteryController? _batteryController;
```

Update constructor:
```dart
SettingsHandler({
  required SettingsController controller,
  required WebUIService service,
  required WebUIStorage webUIStorage,
  BatteryController? batteryController,
}) : _controller = controller,
     _webUIService = service,
     _webUIStorage = webUIStorage,
     _batteryController = batteryController;
```

In GET `/api/v1/settings`, add charging settings to the response:
```dart
'chargingMode': _controller.chargingMode.name,
'nightModeEnabled': _controller.nightModeEnabled,
'nightModeSleepTime': _controller.nightModeSleepTime,
'nightModeMorningTime': _controller.nightModeMorningTime,
```

Add charging state if available:
```dart
if (_batteryController?.currentChargingState != null) {
  final cs = _batteryController!.currentChargingState!;
  result['chargingState'] = cs.toJson();
}
```

In POST `/api/v1/settings`, handle the new fields:
```dart
if (json.containsKey('chargingMode')) {
  final mode = ChargingModeFromString.fromString(json['chargingMode']);
  if (mode == null) {
    return Response.badRequest(body: {'message': '${json["chargingMode"]} is not a valid charging mode'});
  }
  await _controller.setChargingMode(mode);
}
if (json.containsKey('nightModeEnabled')) {
  final value = json['nightModeEnabled'];
  if (value is bool) {
    await _controller.setNightModeEnabled(value);
  } else {
    return Response.badRequest(body: {'message': 'nightModeEnabled must be a boolean'});
  }
}
if (json.containsKey('nightModeSleepTime')) {
  final value = json['nightModeSleepTime'];
  if (value is int && value >= 0 && value < 1440) {
    await _controller.setNightModeSleepTime(value);
  } else {
    return Response.badRequest(body: {'message': 'nightModeSleepTime must be 0-1439'});
  }
}
if (json.containsKey('nightModeMorningTime')) {
  final value = json['nightModeMorningTime'];
  if (value is int && value >= 0 && value < 1440) {
    await _controller.setNightModeMorningTime(value);
  } else {
    return Response.badRequest(body: {'message': 'nightModeMorningTime must be 0-1439'});
  }
}
```

Add imports at top of `settings_handler.dart` (it's a `part of` file, so imports come from `webserver_service.dart`):
In `webserver_service.dart`, add:
```dart
import 'package:reaprime/src/controllers/battery_controller.dart';
import 'package:reaprime/src/settings/charging_mode.dart';
```

**Step 3: Verify**

Run: `flutter analyze lib/src/services/webserver_service.dart lib/src/services/webserver/settings_handler.dart lib/main.dart`
Expected: No issues found.

**Step 4: Commit**

```bash
git add lib/src/services/webserver_service.dart lib/src/services/webserver/settings_handler.dart lib/main.dart
git commit -m "feat: expose charging settings and state via REST API"
```

---

### Task 7: WebSocket — charging state in device emissions

**Files:**
- Modify: `lib/src/services/webserver/devices_handler.dart`
- Modify: `lib/src/services/webserver_service.dart`

**Step 1: Pass BatteryController to DevicesHandler**

In `webserver_service.dart`, update `DevicesHandler` construction:
```dart
final deviceHandler = DevicesHandler(
  controller: deviceController,
  de1Controller: de1Controller,
  scaleController: scaleController,
  batteryController: batteryController,
);
```

**Step 2: Update DevicesHandler**

Add `BatteryController?` field and constructor parameter.

In `_emitStateNow`, add charging state to the emission:
```dart
if (_batteryController?.currentChargingState != null) {
  state['charging'] = _batteryController!.currentChargingState!.toJson();
}
```

Subscribe to charging state changes in `_handleDevicesSocket`:
```dart
if (_batteryController != null) {
  subscriptions.add(
    _batteryController!.chargingState.skip(1).listen((_) => emitState()),
  );
}
```

**Step 3: Verify**

Run: `flutter analyze lib/src/services/webserver/devices_handler.dart`
Expected: No issues found.

**Step 4: Commit**

```bash
git add lib/src/services/webserver/devices_handler.dart lib/src/services/webserver_service.dart
git commit -m "feat: include charging state in WebSocket device emissions"
```

---

### Task 8: Update settings.reaplugin

**Files:**
- Modify: `assets/plugins/settings.reaplugin/plugin.js`
- Modify: `assets/plugins/settings.reaplugin/manifest.json`

**Step 1: Update plugin.js**

In the `generateSettingsHTML` function, add a new section after the REA Application Settings section for "Battery & Charging":

- Display charging mode (read-only or with dropdown to change via POST)
- Display night mode enabled/disabled
- Display sleep/morning times
- Display current charging state (phase, battery %, USB charger on/off, emergency)

The charging state data comes from the existing `fetchReaSettings()` response (which will now include `chargingMode`, `nightModeEnabled`, `nightModeSleepTime`, `nightModeMorningTime`, and `chargingState`).

Add controls:
- ChargingMode select (disabled/longevity/balanced/highAvailability) with Save button calling `updateReaSetting('chargingMode', ...)`
- Night mode enable/disable select with Save button
- Sleep/morning time inputs (display as HH:MM, send as minutes-since-midnight)

Display read-only state:
- Current phase
- Battery percent
- USB charger status
- Emergency status

**Step 2: Bump version in manifest.json**

Change `"version": "0.0.11"` → `"version": "0.0.12"`.

**Step 3: Verify**

Run: `flutter analyze` (plugin files are assets, just check they're valid JS by inspection)

**Step 4: Commit**

```bash
git add assets/plugins/settings.reaplugin/plugin.js assets/plugins/settings.reaplugin/manifest.json
git commit -m "feat: add charging settings to settings.reaplugin"
```

---

### Task 9: API documentation

**Files:**
- Modify: `assets/api/rest_v1.yml`

**Step 1: Update API spec**

Add to the `ReaSettings` response schema (or wherever `/api/v1/settings` is documented):
- `chargingMode` — string enum: disabled, longevity, balanced, highAvailability
- `nightModeEnabled` — boolean
- `nightModeSleepTime` — integer (0-1439, minutes since midnight)
- `nightModeMorningTime` — integer (0-1439, minutes since midnight)
- `chargingState` — object with: `mode`, `nightModeEnabled`, `currentPhase`, `batteryPercent`, `usbChargerOn`, `isEmergency`

Add to the POST `/api/v1/settings` request body documentation.

Document the `chargingState` object in the WebSocket `/ws/v1/devices` response.

**Step 2: Commit**

```bash
git add assets/api/rest_v1.yml
git commit -m "docs: document charging settings and state in API spec"
```

---

### Task 10: Full test suite run + final verification

**Step 1: Run all tests**

Run: `flutter test`
Expected: All tests pass.

**Step 2: Run analyzer**

Run: `flutter analyze`
Expected: No issues found.

**Step 3: Verification approach**

Per CLAUDE.md verification loop, the user should specify which approach:
- Tests + analyze only
- Tests + run app (simulate=1) for visual verification
- Tests + API smoke test (run app, curl endpoints)

Ask the user which verification to perform before claiming complete.

---

## Task Summary

| Task | Description | Dependencies |
|------|-------------|-------------|
| 1 | ChargingMode enum | None |
| 2 | Pure function charging logic + tests | Task 1 |
| 3 | Settings layer (service + controller + mock) | Task 1 |
| 4 | Rewrite BatteryController | Tasks 2, 3 |
| 5 | Settings UI sub-page | Task 3 |
| 6 | REST API endpoints | Tasks 3, 4 |
| 7 | WebSocket device emissions | Tasks 4, 6 |
| 8 | settings.reaplugin update | Task 6 |
| 9 | API documentation | Tasks 6, 7 |
| 10 | Full test suite + verification | All |

Tasks 1-3 can be parallelized. Tasks 5 and 6 can be parallelized after Task 4.
