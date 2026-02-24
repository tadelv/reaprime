# Smart Charging & Night Mode — Design

**Issue:** #12 — Smart charging settings and "night mode"
**Date:** 2026-02-23
**Branch:** `feature/smart-charging`

## Overview

Streamline-Bridge will automatically control the DE1's USB charger output to manage tablet battery health. The system has three independent layers:

1. **Charging Mode** — determines the target battery percentage range
2. **Night Mode** — optional time-based overlay that overrides charging mode during evening/night
3. **Emergency Floor** — hardcoded 15% minimum, always charges regardless of other settings

## Charging Modes

| Mode | Range | Behavior |
|------|-------|----------|
| Disabled | — | USB charger always on |
| Longevity | 45–55% | Best for battery lifespan |
| Balanced | 40–80% | Good balance of availability and health (default) |
| High Availability | 80–95% | Tablet always near full charge |

All modes use hysteresis to prevent rapid charger toggling: charge below the low threshold, stop above the high threshold, maintain direction when in between.

## Night Mode

When enabled, overrides the active charging mode based on a time schedule:

| Phase | Time Window | Behavior |
|-------|-------------|----------|
| Normal | morning → sleep-2h | Charging mode rules apply |
| Hovering | sleep-2h → sleep-30min | Hysteresis around 80% (75–80% band) |
| Charging to Max | sleep-30min → sleep | Charge up to 95% |
| Sleeping | sleep → morning | No charging |

**Defaults:** sleep = 22:00, morning = 07:00. Offsets (2h, 30min) are hardcoded.

**Warning:** Settings UI shows a warning when the no-charge window (sleep → morning) exceeds 10 hours.

## Emergency Floor

If battery drops to 15% or below, charging is enabled regardless of mode or night phase. Hardcoded, not user-configurable (for now).

## Architecture

### Pure Function Core

The charging decision is a pure function with no side effects:

```dart
ChargingDecision decide({
  required int batteryPercent,
  required DateTime currentTime,
  required ChargingMode chargingMode,
  required NightModeConfig? nightModeConfig, // null if disabled
  required bool wasCharging,
}) → ChargingDecision
```

Returns:
```dart
class ChargingDecision {
  final bool shouldCharge;
  final NightPhase nightPhase;
  final String reason; // for logging
}
```

Priority order within the function:
1. Emergency (battery <= 15%) → charge
2. Disabled mode → charge
3. Night mode phase logic (if enabled)
4. Charging mode range logic (with hysteresis)

### Enums

```dart
enum ChargingMode { disabled, longevity, balanced, highAvailability }
enum NightPhase { inactive, normal, hovering, chargingToMax, sleeping }
```

### Observable State

```dart
class ChargingState {
  final ChargingMode mode;
  final bool nightModeEnabled;
  final NightPhase currentPhase;
  final int batteryPercent;
  final bool usbChargerOn;
  final bool isEmergency;
}
```

Exposed as `BehaviorSubject<ChargingState>` from `BatteryController`.

### Dependency Flow

```
SettingsService ──┐
                  ├──► BatteryController ──► De1Controller ──► DE1 (BLE MMR 0x803854)
battery_plus ─────┘         │
                            ▼
                    BehaviorSubject<ChargingState>
                            │
                    ┌───────┴───────┐
                    ▼               ▼
                 Web API        Settings UI
```

### Time Math

Time comparisons use minutes-since-midnight to handle wrapping (e.g., sleep=01:00 means hover starts at 23:00 the previous day).

## Files to Create/Modify

### New Files

| File | Purpose |
|------|---------|
| `lib/src/controllers/charging_logic.dart` | Pure function `decide()`, `ChargingDecision`, `NightPhase`, `NightModeConfig`, `ChargingState` |
| `lib/src/settings/charging_mode.dart` | `ChargingMode` enum (follows `gateway_mode.dart` pattern) |
| `lib/src/settings/battery_charging_settings_page.dart` | Settings sub-page UI |
| `test/controllers/charging_logic_test.dart` | Pure function unit tests |
| `test/controllers/battery_controller_test.dart` | Controller integration tests |

### Modified Files

| File | Changes |
|------|---------|
| `lib/src/controllers/battery_controller.dart` | Rewrite: inject `SettingsService`, 60s timer, call `decide()`, expose `Stream<ChargingState>`, proper `dispose()` |
| `lib/src/settings/settings_service.dart` | Add `chargingMode`, `nightModeEnabled`, `nightModeSleepTime`, `nightModeMorningTime` settings + `SettingsKeys` |
| `lib/src/settings/settings_view.dart` (or equivalent) | Add navigation to Battery & Charging sub-page |
| `lib/main.dart` | Pass `SettingsService` to `BatteryController`, store reference for disposal |
| `lib/src/services/webserver/de1handler.dart` | Add charging state to machine settings response |
| WebSocket device state handler | Include charging state in emissions |
| `assets/api/rest_v1.yml` | Document new charging state fields |
| `settings.reaplugin` | Expose charging settings to plugin system |

## API Surface

### REST

**GET `/api/v1/machine/settings`** — existing endpoint, add to response:
```json
{
  "charging": {
    "mode": "balanced",
    "nightMode": {
      "enabled": true,
      "sleepTime": "22:00",
      "morningTime": "07:00"
    },
    "state": {
      "phase": "normal",
      "batteryPercent": 62,
      "usbChargerOn": true,
      "isEmergency": false
    }
  }
}
```

**POST `/api/v1/machine/settings`** — accept charging mode and night mode config updates.

### WebSocket

Charging state included in device state emissions on `ws/v1/devices`.

## Testing Strategy

### Pure Function Tests (bulk of effort)

- Each charging mode: charge below low, stop above high, hysteresis in between
- Night mode phase transitions at exact boundary times
- Emergency override in every mode and phase
- Midnight wrapping for night mode times
- Edge cases: battery exactly at thresholds, wasCharging true/false at boundaries

### Controller Tests

- Timer fires and calls decide() with correct inputs
- Settings changes are picked up on next tick
- USB charger mode is applied via De1Controller
- ChargingState stream emits on changes
- Proper disposal of timer and subscriptions

### UI Tests

- Charging mode selector updates settings
- Night mode toggle shows/hides time pickers
- Warning appears when no-charge window > 10h
- Navigation from settings to sub-page works

## Check Interval

60 seconds — matches DE1 reference app, handles the 10-minute MMR reset, gives precise enough time transitions for night mode phases.



