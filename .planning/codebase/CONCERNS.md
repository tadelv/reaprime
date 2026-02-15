# Codebase Concerns

**Analysis Date:** 2026-02-15

## Tech Debt

### Incomplete BLE Disconnect Implementation
- Issue: `BluePlusTransport.disconnect()` contains a TODO comment indicating it's not fully implemented, though it calls `_device.disconnect()`
- Files: `lib/src/services/ble/blue_plus_transport.dart:36`
- Impact: Potential resource leaks or incomplete cleanup when disconnecting from BLE devices, may affect subsequent connection attempts
- Fix approach: Complete the disconnect implementation; verify all BLE resources are properly cleaned up, including service/characteristic discovery cache and any pending operations

### Unimplemented Scale Commands
- Issue: `Scale` interface declares `commands` property with TODO: "commands for timer" - timer control not available
- Files: `lib/src/models/device/scale.dart:16`
- Impact: Scales cannot execute timer operations, limiting espresso machine workflow automation
- Fix approach: Define timer command protocol for scale implementations; implement in at least Acaia scales

### Missing Watchdog for Plugin Loading
- Issue: Plugin loading uses `Future.any()` with hardcoded 1-second timeout, but FIXME comment notes no watchdog to prevent broken apps
- Files: `lib/src/plugins/plugin_loader_service.dart:152`
- Impact: If a plugin fails to load after timeout, it can corrupt app state or cause crashes without graceful recovery
- Fix approach: Implement plugin watchdog that detects unresponsive plugins and automatically disables them; add retry logic with backoff

### Serial Device Detection Heuristic
- Issue: Desktop serial DE1 detection uses basic string matching ("TODO: better DE1 detection")
- Files: `lib/src/services/serial/serial_service_desktop.dart:176`
- Impact: May incorrectly identify or miss serial DE1 machines on Windows/macOS/Linux, causing connection failures
- Fix approach: Implement proper USB VID/PID matching or device descriptor inspection for DE1 serial devices

### Duplicate Scan Filter Logic
- Issue: BLE discovery has duplicate scan filter implementation
- Files: `lib/src/services/universal_ble_discovery_service.dart:110`
- Impact: Code maintainability issue, potential inconsistency if one filter is updated but not the other
- Fix approach: Consolidate filter logic into single shared method; reuse across discovery implementations

### Incomplete Profile and Settings Configurations
- Issue: Multiple properties marked "TODO" or "TODO: set defaults" in MMR handling and machine settings
- Files: `lib/src/models/device/impl/de1/de1.models.dart:234-235`, `lib/src/controllers/de1_controller.defaults.dart:7`
- Impact: Heater defaults and some machine settings may not be initialized correctly on first startup
- Fix approach: Document all MMR registers with proper default values; implement initialization logic

### Unimplemented DE1 Endpoints
- Issue: Multiple transport read methods throw `UnimplementedError` for endpoints like `calibration`, `headerWrite`, `frameWrite`
- Files: `lib/src/models/device/impl/de1/unified_de1/unified_de1_transport.dart:323-330`
- Impact: Cannot perform firmware calibration or access raw frame data, limiting advanced DE1 diagnostics
- Fix approach: Implement missing endpoints or clearly document why they're unsupported; remove if truly unneeded

### Configurable Delays as TODOs
- Issue: Hard-coded discovery delays (e.g., BLE scan service delay)
- Files: `lib/src/services/universal_ble_discovery_service.dart:81`
- Impact: Cannot tune discovery performance per platform without code change
- Fix approach: Make delays configurable via settings; expose in gateway configuration

### Linux BLE Service Specification
- Issue: FIXME notes "determine correct way to specify services for linux" in BLE discovery
- Files: `lib/src/services/universal_ble_discovery_service.dart:66`
- Impact: Linux BLE discovery may not filter to correct services, potentially finding wrong devices
- Fix approach: Research and document correct service UUID specification for Linux flutter_blue_plus; test with actual hardware

## Known Bugs

### Machine Parser Type Casting Bug
- Symptoms: Model detection reads MMR data but casting logic appears fragile; IndexError possible if result array too small
- Files: `lib/src/models/device/impl/machine_parser.dart:20-94`
- Trigger: Connect to device with malformed or incomplete MMR response; especially on poor BLE connections
- Workaround: Retry connection if model detection fails
- Root cause: `result` array populated via `firstWhere(..., orElse: () => [])` can return empty list; subsequent indexing at [4] crashes if array too small

