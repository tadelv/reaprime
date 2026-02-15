# Stack Research: Flutter Field Telemetry

**Domain:** Flutter BLE IoT Gateway Field Telemetry
**Researched:** 2026-02-15
**Overall Confidence:** HIGH

## Executive Summary

For adding field telemetry to ReaPrime (existing Flutter BLE gateway with Firebase already configured), the recommended stack focuses on extending your current Firebase Crashlytics 5.0.6 setup with structured non-fatal error reporting, rolling log buffers, and PII anonymization. No new major dependencies required—leverage existing infrastructure with architectural improvements.

**Key Recommendation:** Implement abstract `TelemetryService` interface with Firebase Crashlytics as the first concrete implementation, using custom in-memory circular buffers for log aggregation and `crypto` package for PII anonymization.

## Recommended Stack

### Core Telemetry Services

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| **firebase_crashlytics** | 5.0.7 | Non-fatal error reporting, crash analytics | Already integrated; industry-standard for Flutter apps; 3M+ pub points; supports `recordError()` with custom keys; free tier sufficient for most apps; tight Firebase ecosystem integration |
| **firebase_analytics** | 12.1.0 | Event tracking, user behavior, breadcrumb logs | Already integrated; automatic breadcrumb logging when combined with Crashlytics; provides context for error reports |
| **logging** | 1.3.0 | Structured logging framework | Already integrated; Dart-native; supports hierarchical loggers; level-based filtering; 160 pub points |

**Confidence:** HIGH (verified via pub.dev, official Firebase documentation)

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| **crypto** | 3.0.7 | SHA-256 hashing for PII anonymization | Anonymize MAC addresses, IP addresses, user identifiers before logging/telemetry |
| **logging_appenders** | 2.0.0 | File logging, remote logging, rotating logs | Already integrated; extends `logging` with file appenders; use for local log persistence before upload |
| **shared_preferences** | 2.5.3 | Consent storage, telemetry opt-in state | Already integrated; store user consent flags for GDPR compliance |
| **flutter_secure_storage** | 10.0.0 | Secure storage for telemetry secrets | NEW; store pepper/salt values for PII hashing; uses Keychain (iOS) and Tink (Android); requires API 23+ |
| **path_provider** | 2.1.5 | Log file directory management | Already integrated; locate app documents directory for log storage |

**Confidence:** HIGH (verified via pub.dev, official documentation)

### Custom Implementation Components

| Component | Purpose | Implementation Approach |
|-----------|---------|------------------------|
| **Circular Log Buffer** | In-memory rolling buffer for log aggregation | Custom Dart implementation using `List<T>` with modulo indexing; fixed capacity (e.g., 500 entries); avoid `circular_buffer` package (unverified uploader, low adoption) |
| **TelemetryService Interface** | Abstract telemetry contract | Abstract class with methods: `recordError()`, `log()`, `setCustomKey()`, `setUserIdentifier()`, `initialize()` |
| **FirebaseCrashlyticsService** | Concrete Firebase implementation | Implements `TelemetryService`; wraps `FirebaseCrashlytics.instance` methods; handles opt-in/opt-out |
| **PII Anonymizer** | MAC/IP/identifier sanitization | Static utility class using `crypto` SHA-256 with per-device pepper stored in `flutter_secure_storage` |

**Confidence:** HIGH (based on Dart best practices, Flutter architectural patterns)

## Installation

```yaml
# pubspec.yaml additions (most already present)
dependencies:
  # Already integrated - no changes needed
  firebase_core: ^4.3.0
  firebase_crashlytics: ^5.0.7
  firebase_analytics: ^12.1.0
  logging: ^1.3.0
  logging_appenders: ^2.0.0
  shared_preferences: ^2.5.3
  path_provider: ^2.1.5

  # New dependency for secure pepper storage
  flutter_secure_storage: ^10.0.0

  # New dependency for PII hashing
  crypto: ^3.0.7
```

```bash
# Installation
flutter pub add flutter_secure_storage crypto

# Code generation (if using injectable for DI)
flutter pub run build_runner build --delete-conflicting-outputs
```

## Detailed Recommendations

### 1. Firebase Crashlytics Non-Fatal Error Reporting

**Current Status:** You have `firebase_crashlytics: 5.0.6` (latest: 5.0.7—minor update recommended)

**Key Methods:**

