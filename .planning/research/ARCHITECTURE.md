# Architecture Research: Flutter Telemetry Service

**Domain:** Field telemetry for BLE IoT gateway applications
**Researched:** 2026-02-15
**Confidence:** HIGH

## Standard Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Application Layer                             │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐            │
│  │ Device   │  │  Web     │  │  Plugin  │  │  WebUI   │            │
│  │Controller│  │  Server  │  │  Service │  │  Service │            │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘            │
│       │             │             │             │                   │
│       └─────────────┴─────────────┴─────────────┘                   │
│                          │                                           │
│                          ▼                                           │
├─────────────────────────────────────────────────────────────────────┤
│                   TelemetryService (NEW)                             │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │  LoggingInterceptor → AnonymizationPipeline → BufferManager │    │
│  │        ▲                      │                      │        │    │
│  │        │                      │                      ▼        │    │
│  │  Logger.root              Sanitizers          CircularBuffer │    │
│  │  (WARNING+)                  │                  (16KB FIFO)  │    │
│  │                              ▼                      │        │    │
│  │                     SystemInfoCollector      ExportFormatter │    │
│  │                     (device, platform)              │        │    │
│  │                                                     ▼        │    │
│  │                                           REST Endpoint      │    │
│  │                                           GET /api/v1/debug  │    │
│  └─────────────────────────────────────────────────────────────┘    │
├─────────────────────────────────────────────────────────────────────┤
│                      Logging Infrastructure                          │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐                     │
│  │ package:   │  │  logging_  │  │ File       │                     │
│  │ logging    │  │  appenders │  │ Appenders  │                     │
│  │ (existing) │  │ (existing) │  │ (existing) │                     │
│  └────────────┘  └────────────┘  └────────────┘                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| **TelemetryService** | Central telemetry coordinator, manages lifecycle | Singleton service with constructor DI |
| **LoggingInterceptor** | Captures WARNING+ logs from Logger.root | Custom LogRecordListener attached to Logger.root |
| **AnonymizationPipeline** | Sanitizes PII from log messages | Chain of sanitizer functions (MAC, IP, paths) |
| **BufferManager** | Maintains rolling 16KB log history | CircularBuffer of LogRecord objects |
| **SystemInfoCollector** | Snapshots device/platform metadata | Lazy-initialized, cached snapshot using device_info_plus |
| **ExportFormatter** | Formats logs + system info for export | JSON encoder with timestamp, level, message fields |
| **WebView Log Bridge** | Captures console.log from webview_flutter | JavascriptChannel handler forwarding to TelemetryService |

## Recommended Project Structure

```
lib/src/
├── services/
│   ├── telemetry/
│   │   ├── telemetry_service.dart         # Main service interface & impl
│   │   ├── logging_interceptor.dart       # Logger.root listener
│   │   ├── anonymization_pipeline.dart    # PII sanitization
│   │   ├── buffer_manager.dart            # Circular buffer wrapper
│   │   ├── system_info_collector.dart     # Device metadata snapshot
│   │   └── sanitizers/
│   │       ├── mac_sanitizer.dart         # BLE MAC anonymization
│   │       ├── ip_sanitizer.dart          # IP address hashing
│   │       └── path_sanitizer.dart        # File path truncation
│   └── webserver/
│       └── debug_handler.dart             # REST endpoint for log export
└── webui_support/
    └── webui_service.dart (MODIFIED)      # Add console.log capture
```

### Structure Rationale

- **services/telemetry/:** Groups all telemetry components together; follows existing pattern (services/webserver/, services/storage/)
- **sanitizers/:** Isolates each anonymization strategy for independent testing; supports adding new sanitizers without modifying pipeline
- **debug_handler.dart:** Follows existing handler pattern (de1handler.dart, scale_handler.dart, etc.)
- **webui_service.dart modification:** WebView console capture lives with webview management to avoid circular dependencies

## Architectural Patterns

### Pattern 1: Logger.root Hook via Custom Listener

**What:** Intercept all logs at WARNING+ by attaching a custom listener to Logger.root, not by creating a custom Appender.

**When to use:** When you need to process log messages separately from output destinations (console, file). Appenders are for output; listeners are for side effects.

