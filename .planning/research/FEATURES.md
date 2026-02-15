# Feature Research

**Domain:** Field Telemetry for BLE IoT Gateway Apps
**Researched:** 2026-02-15
**Confidence:** HIGH

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist. Missing these = product feels incomplete.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Automatic crash reporting | Standard in all modern apps; users expect crashes to be tracked | LOW | Firebase Crashlytics auto-capture via FlutterError.onError override |
| Stack traces with symbolication | Developers need readable crash reports, not obfuscated garbage | MEDIUM | Flutter 3.12+ auto-uploads dSYM (iOS), manual upload via Firebase CLI (Android) |
| Non-fatal error reporting | Apps don't just crash—they have recoverable errors users experience | LOW | FirebaseCrashlytics.recordError() for caught exceptions |
| Custom logs/breadcrumbs | Without context, stack traces are guesswork | LOW | FirebaseCrashlytics.log() for breadcrumbs leading to crash |
| User anonymization | Privacy regulations (GDPR) require PII not be sent | MEDIUM | Strip BLE MAC addresses, IP addresses, device identifiers before reporting |
| Opt-in consent for telemetry | GDPR/privacy laws require explicit user consent before data collection | MEDIUM | Disable auto-collection, initialize only after user consent |
| Crash grouping/deduplication | Without intelligent grouping, dashboard becomes noise | LOW | Firebase's updated 2023 algorithm groups by failure point + stack trace |
| Environment separation | Production crashes mixed with dev testing = useless dashboard | LOW | Environment flags to prevent dev/staging crashes polluting production data |

### Differentiators (Competitive Advantage)

Features that set the product apart. Not required, but valuable.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| 16KB rolling log buffer attached to reports | Context beyond breadcrumbs—full log history for debugging edge cases | MEDIUM | Circular buffer of log entries, attached to crash/non-fatal reports |
| Separate WebView console log file | WebView errors are different beast—isolate from app logs | MEDIUM | Capture via setOnConsoleMessage callback, write to separate file |
| WebView log sharing with telemetry | Web skin errors visible in crash dashboard, not hidden in device files | HIGH | Attach WebView console log to Firebase reports when web errors occur |
| Manual report submission with user feedback | Users describe "what I was doing when it broke"—invaluable for reproduction | MEDIUM | Shake-to-report or in-app feedback form with screenshot + log attachment |
| Custom keys for BLE connection state | Gateway-specific context: which BLE device, connection state, signal strength | LOW | FirebaseCrashlytics.setCustomKey() for BLE MAC (anonymized), RSSI, connection state |
| Warning-level auto-reporting | Catch problems before they become crashes—report on WARNING+ log levels | MEDIUM | Logger listener triggers non-fatal report on warning/severe logs |
| Log file export for support | When telemetry fails or user has additional context, manual log sharing | LOW | Export ~/Download/REA1/log.txt or app documents directory logs |
| BLE-specific error categorization | Tag crashes by BLE layer (connection, characteristic read, device type) | MEDIUM | Custom keys: deviceType, bleOperation, connectionState for filtering |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem good but create problems.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Send every log line to server | "We need all data to debug" | Massive data usage, privacy nightmare, overwhelms backend, violates GDPR | Rolling 16KB buffer + breadcrumbs + warning-level auto-reports (targeted) |
| Real-time crash alerting | "We need to know immediately" | Creates alert fatigue, most crashes aren't emergencies, distracts from fixing root causes | Daily digest of new issues + spike alerts only when crash rate exceeds threshold |
| Automatic PII collection | "User emails help us contact them" | GDPR violation, privacy violation, creates liability | Opt-in user ID (hashed), manual feedback form if user wants to be contacted |
| Telemetry always-on (no opt-out) | "We need data from everyone" | Illegal in EU, bad privacy practice, erodes user trust | Opt-in consent with easy revocation, clear privacy policy |
| Full network request logs | "Debug API failures" | Captures auth tokens, API keys, user data—security disaster | Log request method/URL/status only, never bodies or headers |
| Unlimited log retention | "We might need old data" | Storage costs explode, GDPR requires deletion, old data rarely useful | 90-day retention for crashes, 30-day for logs, automated cleanup |

## Feature Dependencies

