# Requirements: ReaPrime Field Telemetry

**Defined:** 2026-02-15
**Core Value:** Reliable, anonymized field telemetry from mission-critical device communication paths so we can diagnose connectivity and stability issues without user intervention.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Core Telemetry Service

- [ ] **TELE-01**: Abstract TelemetryService interface with recordError(), log(), setCustomKey(), setConsentEnabled()
- [ ] **TELE-02**: Firebase Crashlytics TelemetryService implementation
- [ ] **TELE-03**: No-op TelemetryService fallback for unsupported platforms (Linux)
- [ ] **TELE-04**: Automatic crash reporting via FlutterError.onError and PlatformDispatcher.onError
- [ ] **TELE-05**: Environment separation (disable telemetry in debug/simulate mode)

### Privacy & Consent

- [ ] **PRIV-01**: BLE MAC address anonymization via SHA-256 hashing before any report
- [ ] **PRIV-02**: IP address anonymization before any report
- [ ] **PRIV-03**: Telemetry consent prompt in permissions_view.dart alongside other permissions
- [ ] **PRIV-04**: Crashlytics collection disabled until user grants consent

### Log Context

- [ ] **LOGC-01**: 16kb rolling circular log buffer in memory
- [ ] **LOGC-02**: Attach log buffer contents to non-fatal error reports
- [ ] **LOGC-03**: System information snapshot attached to reports (device_info_plus)
- [ ] **LOGC-04**: Connected device snapshot attached to reports (device types, connection states)
- [ ] **LOGC-05**: BLE-specific custom keys on reports (deviceType, bleOperation, connectionState)

### Error Detection

- [ ] **ERRD-01**: Auto-report non-fatal errors on WARNING+ log levels via Logger.root listener
- [ ] **ERRD-02**: Auto-report caught exceptions from mission-critical components
- [ ] **ERRD-03**: Rate limiting — max 1 report per 60s per unique error message

### Integration

- [ ] **INTG-01**: Inject TelemetryService into device discovery services
- [ ] **INTG-02**: Inject TelemetryService into device transport implementations
- [ ] **INTG-03**: Inject TelemetryService into API server (webserver)
- [ ] **INTG-04**: Inject TelemetryService into plugin service
- [ ] **INTG-05**: Inject TelemetryService into WebUI storage

### WebView Logging

- [ ] **WLOG-01**: Capture SkinView webview console output (all levels) via setOnConsoleMessage
- [ ] **WLOG-02**: Write webview console logs to separate dedicated log file
- [ ] **WLOG-03**: Include webview log file in existing user feedback flow

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Enhanced Telemetry

- **ETEL-01**: Sentry TelemetryService implementation (alternative to Firebase)
- **ETEL-02**: Manual report submission with user feedback (shake-to-report or in-app form)
- **ETEL-03**: BLE-specific error categorization with filtering in dashboard
- **ETEL-04**: Crash trend analytics and spike alerting

## Out of Scope

| Feature | Reason |
|---------|--------|
| Sentry implementation | Firebase is the first and only backend for now |
| Real-time telemetry dashboard | Reports go to Firebase console |
| Full network request logging | Security risk — captures auth tokens and API keys |
| Telemetry always-on without consent | GDPR violation |
| Sending every log line to server | Privacy nightmare, massive data usage |
| WebView logs attached to telemetry reports | Only attached to user-sent feedback, not automatic reports |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| TELE-01 | — | Pending |
| TELE-02 | — | Pending |
| TELE-03 | — | Pending |
| TELE-04 | — | Pending |
| TELE-05 | — | Pending |
| PRIV-01 | — | Pending |
| PRIV-02 | — | Pending |
| PRIV-03 | — | Pending |
| PRIV-04 | — | Pending |
| LOGC-01 | — | Pending |
| LOGC-02 | — | Pending |
| LOGC-03 | — | Pending |
| LOGC-04 | — | Pending |
| LOGC-05 | — | Pending |
| ERRD-01 | — | Pending |
| ERRD-02 | — | Pending |
| ERRD-03 | — | Pending |
| INTG-01 | — | Pending |
| INTG-02 | — | Pending |
| INTG-03 | — | Pending |
| INTG-04 | — | Pending |
| INTG-05 | — | Pending |
| WLOG-01 | — | Pending |
| WLOG-02 | — | Pending |
| WLOG-03 | — | Pending |

**Coverage:**
- v1 requirements: 25 total
- Mapped to phases: 0
- Unmapped: 25

---
*Requirements defined: 2026-02-15*
*Last updated: 2026-02-15 after initial definition*