**Trade-offs:**
- PRO: Non-invasive; doesn't interfere with existing PrintAppender/RotatingFileAppender
- PRO: Receives logs before formatting, enabling custom processing
- CON: Must manually filter by level (Logger.root.onRecord emits all levels)
- CON: Not part of logging_appenders disposal chain (manual cleanup required)

**Example:**
```dart
class TelemetryService {
  StreamSubscription<LogRecord>? _logSubscription;

  Future<void> initialize() async {
    _logSubscription = Logger.root.onRecord.listen((record) {
      if (record.level >= Level.WARNING) {
        _captureLog(record);
      }
    });
  }

  void dispose() {
    _logSubscription?.cancel();
  }
}
```

### Pattern 2: Hash-based PII Anonymization with Time-Varying Pepper

**What:** Use SHA-256 with truncation and time-varying pepper for MAC/IP addresses to balance privacy and collision avoidance.

**When to use:** When logs may contain Bluetooth MAC addresses or IP addresses that must be anonymized for GDPR compliance while maintaining debuggability.

**Trade-offs:**
- PRO: Computationally expensive hash resists brute-force MAC enumeration
- PRO: Truncation to 24 bits provides k-anonymity (collision rate <1% for 168K addresses)
- PRO: Time-varying pepper (hourly rotation) prevents long-term tracking
- CON: Hash collisions mean different devices may map to same anonymized ID within same time window
- CON: Requires storing pepper salt for log session reconstruction (not implemented in MVP)

**Example:**
```dart
class MacSanitizer {
  static final _macPattern = RegExp(
    r'\b([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})\b'
  );

  String sanitize(String message) {
    return message.replaceAllMapped(_macPattern, (match) {
      final mac = match.group(0)!;
      final pepper = _getHourlyPepper();
      final hash = sha256.convert(utf8.encode('$pepper$mac')).bytes;
      final truncated = hash.sublist(0, 3); // 24 bits
      return 'MAC-${truncated.map((b) => b.toRadixString(16).padLeft(2, '0')).join('')}';
    });
  }

  String _getHourlyPepper() {
    final hour = DateTime.now().toUtc().hour;
    return 'pepper-$hour';
  }
}
```

### Pattern 3: Circular Buffer with Byte-Bounded FIFO

**What:** Use circular_buffer package with size limit enforced by approximate byte counting, not fixed item count.

**When to use:** When you need bounded memory usage for log storage with predictable overhead (16KB target).

**Trade-offs:**
- PRO: Automatic oldest-item eviction when capacity reached
- PRO: O(1) append performance
- CON: circular_buffer uses item count, not bytes—must implement custom byte tracking
- CON: Approximate byte sizing (JSON-encoded length) may overshoot target by ~10%

**Example:**
```dart
class BufferManager {
  final CircularBuffer<LogRecord> _buffer;
  final int _maxBytes;
  int _currentBytes = 0;

  BufferManager({int maxBytes = 16 * 1024})
      : _maxBytes = maxBytes,
        _buffer = CircularBuffer(1000); // Oversize capacity

  void add(LogRecord record) {
    final recordSize = _estimateBytes(record);

    // Evict oldest until room for new record
    while (_currentBytes + recordSize > _maxBytes && _buffer.length > 0) {
      final removed = _buffer[0];
      _buffer.removeAt(0);
      _currentBytes -= _estimateBytes(removed);
    }

    _buffer.add(record);
    _currentBytes += recordSize;
  }

  int _estimateBytes(LogRecord record) {
    // Rough approximation: JSON-encoded length
    return jsonEncode({
      'time': record.time.toIso8601String(),
      'level': record.level.name,
      'message': record.message,
    }).length;
  }
}
```

### Pattern 4: Constructor Dependency Injection for Singleton Service

**What:** TelemetryService follows ReaPrime's existing pattern: singleton instance created in main.dart, injected via constructors to consumers.

**When to use:** When service needs to be shared across multiple controllers/handlers but shouldn't use global state or service locator.

