# Acaia Scale Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix Acaia Lunar/Pearl/Pyxis pairing by unifying scale implementations with auto-detection, expanded name matching, init retry loop, and reliable tare.

**Architecture:** Merge `AcaiaScale` (IPS) and `AcaiaPyxisScale` (Pyxis) into a single `AcaiaScale` that auto-detects protocol from discovered BLE services. Expand `DeviceMatcher` name rules to cover all known Acaia advertising names.

**Tech Stack:** Dart/Flutter, BLE via `BLETransport` abstraction, `BleServiceIdentifier` for UUID matching.

**Spec:** `doc/plans/2025-03-25-acaia-scale-fix-design.md`

---

### File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `lib/src/services/device_matcher.dart` | Modify | Unified Acaia name matching |
| `lib/src/models/device/impl/acaia/acaia_scale.dart` | Rewrite | Unified Acaia scale with protocol auto-detection |
| `lib/src/models/device/impl/acaia/acaia_pyxis_scale.dart` | Delete | Merged into acaia_scale.dart |
| `test/unit/services/device_matcher_test.dart` | Modify | Update Acaia test cases |
| `test/unit/models/acaia_scale_test.dart` | Create | Protocol detection, init retry, tare, weight parsing |

---

### Task 1: Update DeviceMatcher Name Matching

**Files:**
- Modify: `lib/src/services/device_matcher.dart:46-51`
- Modify: `test/unit/services/device_matcher_test.dart`

- [ ] **Step 1: Update failing test — add new Acaia name variants**

Add test cases for names that currently return `null` but should match `AcaiaScale`. Update existing Pyxis test to expect `AcaiaScale` instead of `AcaiaPyxisScale`.

In `test/unit/services/device_matcher_test.dart`:

- Change the `AcaiaPyxisScale` import to nothing (remove it)
- Change the `'contains match for Acaia Pyxis'` test to expect `isA<AcaiaScale>()`
- Add new tests:

```dart
test('LUNAR matches to AcaiaScale', () async {
  final device = await DeviceMatcher.match(
    transport: mockTransport,
    advertisedName: 'LUNAR',
  );
  expect(device, isNotNull);
  expect(device, isA<AcaiaScale>());
});

test('PEARL-S matches to AcaiaScale', () async {
  final device = await DeviceMatcher.match(
    transport: mockTransport,
    advertisedName: 'PEARL-S',
  );
  expect(device, isNotNull);
  expect(device, isA<AcaiaScale>());
});

test('PEARLS matches to AcaiaScale', () async {
  final device = await DeviceMatcher.match(
    transport: mockTransport,
    advertisedName: 'PEARLS',
  );
  expect(device, isNotNull);
  expect(device, isA<AcaiaScale>());
});

test('PROCH matches to AcaiaScale', () async {
  final device = await DeviceMatcher.match(
    transport: mockTransport,
    advertisedName: 'PROCH',
  );
  expect(device, isNotNull);
  expect(device, isA<AcaiaScale>());
});

test('PYXIS matches to AcaiaScale', () async {
  final device = await DeviceMatcher.match(
    transport: mockTransport,
    advertisedName: 'PYXIS',
  );
  expect(device, isNotNull);
  expect(device, isA<AcaiaScale>());
});

test('Lunar (mixed case) matches to AcaiaScale', () async {
  final device = await DeviceMatcher.match(
    transport: mockTransport,
    advertisedName: 'Lunar',
  );
  expect(device, isNotNull);
  expect(device, isA<AcaiaScale>());
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/unit/services/device_matcher_test.dart -v`
Expected: New tests FAIL (LUNAR, PEARL-S, PROCH, PYXIS return null)

- [ ] **Step 3: Update DeviceMatcher**

In `lib/src/services/device_matcher.dart`:

Replace lines 46-51 (the current Acaia matching block):
```dart
if (nameLower.contains('acaia') ||
    nameLower.contains('lunar') ||
    nameLower.contains('pearl') ||
    nameLower.contains('proch') ||
    nameLower.contains('pyxis')) {
  return AcaiaScale(transport: transport);
}
```

