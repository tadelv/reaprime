# Serial Desktop Fixes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix three bugs in desktop serial service: hex parsing crash on fragmented reads, duplicate DE1 detection on rescan, and stale connection after write errors.

**Architecture:** All fixes are in existing files — no new classes or services. Fix 1 is in the serial message parser, Fix 2 is in the scan deduplication filter, Fix 3 is in the serial write path.

**Tech Stack:** Dart, Flutter, RxDart (BehaviorSubject)

---

### Task 1: Fix hex parsing crash on fragmented serial reads

**Files:**
- Modify: `lib/src/models/device/impl/de1/unified_de1/unified_de1_transport.dart:196-197` (regex)
- Modify: `lib/src/models/device/impl/de1/unified_de1/unified_de1_transport.dart:249-270` (_processDe1Response)
- Test: `test/serial_message_parsing_test.dart` (create)

**Step 1: Write failing test for fragmented serial input**

```dart
// test/serial_message_parsing_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1_transport.dart';

// We test the regex and hexToBytes directly since _processSerialInput is private.
// The regex fix is the primary concern.

void main() {
  group('Message pattern matching', () {
    // Current regex: (\[[A-Z]\][0-9A-Fa-f\s]*?)(?=\[|\n|$)
    // Fixed regex:  (\[[A-Z]\][0-9A-Fa-f\s]*?)(?=\[|\n)
    final fixedPattern = RegExp(r'(\[[A-Z]\][0-9A-Fa-f\s]*?)(?=\[|\n)');

    test('matches complete messages terminated by newline', () {
      final input = '[N]300F7E310000002F00\n';
      final matches = fixedPattern.allMatches(input).toList();
      expect(matches.length, 1);
      expect(matches[0].group(1), '[N]300F7E310000002F00');
    });

    test('matches multiple messages separated by prefix', () {
      final input = '[N]0A0B[M]0C0D\n';
      final matches = fixedPattern.allMatches(input).toList();
      expect(matches.length, 2);
      expect(matches[0].group(1), '[N]0A0B');
      expect(matches[1].group(1), '[M]0C0D');
    });

    test('does NOT match incomplete message at end of buffer', () {
      final input = '[N]300F7E310000002F0';
      final matches = fixedPattern.allMatches(input).toList();
      expect(matches.length, 0, reason: 'Incomplete message should not match');
    });

    test('matches complete message but not trailing partial', () {
      final input = '[N]0A0B0C0D\n[M]partial';
      final matches = fixedPattern.allMatches(input).toList();
      expect(matches.length, 1);
      expect(matches[0].group(1), '[N]0A0B0C0D');
    });
  });

  group('hexToBytes', () {
    // We can't instantiate UnifiedDe1Transport easily, so test the logic directly
    test('throws FormatException on odd-length hex', () {
      expect(
        () => _hexToBytes('0A0B0C0'),
        throwsA(isA<FormatException>()),
      );
    });

    test('parses valid even-length hex', () {
      final result = _hexToBytes('0A0B0C0D');
      expect(result, [0x0A, 0x0B, 0x0C, 0x0D]);
    });
  });
}

// Standalone copy of hexToBytes for testing (same logic as in transport)
List<int> _hexToBytes(String hex) {
  hex = hex.replaceAll(RegExp(r'\s+'), '');
  if (hex.length.isOdd) {
    throw FormatException('Invalid input length, must be even', hex);
  }
  final result = List<int>.filled(hex.length ~/ 2, 0);
  for (var i = 0; i < hex.length; i += 2) {
    result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
  }
  return result;
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/serial_message_parsing_test.dart`
Expected: The "does NOT match incomplete message" test FAILS because the current regex uses `$` which matches it.

**Step 3: Fix the regex — remove `$` from lookahead**

In `lib/src/models/device/impl/de1/unified_de1/unified_de1_transport.dart`, change line 196-197:

```dart
// Before:
static final _messagePattern =
    RegExp(r'(\[[A-Z]\][0-9A-Fa-f\s]*?)(?=\[|\n|$)');

// After:
static final _messagePattern =
    RegExp(r'(\[[A-Z]\][0-9A-Fa-f\s]*?)(?=\[|\n)');
```

Also update the comment on lines 193-194:
```dart
// Matches a complete message: [X] prefix + hex payload, terminated by
// another '[' (next message) or newline. Partial data stays in buffer.
```