**Trade-offs:**
- PRO: Explicit dependencies visible in constructor signatures
- PRO: Supports testing with mock implementations
- PRO: Matches existing ReaPrime architecture (De1Controller, ScaleController, etc.)
- CON: Requires passing service through multiple layers if deeply nested
- CON: main.dart becomes dependency wiring hub (already true in ReaPrime)

**Example:**
```dart
// main.dart
final telemetryService = TelemetryService();
await telemetryService.initialize();

final webserverService = startWebServer(
  deviceController,
  de1Controller,
  scaleController,
  settingsController,
  sensorController,
  workflowController,
  persistenceController,
  pluginService,
  webUIService,
  webUIStorage,
  profileController,
  telemetryService, // NEW
);

// webserver_service.dart
Future<void> startWebServer(
  // ... existing params ...
  TelemetryService telemetryService,
) async {
  final debugHandler = DebugHandler(telemetry: telemetryService);
  // ...
}
```

## Data Flow

### Log Capture Flow

```
[Any component uses Logger("name").warning("message")]
    ↓
Logger.root.onRecord stream emits LogRecord
    ↓
TelemetryService listener filters (level >= WARNING)
    ↓
AnonymizationPipeline.sanitize(record.message)
    ├─→ MacSanitizer: MAC-abc123
    ├─→ IpSanitizer: IP-def456
    └─→ PathSanitizer: .../app/***
    ↓
BufferManager.add(sanitized LogRecord)
    ├─→ Check byte budget
    ├─→ Evict oldest if needed
    └─→ CircularBuffer.add()
    ↓
[Log retained in memory until export or app restart]
```

### WebView Console Capture Flow

```
[JavaScript in WebView calls console.log/warn/error]
    ↓
webview_flutter.setOnConsoleMessage callback fires
    ↓
WebUIService captures JavaScriptConsoleMessage
    ↓
WebUIService calls TelemetryService.captureWebviewLog()
    ↓
[Follows same anonymization + buffer flow as above]
```

### Export Flow

```
[User/client calls GET /api/v1/debug/logs]
    ↓
DebugHandler.exportLogs()
    ├─→ SystemInfoCollector.snapshot() (device, OS, app version)
    ├─→ BufferManager.getLogs() (CircularBuffer contents)
    └─→ ExportFormatter.toJson()
        ├─→ systemInfo: { device, os, appVersion, timestamp }
        └─→ logs: [ { time, level, message }, ... ]
    ↓
HTTP 200 with JSON response
```

### Key Data Flows

1. **Passive collection:** Logs captured automatically via Logger.root listener; no code changes needed in existing components
2. **On-demand export:** Logs stay in memory until API call; no automatic upload/external transmission
3. **Stateless sanitization:** Each log message sanitized independently; no persistent mapping of real→anonymized IDs

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| 0-100 logs/minute | Current design sufficient; 16KB buffer ≈ 80-160 log messages at ~100-200 bytes each |
| 100-1000 logs/minute | Consider increasing buffer to 64KB; add log level filtering (WARNING+ only enforced, but could add runtime config) |
| 1000+ logs/minute | Add sampling (e.g., keep 10% of INFO, 100% of WARNING+); implement log compression (gzip before export); consider time-windowed retention (last 5 minutes) instead of size-bounded |

### Scaling Priorities

1. **First bottleneck:** Memory pressure from large log volume. Fix: Reduce buffer size or increase eviction rate.
2. **Second bottleneck:** Anonymization CPU cost for high-frequency logs. Fix: Cache anonymized strings with LRU eviction (e.g., last 100 MAC addresses).
3. **Third bottleneck:** Export payload size for slow networks. Fix: Add gzip compression to HTTP response.

**Note:** ReaPrime is an IoT gateway, not a high-throughput server. Expected log volume is <10 logs/minute under normal operation. Scaling beyond 100 logs/minute is unlikely unless device enters error loop (in which case, aggressive eviction is acceptable—we want recent logs, not historical volume).

## Anti-Patterns

### Anti-Pattern 1: Creating Custom Appender for Telemetry

**What people do:** Extend logging_appenders' BaseLogAppender to capture logs.

**Why it's wrong:**
- Appenders are designed for output destinations (files, remote servers, console)
- TelemetryService is a side-effect consumer, not an output destination
- Mixing appender lifecycle with service lifecycle creates disposal complexity
- Appenders attach via attachToLogger(), which adds to Logger.root's listener list—same outcome as direct onRecord.listen(), but with extra abstraction

