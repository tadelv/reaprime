# Heartbeat, Machine Sleep & Scheduled Wake — Design

**Issue:** #13
**Date:** 2026-02-24
**Status:** Approved

## Overview

Three related features for managing DE1 machine power state based on user presence and time schedules:

1. **Heartbeat API** — skins and native UI signal user presence; forwarded to DE1 firmware
2. **Sleep timeout** — auto-sleep when no heartbeat received for a configurable duration
3. **Scheduled wake** — wake the machine at configured times with recurring day-of-week schedules

## DE1 Protocol

### Registers

| Register | Address | Size | Values | Purpose |
|----------|---------|------|--------|---------|
| `APP_FEATURE_FLAGS` | `0x00803858` | 4 bytes | `0x01` = USER_PRESENT | Tell firmware the app supports user presence tracking |
| `UserPresent` | `0x00803860` | 4 bytes | 0 or 1 | Signal that a user is currently present |

### Protocol Flow

1. **On connect:** Write `0x01` to `APP_FEATURE_FLAGS` (0x00803858) to opt into user presence tracking
2. **On heartbeat:** Write `0x01` to `UserPresent` (0x00803860), throttled to max once per 30s
3. **On scheduled wake:** Send `SchedIdle` state request (0x15) instead of regular `Idle` (0x02)
4. **On sleep timeout:** Send `Sleep` state request (0x00)

### Reference

- The de1app (TCL) has the `set_user_present` and `set_feature_flags` functions but has NOT activated them (commented out)
- pyDE1 (Python) HAS activated user presence for firmware >= 1320
- `SchedIdle` requires firmware >= 1293
- The `sent_scheduled_idle` flag in de1app prevents user-present signals for 5 seconds after a scheduled wake, to avoid resetting the firmware's idle timer

## Architecture

### Approach: Dedicated `PresenceController`

A new `PresenceController` owns all three concerns. Follows the project's existing pattern of focused controllers with constructor dependency injection.

```
PresenceController({
  required De1Controller de1Controller,
  required SettingsController settingsController,
})
```

## Heartbeat Management

The heartbeat is **event-driven**, not timer-driven. User presence is signaled only when the user is actually interacting.

### Sources of Heartbeat

1. **Skin/WebUI** — calls `POST /api/v1/machine/heartbeat` periodically while the user interacts with the skin
2. **Native Flutter UI** — sends heartbeat on route navigation via a `NavigatorObserver`

### Behavior on Heartbeat

- Forward `userPresent` MMR write to the DE1 (0x00803860 = 1), throttled to max once per 30s to avoid BLE spam
- Reset the sleep timeout timer

### No Automatic Keep-Alive

If nobody calls heartbeat, the machine receives no `userPresent` signals. The firmware enters `userNotPresent` substate (0x13) and the app's timeout eventually puts the machine to sleep.

## Sleep Timeout

- A configurable timeout (default: 30 minutes, stored in settings)
- A single `Timer` that resets on every heartbeat
- When the timer fires (no heartbeat for the configured duration), sends `Sleep` state request
- Only active when machine is in idle state — paused during active operations (espresso, steam, etc.)
- Disabled when timeout is set to 0 (never auto-sleep)

## Scheduled Wake

- A list of `WakeSchedule` entries, persisted in settings
- Each schedule has: time (hour + minute), days of week (1=Mon through 7=Sun, empty = every day), enabled flag
- Multiple schedules supported (e.g., "weekdays at 6:00" + "weekends at 9:00" + "daily at 13:00")
- An in-process `Timer` checks every 60 seconds whether the current time matches any active schedule
- When a match fires, sends `SchedIdle` (0x15) state request
- After firing, marks the schedule as "fired today" to prevent re-triggering within the same minute window

### WakeSchedule Model

```dart
class WakeSchedule {
  final String id;           // UUID
  final int hour;            // 0-23
  final int minute;          // 0-59
  final Set<int> daysOfWeek; // 1-7 (Mon-Sun), empty = every day
  final bool enabled;
}
```

## REST API

New handler: `presence_handler.dart` (part of `webserver_service.dart`)

| Method | Path | Purpose |
|--------|------|---------|
| `POST` | `/api/v1/machine/heartbeat` | Signal user presence. Resets sleep timeout, forwards to DE1. Returns `{"timeout": <seconds_remaining>}` |
| `GET` | `/api/v1/presence/settings` | Get presence settings (sleep timeout, wake schedules) |
| `POST` | `/api/v1/presence/settings` | Update presence settings |
| `GET` | `/api/v1/presence/schedules` | Get all wake schedules |
| `POST` | `/api/v1/presence/schedules` | Add a wake schedule |
| `PUT` | `/api/v1/presence/schedules/<id>` | Update a wake schedule |
| `DELETE` | `/api/v1/presence/schedules/<id>` | Delete a wake schedule |

### Example Schedule JSON

