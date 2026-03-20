# Brightness 0-100 Range Refactor + Battery-Aware Brightness Cap

**Date:** 2026-03-20

## Overview

Replace the binary brightness model (`dim`/`normal` enum) with a continuous 0-100 integer range. Add a battery-aware brightness cap that limits brightness when battery is low. This is a breaking API change.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Brightness representation | Integer 0-100 | Intuitive percentage scale, maps to `screen_brightness` 0.0-1.0 |
| API shape | Single `PUT /api/v1/display/brightness` | Replaces two endpoints (`dim`/`restore`) with one flexible endpoint |
| Pre-sleep restore | Save brightness before sleep, restore on wake | User asked: restore to value before sleep, not a fixed default |
| Battery cap threshold | Hardcoded 30% | Simpler for now, can be made configurable later |
| Battery cap brightness | Hardcoded 20 | Maximum brightness when battery-capped |
| Battery cap setting | `lowBatteryBrightnessLimit` boolean in SettingsService | Follows existing settings pattern, off by default |
| Requested vs actual | Track both in DisplayState | Skins know when they're being capped and what value will restore |
| `setBrightness(100)` semantics | Calls `resetApplicationScreenBrightness()` | Returns to OS-managed brightness (respects auto-brightness) rather than forcing maximum |
| Settings change listener | `ChangeNotifier` listener on `SettingsController` | Enables immediate response to setting toggles (not polling) |

## DisplayController Changes

### State Model

```dart
class DisplayState {
  final bool wakeLockEnabled;
  final bool wakeLockOverride;
  final int brightness;                    // actual applied brightness (0-100)
  final int requestedBrightness;           // what was requested (may differ if battery-capped)
  final bool lowBatteryBrightnessActive;   // true when cap is currently applied
  final DisplayPlatformSupport platformSupported;
}
```

Removes: `DisplayBrightness` enum.

### Controller API

| Old | New |
|-----|-----|
| `dim()` | **Removed** |
| `restore()` | **Removed** |
| — | `setBrightness(int value)` — clamps to 0-100, applies battery cap if active |

### Internal State Tracking

- `_requestedBrightness` (int): What the skin/user last set. Defaults to 100.
- `_preSleepBrightness` (int): Captured in `_onSnapshot` at the moment machine transitions *to* `sleeping` — i.e., before any skin-initiated dimming. Restored on wake.
- Actual applied brightness = `min(_requestedBrightness, _batteryCap)` when cap is active, otherwise `_requestedBrightness`.

### `setBrightness(100)` Semantics

Setting brightness to 100 calls `resetApplicationScreenBrightness()` (the existing `_resetBrightness` injectable) rather than `setApplicationScreenBrightness(1.0)`. This returns control to the OS (respecting auto-brightness settings) rather than forcing maximum. Values 0-99 call `setApplicationScreenBrightness(value / 100.0)`.

Both `_setBrightness` and `_resetBrightness` injectables are retained.

### New Dependencies

- `BatteryController?` or `Stream<ChargingState>?` — the constructor accepts both; internally stores the stream. Nullable since battery is platform-conditional (Android/iOS only). On other platforms, battery cap feature is unavailable. In tests, pass `batteryStateStream:` directly to avoid constructing a real `BatteryController` (which starts timers).
- `SettingsController` — to read `lowBatteryBrightnessLimit` setting. Listens via `ChangeNotifier`.

Constructor changes:
```dart
DisplayController({
  required De1Controller de1Controller,
  BatteryController? batteryController,
  Stream<ChargingState>? batteryStateStream,
  required SettingsController settingsController,
  // ... injectable platform operations unchanged ...
})
```

The constructor resolves: `_batteryStateStream = batteryStateStream ?? batteryController?.chargingState`.

### Battery-Aware Capping Logic

