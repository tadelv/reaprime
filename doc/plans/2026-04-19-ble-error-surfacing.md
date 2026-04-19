# BLE Error Surfacing Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the unstructured `ConnectionStatus.error: String?` with a structured `ConnectionError` object, emit it from every BLE connect failure, mid-session disconnect, and adapter-level problem, and surface it to skins via `ws/v1/devices` / `/api/v1/devices` and to the native Flutter UI via a new `ConnectionErrorBanner`.

**Architecture:** Single aggregation point on `ConnectionManager` (`_emit` / `_clearError`). Existing status stream carries the new shape. Transient errors auto-clear on phase transitions; sticky kinds (`adapterOff`, `bluetoothPermissionDenied`, `scanFailed`) clear on environmental recovery. Deliberate-disconnect suppression via a `Set<String>` keyed by `deviceId` with TTL safety.

**Tech Stack:** Dart / Flutter, `flutter_blue_plus`, `rxdart` `BehaviorSubject`, `shelf` for HTTP/WS, `shadcn_ui` widgets, test via `flutter test`.

**Reference:** Design doc at `doc/plans/2026-04-19-ble-error-surfacing-design.md`. Read it before starting.

**Branch:** `fix/ble-contd` (continue commits here; don't create a new branch).

**Skills referenced:** @tdd-workflow for test-tier selection; @verification-before-completion before claiming tasks done.

---

## Task 1: Introduce `ConnectionError` model

**Files:**
- Create: `lib/src/controllers/connection_error.dart`
- Test: `test/controllers/connection_error_test.dart`

**Step 1: Write the failing test**

```dart
// test/controllers/connection_error_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/connection_error.dart';

void main() {
  group('ConnectionError', () {
    test('toJson produces the documented shape', () {
      final err = ConnectionError(
        kind: ConnectionErrorKind.scaleConnectFailed,
        severity: ConnectionErrorSeverity.error,
        timestamp: DateTime.utc(2026, 4, 19, 7, 49, 29, 25),
        deviceId: '50:78:7D:1F:AE:E1',
        deviceName: 'Decent Scale',
        message: 'Scale connect timed out after 15s.',
        suggestion: 'Try toggling Bluetooth, then retry the scan.',
        details: {'fbp_code': 1},
      );

      expect(err.toJson(), {
        'kind': 'scaleConnectFailed',
        'severity': 'error',
        'timestamp': '2026-04-19T07:49:29.025Z',
        'deviceId': '50:78:7D:1F:AE:E1',
        'deviceName': 'Decent Scale',
        'message': 'Scale connect timed out after 15s.',
        'suggestion': 'Try toggling Bluetooth, then retry the scan.',
        'details': {'fbp_code': 1},
      });
    });

    test('toJson omits null optional fields', () {
      final err = ConnectionError(
        kind: ConnectionErrorKind.adapterOff,
        severity: ConnectionErrorSeverity.error,
        timestamp: DateTime.utc(2026, 4, 19),
        message: 'Bluetooth is turned off.',
      );

      final json = err.toJson();
      expect(json.containsKey('deviceId'), isFalse);
      expect(json.containsKey('deviceName'), isFalse);
      expect(json.containsKey('suggestion'), isFalse);
      expect(json.containsKey('details'), isFalse);
    });

    test('kind constants match the documented taxonomy', () {
      expect(ConnectionErrorKind.scaleConnectFailed, 'scaleConnectFailed');
      expect(ConnectionErrorKind.machineConnectFailed, 'machineConnectFailed');
      expect(ConnectionErrorKind.scaleDisconnected, 'scaleDisconnected');
      expect(ConnectionErrorKind.machineDisconnected, 'machineDisconnected');
      expect(ConnectionErrorKind.adapterOff, 'adapterOff');
      expect(ConnectionErrorKind.bluetoothPermissionDenied,
          'bluetoothPermissionDenied');
      expect(ConnectionErrorKind.scanFailed, 'scanFailed');
    });
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/controllers/connection_error_test.dart`
Expected: compile error — `connection_error.dart` not found.

**Step 3: Write minimal implementation**

```dart
// lib/src/controllers/connection_error.dart

/// Identifiers for BLE-related errors surfaced on
/// `ConnectionManager.status`. Wire format treats these as plain
/// strings — adding new kinds is a server-only change.
class ConnectionErrorKind {
  static const scaleConnectFailed = 'scaleConnectFailed';
  static const machineConnectFailed = 'machineConnectFailed';
  static const scaleDisconnected = 'scaleDisconnected';
  static const machineDisconnected = 'machineDisconnected';
  static const adapterOff = 'adapterOff';
  static const bluetoothPermissionDenied = 'bluetoothPermissionDenied';
  static const scanFailed = 'scanFailed';

  /// Kinds that survive `ConnectionPhase` transitions. They only clear
  /// when the specific environmental condition recovers.
  static const sticky = <String>{
    adapterOff,
    bluetoothPermissionDenied,
    scanFailed,
  };

  const ConnectionErrorKind._();
}

class ConnectionErrorSeverity {
  static const warning = 'warning';
  static const error = 'error';

  const ConnectionErrorSeverity._();
}

class ConnectionError {
  final String kind;
  final String severity;
  final DateTime timestamp;
  final String? deviceId;
  final String? deviceName;
  final String message;
  final String? suggestion;
  final Map<String, dynamic>? details;

  const ConnectionError({
    required this.kind,
    required this.severity,
    required this.timestamp,
    required this.message,
    this.deviceId,
    this.deviceName,
    this.suggestion,
    this.details,
  });

  Map<String, dynamic> toJson() {
    return {
      'kind': kind,
      'severity': severity,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'message': message,
      if (deviceId != null) 'deviceId': deviceId,
      if (deviceName != null) 'deviceName': deviceName,
      if (suggestion != null) 'suggestion': suggestion,
      if (details != null) 'details': details,
    };
  }
}
```

**Step 4: Run tests, verify green**

Run: `flutter test test/controllers/connection_error_test.dart`
Expected: `+3: All tests passed!`

**Step 5: Commit**

```bash
git add lib/src/controllers/connection_error.dart \
        test/controllers/connection_error_test.dart
git commit -m "feat: add ConnectionError model and kind taxonomy"
```

---

## Task 2: Change `ConnectionStatus.error` from `String?` to `ConnectionError?`

**Files:**
- Modify: `lib/src/controllers/connection_manager.dart:25-56` (class `ConnectionStatus`)
- Modify: `lib/src/controllers/connection_manager.dart:432-438` (existing string error in `connectMachine`)
- Modify: `test/controllers/connection_manager_test.dart:134,771` (existing `isNull` assertions still hold)

**Note:** There are existing sites that set `error: () => null` in `copyWith` calls throughout `connection_manager.dart`. Those don't need updating — `null` is still a valid value.

**Step 1: Update type + import**

At the top of `lib/src/controllers/connection_manager.dart` add:

```dart
import 'package:reaprime/src/controllers/connection_error.dart';
```

Update `ConnectionStatus`:

```dart
class ConnectionStatus {
  final ConnectionPhase phase;
  final List<De1Interface> foundMachines;
  final List<Scale> foundScales;
  final AmbiguityReason? pendingAmbiguity;
  final ConnectionError? error;

  const ConnectionStatus({
    this.phase = ConnectionPhase.idle,
    this.foundMachines = const [],
    this.foundScales = const [],
    this.pendingAmbiguity,
    this.error,
  });

  ConnectionStatus copyWith({
    ConnectionPhase? phase,
    List<De1Interface>? foundMachines,
    List<Scale>? foundScales,
    AmbiguityReason? Function()? pendingAmbiguity,
    ConnectionError? Function()? error,
  }) {
    return ConnectionStatus(
      phase: phase ?? this.phase,
      foundMachines: foundMachines ?? this.foundMachines,
      foundScales: foundScales ?? this.foundScales,
      pendingAmbiguity:
          pendingAmbiguity != null ? pendingAmbiguity() : this.pendingAmbiguity,
      error: error != null ? error() : this.error,
    );
  }
}
```

**Step 2: Temporarily silence the `connectMachine` string-error site**

Replace `connection_manager.dart:432-438`:

```dart
    } catch (e) {
      _statusSubject.add(
        currentStatus.copyWith(
          phase: ConnectionPhase.idle,
          // TODO(task-5): emit structured ConnectionError here.
          error: () => null,
        ),
      );
      rethrow;
    }
```

(We'll replace `null` with a real `ConnectionError` in Task 5.)

**Step 3: Update `DevicesStateAggregator` serialization**

Modify `lib/src/services/webserver/devices_handler.dart:166`:

```dart
      'error': cs.error?.toJson(),
```

**Step 4: Run existing tests**

Run: `flutter test test/controllers/connection_manager_test.dart test/devices_handler_test.dart test/devices_ws_test.dart`
Expected: all pass — the `isNull` assertions at lines 134 and 771 still hold because we haven't wired any new emit sites yet.

Also run: `flutter analyze lib/src/controllers/connection_manager.dart lib/src/services/webserver/devices_handler.dart`
Expected: `No issues found!` (modulo pre-existing infos).

**Step 5: Commit**

```bash
git add lib/src/controllers/connection_manager.dart \
        lib/src/services/webserver/devices_handler.dart
git commit -m "refactor: make ConnectionStatus.error a structured ConnectionError"
```

---

## Task 3: Add `_emit` / `_clearError` helpers with clearing rules

**Files:**
- Modify: `lib/src/controllers/connection_manager.dart` (add private helpers + phase-transition hook)
- Modify: `test/controllers/connection_manager_test.dart` (new group)

**Step 1: Write the failing tests**

Add to `test/controllers/connection_manager_test.dart`, inside the existing `group('ConnectionManager', ...)`:

```dart
group('error surfacing', () {
  test('emitting an error publishes it on the status stream', () async {
    final future = connectionManager.status
        .firstWhere((s) => s.error != null);
    connectionManager.debugEmitError(
      kind: ConnectionErrorKind.scaleConnectFailed,
      severity: ConnectionErrorSeverity.error,
      message: 'test',
    );
    final status = await future;
    expect(status.error!.kind, ConnectionErrorKind.scaleConnectFailed);
    expect(status.error!.timestamp.isUtc, isTrue);
  });

  test('transient error clears on phase transition into scanning',
      () async {
    connectionManager.debugEmitError(
      kind: ConnectionErrorKind.scaleConnectFailed,
      severity: ConnectionErrorSeverity.error,
      message: 'test',
    );
    expect(connectionManager.currentStatus.error, isNotNull);

    await connectionManager.connect(scaleOnly: true);
    // After a scan starts and completes, transient error should be gone.
    expect(connectionManager.currentStatus.error, isNull);
  });

  test('sticky error survives phase transitions', () async {
    connectionManager.debugEmitError(
      kind: ConnectionErrorKind.adapterOff,
      severity: ConnectionErrorSeverity.error,
      message: 'off',
    );
    // Force a phase update that would normally clear transient errors.
    connectionManager.debugSetPhase(ConnectionPhase.scanning);
    expect(connectionManager.currentStatus.error, isNotNull);
    expect(connectionManager.currentStatus.error!.kind,
        ConnectionErrorKind.adapterOff);
  });
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/controllers/connection_manager_test.dart --name 'error surfacing'`
Expected: compile error — `debugEmitError` / `debugSetPhase` undefined.

**Step 3: Implement the helpers**

Add to `ConnectionManager` (keep the `@visibleForTesting` annotation on debug shims so production code doesn't call them):

```dart
import 'package:flutter/foundation.dart' show visibleForTesting;

// ...inside ConnectionManager:

void _emit(ConnectionError err) {
  _log.warning('emit error: kind=${err.kind} message=${err.message} '
      'deviceId=${err.deviceId}');
  _statusSubject.add(currentStatus.copyWith(error: () => err));
}

void _clearError() {
  if (currentStatus.error == null) return;
  _statusSubject.add(currentStatus.copyWith(error: () => null));
}

@visibleForTesting
void debugEmitError({
  required String kind,
  required String severity,
  required String message,
  String? deviceId,
  String? deviceName,
  String? suggestion,
  Map<String, dynamic>? details,
}) {
  _emit(ConnectionError(
    kind: kind,
    severity: severity,
    timestamp: DateTime.now().toUtc(),
    message: message,
    deviceId: deviceId,
    deviceName: deviceName,
    suggestion: suggestion,
    details: details,
  ));
}

@visibleForTesting
void debugSetPhase(ConnectionPhase phase) {
  _statusSubject.add(currentStatus.copyWith(phase: phase));
}
```

**Step 4: Wire clearing rule into status publication**

Instead of hooking each `_statusSubject.add` call site, gate all status publications through a helper:

```dart
// Replace raw `_statusSubject.add(next)` with this helper.
void _publishStatus(ConnectionStatus next) {
  final prev = _statusSubject.value;
  // Auto-clear transient errors on phase transitions that start a new
  // operation or reach a stable good state.
  final clearingPhases = {
    ConnectionPhase.scanning,
    ConnectionPhase.connectingMachine,
    ConnectionPhase.connectingScale,
    ConnectionPhase.ready,
  };
  ConnectionError? effectiveError = next.error;
  if (effectiveError != null &&
      !ConnectionErrorKind.sticky.contains(effectiveError.kind) &&
      prev.phase != next.phase &&
      clearingPhases.contains(next.phase)) {
    effectiveError = null;
  } else if (prev.error != null &&
      !ConnectionErrorKind.sticky.contains(prev.error!.kind) &&
      next.error == prev.error &&
      prev.phase != next.phase &&
      clearingPhases.contains(next.phase)) {
    effectiveError = null;
  }
  _statusSubject.add(next.copyWith(error: () => effectiveError));
}
```

**Replace every `_statusSubject.add(...)` inside `ConnectionManager` with `_publishStatus(...)`** — there are roughly a dozen sites. `grep -n '_statusSubject\.add' lib/src/controllers/connection_manager.dart` to enumerate.

**Step 5: Run tests**

Run: `flutter test test/controllers/connection_manager_test.dart`
Expected: all pass (existing + new `error surfacing` group).

**Step 6: Commit**

```bash
git add lib/src/controllers/connection_manager.dart \
        test/controllers/connection_manager_test.dart
git commit -m "feat: add ConnectionManager _emit helper and phase-clearing rule"
```

---

## Task 4: Emit `scaleConnectFailed` on scale connect failure

**Files:**
- Modify: `lib/src/controllers/connection_manager.dart` — `connectScale` catch block (~line 469-477)
- Modify: `test/controllers/connection_manager_test.dart` — extend the "connectScale" group

**Step 1: Write the failing test**

Add inside the existing `group('connectScale', ...)`:

```dart
test('emits scaleConnectFailed when the scale controller throws',
    () async {
  scaleController.failNextConnect = true; // existing MockScaleController hook
  final fakeScale = makeFakeScale(id: '50:78:7D:1F:AE:E1', name: 'Decent Scale');

  await connectionManager.connectScale(fakeScale);

  final err = connectionManager.currentStatus.error;
  expect(err, isNotNull);
  expect(err!.kind, ConnectionErrorKind.scaleConnectFailed);
  expect(err.deviceId, '50:78:7D:1F:AE:E1');
  expect(err.deviceName, 'Decent Scale');
  expect(err.severity, ConnectionErrorSeverity.error);
});

test('emits with fbp_code in details for FlutterBluePlusException',
    () async {
  scaleController.failNextConnectWith =
      FlutterBluePlusException(ErrorPlatform.fbp, 'connect', 1, 'Timed out');
  final fakeScale = makeFakeScale(id: '50:78:7D:1F:AE:E1', name: 'Decent Scale');

  await connectionManager.connectScale(fakeScale);

  final err = connectionManager.currentStatus.error!;
  expect(err.details, containsPair('fbp_code', 1));
});
```

**Check `test/helpers/mock_scale_controller.dart`** — `failNextConnect` may already exist; `failNextConnectWith` may need adding. Add it:

```dart
// test/helpers/mock_scale_controller.dart
Object? failNextConnectWith;

@override
Future<void> connectToScale(Scale scale) async {
  if (failNextConnectWith != null) {
    final e = failNextConnectWith;
    failNextConnectWith = null;
    throw e!;
  }
  if (failNextConnect) {
    failNextConnect = false;
    throw StateError('mock fail');
  }
  // existing success path...
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/controllers/connection_manager_test.dart --name 'scaleConnectFailed'`
Expected: FAIL — `error` is still `null` in catch block.

**Step 3: Implement emission in `connectScale` catch**

Replace the existing catch in `connectScale` (`connection_manager.dart:~469-477`):

```dart
} catch (e) {
  _emit(_buildConnectError(
    kind: ConnectionErrorKind.scaleConnectFailed,
    deviceId: scale.deviceId,
    deviceName: scale.name,
    message: 'Scale ${scale.name} failed to connect.',
    suggestion:
        'Wake the scale and try again. If the problem persists, '
        'toggle Bluetooth off and on.',
    exception: e,
  ));
  _publishStatus(
    currentStatus.copyWith(
      phase:
          _machineConnected ? ConnectionPhase.ready : ConnectionPhase.idle,
    ),
  );
} finally {
  _isConnectingScale = false;
}
```

Add the helper method on `ConnectionManager`:

```dart
ConnectionError _buildConnectError({
  required String kind,
  required String deviceId,
  required String deviceName,
  required String message,
  String? suggestion,
  required Object exception,
}) {
  Map<String, dynamic>? details;
  if (exception is FlutterBluePlusException) {
    details = {
      'fbp_code': exception.code,
      if (exception.description != null) 'fbp_description': exception.description,
    };
  } else {
    details = {'exception': exception.toString()};
  }
  return ConnectionError(
    kind: kind,
    severity: ConnectionErrorSeverity.error,
    timestamp: DateTime.now().toUtc(),
    deviceId: deviceId,
    deviceName: deviceName,
    message: message,
    suggestion: suggestion,
    details: details,
  );
}
```

Add import at top of `connection_manager.dart`:

```dart
import 'package:flutter_blue_plus/flutter_blue_plus.dart'
    show FlutterBluePlusException;
```

**Step 4: Run tests**

Run: `flutter test test/controllers/connection_manager_test.dart`
Expected: all pass.

**Step 5: Commit**

```bash
git add lib/src/controllers/connection_manager.dart \
        test/controllers/connection_manager_test.dart \
        test/helpers/mock_scale_controller.dart
git commit -m "feat: emit scaleConnectFailed on scale connect failure"
```

---

## Task 5: Emit `machineConnectFailed` on machine connect failure

**Files:**
- Modify: `lib/src/controllers/connection_manager.dart` — `connectMachine` catch block (~line 432-438)
- Modify: `test/controllers/connection_manager_test.dart` — extend the "connectMachine" group

**Step 1: Write the failing test**

Add inside `group('connectMachine', ...)`:

```dart
test('emits machineConnectFailed on De1Controller.connectToDe1 throw',
    () async {
  de1Controller.failNextConnect = true; // MockDe1Controller hook
  final fakeDe1 = makeFakeDe1(id: 'D9:11:0B:E6:9F:86', name: 'DE1');

  expect(
    () => connectionManager.connectMachine(fakeDe1),
    throwsA(isA<Object>()),
  );
  // Wait a microtask so the catch block's _publishStatus runs.
  await Future<void>.delayed(Duration.zero);

  final err = connectionManager.currentStatus.error!;
  expect(err.kind, ConnectionErrorKind.machineConnectFailed);
  expect(err.deviceId, 'D9:11:0B:E6:9F:86');
});
```

Confirm `MockDe1Controller.failNextConnect` exists; add if missing (pattern mirrors `MockScaleController`).

**Step 2: Run test, verify fail**

Run: `flutter test test/controllers/connection_manager_test.dart --name 'machineConnectFailed'`
Expected: FAIL — `err` is null because the catch currently emits `error: () => null` (the TODO from Task 2).

**Step 3: Implement emission**

Replace the catch block in `connectMachine`:

```dart
} catch (e) {
  _emit(_buildConnectError(
    kind: ConnectionErrorKind.machineConnectFailed,
    deviceId: machine.deviceId,
    deviceName: machine.name,
    message: 'Machine ${machine.name} failed to connect.',
    suggestion:
        'Make sure the DE1 is powered on and in range, then retry.',
    exception: e,
  ));
  _publishStatus(currentStatus.copyWith(phase: ConnectionPhase.idle));
  rethrow;
} finally {
  _isConnectingMachine = false;
}
```

**Note:** `rethrow` must be preserved — callers (`_connectMachineTracked`) catch this to mark scan-report devices as failed.

**Step 4: Run tests**

Run: `flutter test test/controllers/connection_manager_test.dart`
Expected: all pass.

**Step 5: Commit**

```bash
git add lib/src/controllers/connection_manager.dart \
        test/controllers/connection_manager_test.dart \
        test/helpers/mock_de1_controller.dart
git commit -m "feat: emit machineConnectFailed on DE1 connect failure"
```

---

## Task 6: Deliberate-disconnect tracking (`_expectingDisconnectFor`)

**Files:**
- Modify: `lib/src/controllers/connection_manager.dart`
- Modify: `test/controllers/connection_manager_test.dart`

**Step 1: Write the failing tests**

```dart
group('deliberate disconnect tracking', () {
  test('markExpectingDisconnect suppresses next disconnect error',
      () {
    connectionManager
        .markExpectingDisconnect('50:78:7D:1F:AE:E1');
    // Simulate the scale disconnect subscriber firing.
    connectionManager.debugNotifyScaleDisconnected('50:78:7D:1F:AE:E1');
    expect(connectionManager.currentStatus.error, isNull);
  });

  test('unexpected disconnect emits scaleDisconnected', () {
    connectionManager.debugNotifyScaleDisconnected('50:78:7D:1F:AE:E1');
    expect(connectionManager.currentStatus.error?.kind,
        ConnectionErrorKind.scaleDisconnected);
  });

  test('TTL clears expectation after 10 seconds', () {
    fakeAsync((async) {
      connectionManager.markExpectingDisconnect('50:78:7D:1F:AE:E1');
      async.elapse(const Duration(seconds: 11));
      connectionManager.debugNotifyScaleDisconnected('50:78:7D:1F:AE:E1');
      expect(connectionManager.currentStatus.error?.kind,
          ConnectionErrorKind.scaleDisconnected);
    });
  });

  test('only one matching disconnect is consumed per mark', () {
    connectionManager.markExpectingDisconnect('50:78:7D:1F:AE:E1');
    connectionManager.debugNotifyScaleDisconnected('50:78:7D:1F:AE:E1');
    expect(connectionManager.currentStatus.error, isNull);
    connectionManager.debugNotifyScaleDisconnected('50:78:7D:1F:AE:E1');
    expect(connectionManager.currentStatus.error?.kind,
        ConnectionErrorKind.scaleDisconnected);
  });
});
```

Add imports at the top of the test file:

```dart
import 'package:fake_async/fake_async.dart';
```

Add `fake_async` to `dev_dependencies` in `pubspec.yaml` if not already present (`flutter pub add --dev fake_async`).

**Step 2: Run tests, verify fail**

Run: `flutter test test/controllers/connection_manager_test.dart --name 'deliberate disconnect tracking'`
Expected: compile error — methods not defined.

**Step 3: Implement**

Add to `ConnectionManager`:

```dart
final Set<String> _expectingDisconnectFor = {};
final Map<String, Timer> _expectingDisconnectTimers = {};

void markExpectingDisconnect(String deviceId) {
  _expectingDisconnectFor.add(deviceId);
  _expectingDisconnectTimers[deviceId]?.cancel();
  _expectingDisconnectTimers[deviceId] =
      Timer(const Duration(seconds: 10), () {
    _expectingDisconnectFor.remove(deviceId);
    _expectingDisconnectTimers.remove(deviceId);
  });
}

bool _consumeExpectingDisconnect(String deviceId) {
  final wasExpecting = _expectingDisconnectFor.remove(deviceId);
  if (wasExpecting) {
    _expectingDisconnectTimers.remove(deviceId)?.cancel();
  }
  return wasExpecting;
}

@visibleForTesting
void debugNotifyScaleDisconnected(String deviceId) {
  _handleScaleDisconnect(deviceId);
}

@visibleForTesting
void debugNotifyMachineDisconnected(String deviceId) {
  _handleMachineDisconnect(deviceId);
}

void _handleScaleDisconnect(String deviceId) {
  if (_consumeExpectingDisconnect(deviceId)) {
    _log.fine('Scale $deviceId: expected disconnect, suppressing error');
    return;
  }
  _emit(ConnectionError(
    kind: ConnectionErrorKind.scaleDisconnected,
    severity: ConnectionErrorSeverity.error,
    timestamp: DateTime.now().toUtc(),
    deviceId: deviceId,
    message: 'Scale disconnected unexpectedly.',
    suggestion:
        'The scale may have powered off or moved out of range. '
        'Wake the scale and reconnect.',
  ));
}

void _handleMachineDisconnect(String deviceId) {
  if (_consumeExpectingDisconnect(deviceId)) {
    _log.fine('Machine $deviceId: expected disconnect, suppressing error');
    return;
  }
  _emit(ConnectionError(
    kind: ConnectionErrorKind.machineDisconnected,
    severity: ConnectionErrorSeverity.error,
    timestamp: DateTime.now().toUtc(),
    deviceId: deviceId,
    message: 'Machine disconnected unexpectedly.',
    suggestion:
        'Check the machine is powered on and in range, then '
        'reconnect.',
  ));
}

// Clean up in dispose():
void dispose() {
  // ...existing...
  for (final t in _expectingDisconnectTimers.values) {
    t.cancel();
  }
  _expectingDisconnectTimers.clear();
  _expectingDisconnectFor.clear();
}
```

**Step 4: Run tests**

Run: `flutter test test/controllers/connection_manager_test.dart`
Expected: all pass.

**Step 5: Commit**

```bash
git add lib/src/controllers/connection_manager.dart \
        test/controllers/connection_manager_test.dart \
        pubspec.yaml pubspec.lock
git commit -m "feat: add deliberate-disconnect tracking with TTL cleanup"
```

---

## Task 7: Wire mid-session disconnect subscriber to the new handlers

**Files:**
- Modify: `lib/src/controllers/connection_manager.dart:98-117` (`_listenForDisconnects`)

**Step 1: Augment the existing subscribers**

Replace `_listenForDisconnects` body:

```dart
void _listenForDisconnects() {
  // Watch de1Controller.de1 stream — null means machine disconnected.
  String? lastKnownMachineId;
  _machineDisconnectSub = de1Controller.de1.listen((de1) {
    if (de1 != null) {
      lastKnownMachineId = de1.deviceId;
      return;
    }
    if (_machineConnected && !_isConnectingMachine) {
      _log.fine('Machine disconnected');
      _machineConnected = false;
      _publishStatus(currentStatus.copyWith(phase: ConnectionPhase.idle));
      if (lastKnownMachineId != null) {
        _handleMachineDisconnect(lastKnownMachineId!);
      }
    }
  });

  // Watch scaleController.connectionState — disconnected resets flag
  // AND emits scaleDisconnected unless suppressed.
  _scaleDisconnectSub = scaleController.connectionState.listen((state) {
    final wasConnected = _scaleConnected;
    _scaleConnected = state == device.ConnectionState.connected;
    _log.fine("scale connection update: $_scaleConnected");
    if (wasConnected && state == device.ConnectionState.disconnected) {
      // Grab device id from ScaleController — if it still has _scale
      // reference use it; otherwise fall back to preferredScaleId.
      final id = scaleController.lastConnectedDeviceId ??
          settingsController.preferredScaleId;
      if (id != null) {
        _handleScaleDisconnect(id);
      }
    }
  });
}
```

**Note:** `ScaleController.lastConnectedDeviceId` does not exist — add it as a simple field in `ScaleController` that caches the deviceId of the most recent `_scale` for use after `_onDisconnect` has cleared `_scale`:

```dart
// lib/src/controllers/scale_controller.dart
String? _lastConnectedDeviceId;
String? get lastConnectedDeviceId => _lastConnectedDeviceId;

// In connectToScale after successful state check:
_lastConnectedDeviceId = scale.deviceId;
```

**Step 2: Extend `connectScale` / `connectMachine` to use `markExpectingDisconnect`**

Audit the following call sites that deliberately disconnect and add `markExpectingDisconnect` immediately before:

- `lib/src/controllers/de1_state_manager.dart` — the `scalePowerMode == disconnect` branch that calls `scale.disconnect()` (grep for `scale.disconnect()`).
- Any explicit `_de1Controller.disconnect()` or similar teardown paths. `grep -rn "disconnect()" lib/src/controllers/ | grep -v connectionState`

Example for the sleep-flow scale disconnect in `de1_state_manager.dart:257`:

```dart
} else if (scalePowerMode == ScalePowerMode.disconnect) {
  _connectionManager.markExpectingDisconnect(scale.deviceId);
  scale.disconnect().catchError((e) {
    _logger.warning('Failed to disconnect scale: $e');
  });
}
```

Add the `_connectionManager` field/constructor parameter to `De1StateManager` if not already present, and wire through in `main.dart` construction.

**Step 3: Write an integration test**

Add to `test/controllers/connection_manager_test.dart`:

```dart
test('scale disconnect during sleep flow does not emit error', () async {
  // Simulate: app marks expected disconnect, then scale controller
  // emits disconnected.
  connectionManager.markExpectingDisconnect('50:78:7D:1F:AE:E1');
  scaleController.mockEmitConnectionState(
      device.ConnectionState.disconnected);
  await Future<void>.delayed(Duration.zero);
  expect(connectionManager.currentStatus.error, isNull);
});

test('unexpected scale disconnect emits scaleDisconnected', () async {
  // First pretend scale is connected.
  scaleController.mockEmitConnectionState(device.ConnectionState.connected);
  scaleController.debugSetLastConnectedId('50:78:7D:1F:AE:E1');
  await Future<void>.delayed(Duration.zero);
  // Then drop without marking.
  scaleController.mockEmitConnectionState(
      device.ConnectionState.disconnected);
  await Future<void>.delayed(Duration.zero);
  expect(connectionManager.currentStatus.error?.kind,
      ConnectionErrorKind.scaleDisconnected);
});
```

Add matching shims to `MockScaleController`:

```dart
String? _mockLastConnectedDeviceId;
@override
String? get lastConnectedDeviceId => _mockLastConnectedDeviceId;

void debugSetLastConnectedId(String id) {
  _mockLastConnectedDeviceId = id;
}

void mockEmitConnectionState(device.ConnectionState state) {
  _connectionController.add(state);
}
```

**Step 4: Run tests**

Run: `flutter test test/controllers/`
Expected: all pass.

Run: `flutter analyze lib/src/controllers/`
Expected: no new errors.

**Step 5: Commit**

```bash
git add lib/src/controllers/connection_manager.dart \
        lib/src/controllers/scale_controller.dart \
        lib/src/controllers/de1_state_manager.dart \
        lib/src/main.dart \
        test/controllers/connection_manager_test.dart \
        test/helpers/mock_scale_controller.dart
git commit -m "feat: emit scaleDisconnected / machineDisconnected on unexpected drops"
```

---

## Task 8: Adapter state subscription + `adapterOff` emission

**Files:**
- Modify: `lib/src/controllers/connection_manager.dart`
- Modify: `test/controllers/connection_manager_test.dart`

**Step 1: Verify the scanner exposes adapter state**

`DeviceScanner` aggregates multiple discovery services. For this pass, we only care about BLE. Locate the source:

```bash
rg -n 'adapterStateStream' lib/src
```

If `DeviceScanner` doesn't already expose `adapterStateStream`, plumb through the Ble one — preferred approach: pass `BleDiscoveryService` directly into `ConnectionManager` constructor, or expose `adapterStateStream` on `DeviceScanner` as a passthrough. Choose the passthrough — smaller diff.

**Step 2: Write the failing test**

```dart
group('adapter state', () {
  test('adapter off emits adapterOff error', () async {
    deviceScanner.mockAdapterState(AdapterState.off);
    await Future<void>.delayed(Duration.zero);
    expect(connectionManager.currentStatus.error?.kind,
        ConnectionErrorKind.adapterOff);
  });

  test('adapter on clears adapterOff', () async {
    deviceScanner.mockAdapterState(AdapterState.off);
    await Future<void>.delayed(Duration.zero);
    deviceScanner.mockAdapterState(AdapterState.on);
    await Future<void>.delayed(Duration.zero);
    expect(connectionManager.currentStatus.error, isNull);
  });

  test('adapter on does NOT clear an unrelated transient error',
      () async {
    connectionManager.debugEmitError(
      kind: ConnectionErrorKind.scaleConnectFailed,
      severity: ConnectionErrorSeverity.error,
      message: 'x',
    );
    deviceScanner.mockAdapterState(AdapterState.on);
    await Future<void>.delayed(Duration.zero);
    expect(connectionManager.currentStatus.error?.kind,
        ConnectionErrorKind.scaleConnectFailed);
  });
});
```

Add `mockAdapterState` to the test device scanner (or use the real `BleDiscoveryService` fake, depending on existing test wiring).

**Step 3: Implement**

Add to `ConnectionManager`:

```dart
StreamSubscription<AdapterState>? _adapterSub;

// In _listenForDisconnects (or new _listenForAdapter):
_adapterSub = deviceScanner.adapterStateStream.listen((state) {
  if (state == AdapterState.off) {
    _emit(ConnectionError(
      kind: ConnectionErrorKind.adapterOff,
      severity: ConnectionErrorSeverity.error,
      timestamp: DateTime.now().toUtc(),
      message: 'Bluetooth is turned off.',
      suggestion: 'Turn Bluetooth on to scan for devices.',
    ));
  } else if (state == AdapterState.on &&
      currentStatus.error?.kind == ConnectionErrorKind.adapterOff) {
    _clearError();
  }
});
```

Cancel in `dispose()`.

**Step 4: Run tests**

Run: `flutter test test/controllers/connection_manager_test.dart`
Expected: all pass.

**Step 5: Commit**

```bash
git add lib/src/controllers/connection_manager.dart \
        test/controllers/connection_manager_test.dart \
        test/helpers/mock_device_scanner.dart
git commit -m "feat: emit adapterOff and clear on recovery"
```

---

## Task 9: Classify scan-start failures into `scanFailed` / `bluetoothPermissionDenied`

**Files:**
- Modify: `lib/src/controllers/connection_manager.dart` — `_connectImpl` scan-start section (~line 226-234)
- Modify: `test/controllers/connection_manager_test.dart`

**Step 1: Write failing test**

```dart
group('scan failures', () {
  test('scan throwing permission error emits bluetoothPermissionDenied',
      () async {
    deviceScanner.failNextScanWith = PermissionDeniedException();
    await connectionManager.connect(scaleOnly: true);
    expect(connectionManager.currentStatus.error?.kind,
        ConnectionErrorKind.bluetoothPermissionDenied);
  });

  test('scan throwing generic error emits scanFailed', () async {
    deviceScanner.failNextScanWith = Exception('adapter busy');
    await connectionManager.connect(scaleOnly: true);
    expect(connectionManager.currentStatus.error?.kind,
        ConnectionErrorKind.scanFailed);
  });
});
```

Add hook to the test scanner. Use `permission_handler`'s exception type or a project-defined `PermissionDeniedException` (check `rg -n "PermissionDenied"`). If none exists, define one in `lib/src/models/errors.dart`.

**Step 2: Implement classification around `scanForDevices()`**

Replace `_connectImpl` scan-start section. Wrap `deviceScanner.scanForDevices()` in try/catch:

```dart
try {
  deviceScanner.scanForDevices();
  await deviceScanner.scanningStream.firstWhere((s) => s);
} catch (e) {
  sub.cancel();
  final kind = _classifyScanError(e);
  _emit(ConnectionError(
    kind: kind,
    severity: ConnectionErrorSeverity.error,
    timestamp: DateTime.now().toUtc(),
    message: kind == ConnectionErrorKind.bluetoothPermissionDenied
        ? 'Bluetooth permission was denied.'
        : 'Failed to start Bluetooth scan.',
    suggestion: kind == ConnectionErrorKind.bluetoothPermissionDenied
        ? 'Grant Bluetooth permission in system settings and retry.'
        : 'Check that Bluetooth is enabled and retry.',
    details: {'exception': e.toString()},
  ));
  _publishStatus(currentStatus.copyWith(phase: ConnectionPhase.idle));
  return;
}
await deviceScanner.scanningStream.firstWhere((s) => !s);
sub.cancel();
```

```dart
String _classifyScanError(Object e) {
  if (e is PermissionDeniedException) {
    return ConnectionErrorKind.bluetoothPermissionDenied;
  }
  final msg = e.toString().toLowerCase();
  if (msg.contains('permission')) {
    return ConnectionErrorKind.bluetoothPermissionDenied;
  }
  return ConnectionErrorKind.scanFailed;
}
```

**Step 3: Run tests**

Run: `flutter test test/controllers/connection_manager_test.dart`
Expected: all pass.

**Step 4: Commit**

```bash
git add lib/src/controllers/connection_manager.dart \
        test/controllers/connection_manager_test.dart \
        test/helpers/mock_device_scanner.dart \
        lib/src/models/errors.dart
git commit -m "feat: classify scan-start failures into scanFailed / bluetoothPermissionDenied"
```

---

## Task 10: Widen `DevicesStateAggregator` test coverage for structured error

**Files:**
- Modify: `test/devices_handler_test.dart`

**Step 1: Write tests**

```dart
test('snapshot serializes structured ConnectionError', () async {
  final cm = FakeConnectionManager();
  cm.setError(ConnectionError(
    kind: ConnectionErrorKind.scaleConnectFailed,
    severity: ConnectionErrorSeverity.error,
    timestamp: DateTime.utc(2026, 4, 19),
    deviceId: '50:78:7D:1F:AE:E1',
    deviceName: 'Decent Scale',
    message: 'fail',
  ));
  final agg = DevicesStateAggregator(
    controller: /* fake */,
    connectionManager: cm,
  );
  final snapshot = agg.buildSnapshot();
  expect(snapshot['connectionStatus']['error'], {
    'kind': 'scaleConnectFailed',
    'severity': 'error',
    'timestamp': '2026-04-19T00:00:00.000Z',
    'deviceId': '50:78:7D:1F:AE:E1',
    'deviceName': 'Decent Scale',
    'message': 'fail',
  });
});

test('snapshot error is null when no error set', () {
  final cm = FakeConnectionManager();
  final agg = DevicesStateAggregator(...);
  expect(agg.buildSnapshot()['connectionStatus']['error'], isNull);
});
```

Build out `FakeConnectionManager` in the existing helper file for this test.

**Step 2: Run, verify green**

Run: `flutter test test/devices_handler_test.dart`
Expected: pass.

**Step 3: Commit**

```bash
git add test/devices_handler_test.dart
git commit -m "test: cover DevicesStateAggregator structured-error serialization"
```

---

## Task 11: Native UI — `ConnectionErrorBanner` widget

**Files:**
- Create: `lib/src/shared/connection_error_banner.dart`
- Test: `test/shared/connection_error_banner_test.dart`

**Step 1: Write the widget test**

```dart
// test/shared/connection_error_banner_test.dart
testWidgets('renders when status.error != null', (tester) async {
  final cm = FakeConnectionManager();
  cm.setError(ConnectionError(
    kind: ConnectionErrorKind.scaleConnectFailed,
    severity: ConnectionErrorSeverity.error,
    timestamp: DateTime.now().toUtc(),
    message: 'Scale connect failed.',
    suggestion: 'Retry.',
    deviceName: 'Decent Scale',
  ));

  await tester.pumpWidget(ShadApp(
    home: Scaffold(body: ConnectionErrorBanner(connectionManager: cm)),
  ));
  await tester.pump();

  expect(find.textContaining('Scale connect failed'), findsOneWidget);
  expect(find.textContaining('Retry'), findsOneWidget);
  expect(find.textContaining('Decent Scale'), findsOneWidget);
});

testWidgets('hides when status.error is null', (tester) async {
  final cm = FakeConnectionManager(); // no error set
  await tester.pumpWidget(ShadApp(
    home: Scaffold(body: ConnectionErrorBanner(connectionManager: cm)),
  ));
  expect(find.byType(ShadAlert), findsNothing);
});

testWidgets('retry button dispatches a scan', (tester) async {
  final cm = FakeConnectionManager();
  cm.setError(ConnectionError(
    kind: ConnectionErrorKind.scaleConnectFailed,
    severity: ConnectionErrorSeverity.error,
    timestamp: DateTime.now().toUtc(),
    message: 'x',
    deviceName: 'Decent Scale',
  ));
  await tester.pumpWidget(ShadApp(
    home: Scaffold(body: ConnectionErrorBanner(connectionManager: cm)),
  ));
  await tester.pump();

  await tester.tap(find.text('Retry'));
  await tester.pump();

  expect(cm.connectCalls, 1);
});
```

**Step 2: Implement**

```dart
// lib/src/shared/connection_error_banner.dart
import 'package:flutter/material.dart';
import 'package:reaprime/src/controllers/connection_error.dart';
import 'package:reaprime/src/controllers/connection_manager.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class ConnectionErrorBanner extends StatelessWidget {
  final ConnectionManager connectionManager;

  const ConnectionErrorBanner({super.key, required this.connectionManager});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ConnectionStatus>(
      stream: connectionManager.status,
      initialData: connectionManager.currentStatus,
      builder: (context, snapshot) {
        final err = snapshot.data?.error;
        if (err == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.all(12),
          child: ShadAlert.destructive(
            title: Text(_title(err)),
            description: Text(_body(err)),
            iconData: _icon(err),
            // Retry button for transient kinds with a device in play.
            // (See docs for kind → action map.)
          ),
        );
      },
    );
  }

  String _title(ConnectionError err) {
    final name = err.deviceName;
    switch (err.kind) {
      case ConnectionErrorKind.scaleConnectFailed:
        return name != null ? 'Failed to connect $name' : 'Scale connect failed';
      case ConnectionErrorKind.machineConnectFailed:
        return name != null ? 'Failed to connect $name' : 'Machine connect failed';
      case ConnectionErrorKind.scaleDisconnected:
        return name != null ? '$name disconnected' : 'Scale disconnected';
      case ConnectionErrorKind.machineDisconnected:
        return name != null ? '$name disconnected' : 'Machine disconnected';
      case ConnectionErrorKind.adapterOff:
        return 'Bluetooth is off';
      case ConnectionErrorKind.bluetoothPermissionDenied:
        return 'Bluetooth permission required';
      case ConnectionErrorKind.scanFailed:
        return 'Scan failed';
      default:
        return 'Connection problem';
    }
  }

  String _body(ConnectionError err) {
    final msg = err.message;
    final sug = err.suggestion;
    return sug != null ? '$msg\n$sug' : msg;
  }

  IconData _icon(ConnectionError err) {
    switch (err.kind) {
      case ConnectionErrorKind.adapterOff:
        return Icons.bluetooth_disabled;
      case ConnectionErrorKind.bluetoothPermissionDenied:
        return Icons.lock_outline;
      default:
        return Icons.warning_amber_outlined;
    }
  }
}
```

For the retry button, extend the widget to wrap the alert in a Column containing a `ShadButton.outline` that calls `connectionManager.connect()`. Keep the primary-action wiring local — only the five kinds in the design doc's action table trigger retry.

**Step 3: Run tests**

Run: `flutter test test/shared/connection_error_banner_test.dart`
Expected: pass.

**Step 4: Commit**

```bash
git add lib/src/shared/connection_error_banner.dart \
        test/shared/connection_error_banner_test.dart
git commit -m "feat: add ConnectionErrorBanner widget"
```

---

## Task 12: Mount banner in `DeviceDiscoveryView` and `HomeView`

**Files:**
- Modify: `lib/src/device_discovery_feature/device_discovery_view.dart`
- Modify: `lib/src/home_feature/home_view.dart`
- Modify: `test/device_discovery_view_test.dart`

**Step 1: Add banner to `DeviceDiscoveryView`**

Drop a `ConnectionErrorBanner(connectionManager: ...)` at the top of the Scaffold body, below any AppBar.

**Step 2: Add banner to `HomeView`**

Same — top of the body. Exclusion: if `HomeView` is hosting a fullscreen `SkinView`, skip the banner (skin owns UX).

Pseudocode:

```dart
Column(
  children: [
    if (!isSkinActive) ConnectionErrorBanner(connectionManager: cm),
    // ...rest of the view
  ],
)
```

**Step 3: Extend view test**

In `test/device_discovery_view_test.dart`, after an existing setup, inject a failing connection state and verify the banner renders:

```dart
testWidgets('shows ConnectionErrorBanner when error present',
    (tester) async {
  final cm = FakeConnectionManager();
  cm.setError(ConnectionError(
    kind: ConnectionErrorKind.scaleConnectFailed,
    severity: ConnectionErrorSeverity.error,
    timestamp: DateTime.now().toUtc(),
    message: 'Scale connect timed out.',
  ));

  await tester.pumpWidget(wrapWithApp(
    DeviceDiscoveryView(connectionManager: cm, /* other deps */),
  ));
  await tester.pump();

  expect(find.byType(ConnectionErrorBanner), findsOneWidget);
  expect(find.textContaining('Scale connect timed out'), findsOneWidget);
});
```

**Step 4: Run tests**

Run: `flutter test test/device_discovery_view_test.dart`
Expected: pass.

Run app in simulator: `flutter run --dart-define=simulate=1` — manually verify the banner shows if you force an error (e.g., via a debug menu or by setting one directly if dev tooling is available). Document the manual-verification step.

**Step 5: Commit**

```bash
git add lib/src/device_discovery_feature/device_discovery_view.dart \
        lib/src/home_feature/home_view.dart \
        test/device_discovery_view_test.dart
git commit -m "feat: mount ConnectionErrorBanner in device discovery and home views"
```

---

## Task 13: Update AsyncAPI + OpenAPI specs

**Files:**
- Modify: `assets/api/websocket_v1.yml`
- Modify: `assets/api/rest_v1.yml`

**Step 1: Add `ConnectionError` schema to `websocket_v1.yml`**

Under `components/schemas`, add:

```yaml
ConnectionError:
  type: object
  required: [kind, severity, timestamp, message]
  properties:
    kind:
      type: string
      description: >
        Error kind identifier. Skins should look up localized copy
        by this field. Initial set:
        scaleConnectFailed, machineConnectFailed,
        scaleDisconnected, machineDisconnected,
        adapterOff, bluetoothPermissionDenied, scanFailed.
        New kinds may be added without a version bump.
    severity:
      type: string
      enum: [warning, error]
    timestamp:
      type: string
      format: date-time
    deviceId:
      type: string
      nullable: true
    deviceName:
      type: string
      nullable: true
    message:
      type: string
      description: App-supplied English default message.
    suggestion:
      type: string
      nullable: true
      description: App-supplied English default suggestion for the user.
    details:
      type: object
      additionalProperties: true
      nullable: true
      description: Freeform diagnostic payload; shape varies by kind.
```

Update `ConnectionStatus` schema to reference `ConnectionError` for the `error` field (replace the plain string).

**Step 2: Apply the same change in `rest_v1.yml`**

Find the `/api/v1/devices` response schema and replace `error: string` with a `$ref` to the same shape (either duplicate the schema or extract to a shared definitions file if the project already does that — grep `ConnectionStatus` to decide).

**Step 3: Verify spec validity**

If project has a spec-lint script: run it. Otherwise:

```bash
# Basic YAML parse sanity
python -c "import yaml; yaml.safe_load(open('assets/api/websocket_v1.yml'))"
python -c "import yaml; yaml.safe_load(open('assets/api/rest_v1.yml'))"
```

Expected: no output (success).

**Step 4: Commit**

```bash
git add assets/api/websocket_v1.yml assets/api/rest_v1.yml
git commit -m "docs(api): add ConnectionError schema and wire into ConnectionStatus"
```

---

## Task 14: Update narrative docs

**Files:**
- Modify: `doc/Api.md`
- Modify: `doc/Skins.md`
- Modify: `doc/DeviceManagement.md`

**`doc/Api.md`:** Under the `/api/v1/devices` / `ws/v1/devices` section, document the new `connectionStatus.error` object shape. Link out to the taxonomy.

**`doc/Skins.md`:** New section "Handling connection errors" — paste the skin contract + kind→action table verbatim from the design doc. Include an end-to-end code example:

```js
ws.addEventListener('message', (e) => {
  const msg = JSON.parse(e.data);
  const err = msg.connectionStatus?.error;
  if (!err) { hideBanner(); return; }
  if (err.timestamp !== lastSeen) {
    lastSeen = err.timestamp;
    toast(copyForKind(err.kind) ?? `${err.message}\n${err.suggestion ?? ''}`);
  }
  showBanner(copyForKind(err.kind) ?? err.message);
});
```

**`doc/DeviceManagement.md`:** One paragraph explaining the emission model and a pointer to `_expectingDisconnectFor` for future contributors wiring up new deliberate-disconnect call sites.

**Verification:**

```bash
flutter analyze
```

Expected: no new issues.

**Commit:**

```bash
git add doc/Api.md doc/Skins.md doc/DeviceManagement.md
git commit -m "docs: document BLE error surfacing for API consumers and skins"
```

---

## Task 15: End-to-end scenario doc

**Files:**
- Create: `.agents/skills/streamline-bridge/scenarios/ble-error-surfacing.md`

**Step 1: Write the scenario recipe**

Paste the bullet list from the design doc's Testing / E2E section and flesh out each with concrete `sb-dev` + `curl` + `websocat` commands. Follow the pattern of the existing scenarios (grep `scenarios/` for a template).

Key scenarios to document:

1. Adapter off → `adapterOff`, then on → clear.
2. Scale connect timeout while scale is physically off → `scaleConnectFailed`.
3. Sleep flow with `ScalePowerMode.disconnect` → no error emitted.
4. Force a machine drop via `ScalePowerMode.displayOff` + range change → `machineDisconnected`.

**Step 2: Commit**

```bash
git add .agents/skills/streamline-bridge/scenarios/ble-error-surfacing.md
git commit -m "docs(scenarios): add BLE error surfacing e2e recipes"
```

---

## Task 16: Full-suite regression pass + PR prep

**Step 1: Run the full test suite**

```bash
flutter test
```

Expected: all green. If anything flakes, stop and fix before moving on.

**Step 2: Analyze**

```bash
flutter analyze
```

Expected: no new errors or warnings introduced by this change set.

**Step 3: Archive the plan + design doc**

Move into a meaningful subfolder under `doc/plans/archive/`:

```bash
mkdir -p doc/plans/archive/ble-error-surfacing
git mv doc/plans/2026-04-19-ble-error-surfacing.md \
       doc/plans/archive/ble-error-surfacing/
git mv doc/plans/2026-04-19-ble-error-surfacing-design.md \
       doc/plans/archive/ble-error-surfacing/
git commit -m "docs: archive ble-error-surfacing plan and design"
```

**Step 4: Prepare PR body**

Use the project's tight PR style (per `CLAUDE.md`): what + why only.

**What:**
- Structured `ConnectionError` replaces `String?` on `ConnectionStatus`.
- `ConnectionManager` emits errors for connect/disconnect/adapter paths; skins see them on `ws/v1/devices`.
- Deliberate-disconnect suppression via `markExpectingDisconnect` + 10s TTL.
- Native `ConnectionErrorBanner` widget mounted in discovery + home views.
- API specs + skin docs updated.

**Why:**
Today, BLE failures are swallowed silently and the only recovery path is restarting the app (example: 07:49 UTC timeout on m50mini 2026-04-19). Skins and the native UI now get a structured, sticky-when-needed signal they can display.

**Step 5: Push and open PR — ONLY when user says so.**

Do not push without explicit confirmation.

---

## Verification checklist (before PR)

- [ ] All unit tests pass: `flutter test`
- [ ] `flutter analyze` clean (no new issues)
- [ ] `ws/v1/devices` on a real device emits the new shape when forced to fail (manual sb-dev scenario)
- [ ] Native banner appears in `simulate=1` run
- [ ] API specs validate as YAML
- [ ] Docs updated: Api.md, Skins.md, DeviceManagement.md, scenarios/
- [ ] Plan + design doc archived under `doc/plans/archive/ble-error-surfacing/`

---

## Out of scope (explicitly deferred)

- Auto-reconnect logic
- Operation-level errors (writes, reads, profile upload)
- Skin `ackError` command
- Troubleshooting wizard integration
- i18n of server-side messages

These belong to follow-up designs.
