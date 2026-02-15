# Project Research Summary

**Project:** Flutter BLE IoT Gateway Field Telemetry
**Domain:** Error reporting, crash analytics, and diagnostic logging for BLE gateway applications
**Researched:** 2026-02-15
**Confidence:** HIGH

## Executive Summary

ReaPrime is a mature Flutter BLE gateway with Firebase already integrated. This research examines how to add production-grade field telemetry without introducing new dependencies or architectural complexity. The recommended approach leverages existing Firebase Crashlytics 5.0.6 infrastructure, extending it with structured non-fatal error reporting, rolling log buffers for context enrichment, and PII anonymization for GDPR compliance.

The optimal implementation follows ReaPrime's established constructor dependency injection pattern with a new abstract TelemetryService interface. Firebase Crashlytics serves as the first concrete implementation, intercepting WARNING+ logs via Logger.root listeners (not custom appenders), sanitizing PII before buffering, and maintaining a 16KB circular buffer for crash context. No external telemetry uploads occur—logs stay local until exported via REST API or attached to Crashlytics reports on non-fatal errors.

**Critical risks identified:** Telemetry noise explosion from high-frequency BLE events, privacy violations through unsanitized MAC addresses, circular dependencies between TelemetryService and Logger, and performance degradation from logging BLE data streams (10-100 packets/sec). These risks are mitigated through smart filtering (allow-list pattern for non-fatals), immediate PII anonymization at capture time, explicit initialization ordering in main.dart, and log guards with throttling for high-frequency streams.

## Key Findings

### Recommended Stack

ReaPrime already has the necessary infrastructure—no major new dependencies required. The stack leverages existing Firebase integration with architectural improvements for telemetry-specific needs.

**Core technologies:**
- **firebase_crashlytics 5.0.7** (upgrade from 5.0.6): Non-fatal error reporting via recordError() — industry standard for Flutter apps, already configured, free tier sufficient
- **logging 1.3.0** (existing): Structured logging framework with hierarchical loggers — already integrated, forms the foundation for telemetry capture
- **logging_appenders 2.0.0** (existing): Rotating file appenders for local log persistence — already configured with file rotation

**New dependencies (minimal):**
- **crypto 3.0.7**: SHA-256 hashing for MAC address/IP anonymization — pure Dart, works on all platforms
- **flutter_secure_storage 10.0.0**: Secure pepper storage for PII hashing — uses Keychain (iOS) and Tink (Android)

**Custom implementations (no packages):**
- Circular log buffer (16KB FIFO) using Dart Queue — avoid unverified circular_buffer package
- TelemetryService abstract interface — follows existing controller DI pattern
- PII anonymization pipeline — chain of sanitizers (MAC, IP, file paths)

**Version notes:** firebase_crashlytics 5.0.7 requires iOS 13+, Android SDK 23+. flutter_secure_storage 10.x requires Android SDK 23+ (up from 19 in 9.x). All versions compatible with existing dependencies.

### Expected Features

**Must have (table stakes):**
- Automatic crash reporting — users expect crashes to be tracked; Firebase already does this
- Non-fatal error reporting — BLE failures often don't crash, they fail operations silently
- User anonymization — GDPR/privacy regulations require PII not be sent; legal requirement, not optional
- Opt-in consent for telemetry — GDPR requires explicit consent before data collection
- Stack traces with symbolication — unusable without readable stack traces
- Environment separation — prevent dev/staging crashes polluting production data

**Should have (competitive advantage):**
- 16KB rolling log buffer attached to reports — provides full log history context for debugging edge cases
- BLE-specific custom keys — deviceType, bleOperation, connectionState, RSSI for filtering by BLE layer
- Warning-level auto-reporting — catch problems before they become crashes (BLE disconnections, timeouts)
- Separate WebView console log file — WebView errors are different stream, isolate from app logs

**Defer (v2+):**
- Manual report submission with user feedback — requires UI work, defer until feedback requests increase
- WebView log sharing with telemetry — complex integration, only needed if WebUI errors become common
- BLE-specific error categorization — advanced filtering, defer until crash volume justifies it
- Crash trend analytics — dashboard customization, only valuable with historical data

**Anti-features (avoid):**
- Send every log line to server — massive data usage, privacy nightmare, GDPR violation
- Real-time crash alerting — creates alert fatigue, most crashes aren't emergencies
- Automatic PII collection — GDPR violation, creates liability
- Telemetry always-on (no opt-out) — illegal in EU, erodes user trust

### Architecture Approach

The architecture extends ReaPrime's existing service layer with a TelemetryService that follows established patterns. Services use constructor DI, controllers receive TelemetryService via injection, and lifecycle management mirrors existing services like WebserverService.

