# Phase 01: Core Telemetry Service & Privacy - Research

**Researched:** 2026-02-15
**Domain:** Flutter telemetry/crash reporting with Firebase Crashlytics, privacy-first architecture
**Confidence:** HIGH

## Summary

This phase implements a privacy-first telemetry infrastructure for ReaPrime using Firebase Crashlytics for crash reporting and custom log buffering. The architecture follows Flutter best practices: abstract interface over concrete implementations, constructor dependency injection, and platform-aware service selection. Firebase Crashlytics only supports mobile platforms (iOS/Android), requiring a no-op fallback for Linux. The codebase already has Firebase initialized but lacks consent management and privacy protections.

**Key findings:** Firebase Crashlytics does not support Linux. Consent must be disabled by default and only enabled after explicit user opt-in per GDPR requirements. MAC address and IP anonymization via SHA-256 requires salting to prevent rainbow table attacks. The crypto package is already available as a transitive dependency.

**Primary recommendation:** Create abstract TelemetryService interface with two implementations: FirebaseCrashlyticsTelemetryService for iOS/Android/macOS/Windows and NoOpTelemetryService for Linux. Hook into package:logging at WARNING+ levels to populate a 16kb circular buffer that gets uploaded with crash reports. Store consent in SharedPreferences via SettingsService.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| firebase_crashlytics | 5.0.6 | Crash reporting for mobile/desktop | Already integrated, industry standard for Flutter crash reporting |
| firebase_core | 4.3.0 | Firebase initialization | Required for all Firebase services, already present |
| crypto | 3.0.7 | SHA-256 hashing for anonymization | Available as transitive dependency, used in profile_hash.dart |
| package:logging | 1.3.0 | Structured logging | Already used throughout codebase (Logger.root) |
| shared_preferences | 2.5.3 | Consent storage | Already used by SettingsService for persistence |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| circular_buffer | 0.12.0 | Fixed-size rolling log buffer | For 16kb log buffer in memory |
| package:flutter/foundation | (built-in) | kDebugMode/kReleaseMode constants | Environment detection for disabling telemetry |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Firebase Crashlytics | Sentry | More platforms (Linux support), but requires new integration, privacy model differs |
| circular_buffer package | Hand-rolled List with modulo | Package is simple/lightweight, hand-rolling adds maintenance burden |
| SHA-256 for anonymization | Truncation only | SHA-256 with salt provides stronger privacy guarantees |

**Installation:**
```bash
flutter pub add circular_buffer
# firebase_crashlytics, crypto, logging, shared_preferences already present
```

## Architecture Patterns

### Recommended Project Structure
```
lib/src/services/telemetry/
├── telemetry_service.dart              # Abstract interface
├── firebase_crashlytics_telemetry_service.dart  # iOS/Android/macOS/Windows impl
├── noop_telemetry_service.dart         # Linux/unsupported platforms
├── log_buffer.dart                     # 16kb circular buffer
└── anonymization.dart                  # SHA-256 utilities for MAC/IP
```

### Pattern 1: Abstract Interface with Platform-Specific Implementations
**What:** Define abstract TelemetryService interface, use factory pattern to select implementation based on platform
**When to use:** When service availability differs by platform (Firebase Crashlytics not on Linux)
**Example:**
```dart
// Abstract interface - matches codebase pattern from kv_store_service.dart
abstract class TelemetryService {
  Future<void> initialize();
  Future<void> recordError(Object error, StackTrace? stackTrace, {bool fatal = false});
  Future<void> log(String message);
  Future<void> setCustomKey(String key, Object value);
  Future<void> setConsentEnabled(bool enabled);
}

// Factory pattern for platform selection
TelemetryService createTelemetryService() {
  if (Platform.isLinux) {
    return NoOpTelemetryService();
  }
  return FirebaseCrashlyticsTelemetryService();
}
```