Remove the `AcaiaPyxisScale` import at the top of the file.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/unit/services/device_matcher_test.dart -v`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/src/services/device_matcher.dart test/unit/services/device_matcher_test.dart
git commit -m "fix: expand Acaia name matching to cover Lunar, Pearl, Proch, Pyxis

Previously only matched names containing 'acaia'. Now matches all
known Acaia advertising names: LUNAR, PEARL, PEARLS, PROCH, PYXIS.
Routes all to unified AcaiaScale (AcaiaPyxisScale removed).

Fixes #110"
```

---

### Task 2: Rewrite AcaiaScale with Protocol Auto-Detection

**Files:**
- Rewrite: `lib/src/models/device/impl/acaia/acaia_scale.dart`
- Create: `test/unit/models/acaia_scale_test.dart`

- [ ] **Step 1: Write test for protocol auto-detection**

Create `test/unit/models/acaia_scale_test.dart`. Use a mock transport that returns configurable service UUIDs from `discoverServices()`.

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/acaia/acaia_scale.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:rxdart/rxdart.dart';

class MockAcaiaBleTransport extends BLETransport {
  final List<String> serviceUUIDs;
  final List<List<int>> receivedWrites = [];
  final BehaviorSubject<ConnectionState> _connectionState =
      BehaviorSubject.seeded(ConnectionState.discovered);
  void Function(Uint8List)? _notificationCallback;

  MockAcaiaBleTransport({required this.serviceUUIDs});

  @override
  String get id => 'AA:BB:CC:DD:EE:FF';

  @override
  String get name => 'Test Acaia';

  @override
  Stream<ConnectionState> get connectionState => _connectionState.stream;

  @override
  Future<void> connect() async {
    _connectionState.add(ConnectionState.connected);
  }

  @override
  Future<void> disconnect() async {
    _connectionState.add(ConnectionState.disconnected);
  }

  @override
  Future<List<String>> discoverServices() async => serviceUUIDs;

  @override
  Future<Uint8List> read(String serviceUUID, String characteristicUUID,
          {Duration? timeout}) async =>
      Uint8List(0);

  @override
  Future<void> subscribe(String serviceUUID, String characteristicUUID,
      void Function(Uint8List) callback) async {
    _notificationCallback = callback;
  }

  @override
  Future<void> write(
      String serviceUUID, String characteristicUUID, Uint8List data,
      {bool withResponse = true, Duration? timeout}) async {
    receivedWrites.add(data.toList());
  }

  @override
  Future<void> setTransportPriority(bool prioritized) async {}

  /// Simulate a notification from the scale
  void simulateNotification(List<int> data) {
    _notificationCallback?.call(Uint8List.fromList(data));
  }
}