```json
{
  "id": "abc123",
  "time": "06:00",
  "daysOfWeek": [1, 2, 3, 4, 5],
  "enabled": true
}
```

### Example Settings JSON

```json
{
  "sleepTimeoutMinutes": 30,
  "userPresenceEnabled": true,
  "schedules": [
    {
      "id": "abc123",
      "time": "06:00",
      "daysOfWeek": [1, 2, 3, 4, 5],
      "enabled": true
    }
  ]
}
```

## Settings & Persistence

New settings in `SettingsController` / `SettingsService`:

| Setting | Type | Default | Purpose |
|---------|------|---------|---------|
| `userPresenceEnabled` | `bool` | `true` | Enable/disable the entire user presence system |
| `sleepTimeoutMinutes` | `int` | `30` | Minutes of no heartbeat before auto-sleep. 0 = disabled |
| `wakeSchedules` | `String` (JSON) | `"[]"` | Serialized list of `WakeSchedule` entries |

Schedules are stored as a JSON string via the existing `SettingsService` KV store.

## Settings Plugin Update

The `settings.reaplugin` (`assets/plugins/settings.reaplugin/plugin.js`) gets a new "Presence & Schedule" section:

- Fetch from `GET /api/v1/presence/settings`
- Display: user presence enabled/disabled, sleep timeout value, list of wake schedules with time/days/enabled status
- Follow the existing HTML rendering pattern used for other settings sections
- **Bump manifest version** from `0.0.12` to `0.0.13` in `manifest.json`

## Presence Settings Page (Flutter UI)

A new `PresenceSettingsPage` widget, following the `BatteryChargingSettingsPage` pattern:

**Navigation:** Accessed from `SettingsView` via a `ListTile` → `Navigator.push(MaterialPageRoute(...))`.

**Layout (3 ShadCard sections):**

1. **User Presence** card — `ShadSwitch` to enable/disable, with description text
2. **Sleep Timeout** card (visible when presence enabled) — dropdown for timeout duration (disabled/0, 15, 30, 45, 60 minutes)
3. **Wake Schedules** card — list of schedules with time picker, day-of-week multi-select, enable/disable toggle, delete button, and "Add schedule" button

## Protocol Layer Changes

### New MMR Item

Add `userPresent(0x00803860, 4, "Is User Present")` to the `MMRItem` enum.

### New `De1Interface` Methods

- `Future<void> enableUserPresenceFeature()` — write `0x01` to `appFeatureFlags` (0x00803858)
- `Future<void> sendUserPresent()` — write `0x01` to `userPresent` (0x00803860)

### Connection Setup

Call `enableUserPresenceFeature()` in `UnifiedDe1.onConnect()` after existing initialization.

### SchedIdle State

Add `schedIdle` as a distinct requestable `MachineState` so the controller can send `0x15` to the firmware.

## Files to Create

| File | Purpose |
|------|---------|
| `lib/src/controllers/presence_controller.dart` | Main controller for heartbeat, sleep timeout, scheduled wake |
| `lib/src/models/wake_schedule.dart` | `WakeSchedule` model with JSON serialization |
| `lib/src/services/webserver/presence_handler.dart` | REST API handler |
| `lib/src/settings/presence_settings_page.dart` | Flutter settings UI page |
| `test/controllers/presence_controller_test.dart` | Unit tests |

## Files to Modify

| File | Change |
|------|--------|
| `lib/src/models/device/impl/de1/de1.models.dart` | Add `userPresent` MMR item |
| `lib/src/models/device/de1_interface.dart` | Add `enableUserPresenceFeature()`, `sendUserPresent()` |
| `lib/src/models/device/impl/de1/unified_de1/unified_de1.dart` | Implement new methods |
| `lib/src/models/device/machine.dart` | Add `schedIdle` as requestable state |
| `lib/src/settings/settings_controller.dart` | Add presence settings properties |
| `lib/src/settings/settings_service.dart` | Add persistence methods |
| `lib/src/settings/settings_view.dart` | Add navigation to `PresenceSettingsPage` |
| `lib/src/services/webserver_service.dart` | Register `PresenceHandler` |
| `lib/main.dart` | Wire up `PresenceController` |
| `test/helpers/mock_settings_service.dart` | Add mock methods for new settings |
| `assets/api/rest_v1.yml` | Document new endpoints |
| `assets/plugins/settings.reaplugin/plugin.js` | Add presence & schedule display section |
| `assets/plugins/settings.reaplugin/manifest.json` | Version bump to `0.0.13` |

## Testing

- **Unit tests** for `PresenceController`: mock `De1Controller` and `SettingsController`, verify heartbeat throttling, sleep timeout firing, schedule matching logic
- **Unit tests** for `WakeSchedule` matching: correct day/time matching, edge cases (midnight crossing, empty days = every day)
- **Widget test** for `NavigatorObserver` heartbeat trigger
- **No hardware needed**: all protocol writes are behind the `De1Interface` abstraction
