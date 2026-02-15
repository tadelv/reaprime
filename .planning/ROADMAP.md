# Roadmap: ReaPrime Field Telemetry

## Overview

ReaPrime field telemetry adds production-grade error reporting to an existing Flutter BLE gateway. The journey starts with privacy-first telemetry infrastructure (Phase 1), validates the design through BLE integration where errors are most frequent (Phase 2), ensures production readiness through performance optimization (Phase 3), and optionally extends to WebView console capture (Phase 4). Each phase delivers observable capabilities that build toward reliable, anonymized field diagnostics without user intervention.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Core Telemetry Service & Privacy** - Abstract service with Firebase implementation and PII anonymization
- [ ] **Phase 2: Integration & Error Detection** - BLE transport integration with automatic error reporting
- [ ] **Phase 3: Performance Optimization** - Log throttling and production profiling under BLE load
- [ ] **Phase 4: WebView Integration** - Separate console log capture for WebUI skins

## Phase Details

### Phase 1: Core Telemetry Service & Privacy
**Goal**: Privacy-first telemetry infrastructure with anonymization built-in from day one
**Depends on**: Nothing (first phase)
**Requirements**: TELE-01, TELE-02, TELE-03, TELE-04, TELE-05, PRIV-01, PRIV-02, PRIV-03, PRIV-04, LOGC-01
**Success Criteria** (what must be TRUE):
  1. TelemetryService can be injected into any component via constructor
  2. Firebase Crashlytics records crashes and non-fatal errors without exposing PII
  3. User must explicitly grant consent before any telemetry is collected
  4. BLE MAC addresses and IP addresses are SHA-256 hashed in all reports
  5. Debug/simulate builds never send telemetry to Firebase
**Plans**: TBD

Plans:
- [ ] 01-01: TBD

### Phase 2: Integration & Error Detection
**Goal**: Validate telemetry usefulness through BLE integration and automatic error reporting
**Depends on**: Phase 1
**Requirements**: LOGC-02, LOGC-03, LOGC-04, LOGC-05, ERRD-01, ERRD-02, ERRD-03, INTG-01, INTG-02, INTG-03, INTG-04, INTG-05
**Success Criteria** (what must be TRUE):
  1. WARNING+ log levels automatically trigger non-fatal error reports with full context
  2. BLE disconnections include custom keys (deviceType, bleOperation, connectionState, RSSI)
  3. Each error report includes 16kb rolling log buffer for debugging
  4. Connected device snapshots appear in reports (device types, connection states)
  5. API endpoints can export logs on demand via REST without telemetry upload
**Plans**: TBD

Plans:
- [ ] 02-01: TBD

### Phase 3: Performance Optimization
**Goal**: Ensure telemetry adds zero UI jank under sustained BLE load
**Depends on**: Phase 2
**Requirements**: None (optimization phase)
**Success Criteria** (what must be TRUE):
  1. App maintains 60fps during high-frequency BLE streams (scale weight updates at 10-100/sec)
  2. Log buffer memory usage stays under 20kb even after 24-hour operation
  3. Logging overhead measures under 1ms per call in DevTools timeline
  4. Power-cycling devices mid-connection doesn't crash the app
  5. Rate limiting prevents duplicate errors from flooding Firebase (max 1 report per 60s per unique message)
**Plans**: TBD

Plans:
- [ ] 03-01: TBD

### Phase 4: WebView Integration
**Goal**: Capture JavaScript console output from WebUI skins in separate log stream
**Depends on**: Phase 2 (can run parallel with Phase 3)
**Requirements**: WLOG-01, WLOG-02, WLOG-03
**Success Criteria** (what must be TRUE):
  1. WebView console.log/warn/error output writes to dedicated webview_console.log file
  2. WebView logs are isolated from app logs (different file, different stream)
  3. User feedback flow includes webview logs when submitting reports
**Plans**: TBD

Plans:
- [ ] 04-01: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4

Note: Phase 4 can run parallel with Phase 3 (independent dependency chain).

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Core Telemetry Service & Privacy | 0/TBD | Not started | - |
| 2. Integration & Error Detection | 0/TBD | Not started | - |
| 3. Performance Optimization | 0/TBD | Not started | - |
| 4. WebView Integration | 0/TBD | Not started | - |

---
*Roadmap created: 2026-02-15*
*Last updated: 2026-02-15 after initial creation*
