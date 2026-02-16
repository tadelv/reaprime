---
phase: 04-webview-integration
plan: 01
subsystem: webview-logging
tags: [webview, console_log, skin_view, log_service, file_io]

# Dependency graph
requires:
  - phase: 01-core-telemetry-service-privacy
    provides: Log file directory patterns, LogBuffer design reference
provides:
  - WebViewLogService with file-based logging, 1MB cap, broadcast stream
  - SkinView onConsoleMessage hook routing to WebViewLogService
  - WebViewLogService instantiation and DI through AppRoot -> MyApp -> SkinView
  - startWebServer accepts WebViewLogService parameter (ready for Plan 02)
affects: [webview-logging, skin-development, feedback]

# Tech tracking
tech-stack:
  added: []
  patterns: [dedicated log file per concern, IOSink for efficient appending, broadcast stream for WS consumers]

key-files:
  created:
    - lib/src/services/webview_log_service.dart
  modified:
    - lib/src/skin_feature/skin_view.dart
    - lib/main.dart
    - lib/src/app.dart
    - lib/src/services/webserver_service.dart

key-decisions:
  - "Standalone service class (not a part file) — separate concern from webserver handlers"
  - "IOSink opened once in initialize for efficient appending — avoids repeated file opens"
  - "Truncation keeps second half of file at clean newline boundary — preserves most recent entries"
  - "File size check after each write — acceptable overhead since 1MB truncation is infrequent"
  - "defaultSkinId is non-nullable String — no null fallback needed in console message handler"

patterns-established:
  - "WebViewLogService follows constructor DI pattern — logDirectoryPath resolved in main.dart"
  - "Console messages go to both WebViewLogService (file + stream) and _log.finest (app debug)"
  - "WebViewLogService injected through widget tree: AppRoot -> MyApp -> route builder -> SkinView"

# Metrics
duration: 3min
completed: 2026-02-16
---

# Phase 04 Plan 01: WebViewLogService + SkinView Console Capture Summary

**Dedicated WebView console log service capturing all skin JavaScript output to isolated file with broadcast stream for API consumers**

## Performance

- **Duration:** ~3 min
- **Started:** 2026-02-16
- **Completed:** 2026-02-16
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- WebViewLogService captures all WebView console levels (log, warn, error, debug, info) to dedicated webview_console.log
- Complete isolation from app logs — webview messages never enter package:logging WARNING+ pipeline or telemetry
- 1MB file size cap with oldest-half truncation preserving most recent entries
- Broadcast stream ready for WebSocket consumers (Plan 02)
- File cleared on every app restart per design decision
- Full DI wiring through widget tree for SkinView access

## Task Commits

1. **Task 1: Create WebViewLogService** - `0a8356d` (feat)
2. **Task 2: Hook SkinView and wire in main.dart** - `3922878` (feat)

## Files Created/Modified
- `lib/src/services/webview_log_service.dart` — New standalone service with file logging, 1MB cap, stream broadcasting
- `lib/src/skin_feature/skin_view.dart` — Added WebViewLogService parameter, updated onConsoleMessage callback
- `lib/main.dart` — WebViewLogService instantiation, initialization, injection into AppRoot and startWebServer
- `lib/src/app.dart` — Added WebViewLogService to MyApp constructor and SkinView route
- `lib/src/services/webserver_service.dart` — Added WebViewLogService import and startWebServer parameter

## Decisions Made

**Standalone service vs part file:** WebViewLogService is NOT a part file — it's a separate concern from webserver handlers and needs to be imported independently by both SkinView and the webserver.

**IOSink for appending:** Opened once during initialize() and reused for all writes. Only reopened after 1MB truncation event.

**Truncation at newline boundary:** When file exceeds 1MB, contents are split at the midpoint and the next newline is found for clean line-preserving truncation.

## Deviations from Plan

Minor: Plan suggested `defaultSkinId ?? 'unknown'` but `defaultSkinId` is a non-nullable `String` in SettingsController, so the null coalescing operator was removed to avoid a dead_null_aware_expression warning.

## Issues Encountered

None.

## User Setup Required

None.

## Self-Check: PASSED

**Created files:**
- lib/src/services/webview_log_service.dart exists

**Modified files:**
- lib/src/skin_feature/skin_view.dart exists
- lib/main.dart exists
- lib/src/app.dart exists
- lib/src/services/webserver_service.dart exists

**Commits:**
- 0a8356d (Task 1: Create WebViewLogService)
- 3922878 (Task 2: Hook SkinView and wire main.dart)

All claimed artifacts verified.

---
*Phase: 04-webview-integration*
*Completed: 2026-02-16*
