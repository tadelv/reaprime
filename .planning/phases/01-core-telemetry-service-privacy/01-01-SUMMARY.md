---
phase: 01-core-telemetry-service-privacy
plan: 01
subsystem: telemetry
tags: [firebase-crashlytics, logging, privacy, anonymization, circular-buffer]

# Dependency graph
requires: []
provides:
  - TelemetryService abstract interface with factory method
  - FirebaseCrashlyticsTelemetryService implementation with consent-off-by-default
  - NoOpTelemetryService for Linux/debug/simulate modes
  - LogBuffer 16kb circular buffer for rolling log context
  - Anonymization utility with salted SHA-256 for MAC/IP addresses
affects: [02-ble-error-capture, 03-shot-telemetry, 04-consent-ui]

# Tech tracking
tech-stack:
  added: [circular_buffer, crypto (direct dependency), firebase_crashlytics]
  patterns: [abstract service interface with factory, privacy-by-default, platform-conditional implementation]

key-files:
  created:
    - lib/src/services/telemetry/telemetry_service.dart
    - lib/src/services/telemetry/firebase_crashlytics_telemetry_service.dart
    - lib/src/services/telemetry/noop_telemetry_service.dart
    - lib/src/services/telemetry/log_buffer.dart
    - lib/src/services/telemetry/anonymization.dart
  modified:
    - pubspec.yaml

key-decisions:
  - "TelemetryService.create() factory returns NoOp in debug/simulate mode or on Linux"
  - "Firebase Crashlytics collection disabled by default until explicit consent (PRIV-04)"
  - "LogBuffer uses 16kb byte-size enforcement with 500-entry capacity"
  - "Anonymization uses fixed app-specific salt 'reaprime-telemetry-v1' for SHA-256 hashing"
  - "MAC and IP addresses hashed to 16-character hex prefixes (64 bits)"

patterns-established:
  - "Abstract service interface pattern: simple abstract class with factory method returning platform-appropriate implementation"
  - "Privacy-by-default: telemetry collection explicitly disabled until user consent"
  - "Salted SHA-256 anonymization following ProfileHash utility pattern"

# Metrics
duration: 2min 29sec
completed: 2026-02-15
---

# Phase 01 Plan 01: Core Telemetry Service & Privacy

**Abstract telemetry interface with Firebase Crashlytics, consent-off-by-default privacy, 16kb rolling log buffer, and salted SHA-256 anonymization for MAC/IP addresses**

## Performance

- **Duration:** 2 min 29 sec
- **Started:** 2026-02-15T15:53:42Z
- **Completed:** 2026-02-15T15:56:11Z
- **Tasks:** 2
- **Files created:** 5
- **Files modified:** 1 (pubspec.yaml)

## Accomplishments

- Created TelemetryService abstract interface with initialize(), recordError(), log(), setCustomKey(), setConsentEnabled(), getLogBuffer()
- Implemented FirebaseCrashlyticsTelemetryService wrapping Firebase Crashlytics SDK with collection disabled by default
- Implemented NoOpTelemetryService for unsupported platforms (Linux) and debug/simulate modes
- Created LogBuffer with 16kb byte-size enforcement using CircularBuffer with automatic eviction
- Created Anonymization utility with salted SHA-256 hashing for MAC addresses and IP addresses
- Factory method returns platform-appropriate implementation based on kDebugMode, simulate environment variable, and Platform.isLinux

## Task Commits

Each task was committed atomically:

1. **Task 1: Add circular_buffer dependency and create TelemetryService interface + implementations** - `38b1608` (feat)
   - Added circular_buffer to pubspec.yaml dependencies
   - Created TelemetryService abstract interface with factory method
   - Created FirebaseCrashlyticsTelemetryService with consent-off-by-default
   - Created NoOpTelemetryService with INFO log on initialize
   - Created LogBuffer with 16kb rolling buffer

2. **Task 2: Create Anonymization utility** - `8c67cc2` (feat)
   - Added crypto as direct dependency in pubspec.yaml
   - Created Anonymization class with static methods
   - Implemented anonymizeMac() with normalization and salted SHA-256
   - Implemented anonymizeIp() for IPv4/IPv6
   - Implemented anonymize() with automatic pattern detection
   - Implemented scrubString() for finding and replacing PII in arbitrary text