**Do this instead:**
```dart
// WRONG: Custom appender
class TelemetryAppender extends BaseLogAppender {
  @override
  void handle(LogRecord record) {
    telemetryService.capture(record);
  }
}

// RIGHT: Direct listener
_logSubscription = Logger.root.onRecord.listen((record) {
  if (record.level >= Level.WARNING) {
    _captureLog(record);
  }
});
```

### Anti-Pattern 2: Storing Raw Logs Before Anonymization

**What people do:** Capture raw log messages in buffer, then sanitize during export.

**Why it's wrong:**
- PII exists in memory throughout app lifetime
- Memory dump or crash report could leak unsanitized data
- Export-time sanitization introduces latency for API response
- Violates principle of "collect minimally, sanitize immediately"

**Do this instead:**
```dart
// WRONG: Sanitize on export
void exportLogs() {
  final sanitized = _buffer.map((log) => _sanitize(log.message));
  return sanitized;
}

// RIGHT: Sanitize on capture
void _captureLog(LogRecord record) {
  final sanitized = _anonymizationPipeline.sanitize(record.message);
  final cleanRecord = LogRecord(
    record.level,
    sanitized,
    record.loggerName,
    record.error,
    record.stackTrace,
  );
  _bufferManager.add(cleanRecord);
}
```

### Anti-Pattern 3: Global Singleton Without Constructor DI

**What people do:**
```dart
class TelemetryService {
  static final TelemetryService instance = TelemetryService._();
  TelemetryService._();
}

// Usage anywhere:
TelemetryService.instance.capture(log);
```

