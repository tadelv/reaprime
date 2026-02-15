# Pitfalls Research: Flutter BLE/IoT Gateway Telemetry

**Domain:** Flutter BLE/IoT Gateway with Telemetry & Error Reporting
**Researched:** 2026-02-15
**Confidence:** MEDIUM-HIGH

## Critical Pitfalls

### Pitfall 1: Telemetry Noise Explosion

**What goes wrong:**
Non-fatal error reporting floods Crashlytics/Sentry with thousands of duplicate errors, obscuring real issues. BLE disconnection events, transient connectivity failures, and expected warning-level logs create high cardinality issues that trigger rate limiting or quota exhaustion.

**Why it happens:**
Developers naively report every WARNING+ log event without filtering. BLE devices disconnect frequently (battery, range, user action), and each disconnect generates multiple log messages. Without deduplication or severity thresholds, telemetry becomes unusable noise.

**How to avoid:**
1. **Implement smart filtering**: Don't auto-report all WARNING+ logs. Use an allow-list pattern for exceptions that merit non-fatal reporting.
2. **Deduplicate BLE events**: Track device disconnect/reconnect cycles and report only if disconnect duration exceeds threshold (e.g., 30 seconds).
3. **Avoid high-cardinality metadata**: Never include unique values (user ID, device MAC, timestamps) in error domain/code fields. Use `userInfo`/custom attributes instead.
4. **Rate limit non-fatals**: Maximum 8 non-fatal errors per session (Firebase Crashlytics SDK limit). Implement app-level rate limiting below this threshold.
5. **Monitor telemetry quota**: Set up alerts for quota usage in Firebase console to detect noise spikes early.

**Warning signs:**
- Crashlytics dashboard shows hundreds of "unique" issues that are actually duplicates
- Non-fatal error count exceeds crash count by 100x+
- Rate limiting warnings in logs: "Crashlytics needing to limit the reporting of logged errors"
- Single BLE device generates 20+ error reports in one session

**Phase to address:**
Phase 1 (Core Telemetry Service) — implement filtering/deduplication from the start. Adding filters later requires historical data analysis and cleanup.