```
[Opt-in Consent]
    └──required before──> [Automatic Crash Reporting]
    └──required before──> [Non-Fatal Error Reporting]
    └──required before──> [Warning-Level Auto-Reporting]

[Custom Logs/Breadcrumbs]
    └──enhances──> [Crash Reports]
    └──enhances──> [Non-Fatal Reports]

[16KB Rolling Log Buffer]
    └──requires──> [Logger Infrastructure] (already exists in ReaPrime)
    └──attaches to──> [Crash Reports]
    └──attaches to──> [Non-Fatal Reports]
    └──attaches to──> [Manual Reports]

[User Anonymization]
    └──applied to──> [All Report Types]
    └──required for──> [GDPR Compliance]

[WebView Console Log File]
    └──requires──> [WebView setOnConsoleMessage Capture]
    └──feeds into──> [WebView Log Sharing with Telemetry]

[BLE-Specific Error Categorization]
    └──requires──> [Custom Keys for BLE Connection State]
    └──enhances──> [Crash Grouping]

[Manual Report Submission]
    └──optional add-on to──> [Automatic Crash Reporting]
    └──enhanced by──> [Screenshot Capture]
    └──enhanced by──> [16KB Rolling Log Buffer]
```

### Dependency Notes

- **Opt-in Consent required before telemetry:** GDPR compliance—cannot collect data without explicit consent. Must initialize Firebase Crashlytics with collection disabled, only enable after user accepts.
- **16KB Rolling Log Buffer enhances all reports:** Attaches full context to crashes, non-fatals, and manual reports. Requires existing Logger infrastructure (ReaPrime already logs to `~/Download/REA1/log.txt`).
- **User Anonymization applied universally:** BLE MAC addresses, IP addresses stripped before any data leaves device. Hash device identifiers. No exceptions.
- **WebView logs are separate stream:** WebView console output captured via `setOnConsoleMessage`, written to dedicated file, shared with telemetry only for web-related errors.
- **BLE-specific categorization builds on custom keys:** Tag each report with `deviceType` (DE1, scale, sensor), `bleOperation` (connect, read, write), `connectionState` to enable filtering by BLE layer.

## MVP Definition

### Launch With (v1)

Minimum viable product — what's needed to validate the concept.

- [x] **Automatic crash reporting** — Core functionality; without this, telemetry doesn't exist
- [x] **Stack traces with symbolication** — Unusable without readable stack traces
- [x] **Non-fatal error reporting** — BLE errors often don't crash, they fail operations
- [x] **Custom logs/breadcrumbs** — Minimal context for reproducing issues
- [x] **User anonymization** — Legal requirement, not optional
- [x] **Opt-in consent** — Legal requirement (GDPR), blocks all telemetry until granted
- [x] **Environment separation** — Prevent dev crashes polluting production data

### Add After Validation (v1.x)

Features to add once core is working.

- [ ] **16KB rolling log buffer** — Once basic telemetry proves useful, add deeper context
- [ ] **Warning-level auto-reporting** — After seeing crash patterns, expand to catch warnings
- [ ] **BLE-specific custom keys** — Add after confirming basic telemetry helps debug BLE issues
- [ ] **Separate WebView console log file** — Add when WebUI skins are actively used
- [ ] **Log file export** — Add when users request manual log sharing for support

### Future Consideration (v2+)

Features to defer until product-market fit is established.

- [ ] **Manual report submission with user feedback** — Requires UI work, defer until feedback requests increase
- [ ] **WebView log sharing with telemetry** — Complex integration, only needed if WebUI errors become common
- [ ] **BLE-specific error categorization** — Advanced filtering, defer until crash volume justifies it
- [ ] **Crash trend analytics** — Dashboard customization, only valuable with historical data

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Automatic crash reporting | HIGH | LOW | P1 |
| Stack traces with symbolication | HIGH | MEDIUM | P1 |
| Non-fatal error reporting | HIGH | LOW | P1 |
| User anonymization | HIGH | MEDIUM | P1 |
| Opt-in consent | HIGH | MEDIUM | P1 |
| Custom logs/breadcrumbs | MEDIUM | LOW | P1 |
| Environment separation | MEDIUM | LOW | P1 |
| 16KB rolling log buffer | HIGH | MEDIUM | P2 |
| Warning-level auto-reporting | MEDIUM | MEDIUM | P2 |
| BLE-specific custom keys | MEDIUM | LOW | P2 |
| Separate WebView console log file | MEDIUM | MEDIUM | P2 |
| Log file export | LOW | LOW | P2 |
| Manual report submission | MEDIUM | MEDIUM | P3 |
| WebView log sharing with telemetry | MEDIUM | HIGH | P3 |
| BLE-specific error categorization | LOW | MEDIUM | P3 |

**Priority key:**
- P1: Must have for launch (legal requirement or core functionality)
- P2: Should have, add when basic telemetry proves useful
- P3: Nice to have, defer until justified by usage patterns

## Competitor Feature Analysis