### String Throwing Exception
- Symptoms: Exception throws use plain strings instead of Exception objects
- Files: `lib/src/models/device/impl/machine_parser.dart:83`, `lib/src/models/device/impl/de1/unified_de1/unified_de1_transport.dart:352`
- Impact: Stack traces and exception handling may not work correctly; should throw proper Exception objects
- Fix approach: Replace `throw "message"` with `throw Exception('message')` throughout codebase

### Acaia Scale Subscription Not Stored
- Symptoms: After scale connects, a `disconnectSub` is created but never stored as instance variable
- Files: `lib/src/models/device/impl/acaia/acaia_scale.dart:64-82`
- Impact: If scale reconnects, `disconnectSub?.cancel()` called later may reference wrong subscription; disconnect handling corrupted
- Root cause: `disconnectSub` is local to `onConnect()` method; should be instance variable to persist across calls

## Fragile Areas

### BLE Service Discovery Without Error Handling
- Files: `lib/src/services/ble/blue_plus_transport.dart:58-62, 75-80, 97-102`
- Why fragile: Uses `firstWhere()` on service/characteristic lists without fallback; crashes if expected UUID not found
- Safe modification: Add error handling with descriptive messages; validate service exists before attempting read/write
- Test coverage: No unit tests for missing services; integration tests needed
- Current risk: Missing services crash the transport layer silently to logs only

### Scale Connection State Race Condition
- Files: `lib/src/models/device/impl/acaia/acaia_scale.dart:59`, and multiple scale implementations checking `.first`
- Why fragile: Checking `await _transport.connectionState.first == true` then proceeding may race; transport could disconnect before next operation
- Safe modification: Subscribe to connection state changes instead of checking once; implement state machine
- Test coverage: No concurrency tests for rapid connect/disconnect cycles
- Current risk: Initialization commands sent to disconnected transport silently fail

### JSON Deserialization Without Validation
- Files: `lib/src/models/data/profile.dart:46-61`, profile handler, workflow data structures
- Why fragile: `fromJson()` methods call `.byName()` on enums without try/catch; missing fields return null
- Safe modification: Validate all required fields present; wrap enum parsing in try/catch with clear error messages
- Test coverage: Basic serialization tests exist (`test/profile_test.dart`) but edge cases missing
- Current risk: Corrupted or legacy profile data crashes profile loading; backwards compatibility broken

### Plugin Settings Parsing with Fallback to Empty
- Files: `lib/src/plugins/plugin_loader_service.dart:208-220`
- Why fragile: Invalid JSON returns empty map; plugin gets no settings, may fail silently
- Safe modification: Log warning with actual parse error; potentially reject plugin if critical settings missing
- Test coverage: Not tested
- Current risk: Plugin behavior changes unexpectedly if storage corrupted; hard to diagnose

### MMR Read Without Default Fallback
- Files: `lib/src/models/device/impl/de1/unified_de1/unified_de1.dart` (reading various MMR items)
- Why fragile: If machine doesn't support a specific MMR item, read hangs or crashes
- Safe modification: Add timeout to all MMR reads; implement version-specific fallback values
- Test coverage: Unit tests exist but don't cover device firmware variations
- Current risk: DE1 with old firmware may not initialize if newer MMR items assumed present

## Error Handling Issues

### Bare Exception Strings Throughout Codebase
- Pattern: `throw "message"` instead of `throw Exception('message')`
- Impact: Exception handling code breaks; catch blocks expecting Exception type don't work
- Files affected: Multiple transport and device files
- Fix: Systematic replacement with proper Exception throwing

### Timeout Handling Inconsistency
- Some operations use hardcoded timeouts (`timeout: Duration(seconds: 15)` in BLE reads)
- Others have no timeout and can hang indefinitely
- No unified timeout strategy across device layer
- Files: `lib/src/services/ble/blue_plus_transport.dart`, `lib/src/models/device/impl/de1/unified_de1/unified_de1_transport.dart`

