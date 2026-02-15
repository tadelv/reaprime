# ReaPrime Field Telemetry

## What This Is

ReaPrime (REA/R1) is a Flutter-based gateway for Decent Espresso machines, connecting to DE1 machines and scales via BLE/Serial and exposing REST/WebSocket APIs. This project adds field telemetry — an abstracted telemetry service that reports non-fatal errors from mission-critical components, captures rolling logs and device state, and manages webview console output as a separate log stream.

## Core Value

Reliable, anonymized field telemetry from mission-critical device communication paths so we can diagnose connectivity and stability issues without user intervention.

## Requirements

### Validated

- BLE and Serial device connectivity with transport abstraction — existing
- DE1 machine control (state, settings, profiles, shots) — existing
- Multi-brand scale integration (Acaia, Felicita, Decent, Bookoo, etc.) — existing
- REST/WebSocket API on port 8080 — existing
- Shot control with target weight stopping — existing
- Profile management with content-based hashing — existing
- JavaScript plugin system with sandboxed execution — existing
- WebUI skin support with GitHub release integration — existing
- Firebase SDK configured (Crashlytics, Analytics, Performance) — existing
- Structured logging via package:logging — existing
- User feedback mechanism — existing

### Active

- [ ] Abstract TelemetryService interface
- [ ] Firebase Crashlytics TelemetryService implementation
- [ ] Inject TelemetryService into device discovery services
- [ ] Inject TelemetryService into device transport implementations
- [ ] Inject TelemetryService into API server (webserver)
- [ ] Inject TelemetryService into plugin service
- [ ] Inject TelemetryService into WebUI storage
- [ ] Non-fatal error reporting on log level warning and above
- [ ] Non-fatal error reporting on caught exceptions
- [ ] 16kb rolling log buffer attached to error reports
- [ ] System information snapshot attached to error reports
- [ ] Connected device snapshot attached to error reports
- [ ] Anonymize BLE MAC addresses in reports
- [ ] Anonymize IP addresses in reports
- [ ] Separate log file for SkinView webview console output (all levels)
- [ ] Share webview log file with telemetry reports
- [ ] Include webview logs in existing user feedback flow
- [ ] Share API server logs with telemetry when webview not in use

### Out of Scope

- Sentry implementation — Firebase is the first and only implementation for now
- User-identifiable analytics — telemetry must be anonymized
- Real-time telemetry dashboard — reports go to Firebase console
- Changing existing logging framework — we hook into package:logging, not replace it

## Context

- Firebase is already configured and running (firebase_core, firebase_crashlytics, firebase_performance, firebase_analytics in pubspec)
- Existing logging uses `package:logging` with file appenders writing to `~/Download/REA1/log.txt` (Android) and app documents directory (other platforms)
- The app uses constructor dependency injection throughout — TelemetryService follows this pattern
- Device transport layer already has error handling with try-catch; these are the hook points
- WebUI skins run in flutter_inappwebview — console output from JS can be intercepted
- User feedback mechanism already exists and can be extended to attach log files

## Constraints

- **Privacy**: All telemetry must be anonymized — scrub BLE MAC addresses and IP addresses before sending
- **Payload size**: Rolling log buffer capped at 16kb to keep upload sizes manageable
- **Platform**: Firebase Crashlytics supports Android, iOS, macOS, Windows — Linux may need a no-op fallback
- **Architecture**: Must follow existing constructor DI pattern — no singletons or service locators
- **Non-blocking**: Telemetry reporting must not block device communication paths

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Abstract interface over direct Firebase calls | Enables future Sentry/other backends without changing injection points | — Pending |
| 16kb log buffer | Balances context depth with upload size | — Pending |
| Scrub MAC + IP addresses | Only PII types likely to appear in device communication logs | — Pending |
| Separate webview log file (not app logging) | Keeps skin debug output isolated from app logs; different audiences | — Pending |
| Hook into package:logging for warning+ | Leverages existing logging infrastructure rather than parallel system | — Pending |

---
*Last updated: 2026-02-15 after initialization*