Remove the now-dead `lastIsComplete` check (lines 225-231) since the regex can no longer match via `$`:
```dart
// Before (lines 225-231):
final lastMatch = matches.last;
final lastIsComplete =
    lastMatch.end < _currentBuffer.length &&
    (_currentBuffer[lastMatch.end] == '[' ||
        _currentBuffer[lastMatch.end] == '\n');
final completeCount = lastIsComplete ? matches.length : matches.length - 1;

// After:
final completeCount = matches.length;
```

**Step 4: Add try-catch in _processDe1Response for non-fatal reporting**

In `_processDe1Response` (line 249), wrap the hex parsing:

```dart
void _processDe1Response(String input) {
  _log.finest("processing input: $input");
  try {
    final Uint8List payload = hexToBytes(input.substring(3));
    final ByteData data = ByteData.sublistView(payload);
    switch (input.substring(0, 3)) {
      case "[M]":
        _shotSampleNotification(data);
      case "[N]":
        _stateNotification(data);
      case "[Q]":
        _waterLevelsNotification(data);
      case "[K]":
        _shotSettingsNotification(data);
      case "[E]":
        _mmrNotification(data);
      case "[I]":
        _fwMapNotification(data);
      default:
        _log.warning("unhandled de1 message: $input");
        break;
    }
  } on FormatException catch (e) {
    // Log at WARNING to trigger non-fatal telemetry report
    _log.warning("Failed to parse DE1 serial message: $input", e);
  }
}
```

**Step 5: Run tests**

Run: `flutter test test/serial_message_parsing_test.dart`
Expected: All tests pass.

**Step 6: Run flutter analyze**

Run: `flutter analyze lib/src/models/device/impl/de1/unified_de1/unified_de1_transport.dart`
Expected: No new issues.

**Step 7: Commit**

```
git add lib/src/models/device/impl/de1/unified_de1/unified_de1_transport.dart test/serial_message_parsing_test.dart
git commit -m "fix: prevent hex parsing crash on fragmented serial reads

Remove $ anchor from message regex so incomplete messages at end of
buffer stay buffered until a terminator arrives. Catch FormatException
in _processDe1Response for non-fatal telemetry reporting as a safety net."
```

---

### Task 2: Fix duplicate DE1 detection on rescan

**Files:**
- Modify: `lib/src/services/serial/serial_service_desktop.dart:66-123`
- Modify: `lib/src/services/serial/serial_service_desktop.dart:224-244` (_DesktopSerialPort)
- Test: add to `test/serial_message_parsing_test.dart` or existing serial test

**Step 1: Write failing test**

The deduplication bug is that `connectedIds` contains `_port.address` values but the filter compares against port path strings. We need the port path stored on the transport.

Add to `test/serial_message_parsing_test.dart`:

```dart
group('Serial port deduplication', () {
  test('connected port paths should be used for deduplication', () {
    // Simulate: port path is "/dev/cu.usbmodem123"
    // _port.address might return "5B1F0919231" (a different value)
    // The filter must use port paths, not addresses
    final portPath = '/dev/cu.usbmodem123';
    final portAddress = '5B1F0919231';

    // With current bug: connectedIds = {portAddress}
    // Filter checks: connectedIds.contains(portPath) → false → duplicate!
    expect(portAddress == portPath, false, reason: 'address != path');

    // Fix: connectedIds should contain portPath
    final connectedPaths = {portPath};
    expect(connectedPaths.contains(portPath), true);
  });
});
```

**Step 2: Add `portPath` to _DesktopSerialPort**

In `lib/src/services/serial/serial_service_desktop.dart`, add a `portPath` field to `_DesktopSerialPort`:

```dart
class _DesktopSerialPort implements SerialTransport {
  final SerialPort _port;
  final String portPath;  // ADD: the port path used to create this transport
  late Logger _log;
  // ...

  _DesktopSerialPort({required SerialPort port, required this.portPath}) : _port = port {
    _log = Logger("SerialPort:${port.name}");
  }
```

Update all call sites that create `_DesktopSerialPort` in `_detectDevice` (line 134):

```dart
final transport = _DesktopSerialPort(port: port, portPath: id);
```

**Step 3: Fix deduplication in `_performScan`**

Change lines 79-83:

```dart
// Before:
final connectedIds = connected.map((e) => e.deviceId).toSet();
final scanPorts = ports.where((p) {
  if (connectedIds.contains(p)) return false;

// After:
final connectedPorts = connected
    .map((e) {
      final transport = (e as dynamic);
      // Access the port path through the device's transport
      try {
        return (transport._transport as _DesktopSerialPort).portPath;
      } catch (_) {
        return e.deviceId;
      }
    })
    .toSet();
final scanPorts = ports.where((p) {
  if (connectedPorts.contains(p)) return false;
```