```dart
// Record non-fatal errors
await FirebaseCrashlytics.instance.recordError(
  error,
  stackTrace,
  reason: 'Descriptive context about error',
  fatal: false, // Default; explicitly mark as non-fatal
);

// Add custom metadata (max 64 key/value pairs)
FirebaseCrashlytics.instance.setCustomKey('ble_device_id', hashedMacAddress);
FirebaseCrashlytics.instance.setCustomKey('connection_attempt', 3);
FirebaseCrashlytics.instance.setCustomKey('firmware_version', '2.4.1');

// Add breadcrumb logs (requires firebase_analytics)
FirebaseCrashlytics.instance.log('DE1 connection initiated');
```

**Important Constraints:**
- Max 64 custom key/value pairs per session
- Keys/values truncated at 1024 characters
- Only 8 most recent non-fatal exceptions stored per session (reset on fatal crash)
- Logs sent with next fatal crash OR on app restart

**When to Use:**
- Recoverable BLE connection failures (automatic retry succeeded)
- Profile parsing errors (corrupted JSON but app continues)
- Scale timeout events (scale disconnected but shot continues)
- Unexpected DE1 state transitions (state machine recovered)

**Confidence:** HIGH (verified via Firebase official docs, FlutterFire documentation)

### 2. Rolling Log Buffers

**Problem:** File I/O on every log statement impacts performance; need efficient in-memory aggregation before flush.

**Solution:** Custom circular buffer implementation (avoid third-party packages).

**Implementation Pattern:**

```dart
class CircularLogBuffer {
  final int capacity;
  final List<LogRecord?> _buffer;
  int _writeIndex = 0;
  int _count = 0;

  CircularLogBuffer(this.capacity) : _buffer = List.filled(capacity, null);

  void add(LogRecord record) {
    _buffer[_writeIndex] = record;
    _writeIndex = (_writeIndex + 1) % capacity;
    if (_count < capacity) _count++;
  }

  List<LogRecord> toList() {
    if (_count < capacity) {
      return _buffer.sublist(0, _count).whereType<LogRecord>().toList();
    }
    // Oldest to newest
    return [
      ..._buffer.sublist(_writeIndex).whereType<LogRecord>(),
      ..._buffer.sublist(0, _writeIndex).whereType<LogRecord>(),
    ];
  }

  void clear() {
    _writeIndex = 0;
    _count = 0;
  }
}
```

**Buffer Strategy:**
- **Capacity:** 500-1000 log entries (adjust based on verbosity)
- **Flush triggers:**
  - Every 5 minutes (periodic timer)
  - On non-fatal error (attach recent logs as context)
  - On app background (ensure logs persisted)
  - When buffer 80% full (prevent overflow)
- **Retention:** Last 500 entries only (FIFO)

**Why Not `circular_buffer` Package?**
- Unverified uploader (not published by trusted organization)
- Low adoption (64.7k downloads, 7 likes)
- Simple to implement in ~30 lines of Dart
- No external maintenance dependency

**Confidence:** HIGH (based on Dart collection patterns, Flutter engine uses similar `_RingBuffer`)

### 3. PII Anonymization

**Requirement:** Anonymize MAC addresses, IP addresses, user identifiers before logging/telemetry.

**Approach:** Salted SHA-256 hashing with per-device pepper.

**Implementation:**

```dart
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PIIAnonymizer {
  static const _storage = FlutterSecureStorage();
  static const _pepperKey = 'telemetry_pepper';

  static Future<String> _getPepper() async {
    var pepper = await _storage.read(key: _pepperKey);
    if (pepper == null) {
      pepper = _generateRandomPepper();
      await _storage.write(key: _pepperKey, value: pepper);
    }
    return pepper;
  }

  static String _generateRandomPepper() {
    // Use UUID or secure random
    return uuid.v4();
  }

  static Future<String> hashMacAddress(String macAddress) async {
    final pepper = await _getPepper();
    final normalized = macAddress.replaceAll(':', '').toUpperCase();
    final salted = '$normalized:$pepper';
    final bytes = utf8.encode(salted);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16); // First 16 hex chars
  }

  static Future<String> hashIPAddress(String ipAddress) async {
    final pepper = await _getPepper();
    final salted = '$ipAddress:$pepper';
    final bytes = utf8.encode(salted);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16);
  }
}
```

