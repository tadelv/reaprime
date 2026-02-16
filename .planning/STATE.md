# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-15)

**Core value:** Reliable, anonymized field telemetry from mission-critical device communication paths so we can diagnose connectivity and stability issues without user intervention.
**Current focus:** Phase 3 - Performance Optimization

## Current Position

Phase: 3 of 4 — Performance Optimization
Plan: 1 of TBD in phase 3
Status: Executing Phase 3
Last activity: 2026-02-16 — Completed 03-01-PLAN.md (Telemetry Performance & Memory Fixes)

Progress: [███░░░░░░░] 30%

## Performance Metrics

**Velocity:**
- Total plans completed: 3
- Average duration: 2.6 min
- Total execution time: 0.13 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01 | 2 | 5.9min | 3.0min |
| 03 | 1 | 2.0min | 2.0min |

**Recent Trend:**
- Last plan: 03-01 (2.0min)
- Trend: Improving (3.4min → 2.0min)

*Updated after each plan completion*
| Phase 02 P02 | 3 | 2 tasks | 3 files |
| Phase 02 P01 | 185 | 2 tasks | 3 files |
| Phase 03-performance-optimization P01 | 2 | 2 tasks | 3 files |

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
- [Phase 03-01]: Queue capacity set to 10 reports with FIFO eviction - balances backpressure with context preservation
- [Phase 03-01]: Queue uses microtask scheduling instead of Isolates - simple async is sufficient for non-blocking behavior
- [Phase 03-01]: In-memory queue only - app restart loses pending reports, acceptable for non-critical telemetry
- [Phase 03-01]: LogBuffer rebuilds entire CircularBuffer for size enforcement - workaround for lack of removeFirst()

### Pending Todos

None yet.

### Blockers/Concerns

**Phase 2 readiness:**
- Platform-specific BLE error codes may differ (Android GATT vs iOS CoreBluetooth vs Linux BlueZ) — validate during integration testing
- Firebase Crashlytics quota for non-fatals unclear — monitor Firebase console after 1 week in production

## Session Continuity

Last session: 2026-02-16 (plan execution)
Stopped at: Completed 03-01-PLAN.md
Resume file: .planning/phases/03-performance-optimization/03-01-SUMMARY.md

---
*State initialized: 2026-02-15*
*Last updated: 2026-02-16T06:23:40Z*