### Pattern 2: Constructor Dependency Injection
**What:** Services receive dependencies through constructors, matching existing codebase patterns
**When to use:** All controllers and services in ReaPrime follow this pattern
**Example:**
```dart
// From codebase: SettingsController constructor injection pattern
class SettingsController with ChangeNotifier {
  SettingsController(this._settingsService);
  final SettingsService _settingsService;
  // ...
}

// Apply to telemetry:
class De1Controller {
  De1Controller({
    required DeviceController controller,
    required TelemetryService telemetryService,
  }) : _deviceController = controller,
       _telemetryService = telemetryService;

  final TelemetryService _telemetryService;
  // ...
}
```

### Pattern 3: Consent-First Initialization
**What:** Crashlytics collection disabled until user grants consent via settings
**When to use:** GDPR compliance - always for user-facing telemetry
**Example:**
```dart
// Source: Firebase documentation
// In main.dart initialization
await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

// CRITICAL: Disable collection by default
await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(false);

// Later, after user grants consent (in SettingsService):
await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);

// Hook global error handlers AFTER disabling collection
FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
PlatformDispatcher.instance.onError = (error, stack) {
  FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  return true;
};
```

### Pattern 4: Logging Integration with Circular Buffer
**What:** Listen to package:logging at WARNING+ levels, append to 16kb circular buffer
**When to use:** Provide crash context without exposing sensitive data in logs
**Example:**
```dart
// LogBuffer class using circular_buffer package
class LogBuffer {
  final CircularBuffer<String> _buffer;
  static const int _maxSizeBytes = 16 * 1024; // 16kb

  LogBuffer() : _buffer = CircularBuffer(1000); // Adjust capacity based on avg log size

  void append(String message) {
    final timestamped = "[${DateTime.now().toIso8601String()}] $message";
    _buffer.add(timestamped);
    _trimToSize();
  }

  void _trimToSize() {
    while (_buffer.isNotEmpty && _calculateSize() > _maxSizeBytes) {
      _buffer.removeAt(0); // Remove oldest
    }
  }

  int _calculateSize() {
    return _buffer.fold(0, (sum, msg) => sum + msg.length);
  }

  String getBuffer() => _buffer.join('\n');
}

// Hook into package:logging
Logger.root.onRecord.listen((record) {
  if (record.level >= Level.WARNING) {
    logBuffer.append('${record.level.name}: ${record.message}');
  }
});
```

### Pattern 5: Privacy Anonymization with Salting
**What:** SHA-256 hash MAC addresses and IP addresses with app-specific salt
**When to use:** Before ANY telemetry data leaves the device
**Example:**
```dart
// Source: Existing profile_hash.dart pattern + privacy research
import 'dart:convert';
import 'package:crypto/crypto.dart';

class Anonymization {
  // App-specific salt - store in constants, NOT in SharedPreferences
  static const String _salt = 'reaprime-telemetry-v1';

  static String anonymizeMacAddress(String macAddress) {
    final normalized = macAddress.toUpperCase().replaceAll(':', '');
    final salted = '$_salt:mac:$normalized';
    final bytes = utf8.encode(salted);
    final hash = sha256.convert(bytes);
    return 'mac_${hash.toString().substring(0, 16)}';
  }

  static String anonymizeIpAddress(String ipAddress) {
    final salted = '$_salt:ip:$ipAddress';
    final bytes = utf8.encode(salted);
    final hash = sha256.convert(bytes);
    return 'ip_${hash.toString().substring(0, 16)}';
  }
}
```

### Anti-Patterns to Avoid
- **Don't initialize Firebase without disabling collection first:** Always call `setCrashlyticsCollectionEnabled(false)` before hooking error handlers
- **Don't store raw MAC/IP addresses:** Even temporarily in memory - anonymize immediately upon receipt
- **Don't use hand-rolled circular buffer:** Use circular_buffer package - it's well-tested and handles edge cases
- **Don't skip platform checks:** Linux will throw when accessing Crashlytics - use factory pattern with NoOpTelemetryService
- **Don't assume consent persists:** Check SettingsService.telemetryConsent on every app launch

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Circular buffer with size limits | Custom List + modulo arithmetic | circular_buffer package (0.12.0) | Edge cases (capacity changes, concurrent access), already tested |
| SHA-256 hashing | Custom crypto implementation | crypto package (already available) | Security-critical, needs constant-time comparison, timing attack resistance |
| Platform detection for services | Manual if/else chains | Factory pattern + Platform.is* checks | Maintainable, testable, follows existing codebase patterns |
| Consent storage | Custom file-based persistence | SharedPreferences via SettingsService | Already integrated, type-safe, platform-aware |