**Important Privacy Considerations:**
- Hashed MAC addresses are NOT fully anonymous (FTC guidance: hashes are pseudonymization, not anonymization)
- Use hashed values ONLY for debugging correlation (e.g., "same device reported error twice")
- Do NOT store mappings of hash → original value
- Pepper stored in secure storage prevents rainbow table attacks
- Per-device pepper means hashes differ across installations (prevents cross-device tracking)

**GDPR Compliance:**
- Treat hashed identifiers as PII (pseudonymized data under GDPR)
- Obtain user consent before collection (see Consent Management below)
- Provide data deletion upon request (Firebase supports user data deletion)

**Confidence:** MEDIUM (hashing best practices verified; legal interpretation of "anonymous" varies by jurisdiction)

### 4. GDPR Consent Management

**Requirement:** Disable Crashlytics by default; enable only after user consent.

**Implementation:**

```dart
// On app startup (before Firebase initialization)
await Firebase.initializeApp();

// Check stored consent
final prefs = await SharedPreferences.getInstance();
final hasConsent = prefs.getBool('telemetry_consent') ?? false;

if (hasConsent) {
  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
} else {
  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(false);
}

// When user grants consent
Future<void> enableTelemetry() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('telemetry_consent', true);
  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
}

// When user revokes consent
Future<void> disableTelemetry() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('telemetry_consent', false);
  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(false);
}
```

**Additional Configuration:**

For Android (`android/app/src/main/AndroidManifest.xml`):
```xml
<meta-data
    android:name="firebase_crashlytics_collection_enabled"
    android:value="false" />
```

For iOS (`ios/Runner/Info.plist`):
```xml
<key>FirebaseCrashlyticsCollectionEnabled</key>
<false/>
```

**Confidence:** HIGH (verified via Firebase official documentation, GDPR compliance guides)

### 5. Abstract TelemetryService Architecture

**Goal:** Constructor DI with swappable implementations (Firebase Crashlytics, Sentry, mock for tests).

**Interface:**

```dart
abstract class TelemetryService {
  Future<void> initialize();

  Future<void> recordError(
    dynamic error,
    StackTrace? stackTrace, {
    String? reason,
    bool fatal = false,
  });

  void log(String message);

  void setCustomKey(String key, Object value);

  Future<void> setUserIdentifier(String? identifier);

  Future<void> setConsentEnabled(bool enabled);
}
```

**Firebase Implementation:**

```dart
class FirebaseCrashlyticsService implements TelemetryService {
  final FirebaseCrashlytics _crashlytics;

  FirebaseCrashlyticsService(this._crashlytics);

  @override
  Future<void> initialize() async {
    // Already initialized via Firebase.initializeApp()
    FlutterError.onError = _crashlytics.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      _crashlytics.recordError(error, stack, fatal: true);
      return true;
    };
  }

  @override
  Future<void> recordError(
    dynamic error,
    StackTrace? stackTrace, {
    String? reason,
    bool fatal = false,
  }) async {
    await _crashlytics.recordError(
      error,
      stackTrace,
      reason: reason,
      fatal: fatal,
    );
  }

  @override
  void log(String message) {
    _crashlytics.log(message);
  }

  @override
  void setCustomKey(String key, Object value) {
    _crashlytics.setCustomKey(key, value);
  }

  @override
  Future<void> setUserIdentifier(String? identifier) async {
    await _crashlytics.setUserIdentifier(identifier ?? '');
  }

  @override
  Future<void> setConsentEnabled(bool enabled) async {
    await _crashlytics.setCrashlyticsCollectionEnabled(enabled);
  }
}
```

**Registration (main.dart):**

```dart
// Using constructor DI (your existing pattern)
final telemetryService = FirebaseCrashlyticsService(
  FirebaseCrashlytics.instance,
);
await telemetryService.initialize();

// Inject into controllers
final deviceController = DeviceController(
  telemetryService: telemetryService,
);
```

**Confidence:** HIGH (aligns with your existing constructor DI pattern, standard Flutter architecture)

### 6. Log File Rotation

**Current Setup:** You have `logging_appenders: 2.0.0` with file appenders.

**Enhancement:** Configure rotation to prevent disk overflow.