void main() {
  group('AcaiaScale protocol auto-detection', () {
    test('detects IPS protocol when service 1820 is present', () async {
      final transport = MockAcaiaBleTransport(
        serviceUUIDs: ['00001820-0000-1000-8000-00805f9b34fb'],
      );
      final scale = AcaiaScale(transport: transport);
      await scale.onConnect();

      // Verify connected
      final state = await scale.connectionState.first;
      expect(state, ConnectionState.connected);

      // Verify writes went to IPS characteristic (2a80)
      expect(transport.receivedWrites, isNotEmpty);
    });

    test('detects Pyxis protocol when service 49535343 is present', () async {
      final transport = MockAcaiaBleTransport(
        serviceUUIDs: ['49535343-fe7d-4ae5-8fa9-9fafd205e455'],
      );
      final scale = AcaiaScale(transport: transport);
      await scale.onConnect();

      final state = await scale.connectionState.first;
      expect(state, ConnectionState.connected);

      expect(transport.receivedWrites, isNotEmpty);
    });

    test('fails when neither service is present', () async {
      final transport = MockAcaiaBleTransport(
        serviceUUIDs: ['0000fff0-0000-1000-8000-00805f9b34fb'],
      );
      final scale = AcaiaScale(transport: transport);
      await scale.onConnect();

      final state = await scale.connectionState.first;
      expect(state, ConnectionState.disconnected);
    });
  });

  group('AcaiaScale weight parsing', () {
    test('decodes weight from event type 5 notification', () async {
      final transport = MockAcaiaBleTransport(
        serviceUUIDs: ['00001820-0000-1000-8000-00805f9b34fb'],
      );
      final scale = AcaiaScale(transport: transport);
      await scale.onConnect();

      // Listen for weight snapshots
      final snapshots = <ScaleSnapshot>[];
      scale.currentSnapshot.listen(snapshots.add);

      // Simulate weight notification: header + msgType=12 + length=10 + eventType=5
      // Weight payload at offset 5: value=1850 (0x3A,0x07,0x00), unit=1, sign=0
      // Expected weight: 1850 / 10^1 = 185.0g
      transport.simulateNotification([
        0xEF, 0xDD, 12, 10, 5, // header, msgType, length, eventType
        0x3A, 0x07, 0x00, 0x00, 0x01, 0x00, // weight payload
        0x00, 0x00, 0x00, 0x00, // padding
      ]);

      await Future.delayed(Duration(milliseconds: 50));
      expect(snapshots, hasLength(1));
      expect(snapshots.first.weight, closeTo(185.0, 0.01));
    });

    test('decodes negative weight', () async {
      final transport = MockAcaiaBleTransport(
        serviceUUIDs: ['00001820-0000-1000-8000-00805f9b34fb'],
      );
      final scale = AcaiaScale(transport: transport);
      await scale.onConnect();

      final snapshots = <ScaleSnapshot>[];
      scale.currentSnapshot.listen(snapshots.add);

      // Same as above but sign byte > 1 → negative
      transport.simulateNotification([
        0xEF, 0xDD, 12, 10, 5,
        0x3A, 0x07, 0x00, 0x00, 0x01, 0x02, // sign=2 → negative
        0x00, 0x00, 0x00, 0x00,
      ]);

      await Future.delayed(Duration(milliseconds: 50));
      expect(snapshots, hasLength(1));
      expect(snapshots.first.weight, closeTo(-185.0, 0.01));
    });
  });

  group('AcaiaScale tare', () {
    test('sends tare command 3 times for reliability', () async {
      final transport = MockAcaiaBleTransport(
        serviceUUIDs: ['00001820-0000-1000-8000-00805f9b34fb'],
      );
      final scale = AcaiaScale(transport: transport);
      await scale.onConnect();

      // Clear init writes
      transport.receivedWrites.clear();

      await scale.tare();

      // Should have sent 3 tare commands
      final tareWrites = transport.receivedWrites.where((w) =>
          w.length >= 3 && w[0] == 0xEF && w[1] == 0xDD && w[2] == 0x04);
      expect(tareWrites.length, 3);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/models/acaia_scale_test.dart -v`
Expected: Tests FAIL (AcaiaScale doesn't have auto-detection yet)

- [ ] **Step 3: Rewrite AcaiaScale**

Rewrite `lib/src/models/device/impl/acaia/acaia_scale.dart` with the unified implementation. Key changes from the existing code:

1. Add `AcaiaProtocol` enum (`ips`, `pyxis`)
2. Add both IPS and Pyxis service/characteristic identifiers as static fields
3. In `onConnect()` → `discoverServices()` → check which service is present → set `_protocol`
4. Helper methods `_serviceUuid`, `_notifyCharUuid`, `_writeCharUuid`, `_useWriteResponse` that return the correct value based on `_protocol`
5. `_initScale()`: retry loop — send ident, wait 200ms, send config, wait 500ms, check `_receivingNotifications`, repeat up to 10 times
6. `tare()`: send 3 times with 100ms delays
7. Watchdog timer: Pyxis only (5s timeout)
8. Heartbeat: 3s interval (matching Decenza)

The encoding, notification parsing, and weight decoding remain unchanged — they're already shared between the two classes.

```dart
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:reaprime/src/models/device/ble_service_identifier.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:rxdart/subjects.dart';

import 'package:reaprime/src/models/device/device.dart';

import '../../scale.dart';

/// Detected Acaia BLE protocol variant.
enum AcaiaProtocol { ips, pyxis }

/// Unified Acaia scale implementation supporting both IPS (older ACAIA/PROCH
/// models) and Pyxis (newer LUNAR/PEARL/PYXIS models) protocols.
///
/// Protocol is auto-detected at connection time based on discovered BLE
/// services, matching the Decenza approach. The IPS message format (header
/// 0xEF 0xDD, message type, payload, checksum) is shared across both variants.
///
/// Reference: de1app bluetooth.tcl (acaia_parse_response, acaia_encode)
class AcaiaScale implements Scale {
  // IPS protocol identifiers
  static final _ipsService = BleServiceIdentifier.short('1820');
  static final _ipsCharacteristic = BleServiceIdentifier.short('2a80');

  // Pyxis protocol identifiers
  static final _pyxisService =
      BleServiceIdentifier.long('49535343-fe7d-4ae5-8fa9-9fafd205e455');
  static final _pyxisStatusChar =
      BleServiceIdentifier.long('49535343-1e4d-4bd9-ba61-23c647249616');
  static final _pyxisCmdChar =
      BleServiceIdentifier.long('49535343-8841-43f4-a8d4-ecbe34729bb3');

  static const int _maxInitRetries = 10;

  final Logger _log = Logger('AcaiaScale');
  final String _deviceId;

  final StreamController<ScaleSnapshot> _streamController =
      StreamController.broadcast();

  final BLETransport _transport;

  AcaiaProtocol? _protocol;
  Timer? _heartbeatTimer;
  Timer? _configTimer;
  Timer? _watchdogTimer;
  int _batteryLevel = 0;
  List<int> _commandBuffer = [];
  DateTime _lastResponse = DateTime.now();
  bool _receivingNotifications = false;

  AcaiaScale({required BLETransport transport})
    : _transport = transport,
      _deviceId = transport.id;

  @override
  Stream<ScaleSnapshot> get currentSnapshot => _streamController.stream;

  @override
  String get deviceId => _deviceId;

  @override
  String get name =>
      _transport.name.isNotEmpty ? _transport.name : 'Acaia Scale';

  final StreamController<ConnectionState> _connectionStateController =
      BehaviorSubject.seeded(ConnectionState.discovered);

  @override
  Stream<ConnectionState> get connectionState =>
      _connectionStateController.stream;

  // --- Protocol-dependent helpers ---

  String get _serviceUuid =>
      _protocol == AcaiaProtocol.pyxis ? _pyxisService.long : _ipsService.long;

  String get _notifyCharUuid => _protocol == AcaiaProtocol.pyxis
      ? _pyxisStatusChar.long
      : _ipsCharacteristic.long;

  String get _writeCharUuid => _protocol == AcaiaProtocol.pyxis
      ? _pyxisCmdChar.long
      : _ipsCharacteristic.long;

  bool get _useWriteResponse => _protocol == AcaiaProtocol.pyxis;

  @override
  Future<void> onConnect() async {
    if (await _transport.connectionState.first == ConnectionState.connected) {
      return;
    }
    _connectionStateController.add(ConnectionState.connecting);

    StreamSubscription<ConnectionState>? disconnectSub;

    try {
      await _transport.connect();

      disconnectSub = _transport.connectionState
          .where((state) => state == ConnectionState.disconnected)
          .listen((_) {
        _log.info('Transport disconnected');
        _connectionStateController.add(ConnectionState.disconnected);
        disconnectSub?.cancel();
        _cancelTimers();
      });

      final services = await _transport.discoverServices();

      // Auto-detect protocol from discovered services
      if (_pyxisService.matchesAny(services)) {
        _protocol = AcaiaProtocol.pyxis;
        _log.info('Detected Pyxis protocol');
      } else if (_ipsService.matchesAny(services)) {
        _protocol = AcaiaProtocol.ips;
        _log.info('Detected IPS protocol');
      } else {
        throw Exception(
          'No Acaia service found. Expected ${_pyxisService.long} or '
          '${_ipsService.long}. Discovered: $services',
        );
      }

      await _initScale();
      _connectionStateController.add(ConnectionState.connected);
      _log.info('Scale initialized successfully (protocol: $_protocol)');
    } catch (e) {
      _log.warning('Failed to initialize scale: $e');
      disconnectSub?.cancel();
      _cancelTimers();
      _connectionStateController.add(ConnectionState.disconnected);
      try {
        await _transport.disconnect();
      } catch (_) {}
    }
  }

  @override
  disconnect() async {
    _cancelTimers();
    await _transport.disconnect();
  }

  void _cancelTimers() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _configTimer?.cancel();
    _configTimer = null;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
  }

  @override
  DeviceType get type => DeviceType.scale;

  // --- Protocol encoding (matches de1app acaia_encode) ---

  static const int _header1 = 0xEF;
  static const int _header2 = 0xDD;

  static const List<int> _identPayload = [
    0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37,
    0x38, 0x39, 0x30, 0x31, 0x32, 0x33, 0x34,
  ];

  static const List<int> _configPayload = [
    0x09, 0x00, 0x01, 0x01, 0x02, 0x02, 0x01, 0x03, 0x04,
  ];

  static const List<int> _heartbeatPayload = [0x02, 0x00];

  static Uint8List _encode(int msgType, List<int> payload) {
    int cksum1 = 0;
    int cksum2 = 0;
    for (int i = 0; i < payload.length; i++) {
      if (i % 2 == 0) {
        cksum1 = (cksum1 + payload[i]) & 0xFF;
      } else {
        cksum2 = (cksum2 + payload[i]) & 0xFF;
      }
    }
    return Uint8List.fromList([
      _header1,
      _header2,
      msgType,
      ...payload,
      cksum1,
      cksum2,
    ]);
  }

  // --- Initialization with retry loop (matches de1app/Decenza) ---

  Future<void> _initScale() async {
    _receivingNotifications = false;

    // Notification enable delay: IPS=100ms, Pyxis=500ms
    final notifyDelay = _protocol == AcaiaProtocol.pyxis ? 500 : 100;

    await _transport.subscribe(_serviceUuid, _notifyCharUuid, _parseNotification);
    await Future.delayed(Duration(milliseconds: notifyDelay));

    // Retry ident+config up to _maxInitRetries times until scale responds
    for (int attempt = 1; attempt <= _maxInitRetries; attempt++) {
      if (_receivingNotifications) break;

      _log.fine('Init attempt $attempt/$_maxInitRetries');

      // Send ident
      await _transport.write(
        _serviceUuid,
        _writeCharUuid,
        _encode(0x0B, _identPayload),
        withResponse: _useWriteResponse,
      );

      await Future.delayed(const Duration(milliseconds: 200));

      // Send config
      await _transport.write(
        _serviceUuid,
        _writeCharUuid,
        _encode(0x0C, _configPayload),
        withResponse: _useWriteResponse,
      );

      await Future.delayed(const Duration(milliseconds: 500));
    }

    if (!_receivingNotifications) {
      _log.warning('Scale did not respond after $_maxInitRetries init attempts');
    }

    // Start heartbeat (3s interval, matching Decenza)
    _lastResponse = DateTime.now();
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _sendHeartbeat();
    });

    // Watchdog for Pyxis only (5s timeout)
    if (_protocol == AcaiaProtocol.pyxis) {
      _watchdogTimer?.cancel();
      _watchdogTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _checkWatchdog();
      });
    }
  }

  void _sendHeartbeat() {
    _transport.write(
      _serviceUuid,
      _writeCharUuid,
      _encode(0x00, _heartbeatPayload),
      withResponse: _useWriteResponse,
    );
    _configTimer?.cancel();
    _configTimer = Timer(const Duration(seconds: 1), () {
      _transport.write(
        _serviceUuid,
        _writeCharUuid,
        _encode(0x0C, _configPayload),
        withResponse: _useWriteResponse,
      );
    });
  }

  void _checkWatchdog() {
    final elapsed = DateTime.now().difference(_lastResponse).inMilliseconds;
    if (elapsed > 5000) {
      _log.warning('Watchdog timeout: no response for ${elapsed}ms');
      disconnect();
    }
  }

  // --- Tare: 3x with 100ms spacing (de1app/Decenza workaround) ---

  @override
  Future<void> tare() async {
    final cmd = _encode(0x04, List.filled(15, 0x00));
    await _transport.write(
      _serviceUuid, _writeCharUuid, cmd,
      withResponse: _useWriteResponse,
    );
    await Future.delayed(const Duration(milliseconds: 100));
    await _transport.write(
      _serviceUuid, _writeCharUuid, cmd,
      withResponse: _useWriteResponse,
    );
    await Future.delayed(const Duration(milliseconds: 100));
    await _transport.write(
      _serviceUuid, _writeCharUuid, cmd,
      withResponse: _useWriteResponse,
    );
  }

  // --- Display control ---

  @override
  Future<void> sleepDisplay() async {
    await disconnect();
  }

  @override
  Future<void> wakeDisplay() async {}

  // --- Notification parsing (matches de1app acaia_parse_response) ---

  static const int _metadataLen = 5;

  void _parseNotification(List<int> data) {
    _lastResponse = DateTime.now();
    _commandBuffer.addAll(data);

    while (_commandBuffer.length >= _metadataLen + 1) {
      if (_commandBuffer[0] != _header1 || _commandBuffer[1] != _header2) {
        _commandBuffer.removeAt(0);
        continue;
      }

      int msgType = _commandBuffer[2];
      int length = _commandBuffer[3];
      int eventType = _commandBuffer[4];

      int msgLen = _metadataLen + length;

      if (_commandBuffer.length < msgLen) break;

      if (msgType != 7) {
        _receivingNotifications = true;
      }

      if (msgType == 8 && _commandBuffer.length > 4) {
        _batteryLevel = _commandBuffer[4];
      }

      if (msgType == 12 &&
          (eventType == 5 || eventType == 11) &&
          length <= 64) {
        final payloadOffset =
            eventType == 5 ? _metadataLen : _metadataLen + 3;
        _decodeWeight(_commandBuffer, payloadOffset);
      }

      if (msgLen <= _commandBuffer.length) {
        _commandBuffer = _commandBuffer.sublist(msgLen);
      } else {
        _commandBuffer.clear();
      }
    }
  }

  void _decodeWeight(List<int> buffer, int offset) {
    if (offset + 6 > buffer.length) return;

    int value = ((buffer[offset + 2] & 0xFF) << 16) +
        ((buffer[offset + 1] & 0xFF) << 8) +
        (buffer[offset] & 0xFF);

    int unit = buffer[offset + 4] & 0xFF;
    double weight = value / pow(10, unit);

    if ((buffer[offset + 5] & 0xFF) > 1) {
      weight *= -1;
    }

    _streamController.add(
      ScaleSnapshot(
        timestamp: DateTime.now(),
        weight: weight,
        batteryLevel: _batteryLevel,
      ),
    );
  }

  @override
  Future<void> startTimer() async {}

  @override
  Future<void> stopTimer() async {}

  @override
  Future<void> resetTimer() async {}
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/unit/models/acaia_scale_test.dart -v`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add lib/src/models/device/impl/acaia/acaia_scale.dart test/unit/models/acaia_scale_test.dart
git commit -m "feat: unified AcaiaScale with protocol auto-detection

Auto-detects IPS vs Pyxis protocol from discovered BLE services.
Adds init retry loop (10 attempts, 500ms interval) matching de1app.
Sends tare 3x with 100ms spacing for Acaia Lunar reliability.
Watchdog timer enabled for Pyxis protocol only."
```

---

### Task 3: Delete AcaiaPyxisScale

**Files:**
- Delete: `lib/src/models/device/impl/acaia/acaia_pyxis_scale.dart`

- [ ] **Step 1: Run full test suite to confirm nothing else imports AcaiaPyxisScale**

Run: `flutter test`
Expected: All tests PASS (the only import was in device_matcher.dart and the test, both already updated)

- [ ] **Step 2: Delete the file**

```bash
rm lib/src/models/device/impl/acaia/acaia_pyxis_scale.dart
```

- [ ] **Step 3: Run analysis and tests**

Run: `flutter analyze && flutter test`
Expected: No issues, all tests PASS

- [ ] **Step 4: Commit**

```bash
git add -A lib/src/models/device/impl/acaia/acaia_pyxis_scale.dart
git commit -m "refactor: remove AcaiaPyxisScale (merged into AcaiaScale)"
```

---

### Task 4: Final Verification and Cleanup

**Files:**
- Modify: `doc/plans/2025-03-25-acaia-scale-fix-design.md` (move to archive)

- [ ] **Step 1: Run full test suite**

Run: `flutter test`
Expected: All tests PASS

- [ ] **Step 2: Run analysis**

Run: `flutter analyze`
Expected: No issues

- [ ] **Step 3: Archive the spec and plan**

```bash
mkdir -p doc/plans/archive/acaia-scale-fix
mv doc/plans/2025-03-25-acaia-scale-fix-design.md doc/plans/archive/acaia-scale-fix/
mv doc/plans/2025-03-25-acaia-scale-fix-plan.md doc/plans/archive/acaia-scale-fix/
git add doc/plans/
git commit -m "docs: archive Acaia scale fix spec and plan"
```