**Major components:**
1. **TelemetryService** — Central coordinator managing Logger.root listener, anonymization pipeline, buffer management; singleton created in main.dart and injected to consumers
2. **LoggingInterceptor** — Custom listener on Logger.root.onRecord filtering WARNING+ logs (not a custom Appender); receives logs before formatting for custom processing
3. **AnonymizationPipeline** — Chain of sanitizer functions (MAC, IP, file paths) applied immediately at capture time before buffering; prevents PII from existing in memory
4. **BufferManager** — Circular buffer with byte-bounded FIFO (16KB target, ~80-160 log messages); evicts oldest when full, O(1) append performance
5. **SystemInfoCollector** — Lazy-initialized device metadata snapshot using device_info_plus; cached and included in log exports
6. **DebugHandler** — REST endpoint (GET /api/v1/debug/logs) for on-demand log export following existing handler pattern (de1handler.dart, scale_handler.dart)

**Data flow:** Any component logs via Logger → Logger.root emits LogRecord → TelemetryService listener filters (WARNING+) → AnonymizationPipeline sanitizes → BufferManager adds to circular buffer → On export or non-fatal error, buffer contents attached.

**Key pattern:** Logger.root hook via direct listener (not custom Appender). Appenders are for output destinations; TelemetryService is a side-effect consumer. Direct listener provides same functionality with less abstraction and no disposal complexity.

### Critical Pitfalls

1. **Telemetry noise explosion** — Non-fatal reporting floods dashboard with duplicate BLE disconnections, obscuring real issues. Solution: Allow-list pattern for non-fatals (not all WARNING+), deduplicate BLE events (only report disconnects >30 seconds), rate limit to <10 non-fatals per session.

2. **Privacy violation through logs** — BLE MAC addresses, IP addresses leak into crash reports. Solution: Hash MAC addresses before logging (sha256 with hourly pepper, truncated to 24 bits), anonymize at capture time (not export time), never store raw MAC addresses in buffer.

3. **Circular dependency with logging** — TelemetryService depends on Logger, Logger depends on TelemetryService for auto-send. Solution: TelemetryService never depends on Logger (use debugPrint), Logger registers telemetry listener after TelemetryService initialization, document initialization order in main.dart.

4. **Performance degradation from excessive logging** — High-frequency BLE notifications (10-100/sec) trigger log statements causing UI jank. Solution: Guard high-frequency logs with logger.isLoggable(), throttle stream logs (1 log/sec or every 10th packet), use kDebugMode guards for verbose logging.

5. **BLE disconnection unhandled exceptions** — Device powered off during connection crashes app with unhandled PlatformException. Solution: Wrap all BLE subscriptions in onError handlers, gracefully degrade (save state before closing streams), test disconnect scenarios with mock transports.

## Implications for Roadmap

Based on research, suggested phase structure prioritizes privacy/legal compliance first, then integration, then optimization. Dependencies between anonymization, buffer management, and error handling dictate ordering.

### Phase 1: Core Telemetry Service & Privacy