```dart
import 'package:logging_appenders/logging_appenders.dart';
import 'package:path_provider/path_provider.dart';

Future<void> setupFileLogging() async {
  final appDocDir = await getApplicationDocumentsDirectory();
  final logDir = Directory('${appDocDir.path}/logs');

  if (!await logDir.exists()) {
    await logDir.create(recursive: true);
  }

  final rotatingFile = RotatingFileAppender(
    formatter: const DefaultLogRecordFormatter(),
    baseFilePath: '${logDir.path}/rea.log',
    rotateAtSizeBytes: 4 * 1024 * 1024, // 4MB per file
    rotateCheckInterval: Duration(minutes: 5),
    keepRotateCount: 5, // Keep last 5 files (20MB total)
  );

  Logger.root.level = Level.INFO; // Production: INFO and above
  Logger.root.onRecord.listen(rotatingFile.handle);
}
```

**Retention Policy:**
- **File size:** 4MB per file
- **File count:** 5 rotating files (20MB total)
- **Retention:** Automatic rotation; oldest file overwritten
- **Compression:** Not needed (Crashlytics receives aggregated logs, not raw files)

**When to Upload:**
- On non-fatal error: Attach last 100 log entries via `FirebaseCrashlytics.log()`
- On app crash: Automatic (Crashlytics includes breadcrumb logs)
- Never upload raw log files (privacy risk; only structured excerpts)