When `lowBatteryBrightnessLimit` setting is enabled:
1. Subscribe to `BatteryController.chargingState` stream.
2. When `batteryPercent < 30` → activate cap: actual brightness = `min(_requestedBrightness, 20)`.
3. When `batteryPercent >= 30` → deactivate cap: actual brightness = `_requestedBrightness`.
4. When setting is toggled off while cap is active → immediately restore to `_requestedBrightness`.
5. When setting is toggled on and battery is already low → immediately apply cap.

**Settings change detection:** `DisplayController` registers a `ChangeNotifier` listener on `SettingsController` in `initialize()` (removed in `dispose()`). When the listener fires, it re-reads `lowBatteryBrightnessLimit` and re-evaluates brightness. This is a new pattern for controller-to-settings interaction in this codebase.

**Known limitations:**
- No hysteresis on the 30% threshold — if battery oscillates around 30%, brightness will toggle. Acceptable for initial implementation.
- `BatteryController` polls every 60 seconds, so cap activation/deactivation after charging state changes may be delayed up to 60s. **Document this in `doc/Skins.md`** so skin developers set expectations correctly.

Constants:
```dart
static const int _lowBatteryThreshold = 30;
static const int _lowBatteryBrightnessCap = 20;
```

### Sleep/Wake Interaction

1. Machine transitions *to* `sleeping` (detected in `_onSnapshot`) → save current `_requestedBrightness` as `_preSleepBrightness` **before** any skin-initiated dimming can occur. This is captured at the state transition, not on a subsequent `setBrightness` call.
2. Machine wakes (transitions from `sleeping` to `idle`/`schedIdle`) → call `setBrightness(_preSleepBrightness)`.
3. The restored value still goes through battery cap logic — if battery is low and setting is on, the restored value will be capped.
4. If the skin never dims for sleep, `_preSleepBrightness` still captures the current value, and wake-restore is a no-op (same value).

### Interaction Matrix

| Scenario | Requested | Applied |
|----------|-----------|---------|
| `setBrightness(80)`, battery fine | 80 | 80 |
| `setBrightness(80)`, battery < 30%, setting on | 80 | 20 |
| Battery recovers above 30% | 80 | 80 |
| `setBrightness(15)`, battery < 30%, setting on | 15 | 15 (already below cap) |
| Machine sleeps (brightness was 80) | — | saves 80 as pre-sleep |
| Machine wakes, battery < 30%, setting on | 80 | 20 |
| Machine wakes, battery fine | 80 | 80 |
| Setting toggled off while capped | 80 | 80 (immediate restore) |

## REST API Changes

### Retained Endpoints (Breaking Response Change)

- `GET /api/v1/display` — retained, but response format changes: `brightness` field changes from string (`"normal"`) to integer (`75`), and new fields `requestedBrightness` and `lowBatteryBrightnessActive` are added.

### Removed Endpoints

- `POST /api/v1/display/dim`
- `POST /api/v1/display/restore`

### New Endpoint

**`PUT /api/v1/display/brightness`**

Request body:
```json
{"brightness": 75}
```

Validation:
- `brightness` must be present and an integer 0-100.
- Returns 400 with error message if invalid.

Response: Updated `DisplayState` JSON.

### Updated Response Format

```json
{
  "wakeLockEnabled": true,
  "wakeLockOverride": false,
  "brightness": 20,
  "requestedBrightness": 80,
  "lowBatteryBrightnessActive": true,
  "platformSupported": {
    "brightness": true,
    "wakeLock": true
  }
}
```

### Settings API

`GET /api/v1/settings` response gains:
```json
{
  "lowBatteryBrightnessLimit": false
}
```

`POST /api/v1/settings` accepts:
```json
{
  "lowBatteryBrightnessLimit": true
}
```

## WebSocket Changes

### Updated Commands

| Old | New |
|-----|-----|
| `{"command": "dim"}` | **Removed** |
| `{"command": "restore"}` | **Removed** |
| — | `{"command": "setBrightness", "brightness": 75}` |

### Updated State Messages