**Key insight:** Firebase Crashlytics handles networking, retries, batching, offline storage automatically. Don't build custom upload logic - just call the API methods.

## Common Pitfalls

### Pitfall 1: Enabling Crashlytics Collection Before Consent
**What goes wrong:** User data sent to Firebase before they grant permission, GDPR violation
**Why it happens:** Firebase initializes with collection enabled by default
**How to avoid:** Immediately after `Firebase.initializeApp()`, call `setCrashlyticsCollectionEnabled(false)`
**Warning signs:** Crash reports appearing in Firebase console for users who haven't opted in

### Pitfall 2: SHA-256 Without Salting for MAC Addresses
**What goes wrong:** Rainbow table attacks can reverse hashes (only 2^48 possible MAC addresses)
**Why it happens:** Developers assume SHA-256 alone provides anonymity
**How to avoid:** Always concatenate app-specific salt before hashing: `sha256("$salt:mac:$address")`
**Warning signs:** Security audit findings, research showing MAC addresses are recoverable from hashes

### Pitfall 3: Forgetting Linux Platform Lacks Crashlytics
**What goes wrong:** Runtime crash when accessing FirebaseCrashlytics.instance on Linux
**Why it happens:** firebase_options.dart throws UnsupportedError for Linux
**How to avoid:** Use factory pattern: `Platform.isLinux ? NoOpTelemetryService() : FirebaseCrashlyticsTelemetryService()`
**Warning signs:** Linux builds crash on startup with "DefaultFirebaseOptions have not been configured for linux"

### Pitfall 4: Circular Buffer Memory Leaks in Long-Running Apps
**What goes wrong:** Buffer never cleared, grows unbounded, causes OOM
**Why it happens:** Circular buffer limits ENTRIES not SIZE - one huge log message can exceed 16kb
**How to avoid:** Calculate byte size after each append, trim oldest entries until under 16kb
**Warning signs:** Memory profiler shows LogBuffer consuming >16kb, app crashes on low-memory devices

### Pitfall 5: Hooking Logging Before Setting Consent
**What goes wrong:** Log records captured and uploaded before user consents
**Why it happens:** Logger.root.onRecord.listen() called in main.dart before permissions flow
**How to avoid:** Initialize LogBuffer early but only upload buffer contents when consent=true AND crash occurs
**Warning signs:** Logs appearing in Crashlytics for users who declined telemetry

### Pitfall 6: Not Disabling Telemetry in Debug/Simulate Builds
**What goes wrong:** Development crashes pollute production analytics
**Why it happens:** Developers assume Firebase automatically filters debug builds
**How to avoid:** Check `kDebugMode` and `String.fromEnvironment("simulate")` before enabling Crashlytics
**Warning signs:** Firebase console shows crashes from development devices, test data mixed with production

## Code Examples

Verified patterns from official sources:

### Setting Up Firebase Crashlytics with Consent Control
```dart
// Source: Firebase Crashlytics Flutter documentation
// https://firebase.google.com/docs/crashlytics/flutter/customize-crash-reports

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui';

Future<void> initializeTelemetry() async {
  if (Platform.isLinux) {
    // Skip Firebase on unsupported platforms
    return;
  }

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // CRITICAL: Disable collection until consent granted
  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(false);

  // Hook error handlers (they respect the enabled state)
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };
}

// When user grants consent (in SettingsController/PermissionsView)
Future<void> enableTelemetry() async {
  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
  await settingsService.setTelemetryConsent(true);
}
```

