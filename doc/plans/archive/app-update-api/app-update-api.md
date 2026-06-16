# App Update API (#306)

**Issue:** [#306](https://github.com/tadelv/reaprime/issues/306) — "API support for updating Decent.app." User (Mark) wants a skin to be able to trigger an app update.

**Branch:** `feature/app-update-api` → PR to `main`.

## Goal

Expose the existing update machinery (`UpdateCheckService` + `AndroidUpdater`) over the REST/WebSocket API so a WebUI skin can:
1. read whether an update is available (version, notes, release URL), and
2. trigger download + install on Android (other platforms hand off a GitHub URL).

## Surface

One source of truth — a single `AppUpdateState` stream owned by `UpdateCheckService` — exposed two ways:

| Surface | Route | Role |
|---|---|---|
| Read | `GET /api/v1/update` | snapshot of current `AppUpdateState` (pure read, **no** network call) |
| Live + control | `GET /ws/v1/update` (WebSocket) | streams state changes; accepts inbound `{command}` frames |

Modeled on `devices_handler` (`devices_handler.dart:355+`): a WS that streams state snapshots **and** accepts `{command: ...}` inbound, with REST kept for the cheap one-shot read.

### WebSocket commands

```jsonc
{"command": "check"}     // force re-poll GitHub releases
{"command": "install"}   // Android: auto-check-if-needed -> download -> install
                         // other:   transient {error, url}
```

- **`install` auto-checks**: if phase is `idle` (no known update), it runs the check first; if an update is found it proceeds, otherwise it settles back to `idle` (already latest). One call does the whole job.
- **Coalesce duplicates**: a command received while `checking`/`downloading`/`installing` is a no-op (re-emit current state). Single in-flight op (mirrors the queue-with-coalesce idiom in `ConnectionManager`).

### State model (new)

```dart
enum AppUpdatePhase { idle, checking, available, downloading, installing, error }

class AppUpdateState {
  final AppUpdatePhase phase;
  final String  currentVersion;   // BuildInfo.version
  final String? latestVersion;    // set once known (>= available)
  final String? releaseNotes;
  final String  releaseUrl;       // tag URL when known, else releases page
  final bool    installable;      // Platform.isAndroid && update available
  final double? progress;         // 0..1 while downloading
  final String? error;            // set in phase == error
  Map<String, dynamic> toJson();
}
```

### Error channel split (mirrors `devices_handler`)

- **Command-level** (unknown command, missing field, non-Android `install` not supported) → transient direct socket reply `{"error": "...", "url": "..."}`, **state stream untouched**.
- **Operational** (download/install failure, install-permission missing) → `AppUpdateState{phase: error, error: ...}` in the stream, so `GET` and a reconnecting WS both see it.

## Security

**No new auth.** The whole `/api/v1/*` + `/ws/v1/*` surface runs on the documented LAN-trust model (only `/api/v1/account/proxy/` is token-gated, per `proxy_auth_middleware.dart`). Rationale:
- The APK source is hardcoded (`owner: 'tadelv', repo: 'reaprime'`) — install can only ever fetch an official signed release, not arbitrary code.
- Android install still goes through the OS `REQUEST_INSTALL_PACKAGES` confirmation dialog — **not silent**; a human at the tablet must tap "Install."
- DE1 machine control is already unauthenticated on the same API, so this is not the weakest link.

**Flag for the existing "put the whole API behind auth" TODO** — when that lands, this endpoint must be in scope; do not special-case it.

## Changes

### 1. `AppUpdateState` model (new file)
`lib/src/services/app_update_state.dart` — enum + immutable class + `toJson()`.

### 2. `UpdateCheckService` (extend — single source of truth)
- Replace the `_availableUpdate` field with `BehaviorSubject<AppUpdateState>`.
- Keep `availableUpdate` / `hasAvailableUpdate` getters as **thin wrappers** over the subject's value → `main.dart` `AppLifecycleObserver` and `update_dialog.dart` callers keep compiling unchanged (surgical: no UI edits).
- Add `Stream<AppUpdateState> get updateState` (+ sync `value` getter for GET).
- Add `Future<void> downloadAndInstall()`: drives `checking?` → `downloading{progress}` → `installing`, emitting on each transition; coalesces if already running; non-Android → no-op + signal not-supported to caller (handler turns it into the transient socket error).
- `checkForUpdate()` updates the state stream (`checking` → `available` / `idle` / `error`).

### 3. `AndroidUpdater.downloadUpdate()` (fix)
Rewrite to a **streamed** download (`client.send()` + accumulate bytes against `Content-Length`) so `onProgress(0..1)` actually fires. Currently it reads `response.bodyBytes` whole and never calls `onProgress`. Also improves the in-app dialog (indeterminate → real bar) for free, but **no dialog edits in this PR**.

### 4. `UpdateHandler` (new handler)
`lib/src/services/webserver/update_handler.dart` — standalone handler (like `InfoHandler`), constructor takes `UpdateCheckService`.
- `GET /api/v1/update` → `jsonOk(service.updateState.value.toJson())`.
- `GET /ws/v1/update` → forward `service.updateState` to the socket; `socket.stream.listen` → `_handleCommand` (check / install) following the `devices_handler` shape exactly.

### 5. Wiring
- `webserver_service.dart`: add `UpdateCheckService? updateCheckService` named param to `startWebServer(...)`, thread to `_init`, instantiate `UpdateHandler`, `addRoutes(app)`.
- `main.dart`: pass the existing `updateCheckService` into the `startWebServer(...)` call.

### 6. Spec + docs (required, same PR)
- `assets/api/rest_v1.yml` — `GET /api/v1/update`.
- `assets/api/websocket_v1.yml` — `/ws/v1/update` topic + command frames.
- `doc/Api.md` — user-facing endpoint + command reference.

### 7. Obsidian
Add a proper `#306` TODO entry under the ReaPrime TODO note (currently only in the sync-log line).

## Testing

| Tier | What |
|---|---|
| Unit | `UpdateCheckService` state machine: check → available/idle/error; `install` auto-check path; coalesce; non-Android `install` → not-supported. Mock `AndroidUpdater`. |
| Unit | `AndroidUpdater.downloadUpdate` streamed progress: fake streamed `http.Client`, assert `onProgress` monotonic 0→1. |
| Unit | `UpdateHandler`: GET returns snapshot; WS emits snapshot on connect; unknown command → `{error}`; non-Android install → `{error,url}`. |
| End-to-end | `sb-dev` (macOS) + `websocat ws://localhost:8080/ws/v1/update`: connect → snapshot frame; `{command:"check"}` → `checking`→`idle`; `{command:"install"}` → transient `{error: not installable, url}` (macOS isn't Android). `curl /api/v1/update` → snapshot. |

Android real-install path can't be exercised in sim — note as manual-on-tablet follow-up (not a release gate for the API itself, but call it out).

## Out of scope (deliberately deferred)
- `skip` / `setChannel` WS commands (YAGNI — issue asks only for "trigger update").
- Auth (folded into the global "API behind auth" TODO).
- Migrating `update_dialog.dart` to the state stream (works as-is via callbacks).
- Self-update install on macOS/iOS/Linux/Windows (platform can't; URL hand-off only).

## Open follow-ups
- When global API auth lands, include `/api/v1/update` + `/ws/v1/update`.
- Optional later: migrate the in-app dialog to read `updateState` (removes the callback plumbing).