### Missing Error Context in onError Callbacks
- Files: Multiple device implementations (scales, sensors) with `onError: (error) => _log.warning(...)`
- Impact: Errors logged but not propagated; UI has no way to inform user of failures
- Fix approach: Bubble errors through subject/stream so UI can display error states

## Memory & Resource Leaks

### Stream Subscriptions Not Always Captured
- Pattern: Many `listen()` calls without storing reference to cancel later
- Example: `lib/src/models/device/impl/acaia/acaia_scale.dart:72-82` creates disconnectSub as local variable
- Impact: Subscriptions may not be properly canceled on cleanup; memory leaks on reconnect cycles
- Fix approach: Store all subscriptions as instance variables; cancel in explicit cleanup methods

### No Explicit Dispose Pattern in Controllers
- Files: `lib/src/controllers/de1_state_manager.dart`, `lib/src/controllers/shot_controller.dart`
- Issue: Subscriptions created in constructors but no dispose() method to clean them up
- Impact: Subscriptions keep controller alive even after view removed; memory accumulates
- Fix approach: Implement dispose pattern or equivalent lifecycle management

### StreamController.broadcast() Without Close
- Pattern: Several device implementations create broadcast streams but never close StreamControllers
- Example: `lib/src/models/device/impl/acaia/acaia_scale.dart:25-26`
- Impact: Resources not freed until garbage collection; delayed cleanup on long-running app
- Fix approach: Implement onDisconnect methods that close all StreamControllers

## Security Considerations

### Plugin JavaScript Execution Sandbox Limitations
- Risk: JavaScript plugins execute with `fetch()` access - can make arbitrary HTTP requests
- Files: `lib/src/plugins/plugin_runtime.dart`
- Current mitigation: None documented; plugins run in flutter_js sandbox
- Recommendations: Document security model; implement request signing or allowlist for plugin HTTP requests; rate limit plugin requests

### Environment Variable Secrets Not Protected
- Risk: `.env` file may contain API keys, tokens
- Files: `.env*` files (not readable per forbidden_files)
- Current mitigation: Listed in `.gitignore` (assuming it is)
- Recommendations: Verify `.env*` in gitignore; use encrypted storage for secrets on mobile devices

### Plugin File Permissions
- Risk: Plugin directory copy operations may not preserve secure permissions
- Files: `lib/src/plugins/plugin_loader_service.dart:98`
- Current mitigation: Flutter app sandbox generally limits access
- Recommendations: Validate plugin manifest signatures before loading; scan for suspicious patterns

### Serial Port Access on Desktop
- Risk: Serial discovery and connection could be hijacked via port enumeration
- Files: `lib/src/services/serial/serial_service_desktop.dart`
- Current mitigation: User must grant permissions
- Recommendations: Whitelist known DE1 serial device types; validate before connecting

## Performance Bottlenecks

### Pagination Missing in Shots Handler
- Problem: Shots history endpoint returns all shots without pagination
- Files: `lib/src/services/webserver/shots_handler.dart:25`
- Impact: Large shot histories (1000+ shots) cause memory spikes and slow API responses
- Improvement path: Implement offset/limit query parameters; add cursor-based pagination; consider archiving old shots

### BLE Characteristic Reads Potentially Blocking
- Problem: Hard-coded 15-second timeout on BLE reads blocks event loop
- Files: `lib/src/services/ble/blue_plus_transport.dart:65`, `lib/src/models/device/impl/de1/unified_de1/unified_de1_transport.dart`
- Impact: UI freezes if BLE device unresponsive
- Improvement path: Move reads to background isolate; implement adaptive timeouts based on device responsiveness

### Profile Hashing Happens on Main Thread
- Problem: SHA-256 hashing of large profiles blocks UI
- Files: `lib/src/models/data/profile_hash.dart`
- Impact: Upload of complex profiles may cause frame drops
- Improvement path: Move hash computation to compute() isolate; cache hashes

### Inefficient Scale Weight Filtering
- Problem: ShotController subscribes to all scale updates, filters in main stream
- Files: `lib/src/controllers/shot_controller.dart:63-69`
- Impact: High frequency scale updates (10+ Hz) all processed even if not needed
- Improvement path: Add throttle/debounce at scale transport layer; implement weight range filtering

## Scaling Limits