### Recording Non-Fatal Errors with Custom Keys
```dart
// Source: Firebase Crashlytics Flutter documentation
// https://firebase.flutter.dev/docs/crashlytics/usage/

Future<void> exampleErrorHandling() async {
  try {
    await riskyOperation();
  } catch (error, stackTrace) {
    // Set custom keys for context
    await telemetryService.setCustomKey('user_flow', 'shot_execution');
    await telemetryService.setCustomKey('device_type', 'de1_plus');

    // Record non-fatal error
    await telemetryService.recordError(error, stackTrace, fatal: false);
  }
}
```

### Environment-Aware Telemetry Initialization
```dart
// Source: Flutter foundation constants documentation
// https://api.flutter.dev/flutter/foundation/kDebugMode-constant.html

import 'package:flutter/foundation.dart';

bool shouldEnableTelemetry() {
  // Never send telemetry in debug mode
  if (kDebugMode) return false;

  // Never send telemetry in simulate mode
  if (const String.fromEnvironment("simulate") == "1") return false;

  // Check user consent in release builds
  return settingsController.telemetryConsent;
}
```

### Integrating with package:logging
```dart
// Source: Sentry Logging Integration pattern
// https://docs.sentry.io/platforms/dart/guides/flutter/integrations/logging/

import 'package:logging/logging.dart';

class TelemetryLoggingHandler {
  final LogBuffer _logBuffer;
  final TelemetryService _telemetryService;

  TelemetryLoggingHandler(this._logBuffer, this._telemetryService);

  void initialize() {
    Logger.root.onRecord.listen((record) {
      // Buffer WARNING+ for crash context
      if (record.level >= Level.WARNING) {
        final message = '${record.level.name}: ${record.loggerName}: ${record.message}';
        _logBuffer.append(message);

        // Also send SEVERE as non-fatal errors
        if (record.level >= Level.SEVERE) {
          _telemetryService.recordError(
            Exception(record.message),
            record.stackTrace,
            fatal: false,
          );
        }
      }
    });
  }
}
```