**Why it's wrong:**
- Hides dependencies; consumers don't declare telemetry requirement
- Makes testing difficult (can't inject mock)
- Breaks ReaPrime's established architecture pattern
- Global state complicates disposal order

**Do this instead:**
```dart
// main.dart
final telemetryService = TelemetryService();

// Handler receives via constructor
class DebugHandler {
  final TelemetryService _telemetry;
  DebugHandler({required TelemetryService telemetry}) : _telemetry = telemetry;
}
```

## Integration Points

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| TelemetryService ↔ Logger.root | Stream subscription (onRecord) | One-way: Logger.root → TelemetryService |
| TelemetryService ↔ WebserverService | Constructor DI (DebugHandler) | TelemetryService injected into handler for export endpoint |
| TelemetryService ↔ WebUIService | Method call (captureWebviewLog) | WebUIService calls TelemetryService when console.log received |
| DebugHandler ↔ HTTP Client | REST API (GET /api/v1/debug/logs) | Standard Shelf request/response |

### Component Dependency Graph

```
                        main.dart
                            │
              ┌─────────────┴─────────────┐
              ▼                           ▼
      TelemetryService              WebUIService
              │                           │
              │ (injected)                │ (calls)
              ▼                           ▼
       DebugHandler ←───────────── captureWebviewLog()
              │
              │ (registered route)
              ▼
     GET /api/v1/debug/logs
```

### Build Order Implications

1. **Phase 1:** Core TelemetryService + LoggingInterceptor + BufferManager (no dependencies beyond dart:core and package:logging)
2. **Phase 2:** AnonymizationPipeline + Sanitizers (depends on Phase 1 interfaces)
3. **Phase 3:** SystemInfoCollector (depends on device_info_plus; independent of Phases 1-2)
4. **Phase 4:** DebugHandler (depends on Phases 1-3 + existing WebserverService)
5. **Phase 5:** WebUIService integration (depends on Phase 1; modifies existing code)

**Critical path:** Phase 1 → Phase 2 → Phase 4 (REST endpoint). Phase 3 and Phase 5 are independent features.

## Implementation Constraints

### Memory Constraints

- **Target:** 16KB buffer = ~80-160 log messages
- **Overhead:** circular_buffer package adds ~40 bytes per item for internal bookkeeping
- **Safety margin:** Implement at 14KB target to account for estimation errors

### Anonymization Performance

- **MAC address hashing:** SHA-256 is ~1-2ms per address on mobile ARM
- **Mitigation:** Cache last 100 anonymized MACs with LRU eviction
- **Expected load:** BLE discovery logs ~5-10 MACs/minute; cache hit rate >90%

### Platform Differences

| Platform | Consideration | Solution |
|----------|--------------|----------|
| Android | File paths may expose /storage/emulated/0/Download/REA1/ | Truncate to app-relative paths |
| iOS | Strict sandboxing; paths less revealing | Same truncation for consistency |
| Linux | BlueZ adapter paths (/org/bluez/hci0) may leak | Anonymize hci* patterns |
| Windows | universal_ble may log different MAC format | Regex handles colon and hyphen separators |

### WebView Integration Specifics

**webview_flutter API:**
```dart
// In WebUIService.serveFolderAtPath():
controller.setOnConsoleMessage((JavaScriptConsoleMessage message) {
  _telemetryService?.captureWebviewLog(
    level: _mapConsoleLevel(message.level),
    message: message.message,
    source: 'webview',
  );
});

ConsoleMessageLevel _mapConsoleLevel(JavaScriptConsoleMessageLevel level) {
  switch (level) {
    case JavaScriptConsoleMessageLevel.error:
      return Level.SEVERE;
    case JavaScriptConsoleMessageLevel.warning:
      return Level.WARNING;
    default:
      return Level.INFO;
  }
}
```

## Sources

### Architecture Patterns
- [Flutter Architecture Guide](https://docs.flutter.dev/app-architecture/guide) - Official Flutter architecture recommendations
- [Dependency Injection in Flutter](https://docs.flutter.dev/app-architecture/case-study/dependency-injection) - Google's recommended DI patterns
- [Clean Architecture + DI in Flutter 2026](https://medium.com/@chandakasreenu0/clean-architecture-dependency-injection-in-flutter-the-restaurant-analogy-%EF%B8%8F-f40ba4c5407f) - Singleton vs factory patterns

### Logging Infrastructure
- [logging_appenders package](https://pub.dev/packages/logging_appenders) - Appender API and custom handler patterns
- [Beyond print(): Levelling Up Your Flutter Logging](https://itnext.io/beyond-print-levelling-up-your-flutter-logging-92313f9d18a8) - Logger.root hierarchical configuration

### Data Structures
- [circular_buffer package](https://pub.dev/packages/circular_buffer) - CircularBuffer API and FIFO semantics
- [Most Popular Flutter Logging Libraries (2025-2026)](https://medium.com/@yash22202/most-popular-flutter-logging-libraries-2025-2026-6394a0b13c29) - Buffer-based logging patterns

### Anonymization & Privacy
- [Practical Hash-based Anonymity for MAC Addresses](https://arxiv.org/abs/2005.06580) - SHA-256 truncation and k-anonymity
- [MAC Address Anonymization for Crowd Counting](https://www.mdpi.com/1999-4893/15/5/135) - Salt, pepper, and collision rate analysis
- [Scrubbing Sensitive Data | Sentry for Flutter](https://docs.sentry.io/platforms/flutter/data-management/sensitive-data/) - beforeSend sanitization patterns
- [OWASP Top 10 For Flutter – M6: Inadequate Privacy Controls](https://docs.talsec.app/appsec-articles/articles/owasp-top-10-for-flutter-m6-inadequate-privacy-controls-in-flutter-and-dart) - PII handling best practices

### System Information
- [device_info_plus package](https://pub.dev/packages/device_info_plus) - Device metadata collection API
- [Device Info Plus Package in Flutter](https://medium.com/@abdulaziznuftillayev2/device-info-plus-package-in-flutter-520b62409842) - Platform-specific diagnostic patterns

### WebView Integration
- [Flutter WebView JavaScript Communication](https://medium.com/flutter-community/flutter-webview-javascript-communication-inappwebview-5-403088610949) - Console log capture with setOnConsoleMessage
- [Implementing Flutter WebView with JS Bridge Communication](https://vibe-studio.ai/insights/implementing-flutter-webview-with-js-bridge-communication) - JavascriptChannel patterns

---
*Architecture research for: ReaPrime Telemetry Service*
*Researched: 2026-02-15*