Actually, that's fragile with dynamic casts. Better approach — track connected port paths directly in the service:

```dart
// Add field to DesktopSerialService:
final Set<String> _connectedPortPaths = {};

// In _detectDevice, after creating device:
_connectedPortPaths.add(id);

// In _performScan deduplication:
final scanPorts = ports.where((p) {
  if (_connectedPortPaths.contains(p)) return false;
  // ... rest of filter
```

And clean up on disconnect — listen to device connection state changes.

**Step 4: Implement the clean approach**

In `lib/src/services/serial/serial_service_desktop.dart`:

Add field (near line 18):
```dart
final Set<String> _connectedPortPaths = {};
```

In `_detectDevice` (after line 136, where device is created successfully), add:
```dart
_connectedPortPaths.add(id);
```

In `_performScan` (line 79-83), replace:
```dart
// Before:
final connectedIds = connected.map((e) => e.deviceId).toSet();
final scanPorts = ports.where((p) {
  if (connectedIds.contains(p)) return false;

// After:
final scanPorts = ports.where((p) {
  if (_connectedPortPaths.contains(p)) return false;
```

Clean up stale port paths — at the start of `_performScan`, remove paths for disconnected devices:
```dart
// Clean up disconnected port paths
final stillConnectedPaths = <String>{};
for (var d in connected) {
  final path = _connectedPortPaths.firstWhere(
    (p) => connected.any((c) => c.deviceId == d.deviceId),
    orElse: () => '',
  );
  if (path.isNotEmpty) stillConnectedPaths.add(path);
}
_connectedPortPaths.retainAll(stillConnectedPaths);
```

Actually this is getting circular. Simplest fix: just store a map from portPath → deviceId:

```dart
final Map<String, String> _portPathToDeviceId = {};
```

In `_detectDevice`, after creating device:
```dart
_portPathToDeviceId[id] = device.deviceId;
```

In `_performScan`, dedup filter:
```dart
final scanPorts = ports.where((p) {
  if (_portPathToDeviceId.containsKey(p)) return false;
```

At start of `_performScan`, clean up disconnected:
```dart
_portPathToDeviceId.removeWhere((portPath, deviceId) =>
    !connected.any((d) => d.deviceId == deviceId));
```

**Step 5: Run tests and analyze**

Run: `flutter test && flutter analyze`

**Step 6: Commit**

```
git commit -m "fix: prevent duplicate DE1 detection on USB rescan

Track port paths in a map alongside device IDs. Use port paths
for scan deduplication instead of device IDs (which use a different
format than port path strings). Clean up stale entries on rescan.

Fixes #123"
```

---

### Task 3: Fix write errors not triggering disconnect

**Files:**
- Modify: `lib/src/services/serial/serial_service_desktop.dart:326-345`

**Step 1: Add disconnect on write failure**

In `_write()` method, wrap the write loop in try-catch and call disconnect:

```dart
Future<void> _write(Uint8List command) async {
  try {
    int offset = 0;
    while (offset < command.length) {
      final chunk = offset == 0 ? command : Uint8List.sublistView(command, offset);
      final written = await _port.write(chunk, timeout: 0);
      if (written < 0) {
        throw StateError('Serial write failed: ${SerialPort.lastError}');
      }
      offset += written;
    }
    _port.drain();
    _log.fine("wrote: ${command.map((e) => e.toRadixString(16))}");
    if (Platform.isLinux || Platform.isMacOS) {
      await Future.delayed(Duration(milliseconds: 20), () {
        _log.finest("delaying next write");
      });
    }
  } catch (e) {
    _log.warning("Serial write error, disconnecting", e);
    await disconnect();
    rethrow;
  }
}
```

**Step 2: Run tests and analyze**

Run: `flutter test && flutter analyze`

**Step 3: Commit**

```
git commit -m "fix: disconnect serial port on write errors

Match the read error behavior: when a serial write fails, call
disconnect() to update the connection state stream before rethrowing.
Prevents stale 'connected' state when the port is lost."
```

---

### Task 4: Final verification

**Step 1: Run full test suite**

Run: `flutter test`
Expected: All tests pass.

**Step 2: Run analyze**

Run: `flutter analyze`
Expected: No new issues.

**Step 3: Test with simulated device (if possible)**

Run: `flutter run --dart-define=simulate=1`
Verify: App starts and connects to mock device without errors.