| Feature | Firebase Crashlytics (Industry Standard) | Sentry (Premium Alternative) | Our Approach (ReaPrime) |
|---------|------------------------------------------|------------------------------|-------------------------|
| Crash reporting | Auto-capture via FlutterError.onError, intelligent grouping | Similar auto-capture, more customizable grouping | Use Firebase (already configured), standard implementation |
| Non-fatal errors | recordError() API, logged on-device, sent with next crash | captureException() API, immediate send | Firebase recordError() + auto-report on WARNING+ log levels |
| Custom context | setCustomKey(), log() breadcrumbs, user IDs | setContext(), addBreadcrumb(), setUser() | Firebase APIs + BLE-specific keys (deviceType, bleOperation, RSSI) |
| Log attachment | Breadcrumbs only (Google Analytics powered) | Full attachments supported | 16KB rolling buffer as attachment (differentiator) |
| WebView logging | Not built-in | Not built-in | Separate WebView console log file + optional telemetry integration (differentiator) |
| Opt-in consent | Supported via setCrashlyticsCollectionEnabled() | Supported via beforeSend callback | Firebase opt-in + settings UI with GDPR-compliant consent flow |
| Anonymization | Manual (must implement yourself) | Manual (must implement yourself) | Automated PII stripping: BLE MAC, IP addresses, hashed device IDs |
| Sampling | Not built-in (send all crashes) | Configurable sampling rates | Start with 100% (low volume), add sampling if costs increase |

## Implementation Notes

### BLE-Specific Telemetry Needs

**Context Missing from Generic Crash Reports:**
- Which BLE device was involved? (DE1 vs. scale vs. sensor)
- What BLE operation failed? (connect, read characteristic, write, subscribe)
- Connection state when error occurred? (connected, disconnected, connecting)
- Signal strength (RSSI) at failure time?
- Device firmware version?

**Solution: Custom Keys**
```dart
FirebaseCrashlytics.instance.setCustomKey('deviceType', 'DE1');
FirebaseCrashlytics.instance.setCustomKey('bleOperation', 'readCharacteristic');
FirebaseCrashlytics.instance.setCustomKey('connectionState', 'connected');
FirebaseCrashlytics.instance.setCustomKey('rssi', -65);
FirebaseCrashlytics.instance.setCustomKey('firmwareVersion', 'v1.2.3');
```

**Anonymization Strategy:**
- BLE MAC addresses: Hash with salt, or truncate to manufacturer prefix (first 3 octets)
- IP addresses: Remove last octet (192.168.1.xxx → 192.168.1.0)
- Device identifiers: Double-hash (salt + hash on device, hash again on server)
- User IDs: Never send email/name, only hashed anonymous ID

### WebView Logging Strategy

**Problem:** WebUI skins (React/Next.js) run in WebView, their console.log/error go to separate stream, not visible in app logs or crash reports.

**Solution:**
1. Capture WebView console messages via `setOnConsoleMessage` callback
2. Write to dedicated file: `webview_console.log` (separate from app log)
3. For web-related errors, attach WebView log to Firebase report
4. Share WebView logs with user feedback (manual reports)

**When to Attach WebView Logs to Telemetry:**
- JavaScript exception in WebView
- WebUI skin fails to load
- User reports issue via manual feedback (if they were using WebUI)
- Do NOT attach for every crash (privacy + data size)

### Rolling Log Buffer Implementation

**Circular Buffer Strategy:**
- In-memory buffer: 16KB (approximately 200-300 log lines)
- When full, oldest entries dropped (FIFO)
- On crash/non-fatal/manual report: serialize buffer to string, attach as custom log
- Separate from persistent log file (`~/Download/REA1/log.txt`)

**What to Include:**
- Timestamp
- Log level
- Logger name
- Message
- Exception (if present)

**What to Exclude (Privacy):**
- BLE MAC addresses (anonymize first)
- IP addresses (strip last octet)
- User PII (emails, names)

**Performance Impact:**
- Memory: 16KB negligible on modern devices
- CPU: Minimal (append to circular buffer on each log)
- Network: Only sent with crash reports (not continuous)

### Warning-Level Auto-Reporting

**Trigger:** Logger emits WARNING or SEVERE level log

**Action:** Call `FirebaseCrashlytics.instance.recordError()` with non-fatal error

**Why Valuable for BLE Gateway:**
- BLE connection failures often don't crash, they log warnings
- "Failed to read characteristic" = warning, not crash
- "Device disconnected unexpectedly" = warning, not crash
- Auto-reporting catches these before they escalate

**Implementation:**
```dart
Logger.root.onRecord.listen((record) {
  if (record.level >= Level.WARNING) {
    FirebaseCrashlytics.instance.recordError(
      record.error ?? record.message,
      record.stackTrace,
      reason: record.loggerName,
      fatal: false,
    );
  }
});
```

**Rate Limiting:** Don't spam Firebase with warnings—limit to 1 report per 60 seconds per unique message to avoid overwhelming the backend.

