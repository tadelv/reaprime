# Screen Brightness API & Wake-Lock Design

**Issue:** [#15 — Screen brightness API and wake-lock](https://github.com/tadelv/reaprime/issues/15)
**Date:** 2026-02-25

## Overview

Expose screen brightness and wake-lock control via REST and WebSocket APIs. Skins can dim the display when the machine sleeps and request persistent wake-lock for screensaver-style UIs. The app auto-manages wake-lock based on machine state, with skin override capability.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Wake-lock management | Auto-managed + skin override | Auto-enable when machine awake, auto-release on sleep. Skins can override for screensaver scenarios. |
| Brightness control | Dim/restore (skin-initiated) | Simple API. App doesn't auto-dim on sleep — skins decide. Safety net: auto-restore on machine wake. |
| Plugin approach | Community packages | `wakelock_plus` + `screen_brightness`. Well-maintained, no permissions needed. |
| State broadcast | New `/ws/v1/display` WebSocket | Dedicated channel for display state changes. |
| Architecture | New DisplayController + DisplayHandler | Follows existing controller/handler pattern. Single responsibility. |

## DisplayController

**File:** `lib/src/controllers/display_controller.dart`

### Responsibilities

1. **Wake-lock auto-management** — Listens to `De1Controller.de1` stream and machine snapshots. Enables wake-lock when machine is connected and not sleeping. Releases when machine sleeps or disconnects.
2. **Wake-lock override** — Skins can force wake-lock on via `requestWakeLock()`. Override persists until `releaseWakeLock()` is called. Auto-released when the requesting WebSocket disconnects.
3. **Brightness dim/restore** — `dim()` saves current brightness and sets application brightness to a low level (~0.05). `restore()` resets to previous brightness. Auto-restore as safety net when machine transitions from sleeping to idle/schedIdle.
4. **State broadcasting** — `BehaviorSubject<DisplayState>` for real-time state.

### Dependencies

- `De1Controller` (machine state)
- `wakelock_plus` package
- `screen_brightness` package

### Platform Awareness

- Brightness: Android, iOS, macOS (where `screen_brightness` works). No-op on other platforms.
- Wake-lock: All platforms via `wakelock_plus`.
- `DisplayState.platformSupported` reports capability per feature.

### DisplayState Model

```dart
class DisplayState {
  final bool wakeLockEnabled;
  final bool wakeLockOverride;
  final DisplayBrightness brightness; // enum: normal, dimmed
  final DisplayPlatformSupport platformSupported;
}

enum DisplayBrightness { normal, dimmed }

class DisplayPlatformSupport {
  final bool brightness;
  final bool wakeLock;
}
```

## REST API

**Handler file:** `lib/src/services/webserver/display_handler.dart`

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/api/v1/display` | Get current display state |
| `POST` | `/api/v1/display/dim` | Dim screen to low brightness |
| `POST` | `/api/v1/display/restore` | Restore screen brightness |
| `POST` | `/api/v1/display/wakelock` | Request wake-lock override |
| `DELETE` | `/api/v1/display/wakelock` | Release wake-lock override |

### Response Format

```json
{
  "wakeLockEnabled": true,
  "wakeLockOverride": false,
  "brightness": "normal",
  "platformSupported": {
    "brightness": true,
    "wakeLock": true
  }
}
```

## WebSocket Channel

| Path | Direction | Payload |
|------|-----------|---------|
| `/ws/v1/display` | Server → Client | `DisplayState` JSON on every state change |

### Wake-lock Override Lifecycle

The wake-lock override is tied to the requesting client. If the skin's WebSocket disconnects without releasing, the override auto-releases. This prevents orphaned overrides from crashed skins.

## Integration

### main.dart

- Create `DisplayController(de1Controller: de1Controller)` after de1Controller
- Call `displayController.initialize()`
- Pass to `startWebServer()`

### webserver_service.dart

- Add `DisplayController?` parameter to `startWebServer()`
- Add `part 'webserver/display_handler.dart'`
- Create `DisplayHandler`, register routes (same pattern as `PresenceHandler`)

### pubspec.yaml

```yaml
wakelock_plus: ^4.0.0
screen_brightness: ^1.0.0
```

### API Docs

- `assets/api/rest_v1.yml` — new display endpoints
- `assets/api/websocket_v1.yml` — new `/ws/v1/display` channel

## Files

| Action | File |
|--------|------|
| Create | `lib/src/controllers/display_controller.dart` |
| Create | `lib/src/services/webserver/display_handler.dart` |
| Create | `test/controllers/display_controller_test.dart` |
| Modify | `lib/main.dart` |
| Modify | `lib/src/services/webserver_service.dart` |
| Modify | `pubspec.yaml` |
| Modify | `assets/api/rest_v1.yml` |
| Modify | `assets/api/websocket_v1.yml` |

## Testing Strategy

- **Unit tests** for `DisplayController` using mock `De1Controller` and `fakeAsync`
- Test auto wake-lock on machine connect/disconnect and state transitions
- Test dim/restore logic (mock brightness — can't test actual screen in unit tests)
- Test override lifecycle (request, release, auto-release)
- **Handler tests** for REST endpoint responses