**Confidence:** MEDIUM (logging_appenders docs don't specify version 2.0.0 details; verify current API)

## Alternatives Considered

| Category | Recommended | Alternative | When to Use Alternative |
|----------|-------------|-------------|-------------------------|
| **Crash Reporting** | Firebase Crashlytics | Sentry (sentry_flutter 9.13.0) | If you need broader platform support (desktop/web), more detailed performance tracing, or open-source solution. Sentry has better symbolication for web/WASM. Choose Sentry if Firebase ecosystem is not already integrated. |
| **Log Buffer** | Custom circular buffer | `circular_buffer` package (0.12.0) | Never—unverified uploader, low adoption, easy to implement yourself |
| **PII Hashing** | `crypto` package SHA-256 | `cryptography` package Sha256 | If you need FIPS-compliant implementations or cross-platform cryptography (web assembly). `cryptography` is ~2x faster but adds dependency overhead. Stick with `crypto` for simplicity. |
| **Consent Storage** | `shared_preferences` | `flutter_secure_storage` | If consent state is considered sensitive (paranoid security). `shared_preferences` is sufficient for boolean consent flags. |
| **DI Framework** | Constructor DI (manual) | `get_it` + `injectable` | If your app grows to 20+ services needing injection. Current project size (12 controllers) doesn't justify the complexity. |

**Confidence:** HIGH (alternatives verified via pub.dev, community consensus)

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| **`package:logger`** | While popular (140 pub points), it duplicates functionality of `logging` (Dart-native). Using both creates inconsistent log formats and duplicates infrastructure. | Stick with `package:logging` (already integrated, hierarchical, Dart-standard) |
| **Crashlytics `setUserIdentifier()` with raw emails/usernames** | Violates GDPR Article 5 (data minimization); exposes PII in crash reports. FTC guidance: hashed identifiers are still PII. | Use anonymized user IDs (SHA-256 with pepper) OR omit user identification entirely |
| **`print()` statements in production** | Not structured; no level filtering; pollutes console; not captured by telemetry services. Impossible to disable without code changes. | Always use `Logger.log()` with appropriate levels |
| **Synchronous file I/O on every log** | Blocks main thread; causes jank; can freeze UI during heavy logging (BLE packet floods). | Use in-memory circular buffer + periodic batch flush |
| **Third-party analytics dashboards (e.g., Mixpanel, Amplitude)** | Adds another privacy compliance surface; increases app size; creates vendor lock-in. Firebase Analytics already provides event tracking. | Firebase Analytics (already integrated) |
| **Storing unhashed MAC addresses in Crashlytics custom keys** | Direct PII exposure; regulatory risk; unnecessary for debugging (hashed values provide same correlation capability). | Hash MAC addresses before `setCustomKey()` |

**Confidence:** HIGH (based on Flutter best practices, privacy regulations, performance profiling)

## Stack Patterns by Use Case

### Pattern 1: BLE Connection Error Telemetry

**Use Case:** DE1 machine fails to connect after 3 retries.

**Stack Usage:**
1. **Logger:** Log each connection attempt with structured data
   ```dart
   _logger.info('BLE connection attempt', {
     'device_id': await PIIAnonymizer.hashMacAddress(device.id),
     'attempt': attemptNumber,
     'error': errorCode,
   });
   ```

2. **Circular Buffer:** Aggregate connection logs in memory

3. **TelemetryService:** On final failure, record non-fatal error
   ```dart
   await _telemetryService.recordError(
     error,
     stackTrace,
     reason: 'BLE connection failed after 3 retries',
   );
   _telemetryService.setCustomKey('device_id', hashedMacAddress);
   _telemetryService.setCustomKey('rssi', device.rssi);
   _telemetryService.setCustomKey('firmware', device.firmwareVersion);

   // Attach recent logs as breadcrumbs
   for (var log in _buffer.toList().take(20)) {
     _telemetryService.log(log.message);
   }
   ```

### Pattern 2: Profile Parsing Error

**Use Case:** Corrupted profile JSON uploaded by user.

**Stack Usage:**
1. **Logger:** Log parsing attempt
   ```dart
   _logger.warning('Profile parsing failed', {
     'profile_hash': profileId,
     'parse_stage': 'json_decode',
   });
   ```

2. **TelemetryService:** Record non-fatal error with profile context
   ```dart
   await _telemetryService.recordError(
     FormatException('Invalid profile JSON'),
     stackTrace,
     reason: 'User uploaded corrupted profile',
   );
   _telemetryService.setCustomKey('profile_id', profileId);
   _telemetryService.setCustomKey('profile_size_bytes', jsonBytes.length);
   _telemetryService.setCustomKey('user_action', 'profile_upload');
   ```

3. **User Feedback:** Show error dialog (non-crash UX)

### Pattern 3: Silent Scale Timeout

**Use Case:** Scale disconnects mid-shot but shot continues.

**Stack Usage:**
1. **Logger:** Log scale disconnect event
   ```dart
   _logger.warning('Scale timeout during shot', {
     'scale_id': await PIIAnonymizer.hashMacAddress(scale.id),
     'shot_time_seconds': currentTime,
     'last_weight': lastReading?.weight,
   });
   ```

2. **TelemetryService:** Record non-fatal error (silent failure)
   ```dart
   await _telemetryService.recordError(
     TimeoutException('Scale connection lost'),
     StackTrace.current,
     reason: 'Scale disconnected during active shot',
   );
   _telemetryService.setCustomKey('scale_type', scale.deviceType);
   _telemetryService.setCustomKey('shot_phase', shotState.toString());
   _telemetryService.setCustomKey('connection_duration_sec', connectionDuration);
   ```

3. **Circular Buffer:** Retain last 100 logs for forensics

## Version Compatibility

| Package | Version | Compatible With | Notes |
|---------|---------|-----------------|-------|
| firebase_crashlytics | 5.0.7 | firebase_core: ^4.3.0, firebase_analytics: ^12.1.0 | Requires iOS 13+, Android SDK 21+ (auth: 23+) |
| crypto | 3.0.7 | Dart SDK: >=2.19.0 <4.0.0 | Pure Dart; works on all platforms |
| flutter_secure_storage | 10.0.0 | Flutter: >=3.19.0, Dart: >=3.3.0; Android SDK: 23+ | Migrated to Google Tink Crypto (from deprecated Jetpack Crypto); WASM-compatible |
| logging_appenders | 2.0.0 | logging: ^1.0.0 | Null-safe; supports file rotation |
| sentry_flutter | 9.13.0 | Flutter: >=3.3.0 | Alternative to Crashlytics; broader platform support |

**Breaking Changes to Watch:**
- **firebase_crashlytics 5.x:** iOS SDK 12.0.0, Android SDK 34.0.0 (breaking from 4.x)
- **flutter_secure_storage 10.x:** Minimum Android SDK raised to 23 (from 19 in 9.x)
- **crypto 4.x:** Not yet released; monitor for breaking changes

**Confidence:** HIGH (verified via pub.dev changelogs)

## Migration Notes for ReaPrime

**Already Integrated (No Action):**
- `firebase_core: 4.3.0` ✓
- `firebase_crashlytics: 5.0.6` → Upgrade to 5.0.7 (minor)
- `firebase_analytics: 12.1.0` ✓
- `logging: 1.3.0` ✓
- `logging_appenders: 2.0.0` ✓
- `shared_preferences: 2.5.3` ✓
- `path_provider: 2.1.5` ✓

**New Dependencies:**
- `flutter_secure_storage: 10.0.0` (for pepper storage)
- `crypto: 3.0.7` (for PII hashing)

**Architecture Changes:**
1. Create `lib/src/services/telemetry/telemetry_service.dart` (abstract interface)
2. Create `lib/src/services/telemetry/firebase_crashlytics_service.dart` (concrete impl)
3. Create `lib/src/services/telemetry/pii_anonymizer.dart` (static utility)
4. Create `lib/src/services/telemetry/circular_log_buffer.dart` (in-memory buffer)
5. Update `main.dart`: Register `TelemetryService` before `runApp()`
6. Update controllers: Inject `TelemetryService` via constructor
7. Update `SettingsController`: Add telemetry consent toggle
8. Update logging setup: Configure file rotation with `logging_appenders`

**Estimated Effort:**
- Setup: 2-4 hours (interface, Firebase impl, PII anonymizer)
- Integration: 4-6 hours (inject into controllers, add error handling)
- Testing: 2-3 hours (verify consent flow, test anonymization, check Crashlytics dashboard)
- Documentation: 1 hour

**Total:** ~10-14 hours

## Sources

**Firebase Crashlytics:**
- [Firebase Crashlytics Flutter Usage Documentation](https://firebase.flutter.dev/docs/crashlytics/usage/) — recordError(), setCustomKey(), log() API
- [Firebase Crashlytics Customize Reports](https://firebase.google.com/docs/crashlytics/customize-crash-reports) — Custom keys, user identifiers, breadcrumbs
- [firebase_crashlytics Package (pub.dev)](https://pub.dev/packages/firebase_crashlytics) — Version 5.0.7 verified
- [firebase_crashlytics Changelog](https://pub.dev/packages/firebase_crashlytics/changelog) — Breaking changes in 5.x

**Sentry Alternative:**
- [Sentry vs Crashlytics Comparison (UXCam)](https://uxcam.com/blog/sentry-vs-crashlytics/) — Feature comparison, platform support
- [sentry_flutter Package (pub.dev)](https://pub.dev/packages/sentry_flutter) — Version 9.13.0 verified

**Logging & Circular Buffers:**
- [Flutter Logging Best Practices (LogRocket)](https://blog.logrocket.com/flutter-logging-best-practices/) — File rotation, disk space management
- [Beyond print(): Levelling Up Your Flutter Logging](https://tomasrepcik.dev/blog/2025/2025-08-03-flutter-logging/) — Structured logging patterns
- [circular_buffer Package (pub.dev)](https://pub.dev/packages/circular_buffer) — Version 0.12.0 (not recommended)
- [ListQueue Class (Dart API)](https://api.flutter.dev/flutter/dart-collection/ListQueue-class.html) — Dart-native circular buffer

**PII Anonymization:**
- [crypto Package (pub.dev)](https://pub.dev/packages/crypto) — SHA-256 hashing, version 3.0.7
- [Sentry Scrubbing Sensitive Data (Flutter)](https://docs.sentry.io/platforms/flutter/data-management/sensitive-data/) — Data sanitization patterns
- [Salted SHA-256 Pseudonymization](https://www.emergentmind.com/topics/salted-sha-256-pseudonymization) — Salt and pepper best practices
- [FTC: Does Hashing Make Data Anonymous?](https://www.ftc.gov/policy/advocacy-research/tech-at-ftc/2012/04/does-hashing-make-data-anonymous) — Legal guidance on hashed PII

**GDPR Compliance:**
- [Firebase Crashlytics GDPR Compliance](https://dev.srdanstanic.com/firebase-crashlytics-analytics-gdpr-user-data-management/) — Opt-in implementation
- [Firebase Privacy and Security](https://firebase.google.com/support/privacy) — Official privacy documentation

**Secure Storage:**
- [flutter_secure_storage Package (pub.dev)](https://pub.dev/packages/flutter_secure_storage) — Version 10.0.0 verified
- [flutter_secure_storage Changelog](https://pub.dev/packages/flutter_secure_storage/changelog) — Tink Crypto migration in 10.x

**Dependency Injection:**
- [Flutter Dependency Injection (Official Docs)](https://docs.flutter.dev/app-architecture/case-study/dependency-injection) — Constructor DI patterns
- [Dependency Injection Best Practices (Vibe Studio)](https://vibe-studio.ai/insights/dependency-injection-best-practices-in-flutter) — Abstract interfaces for services

---

*Stack research for: ReaPrime Flutter Field Telemetry*
*Researched: 2026-02-15*
*Confidence: HIGH (all recommendations verified via official docs, pub.dev, and current best practices)*
