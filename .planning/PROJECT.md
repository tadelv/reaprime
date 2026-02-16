# ReaPrime Field Telemetry

## What This Is

ReaPrime (REA/R1) is a Flutter-based gateway for Decent Espresso machines, connecting to DE1 machines and scales via BLE/Serial and exposing REST/WebSocket APIs. Field telemetry provides privacy-first, anonymized error reporting from mission-critical device communication paths with automatic crash and non-fatal error capture, rolling log context, device state snapshots, and isolated WebView console logging.

## Core Value

Reliable, anonymized field telemetry from mission-critical device communication paths so we can diagnose connectivity and stability issues without user intervention.

## Requirements

### Validated

- ✓ Abstract TelemetryService interface with Firebase Crashlytics and NoOp implementations — v1.0
- ✓ Automatic crash and non-fatal error reporting via FlutterError.onError and Logger.root — v1.0
- ✓ BLE MAC and IP address anonymization via SHA-256 hashing — v1.0
- ✓ Consent-first privacy model with dialog, settings toggle, collection disabled by default — v1.0
- ✓ 16kb rolling log buffer attached to error reports — v1.0
- ✓ System info and connected device snapshots as custom keys — v1.0
- ✓ Error report rate limiting (1 per 60s per unique message) — v1.0
- ✓ TelemetryService injected into device controller and covered globally via Logger.root — v1.0
- ✓ Non-blocking async report queue with bounded capacity — v1.0
- ✓ Synchronized 10Hz UI stream throttling for zero jank under BLE load — v1.0
- ✓ Dedicated WebView console log capture to separate file — v1.0
- ✓ WebView logs exposed via REST/WS APIs and included in feedback submissions — v1.0
- ✓ Environment separation — debug/simulate modes never send telemetry — v1.0

### Active

(No active requirements — next milestone not yet planned)

### Out of Scope

- Sentry implementation — Firebase is the first and only backend for now
- Real-time telemetry dashboard — reports go to Firebase console
- Full network request logging — security risk with auth tokens
- Telemetry always-on without consent — GDPR violation
- WebView logs in automatic telemetry reports — only in user-sent feedback

## Context

Shipped v1.0 with +1,314 LOC Dart across 21 files.
Tech stack: Flutter, Firebase Crashlytics, RxDart, package:logging, device_info_plus, flutter_inappwebview.
Telemetry architecture: Abstract TelemetryService → Firebase/NoOp implementations, global Logger.root listener for auto-reporting.
INTG-03/04/05 use global listener instead of explicit injection — functionally complete but architecturally noted as tech debt.
Firebase Crashlytics quota for non-fatals should be monitored after 1 week in production.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Abstract interface over direct Firebase calls | Enables future Sentry/other backends without changing injection points | ✓ Good |
| 16kb log buffer with 500-entry capacity | Balances context depth with upload size | ✓ Good |
| SHA-256 hashing with app-specific salt for MAC/IP | Enables correlation across reports while preventing reversibility | ✓ Good |
| Separate webview log file (not app logging) | Keeps skin debug output isolated from app logs; different audiences | ✓ Good |
| Global Logger.root listener for warning+ | Leverages existing logging infrastructure; covers all components automatically | ✓ Good (but see INTG-03/04/05 tech debt) |
| TelemetryService injection via setter | Avoids breaking existing SettingsController constructor signature | ✓ Good |
| Non-blocking consent prompt at first launch | Consent defaults OFF; user explicitly enables in Settings | ✓ Good |
| TelemetryReportQueue with bounded capacity (10) | Non-blocking FIFO eviction prevents telemetry from blocking device communication | ✓ Good |
| Synchronized 10Hz stream throttling via Rx.merge | Single merged tick prevents independent throttle drift and reduces setState calls | ✓ Good |
| WebSocket raw log lines (not parsed JSON) | Simpler, consistent with file format; clients parse if needed | ✓ Good |
| WebView logs piggyback on includeLogs flag | No new flag needed; skin debug output has no PII concern | ✓ Good |

## Constraints

- **Privacy**: All telemetry anonymized — BLE MAC and IP addresses scrubbed before sending
- **Payload size**: Rolling log buffer capped at 16kb
- **Platform**: Firebase Crashlytics on Android, iOS, macOS — NoOp on Linux, Windows
- **Architecture**: Constructor DI pattern throughout (setter exception for TelemetryService)
- **Non-blocking**: Telemetry reporting never blocks device communication paths

---
*Last updated: 2026-02-16 after v1.0 milestone*