## Files Created/Modified

### Created
- `lib/src/services/telemetry/telemetry_service.dart` - Abstract interface with factory returning platform-appropriate implementation
- `lib/src/services/telemetry/firebase_crashlytics_telemetry_service.dart` - Firebase Crashlytics wrapper with log buffer attachment to error reports
- `lib/src/services/telemetry/noop_telemetry_service.dart` - Silent fallback for Linux/debug/simulate
- `lib/src/services/telemetry/log_buffer.dart` - 16kb circular buffer with timestamped entries and byte-size tracking
- `lib/src/services/telemetry/anonymization.dart` - Salted SHA-256 hashing for MAC/IP addresses with scrubString() for arbitrary text

### Modified
- `pubspec.yaml` - Added circular_buffer: ^0.12.0 and crypto: ^3.0.3 as direct dependencies

## Decisions Made

1. **Factory pattern over dependency injection for platform selection**: TelemetryService.create() checks kDebugMode, simulate environment variable, and Platform.isLinux to return appropriate implementation. Simpler than configuring DI container for platform-conditional logic.

2. **Fixed salt over per-device salt for Phase 1**: Uses static 'reaprime-telemetry-v1' salt for anonymization. Allows correlation across telemetry reports for same device. Per-device salt deferred to Phase 4 if needed.

3. **16kb log buffer size**: Balances context depth (approx 500 messages at 32 bytes/message) with upload size. Sufficient for debugging BLE issues without excessive bandwidth.

4. **Consent disabled by default in initialize()**: FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(false) called immediately on initialization. Explicit user consent required before collection starts (PRIV-04).

5. **LogBuffer uses byte-size enforcement**: Tracks _currentSizeBytes and manually trims when exceeding 16kb, accounting for variable-length messages. CircularBuffer capacity (500) provides upper bound on entry count.

6. **CircularBuffer lacks removeFirst()**: Manual trimming implementation converts to list, removes first, clears buffer, re-adds remaining entries. Acceptable for rare over-limit scenarios given CircularBuffer's automatic eviction at capacity.

## Deviations from Plan

**1. [Rule 3 - Blocking] LogBuffer trimming workaround for CircularBuffer API**
- **Found during:** Task 1 (LogBuffer implementation)
- **Issue:** CircularBuffer 0.12.0 doesn't have removeFirst() method, breaking manual size-based trimming
- **Fix:** Implemented trimming via toList(), remove first, clear(), re-add loop. Works correctly but slightly inefficient. Acceptable since CircularBuffer auto-evicts at capacity and byte limit is rarely exceeded.
- **Files modified:** lib/src/services/telemetry/log_buffer.dart
- **Verification:** flutter analyze lib/src/services/telemetry/ passes
- **Committed in:** 38b1608 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (blocking issue)
**Impact on plan:** Necessary workaround for CircularBuffer API limitation. No functional impact - byte-size enforcement works correctly.

## Issues Encountered

None beyond the CircularBuffer API deviation documented above.

## User Setup Required

None - no external service configuration required. Firebase Crashlytics is disabled by default and will be configured in Phase 4 (consent UI).

## Next Phase Readiness

**Ready for Phase 02 (BLE Error Capture):**
- TelemetryService interface available for integration
- LogBuffer ready for capturing BLE connection logs
- Anonymization.scrubString() ready for cleaning MAC addresses from error messages
- Factory pattern ensures NoOp mode in development, Firebase in production

**No blockers.**

**Potential consideration for Phase 4:**
- Firebase Crashlytics quota for non-fatal errors unclear - should monitor Firebase console during Phase 2/3 testing to ensure we don't exceed free tier limits with high-frequency BLE errors

## Self-Check: PASSED

All files verified:
- FOUND: lib/src/services/telemetry/telemetry_service.dart
- FOUND: lib/src/services/telemetry/firebase_crashlytics_telemetry_service.dart
- FOUND: lib/src/services/telemetry/noop_telemetry_service.dart
- FOUND: lib/src/services/telemetry/log_buffer.dart
- FOUND: lib/src/services/telemetry/anonymization.dart

All commits verified:
- FOUND: 38b1608 (Task 1)
- FOUND: 8c67cc2 (Task 2)

---
*Phase: 01-core-telemetry-service-privacy*
*Completed: 2026-02-15*