## Sources

### Firebase Crashlytics Documentation
- [Get started with Crashlytics for Flutter](https://firebase.google.com/docs/crashlytics/flutter/get-started) — Official setup guide
- [Customize crash reports for Flutter](https://firebase.google.com/docs/crashlytics/flutter/customize-crash-reports) — Custom keys, logs, user IDs
- [Firebase Crashlytics Overview](https://firebase.flutter.dev/docs/crashlytics/overview/) — FlutterFire documentation
- [Firebase Crashlytics Usage](https://firebase.flutter.dev/docs/crashlytics/usage/) — FlutterFire API reference
- [Introducing a smarter algorithm in Crashlytics](https://firebase.blog/posts/2023/05/crashlytics-event-grouping-algorithm-update/) — 2023 grouping improvements

### Mobile Telemetry Best Practices
- [How TelemetryDeck anonymizes user data](https://telemetrydeck.com/docs/articles/anonymization-how-it-works/) — Privacy-first anonymization patterns
- [Handling sensitive data | OpenTelemetry](https://opentelemetry.io/docs/security/handling-sensitive-data/) — Data minimization principles
- [Security by Design: Building Privacy First Mobile Apps in 2026](https://booleaninc.com/blog/security-by-design-building-privacy-first-mobile-apps-in-2026/) — Privacy-preserving analytics
- [Lawful processing of telemetry data](https://www.activemind.legal/guides/telemetry-data/) — GDPR requirements for opt-in consent
- [Mobile App Consent Management SDK: What You Need to Know in 2025](https://secureprivacy.ai/blog/mobile-app-sdk-consent-management) — GDPR-compliant consent flows

### IoT Gateway Telemetry Patterns
- [Telemetry :: IoT Atlas](https://iotatlas.net/en/patterns/telemetry/) — IoT telemetry patterns
- [IoT Monitoring | Datadog](https://www.datadoghq.com/solutions/iot-monitoring/) — Gateway criticality in error monitoring
- [What Is IoT Monitoring: Definition, Architecture, Use Cases](https://www.velodb.io/glossary/iot-monitoring) — Telemetry data challenges

### BLE App Development & Debugging
- [BLE App Development in 2026: Trends, Opportunities & Best Practices](https://blogs.bleappdevelopers.com/ble-app-development-in-2026-trends-opportunities-best-practices/) — BLE 5.x trends
- [Debug A BLE Mobile App With LightBlue](https://punchthrough.com/debug-a-ble-mobile-app/) — BLE debugging tools
- [Android BLE: The Ultimate Guide To Bluetooth Low Energy](https://punchthrough.com/android-ble-guide/) — Common BLE errors ("App is scanning too frequently")

### WebView Logging & Debugging
- [Debugging WebViews | InAppWebView](https://inappwebview.dev/docs/debugging-webviews/) — WebView debugging on Android/iOS/macOS
- [inappwebview_inspector | Flutter package](https://pub.dev/packages/inappwebview_inspector) — Real-time console monitoring
- [Provide method to view webview console logs (Flutter Issue #32908)](https://github.com/flutter/flutter/issues/32908) — Community discussion on WebView logging

### User Feedback & Bug Reporting
- [Instabug Android SDK](https://github.com/Instabug/Instabug-Android) — Shake-to-report with screenshots
- [Top 10 In-App Feedback Tools in 2026](https://www.zonkafeedback.com/blog/in-app-feedback-tools) — Comparison of feedback tools
- [Bug and crash reporting for mobile apps | Shake](https://www.shakebugs.com/) — Manual submission with user feedback

### Performance & Sampling
- [Client-side Apps | OpenTelemetry](https://opentelemetry.io/docs/platforms/client-apps/) — Mobile-specific telemetry challenges
- [OpenTelemetry experts on tough telemetry challenges in mobile](https://embrace.io/blog/opentelemetry-experts-on-tough-telemetry-challenges-in-mobile/) — Sampling strategies
- [How to Configure Environment-Specific OpenTelemetry Settings](https://oneuptime.com/blog/post/2026-02-06-otel-env-files-variables/view) — Dev/staging/prod configuration

### Log Retention & Rotation
- [What Is Log Rotation? Setup, Benefits, and Pitfalls](https://edgedelta.com/company/knowledge-center/what-is-log-rotation) — Log rotation best practices
- [Log Retention: Policies, Best Practices & Tools](https://last9.io/blog/log-retention/) — Retention duration examples

---
*Feature research for: Field Telemetry in BLE IoT Gateway Apps*
*Researched: 2026-02-15*
*Confidence: HIGH (verified with official Firebase docs, OpenTelemetry standards, GDPR legal guidance, and IoT telemetry patterns)*
