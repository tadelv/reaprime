---
phase: 01-core-telemetry-service-privacy
plan: 02
subsystem: telemetry
tags: [firebase-crashlytics, settings, consent, permissions, logging]

# Dependency graph
requires:
  - phase: 01-01
    provides: TelemetryService abstract interface, LogBuffer, Anonymization utility
provides:
  - Telemetry consent persistence in SharedPreferences with default OFF
  - TelemetryService wired into main.dart lifecycle
  - Logger.root.onRecord listener capturing WARNING+ with PII scrubbing
  - Global error handlers (FlutterError.onError, PlatformDispatcher.onError) routing through TelemetryService
  - Telemetry prompt check in permissions startup flow
affects: [02-ble-error-capture, 03-shot-telemetry, 04-consent-ui]

# Tech tracking
tech-stack:
  added: []
  patterns: [settings controller telemetry service injection, consent-off-by-default persistence]

key-files:
  created: []
  modified:
    - lib/src/settings/settings_service.dart
    - lib/src/settings/settings_controller.dart
    - lib/main.dart
    - lib/src/permissions_feature/permissions_view.dart
    - lib/src/services/telemetry/telemetry_service.dart
    - lib/src/services/telemetry/firebase_crashlytics_telemetry_service.dart

key-decisions:
  - "TelemetryService.create() factory now requires logBuffer parameter for explicit dependency"
  - "Windows added to NoOp platforms alongside Linux (limited Crashlytics support)"
  - "Firebase initialization moved before TelemetryService creation in main.dart"
  - "Error handlers set up in FirebaseCrashlyticsTelemetryService.initialize() instead of main.dart"
  - "Telemetry prompt marked as shown on first launch without blocking UI"

patterns-established:
  - "Settings controller service injection via setter to avoid constructor changes"
  - "Consent sync to TelemetryService on loadSettings() and setTelemetryConsent()"
  - "Non-blocking startup consent tracking (mark as shown, user enables in Settings)"

# Metrics
duration: 3min 24sec
completed: 2026-02-15
---

# Phase 01 Plan 02: TelemetryService Integration

**TelemetryService wired into app lifecycle with consent-off-by-default persistence, Logger.root WARNING+ capture with PII scrubbing, and global error handlers routing through TelemetryService**

## Performance

- **Duration:** 3 min 24 sec
- **Started:** 2026-02-15T15:59:06Z
- **Completed:** 2026-02-15T16:02:30Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments

- Added telemetryConsent and telemetryPromptShown to SettingsService and SettingsController with persistence
- Wired TelemetryService into main.dart: created LogBuffer, initialized service, set up error handlers
- Hooked Logger.root.onRecord to capture WARNING+ messages with PII scrubbing via Anonymization.scrubString()
- Moved global error handlers (FlutterError.onError, PlatformDispatcher.onError) into FirebaseCrashlyticsTelemetryService.initialize()
- Added telemetry prompt check in permissions_view.dart (marks as shown on first launch, consent defaults OFF)
- Updated TelemetryService.create() factory to accept logBuffer parameter for explicit dependency

## Task Commits

Each task was committed atomically:

1. **Task 1: Add telemetry consent to SettingsService and SettingsController** - `0c6bfd1` (feat)
   - Added telemetryConsent and telemetryPromptShown to SettingsKeys enum
   - Added getter/setter methods in SettingsService (default OFF for consent)
   - Added TelemetryService field and setter in SettingsController
   - SettingsController syncs consent to TelemetryService on load and change

2. **Task 2: Wire TelemetryService in main.dart and add consent toggle in permissions_view.dart** - `7672630` (feat)
   - Updated TelemetryService.create() factory to accept logBuffer parameter
   - Added Windows to NoOp platforms (alongside Linux, debug, simulate)
   - FirebaseCrashlyticsTelemetryService.initialize() now sets up global error handlers
   - Added Firebase initialization in main.dart (before TelemetryService creation)
   - Created LogBuffer and TelemetryService in main.dart
   - Hooked Logger.root.onRecord to capture WARNING+ with PII scrubbing
   - Wired settingsController.telemetryService before loadSettings()
   - Added telemetry prompt check in permissions_view.dart

## Files Created/Modified

### Modified
- `lib/src/settings/settings_service.dart` - Added telemetryConsent() and telemetryPromptShown() getters/setters, updated SettingsKeys enum
- `lib/src/settings/settings_controller.dart` - Added telemetryConsent/telemetryPromptShown fields and setters, added TelemetryService injection via setter, added consent sync to TelemetryService on load and change
- `lib/main.dart` - Removed old Firebase initialization block, added LogBuffer creation, TelemetryService creation and initialization, Logger.root.onRecord listener with PII scrubbing, wired settingsController.telemetryService
- `lib/src/permissions_feature/permissions_view.dart` - Added telemetry prompt check in checkPermissions() (marks as shown on first launch)
- `lib/src/services/telemetry/telemetry_service.dart` - Updated create() factory to accept logBuffer parameter, added Windows to NoOp platforms
- `lib/src/services/telemetry/firebase_crashlytics_telemetry_service.dart` - Updated initialize() to set up FlutterError.onError and PlatformDispatcher.onError handlers

## Decisions Made

1. **TelemetryService injection via setter instead of constructor parameter**: Avoids breaking existing SettingsController constructor signature used throughout the codebase. Allows main.dart to wire telemetryService after creation but before loadSettings().

2. **Non-blocking consent prompt in permissions_view**: Instead of showing a modal dialog that blocks startup, simply mark telemetryPromptShown as true on first launch. Consent defaults to OFF per PRIV-04. User can enable in Settings UI (deferred to Phase 4 or gap closure).

3. **Firebase initialization before TelemetryService creation**: Firebase.initializeApp must run before TelemetryService.create() on supported platforms. Moved to explicit block checking Platform.isLinux/isWindows and kDebugMode/simulate flags.

4. **Global error handlers in FirebaseCrashlyticsTelemetryService.initialize()**: Moved FlutterError.onError and PlatformDispatcher.onError setup from main.dart into TelemetryService implementation. Satisfies TELE-04 (error handlers route through TelemetryService) and centralizes error handling configuration.

5. **Windows added to NoOp platforms**: Firebase Crashlytics support on Windows is limited. Updated TelemetryService.create() factory to return NoOpTelemetryService for Linux OR Windows.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None - all tasks completed as specified in the plan.

## User Setup Required

None - no external service configuration required. Firebase Crashlytics is disabled by default and will be configured in Phase 4 (consent UI).

## Next Phase Readiness

**Ready for Phase 02 (BLE Error Capture):**
- TelemetryService is wired into app lifecycle and available globally
- Logger.root WARNING+ messages are captured in LogBuffer with PII scrubbed
- Anonymization.scrubString() ready for cleaning MAC addresses from BLE error messages
- Consent persistence works correctly (default OFF, syncs to TelemetryService)
- Global error handlers route through TelemetryService

**No blockers.**

## Self-Check: PASSED

All files verified:
- FOUND: lib/src/settings/settings_service.dart (modified)
- FOUND: lib/src/settings/settings_controller.dart (modified)
- FOUND: lib/main.dart (modified)
- FOUND: lib/src/permissions_feature/permissions_view.dart (modified)
- FOUND: lib/src/services/telemetry/telemetry_service.dart (modified)
- FOUND: lib/src/services/telemetry/firebase_crashlytics_telemetry_service.dart (modified)

All commits verified:
- FOUND: 0c6bfd1 (Task 1)
- FOUND: 7672630 (Task 2)

---
*Phase: 01-core-telemetry-service-privacy*
*Completed: 2026-02-15*
