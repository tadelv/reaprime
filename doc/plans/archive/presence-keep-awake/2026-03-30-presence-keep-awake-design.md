# Presence Schedule Keep-Awake Window

**Issue:** #117 — Add sleep time option to presence schedule API
**Date:** 2026-03-30

## Summary

Add an optional `keepAwakeFor` duration (in minutes) to wake schedules. When a schedule fires and has `keepAwakeFor` set, auto-sleep is suppressed for that duration. After the window expires, normal auto-sleep timeout resumes.

## Model Change

Add to `WakeSchedule`:

```dart
final int? keepAwakeFor; // minutes, 1–720 (12 hours), null = wake only
```

JSON representation:

```json
{
  "id": "8ff7585d-e5c8-4de6-8e22-7055737d399a",
  "time": "10:00",
  "keepAwakeFor": 60,
  "daysOfWeek": [1, 3],
  "enabled": true
}
```

- `keepAwakeFor` is optional. Absent or null means wake-only (current behavior).
- Validated: integer 1–720, or null/absent.
- 0 treated as null (no keep-awake).

## Controller Logic

`PresenceController` changes:

1. **New state:** `DateTime? _keepAwakeUntil` — timestamp when the current keep-awake window expires.

2. **On schedule fire** (`_checkSchedules`): If the matched schedule has `keepAwakeFor`, set `_keepAwakeUntil = DateTime.now().add(Duration(minutes: keepAwakeFor))`.

3. **Sleep timeout suppression** (`_onSleepTimeout`): Before sending sleep, check if `_keepAwakeUntil != null && DateTime.now().isBefore(_keepAwakeUntil!)`. If so, skip sleep and restart the timer. This effectively keeps the machine idle but awake.

4. **Manual sleep override:** The controller already subscribes to machine state via `_onSnapshot`. If the machine transitions to `sleeping` while `_keepAwakeUntil` is set, clear `_keepAwakeUntil`. The keep-awake is a convenience, not a lock — user intent takes priority. (Note: this also triggers if firmware auto-sleeps for reasons outside our control, which is the correct behavior.)

5. **Restart behavior:** `_keepAwakeUntil` is in-memory only. On app restart, the schedule checker re-fires within 30 seconds if still within the schedule's minute. If the app restarts mid-window but after the schedule minute has passed, the keep-awake is lost — acceptable trade-off for simplicity.

6. **Expose keep-awake status:** Add a method or stream so the UI/API can show whether keep-awake is active and when it expires. Include in the presence settings GET response.

## API Changes

### Existing endpoints — additive changes only

**GET/POST `/api/v1/presence/settings`** response adds:

```json
{
  "userPresenceEnabled": true,
  "sleepTimeoutMinutes": 15,
  "keepAwakeUntil": "2026-03-30T11:00:00.000",
  "schedules": [...]
}
```

`keepAwakeUntil` is null when no keep-awake window is active. ISO 8601 local time.

**POST `/api/v1/presence/schedules`** and **PUT `/api/v1/presence/schedules/{id}`** accept `keepAwakeFor` in the body. Validation: if present and non-null, must be integer 1–720.

### No new endpoints needed

## UI Changes

`presence_settings_page.dart`:

- Add optional duration input to each schedule row (e.g., dropdown or number input: 15, 30, 45, 60, 90, 120 minutes, or custom). <<< make it a number input, with validation
- Show "Keep awake for X min" label on schedules that have it set.
- When keep-awake is active, show indicator on the presence settings page (e.g., "Keeping awake until HH:MM").

## MCP Tools

No dedicated presence MCP tools exist currently. Out of scope for this change — the REST API is directly usable via the generic MCP REST tools.

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| `keepAwakeFor` is 0 | Treated as null — wake only |
| `keepAwakeFor` > 720 | Rejected with 400 Bad Request |
| `keepAwakeFor` is negative | Rejected with 400 Bad Request |
| User manually sleeps machine during window | Keep-awake cleared, machine sleeps |
| Multiple schedules fire with different `keepAwakeFor` | Later one extends `_keepAwakeUntil` if its expiry is further in the future |
| App restarts during keep-awake window | Window lost; schedule may re-fire if still within the same minute |
| Auto-sleep timeout is 0 (disabled) | Keep-awake has no effect (auto-sleep already disabled) |
| Machine in active state (espresso, steam, etc.) when window expires | Existing logic: auto-sleep waits for idle state anyway |

## Testing

### Unit tests (WakeSchedule model)
- Serialization round-trip with `keepAwakeFor` present, null, absent, and 0
- Validation of bounds (1–720)
- `copyWith` with `keepAwakeFor`

### Unit tests (PresenceController)
- Schedule fires with `keepAwakeFor` → `_keepAwakeUntil` is set
- Auto-sleep suppressed during keep-awake window
- Auto-sleep resumes after window expires
- Manual sleep clears keep-awake
- Multiple schedules: latest expiry wins
- Schedule without `keepAwakeFor` does not set keep-awake

### Integration / MCP verification
- Create schedule with `keepAwakeFor` via API, verify it persists
- GET settings shows `keepAwakeUntil` when active

## Files to Modify

| File | Change |
|------|--------|
| `lib/src/models/wake_schedule.dart` | Add `keepAwakeFor` field, serialization, validation |
| `lib/src/controllers/presence_controller.dart` | Add `_keepAwakeUntil`, suppress logic, manual sleep detection |
| `lib/src/services/webserver/presence_handler.dart` | Pass through `keepAwakeFor`, expose `keepAwakeUntil` |
| `lib/src/settings/presence_settings_page.dart` | Duration picker UI |
| `test/models/wake_schedule_test.dart` | New test cases |
| `test/controllers/presence_controller_test.dart` | New test cases |
| `assets/api/rest_v1.yml` | Document new fields |