### Single BLE Scan Service Instance
- Current capacity: One discovery service per platform
- Limit: Scanning 15+ devices simultaneously causes BLE stack instability on Android
- Scaling path: Implement scan batching or sequential discovery; add configurable scan window

### WebSocket Connection Limits
- Current capacity: No explicit limit on simultaneous WebSocket connections
- Limit: 100+ concurrent clients may exhaust memory
- Scaling path: Implement connection pooling; rate limit broadcasts to slow clients

### Hive Database Performance
- Current capacity: Works well up to 10,000 profiles
- Limit: Larger profile libraries show slowdown; no database optimization
- Scaling path: Implement database indexing; consider splitting into multiple Hive boxes by category

## Dependencies at Risk

### Flutter Blue Plus (fork uncertainty)
- Risk: Project uses `flutter_blue_plus` which is community-maintained fork of deprecated flutter_blue
- Impact: Security updates may lag; breaking changes possible between minor versions
- Migration plan: Consider `flutter_reactive_ble` or `blutooth` as alternatives; both actively maintained

### Custom Flutter JS Bridge
- Risk: `flutter_js` package for JavaScript execution is niche, may be abandoned
- Impact: Plugin system depends on this; limited community support for issues
- Migration plan: Evaluate `quickjs_dart` or migrate plugins to native Dart instead of JavaScript

### Hive Database on Flutter Web
- Risk: Hive stores data as files; web platform lacks filesystem, breaks profile storage
- Impact: Web version (if built) cannot persist profiles
- Migration plan: For web, use IndexedDB or localStorage instead; abstract storage layer needed

## Test Coverage Gaps

### Device Connection State Transitions
- What's not tested: Complex connect/disconnect/reconnect cycles, especially rapid toggles
- Files: `lib/src/models/device/impl/*/` (scale and transport implementations)
- Risk: Race conditions in connection state machines undetected
- Priority: High - affects reliability of device discovery

### BLE Service Discovery Failures
- What's not tested: Missing services, missing characteristics, timeout scenarios
- Files: `lib/src/services/ble/blue_plus_transport.dart`
- Risk: Crashes when device doesn't implement expected BLE structure
- Priority: High - can crash entire transport layer

### Profile Backward Compatibility
- What's not tested: Loading profiles from older app versions with schema changes
- Files: `lib/src/models/data/profile.dart`, `test/profile_test.dart`
- Risk: Cannot upgrade app without losing shot history
- Priority: Medium - affects data integrity over time

### Plugin Error Scenarios
- What's not tested: Plugin crashes, plugin timeout, invalid manifest, corrupted JS code
- Files: `lib/src/plugins/`
- Risk: Broken plugin can bring down entire app
- Priority: High - critical for stability

### Scale-Machine Synchronization
- What's not tested: Scale disconnects mid-shot, weight sensor failures, DE1 state changes during shot control
- Files: `lib/src/controllers/shot_controller.dart`
- Risk: Shots stop unexpectedly or at wrong weight
- Priority: High - affects core functionality

### Serial Port Edge Cases
- What's not tested: Serial port not found, port already in use, permission denied, data corruption on serial lines
- Files: `lib/src/services/serial/serial_service_*.dart`
- Risk: Desktop platforms may not initialize properly
- Priority: Medium - only affects non-Android platforms

## Potential Data Loss Scenarios

### Hive Database Corruption
- Scenario: App crash during write to profile database leaves database in inconsistent state
- Files: `lib/src/services/storage/hive_profile_storage.dart`
- Mitigation needed: Backup profiles before major operations; implement database repair on startup
- Current state: No backup mechanism visible

### Shot Record Truncation
- Scenario: Long shots with thousands of data points may truncate if datapoint array has size limit
- Files: `lib/src/models/data/shot_record.dart`
- Mitigation needed: Document array size limits; implement streaming or pagination
- Current state: No size limits found in code review, but untested at extreme scales

### Profile Upload Interruption
- Scenario: Upload to DE1 interrupted by disconnect - machine left with partial profile
- Files: `lib/src/services/webserver/de1handler.dart`
- Mitigation needed: Verify complete upload before marking success; implement resume capability
- Current state: No validation of complete upload

---

*Concerns audit: 2026-02-15*