### Circular Buffer Implementation
```dart
// Source: circular_buffer package pub.dev
// https://pub.dev/packages/circular_buffer

import 'package:circular_buffer/circular_buffer.dart';

class LogBuffer {
  final CircularBuffer<String> _buffer;
  static const int maxSizeBytes = 16 * 1024; // 16kb
  int _currentSizeBytes = 0;

  LogBuffer() : _buffer = CircularBuffer<String>(500);

  void append(String message) {
    final timestamped = '[${DateTime.now().toIso8601String()}] $message';
    _buffer.add(timestamped);
    _currentSizeBytes += timestamped.length;

    // Trim oldest entries if over size limit
    while (_currentSizeBytes > maxSizeBytes && _buffer.isNotEmpty) {
      final removed = _buffer.removeAt(0);
      _currentSizeBytes -= removed.length;
    }
  }

  String getContents() => _buffer.join('\n');

  void clear() {
    _buffer.clear();
    _currentSizeBytes = 0;
  }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Always-on crash reporting | Opt-in with consent | GDPR (2018), emphasized 2020+ | Privacy compliance is now table stakes |
| PlatformDispatcher.onError optional | Required for async errors | Dart 2.17 (May 2022) | Must hook both FlutterError.onError AND PlatformDispatcher.onError |
| Manual platform checks | kDebugMode/kReleaseMode constants | Flutter 1.20 (2020) | Compile-time tree shaking removes debug code from release builds |
| Custom logging solutions | package:logging standard | Long-standing, emphasized in Flutter 3.0+ | Ecosystem convergence on logging package |

**Deprecated/outdated:**
- **Automatic crash reporting without consent:** Privacy regulations (GDPR, CCPA) require explicit opt-in
- **Assuming Firebase works on all platforms:** Linux never supported, Windows added later but Crashlytics still mobile-first
- **Storing consent in app state only:** Must persist to SharedPreferences to survive app restarts

## Open Questions

1. **Salt rotation strategy for anonymization**
   - What we know: SHA-256 with fixed salt prevents rainbow tables but doesn't protect against targeted attacks
   - What's unclear: Should salt rotate periodically? Trade-off: better privacy vs. inability to correlate events over time
   - Recommendation: Use fixed salt for Phase 1 (simpler, good enough for MAC/IP anonymization), document for future enhancement

2. **Log buffer persistence across app restarts**
   - What we know: 16kb in-memory buffer provides context for crashes during current session
   - What's unclear: Should buffer persist to disk and reload on next launch to capture pre-crash state?
   - Recommendation: In-memory only for Phase 1 (simpler, avoids disk I/O), revisit if crash reports lack sufficient context

3. **Telemetry consent UI placement**
   - What we know: Requirements say "permissions_view.dart alongside other permissions"
   - What's unclear: Should telemetry be a toggle or one-time prompt? Should it block app usage?
   - Recommendation: Add as optional toggle in permissions_view.dart checkPermissions() flow - don't block app usage, default OFF

4. **Custom keys for BLE devices**
   - What we know: Need to anonymize MAC addresses before setting as custom keys
   - What's unclear: Should we set separate keys for each connected device or aggregate count only?
   - Recommendation: Set device type + anonymized MAC as custom keys (e.g., "de1_mac: mac_abc123", "scale_mac: mac_def456") for debugging multi-device scenarios

## Sources

### Primary (HIGH confidence)
- [Firebase Crashlytics Flutter Get Started](https://firebase.google.com/docs/crashlytics/flutter/get-started) - Official setup guide
- [Firebase Crashlytics Flutter Customize Reports](https://firebase.google.com/docs/crashlytics/flutter/customize-crash-reports) - Custom keys, opt-in reporting
- [FlutterFire Crashlytics Usage](https://firebase.flutter.dev/docs/crashlytics/usage/) - recordError, setCustomKey API
- [Flutter Error Handling Official Docs](https://docs.flutter.dev/testing/errors) - FlutterError.onError, PlatformDispatcher.onError
- [circular_buffer package pub.dev](https://pub.dev/packages/circular_buffer) - Version 0.12.0 API and usage
- [kDebugMode Flutter API](https://api.flutter.dev/flutter/foundation/kDebugMode-constant.html) - Compile-time constants
- ReaPrime codebase - main.dart (existing Firebase init), profile_hash.dart (crypto usage), settings_service.dart (SharedPreferences patterns)

### Secondary (MEDIUM confidence)
- [Sentry Logging Integration](https://docs.sentry.io/platforms/dart/guides/flutter/integrations/logging/) - Pattern for hooking package:logging (verified concept applicable to Firebase)
- [Practical Hash-based Anonymity for MAC Addresses (PDF)](https://www.scitepress.org/Papers/2020/98251/98251.pdf) - Research on salting requirements
- [Novel Bits BLE Privacy](https://novelbits.io/bluetooth-address-privacy-ble/) - BLE MAC randomization context
- [Firebase Crashlytics GDPR Compliance](https://dev.srdanstanic.com/firebase-crashlytics-analytics-gdpr-user-data-management/) - Consent management patterns

### Tertiary (LOW confidence)
- Web search results on Flutter DI patterns (general best practices, not Firebase-specific)
- General circular buffer algorithms (Wikipedia, Baeldung) - concepts apply but not Dart-specific implementation details

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All packages verified in pubspec.yaml or pub.dev, versions confirmed
- Architecture: HIGH - Patterns verified against existing ReaPrime codebase (kv_store_service.dart, settings_controller.dart) and official Flutter/Firebase docs
- Pitfalls: HIGH - Consent requirement from GDPR research and Firebase docs, Linux unsupported verified in firebase_options.dart, SHA-256 salting from security research paper

**Research date:** 2026-02-15
**Valid until:** 2026-04-15 (60 days - Firebase APIs stable, Flutter 3.x patterns established)