**Sources:**
- [Firebase Crashlytics Customize Reports](https://firebase.google.com/docs/crashlytics/customize-crash-reports) (HIGH confidence)
- [Crashlytics Non-Fatal Discussion](https://groups.google.com/g/firebase-talk/c/xQ-H-0YaXlM) (MEDIUM confidence)

---

### Pitfall 2: Privacy Violation Through Logs

**What goes wrong:**
BLE MAC addresses, IP addresses, user identifiable data leak into crash reports and logs. GDPR/CCPA violations, customer trust breach, potential fines. Logs stored on device or shared contain PII without user consent.

**Why it happens:**
Default logging libraries include full exception messages (which contain URLs, device identifiers). Developers log `device.toString()` for debugging, forgetting it contains MAC address. Crashlytics/Sentry breadcrumbs capture network requests with full query parameters.

**How to avoid:**
1. **Anonymize at capture**: Hash MAC addresses before logging: `sha256(mac).substring(0, 8)` or use placeholder `device-<index>`.
2. **Scrub exceptions**: Use `beforeSend` (Sentry) or custom error handler to remove MAC/IP from exception messages.
3. **Sanitize breadcrumbs**: Configure `beforeBreadcrumb` to strip query parameters from URLs.
4. **Never log passwords/tokens**: Even in debug mode. Use placeholders: `password: ******`.
5. **Release mode guardrails**: Use `dart:developer log()` which doesn't print in release builds, preventing accidental console leakage.
6. **Document anonymization rules**: Create `lib/src/utils/telemetry_sanitizer.dart` with reusable sanitization functions.

**Warning signs:**
- Crash reports contain strings like `"connecting to device AA:BB:CC:DD:EE:FF"`
- IP addresses visible in breadcrumbs: `"HTTP GET 192.168.1.5:8080/api?user=john@example.com"`
- Log sharing feature exports files containing full MAC addresses

**Phase to address:**
Phase 1 (Core Telemetry Service) — anonymization must be built into the TelemetryService abstraction from day one. Retrofitting is complex and leaves historical data exposed.

**Sources:**
- [OWASP Top 10 Flutter Privacy Controls](https://medium.com/@talsec/owasp-top-10-for-flutter-m6-inadequate-privacy-controls-in-flutter-dart-b11df113dcef) (HIGH confidence)
- [Sentry Scrubbing Sensitive Data](https://docs.sentry.io/platforms/flutter/data-management/sensitive-data/) (HIGH confidence)
- [Flutter Privacy Best Practices](https://www.oneclickitsolution.com/centerofexcellence/flutter/ethical-handling-of-large-data-sets) (MEDIUM confidence)

---

### Pitfall 3: Circular Dependency with Logging

**What goes wrong:**
TelemetryService depends on Logger to report its own initialization errors. Logger depends on TelemetryService to send critical logs. App crashes on startup with "Circular reference detected" or initialization deadlock.

**Why it happens:**
Constructor DI pattern makes this trap easy to fall into. TelemetryService constructor accepts `Logger logger`, and Logger is configured with `TelemetryService telemetryService` to auto-send ERROR+ logs. Both try to initialize each other.

**How to avoid:**
1. **TelemetryService never depends on Logger**: Use plain `print()` or `debugPrint()` for TelemetryService's own logging.
2. **Logger registers telemetry handler after init**:
   ```dart
   final telemetryService = TelemetryService();
   await telemetryService.initialize();
   Logger.root.onRecord.listen((record) {
     if (record.level >= Level.WARNING) {
       telemetryService.recordError(...);
     }
   });
   ```
3. **Lazy injection**: TelemetryService accepts `Logger? logger` (nullable), defaults to `debugPrint` internally.
4. **Document initialization order**: In `main.dart`, comment the required sequence: Firebase → Telemetry → Logger → App.

**Warning signs:**
- App crashes on startup in release mode but works in debug
- Error: "Circular reference detected for function/class X"
- Infinite loop during `main()` initialization
- TelemetryService constructor hangs indefinitely

**Phase to address:**
Phase 1 (Core Telemetry Service) — define initialization contract in service interfaces. Prevents cascading refactors.

**Sources:**
- [Flutter Circular Dependency Causes](https://www.omi.me/blogs/flutter-errors/circular-reference-detected-in-flutter-causes-and-how-to-fix) (MEDIUM confidence)
- [Flutter Crash Reporting](https://docs.flutter.dev/reference/crash-reporting) (HIGH confidence)

---

### Pitfall 4: Performance Degradation from Excessive Logging

**What goes wrong:**
High-frequency BLE characteristic notifications (10-100/sec) trigger log statements on every packet. App frame rate drops from 60fps to 15fps. UI freezes during shot pulls. Battery drains 30% faster.

**Why it happens:**
Developers use `logger.fine()` liberally for BLE data streams. Logger packages format messages, write to file buffers, and potentially send to telemetry on every call. Even "disabled" log levels incur formatting overhead if using string interpolation: `logger.fine("Weight: $weight")` — string is built before level check.

**How to avoid:**
1. **Guard high-frequency logs**:
   ```dart
   if (logger.isLoggable(Level.FINE)) {
     logger.fine("Weight: $weight");
   }
   ```
2. **Use lazy callbacks**: Some packages support `() => "Weight: $weight"` to avoid string construction.
3. **Throttle stream logs**: Only log every 10th BLE notification, or use time-based throttling (max 1 log/sec).
4. **Separate data logs**: Don't log raw BLE packets to main logger. Use dedicated trace buffer or disable in production.
5. **Profile logger overhead**: DevTools timeline recording to measure logging impact. Target <1ms per log call.
6. **Use kDebugMode**: Wrap verbose logging: `if (kDebugMode) { logger.fine(...); }`.

**Warning signs:**
- DevTools performance overlay shows dropped frames (red bars) during BLE activity
- Timeline shows `Logger.log()` calls consuming >10% of frame budget
- Battery usage in Android settings shows app consuming >5% per hour in background
- Users report "laggy" UI during espresso shots

**Phase to address:**
Phase 2 (Integration & Optimization) — add performance testing with BLE load. Identify hot paths before production.

**Sources:**
- [Flutter Logging Performance Best Practices](https://blog.logrocket.com/flutter-logging-best-practices/) (HIGH confidence)
- [Managing Flutter Logs](https://medium.com/@punithsuppar7795/managing-flutter-logs-reducing-noise-in-debug-console-0229ff7a9235) (MEDIUM confidence)
- [Advanced BLE Development](https://medium.com/@sparkleo/advanced-ble-development-with-flutter-blue-plus-ec6dd17bf275) (MEDIUM confidence)

---

### Pitfall 5: Zone Initialization Race Condition

**What goes wrong:**
Firebase Crashlytics misses early errors or crashes during app initialization. `runZonedGuarded` conflicts with `FlutterError.onError`, causing Zone mismatch errors. Non-fatal errors silently dropped.

**Why it happens:**
Outdated tutorials recommend wrapping `main()` in `runZonedGuarded` for Crashlytics. Modern Firebase SDK uses `PlatformDispatcher.instance.onError` instead. Mixing both creates competing error handlers in different Zones.

**How to avoid:**
1. **Don't use `runZonedGuarded`**: Modern pattern (2024+) doesn't need it.
2. **Sequential initialization**:
   ```dart
   void main() async {
     WidgetsFlutterBinding.ensureInitialized();
     await Firebase.initializeApp();
     FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterError;
     PlatformDispatcher.instance.onError = (error, stack) {
       FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
       return true;
     };
     runApp(MyApp());
   }
   ```
3. **Test initialization errors**: Throw exception in `initState()` of root widget to verify Crashlytics captures it.
4. **Check for Zone mismatch errors**: Search logs for "Zone Mismatch" warnings.

**Warning signs:**
- Crashlytics dashboard shows zero crashes despite known initialization failures
- Console error: "Zone Mismatch: FlutterError.onError called in different zone"
- Non-fatal errors reported in debug but not release
- Crashlytics shows crashes hours after they occurred (delayed upload)

**Phase to address:**
Phase 1 (Core Telemetry Service) — establish initialization pattern in service documentation. All integrations must follow it.

**Sources:**
- [Firebase Crashlytics Flutter Usage](https://firebase.flutter.dev/docs/crashlytics/usage/) (HIGH confidence)
- [Crashlytics Comprehensive Guide](https://medium.com/@faikirkham/firebase-crashlytics-in-flutter-a-comprehensive-guide-50d9702b7175) (MEDIUM confidence)
- [Zone Mismatch Error Resolution](https://developermemos.com/posts/zone-mismatch-error-flutter/) (MEDIUM confidence)

---

### Pitfall 6: Log Buffer Memory Leak

**What goes wrong:**
16KB rolling log buffer grows unbounded, consuming 50-100MB+ of RAM over 24 hours. App killed by OS due to memory pressure. Users report "app crashes after long sessions."

**Why it happens:**
Circular/ring buffer implementation forgets to overwrite old entries. String concatenation creates new objects without releasing old buffers. BLE stream logs accumulate faster than buffer rotation. Dart GC doesn't collect if buffer maintains references.

**How to avoid:**
1. **Use fixed-size collection**: `Queue<String>` with max capacity, remove first when adding to full queue:
   ```dart
   class RollingLogBuffer {
     final Queue<String> _entries = Queue();
     final int _maxEntries = 200; // ~16KB at ~80 bytes/entry

     void add(String entry) {
       if (_entries.length >= _maxEntries) {
         _entries.removeFirst(); // Release old reference
       }
       _entries.add(entry);
     }
   }
   ```
2. **Byte-based limit**: Track cumulative string length, remove entries until under 16KB.
3. **Periodic memory profiling**: DevTools memory view to detect leaks. Snapshot diff before/after buffer adds.
4. **Clear on dispose**: `_entries.clear()` when PersistenceController disposes.
5. **Monitor buffer size**: Log warning if buffer exceeds 20KB (indicates leak).

**Warning signs:**
- DevTools memory view shows sawtooth pattern (no GC collection)
- Heap snapshot reveals thousands of String objects in buffer
- App memory usage grows linearly with runtime (5MB/hour)
- Android logcat: "Growing heap size exceeded maximum" before crash

**Phase to address:**
Phase 2 (Integration & Optimization) — memory profiling under sustained load (24-hour BLE session).

**Sources:**
- [Flutter Memory Leak Detection](https://sayed3li97.medium.com/detecting-and-solving-memory-leaks-in-flutter-development-ea325812ef94) (HIGH confidence)
- [Preventing Memory Leaks in Flutter](https://medium.com/@siddharthmakadiya/preventing-memory-leaks-in-flutter-best-practices-and-tools-293ddca1556e) (HIGH confidence)

---

### Pitfall 7: BLE Disconnection Unhandled Exceptions

**What goes wrong:**
BLE device powered off during active connection crashes app with unhandled PlatformException. Crashlytics flooded with "GATT connection lost" errors. Users lose in-progress shot data.

**Why it happens:**
BLE libraries (`flutter_reactive_ble`, `flutter_blue_plus`) throw exceptions on unexpected disconnect. Exception bubbles up through stream subscriptions, bypassing error handlers. Android/iOS BLE stacks have different error codes, creating platform-specific crashes.

**How to avoid:**
1. **Wrap BLE subscriptions in error handlers**:
   ```dart
   _deviceConnection.listen(
     (state) => _handleState(state),
     onError: (error) {
       logger.warning("BLE connection error: $error");
       telemetryService.recordError(
         error,
         StackTrace.current,
         fatal: false,
         attributes: {"device": _anonymizedMac},
       );
       _handleDisconnection();
     },
   );
   ```
2. **Handle platform-specific errors**: Check error message for "GATT", "133", "connection lost" patterns.
3. **Graceful degradation**: On disconnect, save current state to persistence before closing streams.
4. **Test disconnect scenarios**: Unit tests with mock BLE transport that simulates power-off.
5. **Monitor disconnect crashes**: Crashlytics filter for "PlatformException" + "Bluetooth".

**Warning signs:**
- Crashlytics top crash: "Unhandled Exception: PlatformException(..."
- Users report: "App crashes when I walk away from machine"
- Crash rate spikes in morning (users power off devices overnight)
- Android-only crashes (iOS handles gracefully)

**Phase to address:**
Phase 1 (Core Telemetry Service) — error handling patterns must be part of transport abstraction. Phase 3 (Testing & Hardening) — add disconnect chaos testing.

**Sources:**
- [BLE Device Disconnect Crashes](https://github.com/PhilipsHue/flutter_reactive_ble/issues/860) (MEDIUM confidence - GitHub issue)
- [Flutter BLE Error Handling](https://github.com/PhilipsHue/flutter_reactive_ble/issues/97) (MEDIUM confidence - GitHub issue)

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Skip anonymization in development | Faster debugging with real MAC addresses | Accidentally ship non-anonymized logs to production, GDPR violation | Never — use build flavors with conditional anonymization |
| Use `print()` instead of Logger | No setup required | Can't filter by severity, no file output, hard to integrate telemetry | Only in TelemetryService's own error logging (avoid circular dep) |
| Report all exceptions as non-fatal | "Full visibility" into app behavior | Telemetry noise, quota exhaustion, obscures real issues | Never — use allow-list pattern |
| Store logs in SharedPreferences | Simple key-value API | 2MB limit, no rotation, serialization overhead | Never — use file-based rolling buffer |
| Single TelemetryService for all platforms | Code reuse across Android/iOS/Linux | Linux requires Sentry instead of Crashlytics, forced platform checks everywhere | Never — use factory pattern with platform-specific implementations |

---

## Integration Gotchas

Common mistakes when connecting to external services.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Firebase Crashlytics | Calling `recordError()` before `initialize()` completes | `await Firebase.initializeApp()` before any Crashlytics calls |
| Sentry Flutter | Not setting `environment` tag | Use `environment: kDebugMode ? 'debug' : 'production'` to separate dev noise |
| Linux fallback telemetry | Assuming Crashlytics works on Linux | Check platform: `if (Platform.isLinux) { useSentry(); } else { useCrashlytics(); }` |
| RxDart BehaviorSubject | Forgetting to call `.close()` on dispose | Always close in controller's `dispose()`, cancel subscriptions |
| Logger package | Using string interpolation in log calls | Guard with `logger.isLoggable(level)` or use lazy callbacks |
| WebView logs | Expecting Flutter logger to capture JS console.log | Use `InAppWebViewController.debugLoggingSettings` + separate file |

---

## Performance Traps

Patterns that work at small scale but fail as usage grows.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Logging every BLE packet | Dropped frames, UI jank, slow file writes | Throttle to 1 log/sec or log every 10th packet | >20 packets/sec (scale weight updates) |
| Synchronous file writes for logs | App freezes for 50-100ms when writing buffer | Use isolates or async file I/O with buffering | Log file >1MB, writes >10/min |
| Unbounded log history | OOM crash after days of uptime | Fixed-size Queue with FIFO eviction (16KB limit) | >1000 log entries (~50KB) |
| StreamBuilder rebuilds on every log | UI rebuilds 60x/sec during BLE activity | Use `distinctUntilChanged()` on log stream | >10 log events/sec |
| Sending breadcrumbs for every HTTP request | Crashlytics upload size limit, slow reports | Filter breadcrumbs: only track failures, not 200 OK | >100 requests/session |

---

## Security Mistakes

Domain-specific security issues beyond general web security.

| Mistake | Risk | Prevention |
|---------|------|------------|
| Logging WiFi SSIDs or IP addresses | User location tracking, privacy violation | Anonymize IPs: `192.168.x.x`, don't log SSIDs |
| Including device serial numbers in crash reports | Device fingerprinting, warranty tracking bypass | Use anonymized device ID: hash(serial).substring(0,8) |
| Storing unencrypted logs on shared storage | Log file readable by other apps (Android) | Use app-private directory: `getApplicationDocumentsDirectory()` |
| Sharing logs via HTTP endpoint | Logs exposed to network sniffing, MITM | Require HTTPS for log export API, or use local-only sharing |
| Hardcoded Firebase API keys in logs | API key visible in crash reports if logged | Never log config values, use environment variables |

---

## UX Pitfalls

Common user experience mistakes in this domain.

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Showing "non-fatal error reported" toasts | User panic: "Is my app broken?" | Silent reporting, only show actionable errors |
| Uploading 10MB crash reports on mobile data | Data overage charges, slow uploads | WiFi-only uploads for large reports, compress logs |
| Blocking UI while writing logs | Frozen "Share Logs" button for 2+ seconds | Async file I/O, show progress indicator |
| Log sharing exports 50MB unfiltered file | Email fails to send, overwhelming for support | Export last 16KB only, compress to ZIP |
| Generic error messages | User can't troubleshoot: "Telemetry error" | Specific: "Failed to upload crash report (offline)" |

---

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces.

- [ ] **Telemetry integration:** Often missing platform detection (Linux needs Sentry, not Crashlytics) — verify `if (Platform.isLinux)` branches exist
- [ ] **Log anonymization:** Often missing MAC address hashing — verify crash reports don't contain `AA:BB:CC:DD:EE:FF` patterns
- [ ] **Non-fatal filtering:** Often missing rate limiting — verify <10 non-fatals per session in Crashlytics dashboard
- [ ] **Rolling log buffer:** Often missing memory bounds — verify max 200 entries or 16KB limit enforced
- [ ] **BLE error handling:** Often missing `onError` in stream subscriptions — verify disconnect doesn't crash app
- [ ] **WebView log separation:** Often missing separate file output — verify JS errors don't pollute main log
- [ ] **Logger initialization order:** Often missing guards against circular deps — verify TelemetryService doesn't inject Logger
- [ ] **Performance profiling:** Often missing BLE load testing — verify 60fps maintained with 100 packets/sec
- [ ] **Crashlytics symbolication:** Often missing Flutter symbol upload — verify crash stacks show line numbers, not hex addresses
- [ ] **Sentry environment tags:** Often missing debug/production separation — verify dev crashes don't pollute production metrics

---

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Telemetry noise explosion | MEDIUM | 1. Disable non-fatal reporting in emergency release. 2. Add allow-list filter. 3. Re-enable with monitoring. 4. Archive/delete noise issues in Crashlytics console. |
| Privacy violation (PII leaked) | HIGH | 1. Release hotfix with sanitization. 2. Request Firebase support to purge reports (may not be possible). 3. Document incident for compliance. 4. Notify affected users if required by GDPR. |
| Circular dependency crash | LOW | 1. Remove Logger injection from TelemetryService. 2. Use `debugPrint()` for telemetry's own errors. 3. Register Logger listener after init. |
| Performance degradation | MEDIUM | 1. Add `if (kDebugMode)` guards to hot paths. 2. Throttle BLE logs to 1/sec. 3. Profile with DevTools. 4. Release performance patch. |
| Zone initialization race | LOW | 1. Remove `runZonedGuarded` wrapper. 2. Use `PlatformDispatcher.instance.onError`. 3. Test initialization error capture. |
| Log buffer memory leak | MEDIUM | 1. Add explicit `clear()` on dispose. 2. Enforce max entries limit. 3. Ask users to restart app. 4. Release memory leak fix. |
| BLE disconnect crashes | HIGH | 1. Wrap all BLE subscriptions in `onError`. 2. Add disconnect retry logic. 3. Save state before closing streams. 4. Urgent release to prevent data loss. |

---

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Telemetry noise explosion | Phase 1: Core Service | Review Crashlytics dashboard after 1 week: <50 unique non-fatal issues |
| Privacy violation (PII) | Phase 1: Core Service | Grep crash reports for MAC patterns: `[0-9A-F]{2}:[0-9A-F]{2}:...` = zero matches |
| Circular dependency | Phase 1: Core Service | App starts successfully in release mode, no initialization errors |
| Performance degradation | Phase 2: Integration | DevTools timeline shows <1ms per log call, 60fps maintained under BLE load |
| Zone initialization race | Phase 1: Core Service | Throw exception in root widget init, verify Crashlytics captures it |
| Log buffer memory leak | Phase 2: Integration | 24-hour memory profiling: heap growth <5MB/hour |
| BLE disconnect crashes | Phase 3: Testing | Chaos testing: power off device during connection, app doesn't crash |
| WebView log separation | Phase 2: Integration | Verify separate `webview_console.log` file exists, contains JS errors |
| Linux Crashlytics failure | Phase 1: Core Service | Test on Linux: Sentry receives crash report, not Crashlytics |
| Crashlytics symbol upload | Phase 4: Deployment | Release build crash shows `de1.dart:123` not `<anonymous>:0x4f2a` |

---

## Sources

**HIGH Confidence (Official Docs / Context7):**
- [Using Firebase Crashlytics | FlutterFire](https://firebase.flutter.dev/docs/crashlytics/usage/)
- [Customize Crashlytics Reports](https://firebase.google.com/docs/crashlytics/customize-crash-reports)
- [Sentry Scrubbing Sensitive Data](https://docs.sentry.io/platforms/flutter/data-management/sensitive-data/)
- [Flutter Performance Best Practices](https://docs.flutter.dev/perf/best-practices)
- [Flutter Crash Reporting](https://docs.flutter.dev/reference/crash-reporting)
- [firebase_crashlytics package](https://pub.dev/packages/firebase_crashlytics)
- [sentry_flutter package](https://pub.dev/packages/sentry_flutter)

**MEDIUM Confidence (Verified Web Sources, Multiple Corroborations):**
- [Flutter Logging Best Practices - LogRocket](https://blog.logrocket.com/flutter-logging-best-practices/)
- [OWASP Top 10 Flutter Privacy Controls](https://medium.com/@talsec/owasp-top-10-for-flutter-m6-inadequate-privacy-controls-in-flutter-dart-b11df113dcef)
- [Firebase Crashlytics Comprehensive Guide](https://medium.com/@faikirkham/firebase-crashlytics-in-flutter-a-comprehensive-guide-50d9702b7175)
- [Advanced BLE Development](https://medium.com/@sparkleo/advanced-ble-development-with-flutter-blue-plus-ec6dd17bf275)
- [Flutter Memory Leak Detection](https://sayed3li97.medium.com/detecting-and-solving-memory-leaks-in-flutter-development-ea325812ef94)
- [Preventing Memory Leaks in Flutter](https://medium.com/@siddharthmakadiya/preventing-memory-leaks-in-flutter-best-practices-and-tools-293ddca1556e)
- [Zone Mismatch Error Resolution](https://developermemos.com/posts/zone-mismatch-error-flutter/)
- [Sentry vs Crashlytics Comparison](https://sentry.io/from/crashlytics/)
- [Flutter Circular Dependency Causes](https://www.omi.me/blogs/flutter-errors/circular-reference-detected-in-flutter-causes-and-how-to-fix)

**MEDIUM-LOW Confidence (GitHub Issues - Real-world evidence but specific to libraries):**
- [BLE Device Disconnect Crashes](https://github.com/PhilipsHue/flutter_reactive_ble/issues/860)
- [Flutter BLE Error Handling](https://github.com/PhilipsHue/flutter_reactive_ble/issues/97)
- [Crashlytics Non-Fatal Discussion](https://groups.google.com/g/firebase-talk/c/xQ-H-0YaXlM)
- [WebView Console Logs Request](https://github.com/flutter/flutter/issues/32908)

---

*Pitfalls research for: ReaPrime Flutter BLE/IoT Gateway Telemetry*
*Researched: 2026-02-15*