**Rationale:** Privacy and legal compliance must be foundational—retrofitting anonymization after launch leaves historical data exposed. TelemetryService interface establishes abstraction allowing future Sentry integration for Linux (Firebase Crashlytics doesn't support Linux).

**Delivers:**
- Abstract TelemetryService interface (recordError, log, setCustomKey, initialize)
- Firebase Crashlytics implementation with opt-in consent flow
- PII anonymization pipeline (MAC, IP, file path sanitizers)
- Circular log buffer (16KB byte-bounded FIFO)
- Initialization contract preventing circular dependencies

**Addresses (from FEATURES.md):**
- Automatic crash reporting (table stakes)
- Non-fatal error reporting (table stakes)
- User anonymization (table stakes)
- Opt-in consent for telemetry (table stakes)
- Environment separation (table stakes)

**Avoids (from PITFALLS.md):**
- Privacy violation through logs (CRITICAL — anonymize at capture)
- Circular dependency with logging (CRITICAL — explicit init order)
- Telemetry noise explosion (CRITICAL — allow-list for non-fatals)

**Research flag:** Standard implementation—Firebase Crashlytics and anonymization patterns well-documented. Skip research-phase.

### Phase 2: Integration & BLE Error Handling

**Rationale:** BLE transport layer has highest error frequency (disconnections, timeouts, characteristic failures). Integrating telemetry here validates usefulness and identifies noise sources before production rollout.

**Delivers:**
- Logger.root listener installed with WARNING+ filtering
- BLE-specific custom keys (deviceType, bleOperation, connectionState, RSSI)
- Error handlers on BLE stream subscriptions (DataTransport, BleTransport implementations)
- Telemetry injection into De1Controller, ScaleController, SensorController
- DebugHandler with GET /api/v1/debug/logs endpoint for log export

**Uses (from STACK.md):**
- logging 1.3.0 (Logger.root.onRecord stream)
- firebase_crashlytics 5.0.7 (setCustomKey, recordError)
- logging_appenders 2.0.0 (file rotation config)

**Implements (from ARCHITECTURE.md):**
- LoggingInterceptor (direct listener pattern)
- DebugHandler (REST API for log export)
- Constructor DI pattern (inject TelemetryService to controllers)

**Avoids (from PITFALLS.md):**
- BLE disconnection unhandled exceptions (CRITICAL — onError wrappers)
- Log buffer memory leak (monitor buffer size, enforce 16KB limit)

**Research flag:** BLE error patterns may reveal platform-specific issues (Android vs iOS vs Linux BlueZ). Consider targeted research-phase if disconnection error codes vary significantly across platforms.

### Phase 3: Performance Optimization & Testing

**Rationale:** High-frequency BLE data streams (scale weight updates 10-100/sec) risk performance degradation. Profiling under load identifies logging overhead before production.

**Delivers:**
- Log guards (logger.isLoggable checks) for high-frequency streams
- Throttling for BLE characteristic notifications (1 log/sec or every 10th packet)
- 24-hour memory profiling (verify <5MB heap growth)
- Disconnect chaos testing (power off devices mid-connection)
- DevTools timeline verification (60fps under BLE load, <1ms per log call)

**Addresses:**
- Performance degradation from excessive logging (CRITICAL pitfall)
- Log buffer memory leak (verify fixed-size Queue enforcement)

**Research flag:** Standard Flutter performance profiling—DevTools documentation sufficient. Skip research-phase.

### Phase 4: WebView Integration (Optional)

**Rationale:** WebUI skins are secondary feature (not all users enable them). Defer until Phase 1-3 proven stable. WebView console capture is straightforward via setOnConsoleMessage callback.

**Delivers:**
- WebUIService modification: setOnConsoleMessage handler forwarding to TelemetryService
- Separate webview_console.log file (isolation from app logs)
- Optional attachment of WebView logs to crash reports on JS errors

**Addresses (from FEATURES.md):**
- Separate WebView console log file (differentiator)
- WebView log sharing with telemetry (v2+ feature, optional)

**Avoids:**
- Mixing WebView noise with app telemetry (separate file prevents pollution)

**Research flag:** webview_flutter API for console message capture is well-documented. Skip research-phase.

### Phase Ordering Rationale

- **Privacy first:** Anonymization built into Phase 1 prevents accidental PII exposure in all subsequent phases. Historical data cleanup is complex—get it right from start.
- **BLE integration validates design:** Phase 2 integration into high-error-rate component (BLE transport) proves telemetry usefulness and reveals noise sources before broader rollout.
- **Performance testing prevents production issues:** Phase 3 profiling under sustained BLE load catches logging overhead before users experience UI jank.
- **WebView deferred:** Phase 4 is independent (no dependencies on Phases 1-3) and optional (WebUI skins are secondary feature). Can be skipped if WebUI adoption is low.

**Dependency chain:**
- Phase 1 → Phase 2 (must have TelemetryService before integration)
- Phase 2 → Phase 3 (must integrate before performance testing meaningful)
- Phase 4 independent (can run parallel with Phase 3 or defer)

### Research Flags

**Needs research:**
- **Phase 2 (BLE integration):** Platform-specific BLE error codes may differ (Android GATT errors vs iOS CoreBluetooth vs Linux BlueZ). Consider targeted research-phase if error patterns are inconsistent across platforms. Confidence: MEDIUM (GitHub issues show Android-specific crashes, needs validation).

**Standard patterns (skip research):**
- **Phase 1 (Core Service):** Firebase Crashlytics integration, PII anonymization, circular buffers all have well-documented patterns. Confidence: HIGH (official Firebase docs, OWASP privacy guides, Dart collection patterns).
- **Phase 3 (Performance):** Flutter DevTools profiling, memory leak detection standard for all Flutter apps. Confidence: HIGH (official Flutter docs).
- **Phase 4 (WebView):** webview_flutter console capture API straightforward. Confidence: HIGH (official package docs).

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All technologies verified via pub.dev, official docs. firebase_crashlytics 5.0.7, crypto 3.0.7, flutter_secure_storage 10.0.0 versions confirmed. ReaPrime already has Firebase integrated—minimal new dependencies. |
| Features | HIGH | Feature landscape validated against Firebase Crashlytics docs, OpenTelemetry mobile telemetry guides, GDPR compliance resources. Table stakes (crash reporting, anonymization, consent) universally expected. Differentiators (16KB buffer, BLE custom keys) align with IoT gateway needs. |
| Architecture | HIGH | TelemetryService pattern matches ReaPrime's existing constructor DI architecture (DeviceController, De1Controller, etc.). Logger.root listener pattern verified in logging package docs. Circular buffer implementation standard Dart collection pattern. |
| Pitfalls | MEDIUM-HIGH | Critical pitfalls (noise explosion, privacy violations, circular deps, performance, BLE errors) verified via official docs, OWASP guides, and GitHub issues. Platform-specific BLE error handling has MEDIUM confidence (based on GitHub issues, not official docs). Recovery strategies inferred from general Flutter best practices. |

**Overall confidence:** HIGH

### Gaps to Address

**Platform-specific BLE errors:** Research identified Android GATT error code 133 (connection lost) as common crash source, but iOS CoreBluetooth and Linux BlueZ error mappings unclear. Validate during Phase 2 implementation by testing disconnect scenarios on all three platforms. If error codes/messages differ significantly, add platform-specific error handlers.

**WebView log capture lifecycle:** When WebView is backgrounded (app lifecycle change), does setOnConsoleMessage continue firing? Research didn't cover WebView lifecycle interaction with Flutter app lifecycle. Test during Phase 4 by backgrounding app during active WebUI session and verifying logs still captured.

**Circular buffer byte estimation accuracy:** BufferManager uses JSON-encoded length as proxy for byte size. Research didn't quantify estimation error margin. During Phase 3 profiling, measure actual buffer memory usage vs estimated bytes to validate 16KB target isn't significantly exceeded (acceptable margin: <20% overshoot = 19KB max).

**Firebase Crashlytics quota for non-fatals:** Documentation states "8 most recent non-fatal exceptions per session" but doesn't specify quota across all sessions/users. During Phase 2 integration, monitor Firebase console for quota warnings after 1 week in production. If quota issues arise, reduce auto-reporting threshold or implement sampling.

## Sources

### Primary (HIGH confidence)

**Stack Research:**
- firebase_crashlytics package (pub.dev) — Version 5.0.7, API reference
- Firebase Crashlytics Flutter Usage (firebase.flutter.dev) — recordError(), setCustomKey(), log() methods
- crypto package (pub.dev) — SHA-256 hashing API, version 3.0.7
- flutter_secure_storage package (pub.dev) — Secure storage API, version 10.0.0, Android Tink migration

**Feature Research:**
- Firebase Crashlytics Customize Reports (firebase.google.com) — Custom keys, breadcrumbs, symbolication
- Firebase Crashlytics Grouping Algorithm (firebase blog) — 2023 grouping improvements
- GDPR Consent Management (activemind.legal) — Lawful processing of telemetry data
- TelemetryDeck Anonymization (telemetrydeck.com) — Privacy-first anonymization patterns

**Architecture Research:**
- Flutter Architecture Guide (docs.flutter.dev) — Official DI patterns
- logging_appenders package (pub.dev) — Appender API, custom handler patterns
- circular_buffer package (pub.dev) — CircularBuffer FIFO semantics (not recommended, research reference only)
- device_info_plus package (pub.dev) — Device metadata collection

**Pitfalls Research:**
- Firebase Crashlytics Usage (firebase.flutter.dev) — Zone initialization, error handler setup
- Flutter Performance Best Practices (docs.flutter.dev) — Logging overhead, frame budget
- OWASP Top 10 Flutter Privacy Controls (docs.talsec.app) — PII handling, inadequate privacy controls
- Sentry Scrubbing Sensitive Data (docs.sentry.io) — beforeSend sanitization patterns

### Secondary (MEDIUM confidence)

- Flutter Logging Best Practices (LogRocket blog) — File rotation, disk space management
- Beyond print(): Levelling Up Your Flutter Logging (itnext.io) — Hierarchical logger configuration
- Clean Architecture DI in Flutter (Medium) — Singleton vs factory patterns
- Firebase Crashlytics Comprehensive Guide (Medium - Faik Irkham) — GDPR opt-in implementation
- Advanced BLE Development (Medium - sparkleo) — BLE error patterns
- Flutter Memory Leak Detection (Medium - sayed3li97) — Heap profiling, leak symptoms

### Tertiary (LOW confidence, needs validation)

- BLE Device Disconnect Crashes (GitHub issue flutter_reactive_ble #860) — Android-specific GATT errors
- Flutter BLE Error Handling (GitHub issue flutter_reactive_ble #97) — Platform differences
- Crashlytics Non-Fatal Discussion (Google Groups firebase-talk) — Rate limiting behavior
- Flutter WebView Console Logs Request (GitHub issue flutter #32908) — Community workarounds

---
*Research completed: 2026-02-15*
*Ready for roadmap: yes*
