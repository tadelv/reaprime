---
phase: 02-integration-error-detection
plan: 02
subsystem: telemetry
tags: [device_info_plus, system_info, log_export, rest_api, firebase_crashlytics]

# Dependency graph
requires:
  - phase: 01-core-telemetry-service-privacy
    provides: TelemetryService with custom keys support, LogBuffer implementation
provides:
  - System information custom keys (OS, device model, app version) set on startup
  - REST API endpoint GET /api/v1/logs for log buffer export
  - LogsHandler REST handler for log access
affects: [error-reporting, debugging, device-diagnostics]

# Tech tracking
tech-stack:
  added: [device_info_plus]
  patterns: [system info collection at startup, log export via REST endpoint]

key-files:
  created:
    - lib/src/services/webserver/logs_handler.dart
  modified:
    - lib/main.dart
    - lib/src/services/webserver_service.dart

key-decisions:
  - "System info collected via device_info_plus after telemetry initialization"
  - "Platform-adaptive field names for device model/brand (handles Android/iOS/macOS/Windows differences)"
  - "Log export returns raw buffer contents without triggering telemetry upload"
  - "Non-blocking system info collection with error handling to avoid blocking app startup"

patterns-established:
  - "_setSystemInfoKeys helper function pattern for telemetry custom key population"
  - "LogsHandler follows existing handler pattern (part file with addRoutes method)"
  - "LogBuffer passed as parameter to startWebServer for REST endpoint access"

# Metrics
duration: 3min
completed: 2026-02-15
---

# Phase 02 Plan 02: System Info & Log Export Summary

**System information snapshot on startup with platform-adaptive device details and REST log export endpoint for local debugging**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-15T17:59:57Z
- **Completed:** 2026-02-15T18:03:46Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- System information (OS, device, app version) automatically attached to all error reports as custom keys
- GET /api/v1/logs endpoint provides instant access to log buffer for debugging without requiring telemetry consent
- Platform-adaptive device info handling (Android brand/model, macOS computerName/hostName, etc.)
- Non-blocking startup with graceful error handling for device info collection

## Task Commits

Each task was committed atomically:

1. **Task 1: Set system info custom keys on startup** - `d818d49` (feat)
2. **Task 2: Create GET /api/v1/logs endpoint** - `c3da3ec` (feat)

## Files Created/Modified
- `lib/main.dart` - Added device_info_plus import, _setSystemInfoKeys helper function, call after telemetry initialization
- `lib/src/services/webserver/logs_handler.dart` - REST handler for log buffer export with GET /api/v1/logs endpoint
- `lib/src/services/webserver_service.dart` - Added LogBuffer import, part directive, LogsHandler creation and wiring

## Decisions Made

**System info collection timing:** Called after telemetryService.initialize() but before Logger.root hook - ensures custom keys are set before any errors can be reported.

**Platform-adaptive field names:** deviceInfo.data['model'] ?? deviceInfo.data['computerName'] ?? 'unknown' handles different platform field names without platform-specific conditionals.

**Non-blocking error handling:** System info collection wrapped in try-catch with warning log - device info failures never block app startup.

**Log export scope:** Returns raw LogBuffer.getContents() without filtering or scrubbing - buffer already contains scrubbed WARNING+ messages from Logger.root hook, and endpoint is for local debugging only (not telemetry upload).

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None - implementation was straightforward. device_info_plus was already in pubspec.yaml as expected, and LogBuffer was already being passed to startWebServer from a recent change (likely from 02-01 plan execution).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

System information context is now attached to all error reports automatically. Log export endpoint provides immediate debugging capability without requiring telemetry opt-in.

Ready for next integration tasks in phase 02:
- Error detection integration points (BLE, Serial, Scale, Machine state changes)
- Rate limiting and throttling for non-fatal error reports
- Error context enrichment with connection state

**Blockers/Concerns:** None

## Self-Check: PASSED

**Created files:**
- ✓ lib/src/services/webserver/logs_handler.dart exists

**Modified files:**
- ✓ lib/main.dart exists
- ✓ lib/src/services/webserver_service.dart exists

**Commits:**
- ✓ d818d49 (Task 1: Set system info custom keys)
- ✓ c3da3ec (Task 2: Add GET /api/v1/logs endpoint)

All claimed artifacts verified.

---
*Phase: 02-integration-error-detection*
*Completed: 2026-02-15*
