# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-15)

**Core value:** Reliable, anonymized field telemetry from mission-critical device communication paths so we can diagnose connectivity and stability issues without user intervention.
**Current focus:** Phase 2 - Integration & Error Detection

## Current Position

Phase: 2 of 4 — Integration & Error Detection
Plan: 2 of TBD in phase 2
Status: Executing Phase 2
Last activity: 2026-02-15 — Completed 02-02-PLAN.md (System Info & Log Export)

Progress: [██░░░░░░░░] 25%

## Performance Metrics

**Velocity:**
- Total plans completed: 2
- Average duration: 3.0 min
- Total execution time: 0.10 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01 | 2 | 5.9min | 3.0min |

**Recent Trend:**
- Last plan: 01-02 (3.4min)
- Trend: Stable (2.5min → 3.4min)

*Updated after each plan completion*
| Phase 02 P02 | 3 | 2 tasks | 3 files |
| Phase 02 P01 | 185 | 2 tasks | 3 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Abstract interface over direct Firebase calls — enables future backends
- 16kb log buffer — balances context depth with upload size
- Scrub MAC + IP addresses — only PII types in device logs
- Separate webview log file — isolates skin debug output
- Hook into package:logging for warning+ — leverages existing infrastructure
- TelemetryService.create() factory returns NoOp in debug/simulate mode or on Linux — platform-conditional implementation
- Firebase Crashlytics collection disabled by default until explicit consent (PRIV-04) — privacy-by-default
- LogBuffer uses 16kb byte-size enforcement with 500-entry capacity — balances context vs bandwidth
- Anonymization uses fixed app-specific salt 'reaprime-telemetry-v1' for SHA-256 hashing — enables correlation across reports
- MAC and IP addresses hashed to 16-character hex prefixes (64 bits) — sufficient for correlation without reversibility
- TelemetryService injection via setter instead of constructor parameter — avoids breaking existing SettingsController constructor signature
- Non-blocking consent prompt in permissions_view — marks telemetryPromptShown on first launch, consent defaults OFF, user enables in Settings
- Global error handlers in FirebaseCrashlyticsTelemetryService.initialize() — centralizes error handling configuration (TELE-04)
- Windows added to NoOp platforms alongside Linux — limited Crashlytics support
- [Phase 02-01]: 60-second rate limit window for error reports - balances noise reduction with issue freshness
- [Phase 02-01]: Throttle map cleanup at 100 entries - prevents unbounded memory growth
- [Phase 02-01]: Device counts use simple presence in _devices map - no complex connection state tracking needed
- [Phase 02-02]: System info collected via device_info_plus after telemetry initialization
- [Phase 02-02]: Platform-adaptive field names for device model/brand (handles Android/iOS/macOS/Windows differences)
- [Phase 02-02]: Log export returns raw buffer contents without triggering telemetry upload

### Pending Todos

None yet.

### Blockers/Concerns

**Phase 2 readiness:**
- Platform-specific BLE error codes may differ (Android GATT vs iOS CoreBluetooth vs Linux BlueZ) — validate during integration testing
- Firebase Crashlytics quota for non-fatals unclear — monitor Firebase console after 1 week in production

## Session Continuity

Last session: 2026-02-15 (plan execution)
Stopped at: Completed 02-02-PLAN.md (System Info & Log Export) — Phase 2 Plan 2 Complete
Resume file: None

---
*State initialized: 2026-02-15*
*Last updated: 2026-02-15T20:29:37Z*
