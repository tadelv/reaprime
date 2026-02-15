# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-15)

**Core value:** Reliable, anonymized field telemetry from mission-critical device communication paths so we can diagnose connectivity and stability issues without user intervention.
**Current focus:** Phase 1 - Core Telemetry Service & Privacy

## Current Position

Phase: 1 of 4 (Core Telemetry Service & Privacy)
Plan: 2 of 2 in current phase (Phase Complete)
Status: Ready for next phase
Last activity: 2026-02-15 — Completed 01-02-PLAN.md (TelemetryService Integration)

Progress: [████░░░░░░] 25%

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

### Pending Todos

None yet.

### Blockers/Concerns

**Phase 2 readiness:**
- Platform-specific BLE error codes may differ (Android GATT vs iOS CoreBluetooth vs Linux BlueZ) — validate during integration testing
- Firebase Crashlytics quota for non-fatals unclear — monitor Firebase console after 1 week in production

## Session Continuity

Last session: 2026-02-15 (plan execution)
Stopped at: Completed 01-02-PLAN.md (TelemetryService Integration) — Phase 1 Complete
Resume file: None

---
*State initialized: 2026-02-15*
*Last updated: 2026-02-15T16:02:30Z*
