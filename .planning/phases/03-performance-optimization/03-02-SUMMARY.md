---
phase: 03-performance-optimization
plan: 02
subsystem: telemetry, ui-performance
tags: [reconnection-tracking, devtools-profiling, stream-throttling, ui-jank]

# Dependency graph
requires:
  - phase: 03-performance-optimization
    plan: 01
    provides: Non-blocking telemetry report queue, fixed LogBuffer
provides:
  - Reconnection event tracking with disconnection duration
  - Synchronized 10Hz stream throttling for StatusTile
  - Telemetry consent dialog and settings toggle (Phase 1 gap closure)
  - FutureBuilder caching to prevent triple initialization
affects: [04-webview-integration]

# Tech tracking
tech-stack:
  added: []
  patterns: [merged-stream-tick, subscription-based-state, cached-stream-reference]

key-files:
  created: []
  modified:
    - lib/src/controllers/device_controller.dart
    - lib/src/home_feature/tiles/status_tile.dart
    - lib/src/permissions_feature/permissions_view.dart
    - lib/src/settings/settings_view.dart
    - lib/src/settings/settings_controller.dart
    - lib/src/settings/settings_service.dart

key-decisions:
  - "Merged Rx.merge + single throttleTime for synchronized 10Hz UI updates across machine, scale, and water level streams"
  - "Cache Rx.combineLatest3 stream in initState to prevent StreamBuilder reconnection flashing on setState"
  - "Added telemetryConsentDialogShown key to handle existing users who had telemetryPromptShown already set"
  - "Cached checkPermissions() Future to prevent FutureBuilder re-execution on widget rebuild"

patterns-established:
  - "Merge high-frequency streams, cache latest values in state, throttle merged stream once for synchronized rebuilds"
  - "Cache combined streams in initState instead of creating in build() to prevent StreamBuilder thrashing"

# Metrics
duration: manual (checkpoint phase with user-driven testing)
completed: 2026-02-16
---

# Phase 03 Plan 02: Reconnection Tracking & DevTools Profiling Summary

**Added reconnection event tracking, verified telemetry performance via DevTools, and fixed UI jank and Phase 1 consent gaps discovered during profiling.**

## Performance

- **Started:** 2026-02-16
- **Completed:** 2026-02-16
- **Tasks:** 2 (1 auto + 1 checkpoint)
- **Files modified:** 6
- **Additional fixes during checkpoint:** 5

## Accomplishments

### Planned Work
- DeviceController tracks disconnection timestamps per device and logs reconnection duration at INFO level
- Telemetry custom keys include `reconnection_duration_{device}` for correlation
- Stale disconnection entries cleaned up after 24 hours
- DevTools profiling confirmed zero UI jank from telemetry during scan/connect flows

### Gaps Found During Checkpoint Verification
- **Telemetry consent dialog missing** — Phase 1 PRIV-03/PRIV-04 was half-implemented (silently set flag without showing UI). Added real consent dialog in permissions_view and toggle in settings_view.
- **Existing users never see dialog** — Old code had already set `telemetryPromptShown=true`. Added new `telemetryConsentDialogShown` key that only the real dialog sets.
- **checkPermissions() running 3x** — `PermissionsView` created new Future in FutureBuilder on every rebuild, causing triple WebUI init and port binding failures. Cached Future in constructor.
- **Scale weight jank** — `weightSnapshot` StreamBuilder firing at 10-20+/sec caused janked frames. Throttled to 10Hz.
- **Machine snapshot + scale unsynchronized** — Two independent `throttleTime` calls fired at different offsets. Replaced with single merged subscription: `Rx.merge([currentSnapshot, weightSnapshot, waterLevels])` throttled once at 100ms, with cached state fields and a single `setState` per tick.
- **Settings stream flashing** — `Rx.combineLatest3` created in `build()` caused StreamBuilder to disconnect/reconnect each tick, flashing "Waiting". Cached as `late final` in `initState()`.

## Task Commits

1. **Task 1: Reconnection event tracking** — `15ad6dd`
2. **Checkpoint fixes found during DevTools verification:**
   - `b981ff7` — fix(telemetry): add consent dialog and settings toggle
   - `e9e446d` — fix(telemetry): use new key for consent dialog so existing users see it
   - `e16952e` — fix(permissions): cache Future to prevent checkPermissions running 3x
   - `eb3b791` — perf(status-tile): throttle scale weight stream to 10fps
   - `4c6eac7` — perf(status-tile): throttle machine snapshot stream to 10fps
   - `0b8f39b` — perf(status-tile): synchronize machine + scale streams to single 10Hz tick
   - `152462a` — fix(status-tile): cache settings stream and add water levels to tick

## Files Modified

- `lib/src/controllers/device_controller.dart` — Disconnection timestamp tracking, reconnection duration logging, 24hr cleanup
- `lib/src/home_feature/tiles/status_tile.dart` — Merged stream subscription with synchronized 10Hz tick, cached settings stream, water levels moved to tick
- `lib/src/permissions_feature/permissions_view.dart` — Real consent dialog via addPostFrameCallback, cached FutureBuilder Future
- `lib/src/settings/settings_view.dart` — Anonymous crash reporting toggle in Advanced section
- `lib/src/settings/settings_controller.dart` — telemetryConsentDialogShown field, getter, loader, setter
- `lib/src/settings/settings_service.dart` — telemetryConsentDialogShown key, getter, setter

## Deviations from Plan

Task 2 (checkpoint) uncovered 5 additional issues beyond the planned "verify zero jank" scope. All were fixed during the checkpoint before approval:
- Phase 1 consent gaps (PRIV-03/PRIV-04 incomplete)
- FutureBuilder anti-pattern causing triple initialization
- StatusTile stream jank requiring full refactor to subscription-based state

## Issues Encountered

- `telemetryPromptShown` was already `true` for existing installs, requiring a new key (`telemetryConsentDialogShown`) to ensure the dialog appears
- `Rx.combineLatest3` in `build()` creates a new stream reference each call, causing StreamBuilder to flash — must be cached in `initState()`

## Self-Check

**Reconnection tracking:**
- `_disconnectedAt` map in device_controller.dart: PRESENT
- Reconnection duration logging: PRESENT
- 24hr cleanup: PRESENT

**UI performance:**
- Synchronized 10Hz tick via Rx.merge: PRESENT
- Cached settings stream: PRESENT
- Water levels in tick subscription: PRESENT
- User confirmed zero telemetry jank: VERIFIED

**Consent flow:**
- Dialog in permissions_view: PRESENT
- Toggle in settings_view: PRESENT
- telemetryConsentDialogShown key: PRESENT

## Self-Check: PASSED

---
*Phase: 03-performance-optimization*
*Completed: 2026-02-16*