Same format as the REST response — includes `brightness`, `requestedBrightness`, and `lowBatteryBrightnessActive`.

### WebSocket Validation

Invalid `setBrightness` commands (missing `brightness` field, out-of-range values) are silently ignored and logged — matching the existing error handling pattern in the WebSocket handler's `catch` block. No error message is sent back on the socket.

## Settings

### SettingsService

Add to abstract interface:
```dart
Future<bool> lowBatteryBrightnessLimit();
Future<void> setLowBatteryBrightnessLimit(bool value);
```

Add `lowBatteryBrightnessLimit` to `SettingsKeys` enum.

Implement in `SharedPreferencesSettingsService` (default: `false`).

### SettingsController

Add field, getter, loader line in `loadSettings()`, and setter method following existing pattern.

### Settings Plugin UI

Add a toggle in the "Battery & Charging" section of `assets/plugins/settings.reaplugin/plugin.js`. Bump manifest version from `0.0.13` to `0.0.14`.

## Files to Change

| Action | File | Change |
|--------|------|--------|
| Modify | `lib/src/controllers/display_controller.dart` | Replace enum with int, dim/restore → setBrightness, add battery subscription, add settings dependency |
| Modify | `lib/src/services/webserver/display_handler.dart` | Replace dim/restore routes with PUT brightness, update WS commands |
| Modify | `test/controllers/display_controller_test.dart` | Rewrite brightness tests for 0-100, add battery cap tests |
| Modify | `lib/src/settings/settings_service.dart` | Add lowBatteryBrightnessLimit setting |
| Modify | `lib/src/settings/settings_controller.dart` | Add field + getter + setter |
| Modify | `lib/src/services/webserver/settings_handler.dart` | Add lowBatteryBrightnessLimit to GET/POST |
| Modify | `lib/main.dart` | Pass batteryController + settingsController to DisplayController |
| Modify | `assets/api/rest_v1.yml` | Update display endpoints and schema; document that brightness 100 resets to OS-managed brightness |
| Modify | `assets/api/websocket_v1.yml` | Update display commands and schema |
| Modify | `doc/Skins.md` | Update display control docs: document `setBrightness(100)` = return to OS auto-brightness, document 60s battery polling delay for cap changes |
| Modify | `assets/plugins/settings.reaplugin/plugin.js` | Add toggle in Battery & Charging section |
| Modify | `assets/plugins/settings.reaplugin/manifest.json` | Bump version to 0.0.14 |

**Out of scope:** No dedicated display MCP tool exists in `packages/mcp-server/src/tools/`. The `streaming.ts` tool references `/ws/v1/display` for subscriptions but does not need changes (it passes through raw WebSocket messages).

## Testing Strategy

Tests written before implementation (TDD):

### Unit Tests (DisplayController)

1. **Basic brightness:** `setBrightness(50)` → state shows brightness 50
2. **Clamping:** `setBrightness(150)` → clamped to 100; `setBrightness(-5)` → clamped to 0
3. **Initial state:** brightness starts at 100, requestedBrightness 100
4. **Sleep/wake:** brightness saved on sleep, restored on wake
5. **Battery cap activation:** setting on + battery < 30% → brightness capped at 20
6. **Battery cap with low request:** request 15 when capped → applied 15 (below cap)
7. **Battery recovery:** battery rises above 30% → brightness restores to requested
8. **Setting toggle off:** cap active → toggle off → immediate restore
9. **Setting toggle on:** battery already low → immediate cap
10. **No battery controller:** on desktop, battery cap feature is unavailable, setBrightness works normally
11. **Sleep/wake + battery cap:** wake from sleep while battery low → restored value is capped

### Handler Tests

1. `PUT /brightness` with valid body → 200 + updated state
2. `PUT /brightness` with missing brightness → 400
3. `PUT /brightness` with out-of-range value → 400
4. Old endpoints (`POST /dim`, `POST /restore`) → 404
