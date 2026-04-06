# Shot Scale Disconnect Recovery Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Gracefully handle scale disconnection mid-shot so stop-at-weight disables cleanly instead of using stale data or crashing.

**Architecture:** ShotController currently decides scale availability once at construction time and never re-evaluates. We add a `scaleController.connectionState` listener that sets a `_scaleLost` flag when the scale disconnects during an active shot (`preheating`, `pouring`, or `stopping`). All scale interactions (SAW checks, tare, timer commands) are gated on this flag. The `withLatestFrom` stream keeps flowing (machine data is still valuable) but scale data in snapshots is ignored once the flag is set.

**Tech Stack:** Dart, Flutter, RxDart (BehaviorSubject, withLatestFrom), fake_async for testing

---

## Background

### The bug

`ShotController` constructor (line 49-78 of `lib/src/controllers/shot_controller.dart`) checks scale connectivity once:

```dart
final scaleConnected =
    scaleController.currentConnectionState == device.ConnectionState.connected;
```

If connected, it creates a combined stream via `withLatestFrom`. When the scale disconnects mid-shot:

1. **Stale weight data:** `withLatestFrom` keeps emitting the last known `WeightSnapshot`. SAW decisions use stale weight — could over-shoot or never trigger.
2. **Crash on scale commands:** `scaleController.connectedScale()` throws because `_scale` is nulled on disconnect. Timer/tare calls in `_handleStateTransition` will crash.
3. **No recovery path:** There's no mechanism to disable SAW mid-shot and let the shot complete naturally.

### The fix

- Add `_scaleLost` flag + `connectionState` subscription to ShotController
- Gate all `scale` usage on `!_scaleLost` (not just `scale != null`)
- Gate all `connectedScale()` calls on `!_scaleLost`
- Log clearly when scale is lost mid-shot so the user knows SAW was disabled

### What we're NOT doing

- Not implementing software baseline tracking (Decenza #475) — separate concern
- Not adding a watchdog timer — the scale's own disconnect is sufficient
- Not changing stream architecture (e.g., switching to `combineLatest`) — too invasive, `withLatestFrom` is fine when we gate the data

---

## Task 1: Add test helper — TestDe1 and enhanced TestScale

The existing `_TestDe1` in `presence_controller_test.dart` is test-local. We need a shared version. The existing `TestScale` doesn't emit snapshots. We need one that does.

**Files:**
- Create: `test/helpers/test_de1.dart`
- Modify: `test/helpers/test_scale.dart`

### Step 1: Create shared TestDe1

Create `test/helpers/test_de1.dart` — extracted from `presence_controller_test.dart`'s `_TestDe1`, with an added `emitSnapshot` method for full control and `emitStateAndSubstate` for combined state+substate changes.

```dart
import 'dart:typed_data';

import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/de1_rawmessage.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/wake_schedule.dart';
import 'package:rxdart/subjects.dart';

/// Shared De1Interface test double with controllable snapshot stream.
class TestDe1 implements De1Interface {
  final BehaviorSubject<MachineSnapshot> snapshotSubject =
      BehaviorSubject.seeded(
    MachineSnapshot(
      timestamp: DateTime(2026, 1, 15, 8, 0),
      state: const MachineStateSnapshot(
        state: MachineState.idle,
        substate: MachineSubstate.idle,
      ),
      flow: 0,
      pressure: 0,
      targetFlow: 0,
      targetPressure: 0,
      mixTemperature: 90,
      groupTemperature: 90,
      targetMixTemperature: 93,
      targetGroupTemperature: 93,
      profileFrame: 0,
      steamTemperature: 0,
    ),
  );

  final List<MachineState> requestedStates = [];

  void emitSnapshot(MachineSnapshot snapshot) {
    snapshotSubject.add(snapshot);
  }

  void emitStateAndSubstate(MachineState state, MachineSubstate substate) {
    final current = snapshotSubject.value;
    snapshotSubject.add(current.copyWith(
      state: MachineStateSnapshot(state: state, substate: substate),
      timestamp: DateTime.now(),
    ));
  }

  @override
  Stream<MachineSnapshot> get currentSnapshot => snapshotSubject.stream;

  @override
  Future<void> requestState(MachineState newState) async {
    requestedStates.add(newState);
  }

  // --- Stubs for the rest of De1Interface ---
  @override
  String get deviceId => 'test-de1';
  @override
  String get name => 'TestDe1';
  @override
  DeviceType get type => DeviceType.machine;
  @override
  Future<void> onConnect() async {}
  @override
  Future<void> disconnect() async {}
  @override
  Stream<ConnectionState> get connectionState =>
      BehaviorSubject.seeded(ConnectionState.connected).stream;
  @override
  Stream<bool> get ready => Stream.value(true);
  @override
  MachineInfo get machineInfo => MachineInfo(
        version: '1',
        model: '1',
        serialNumber: '1',
        groupHeadControllerPresent: false,
        extra: {},
      );
  @override
  Stream<De1ShotSettings> get shotSettings => const Stream.empty();
  @override
  Future<void> updateShotSettings(De1ShotSettings newSettings) async {}
  @override
  Stream<De1WaterLevels> get waterLevels => const Stream.empty();
  @override
  Future<void> setRefillLevel(int newRefillLevel) async {}
  @override
  Future<void> setProfile(Profile profile) async {}
  @override
  Future<void> setFanThreshhold(int temp) async {}
  @override
  Future<int> getFanThreshhold() async => 0;
  @override
  Future<int> getTankTempThreshold() async => 0;
  @override
  Future<void> setTankTempThreshold(int temp) async {}
  @override
  Future<void> setSteamFlow(double newFlow) async {}
  @override
  Future<double> getSteamFlow() async => 0;
  @override
  Future<void> setHotWaterFlow(double newFlow) async {}
  @override
  Future<double> getHotWaterFlow() async => 0;
  @override
  Future<void> setFlushFlow(double newFlow) async {}
  @override
  Future<double> getFlushFlow() async => 0;
  @override
  Future<void> setFlushTimeout(double newTimeout) async {}
  @override
  Future<double> getFlushTimeout() async => 0;
  @override
  Future<double> getFlushTemperature() async => 0;
  @override
  Future<void> setFlushTemperature(double newTemp) async {}
  @override
  Future<double> getFlowEstimation() async => 1.0;
  @override
  Future<void> setFlowEstimation(double multiplier) async {}
  @override
  Future<bool> getUsbChargerMode() async => false;
  @override
  Future<void> setUsbChargerMode(bool t) async {}
  @override
  Future<void> setSteamPurgeMode(int mode) async {}
  @override
  Future<int> getSteamPurgeMode() async => 0;
  @override
  Future<void> enableUserPresenceFeature() async {}
  @override
  Future<void> sendUserPresent() async {}
  @override
  Stream<De1RawMessage> get rawOutStream => const Stream.empty();
  @override
  void sendRawMessage(De1RawMessage message) {}
  @override
  Future<double> getHeaterPhase1Flow() async => 0;
  @override
  Future<void> setHeaterPhase1Flow(double val) async {}
  @override
  Future<double> getHeaterPhase2Flow() async => 0;
  @override
  Future<void> setHeaterPhase2Flow(double val) async {}
  @override
  Future<double> getHeaterPhase2Timeout() async => 0;
  @override
  Future<void> setHeaterPhase2Timeout(double val) async {}
  @override
  Future<double> getHeaterIdleTemp() async => 0;
  @override
  Future<void> setHeaterIdleTemp(double val) async {}
  @override
  Future<void> updateFirmware(Uint8List fwImage,
      {required void Function(double progress) onProgress}) async {}
}
```

### Step 2: Add snapshot emission to TestScale

Add a `BehaviorSubject<ScaleSnapshot>` to `TestScale` so tests can emit weight data:

```dart
// Add to TestScale:
final BehaviorSubject<ScaleSnapshot> _snapshotSubject = BehaviorSubject();

@override
Stream<ScaleSnapshot> get currentSnapshot => _snapshotSubject.stream;

void emitSnapshot(ScaleSnapshot snapshot) {
  _snapshotSubject.add(snapshot);
}

// Update dispose to also close _snapshotSubject
```

Replace the existing `Stream<ScaleSnapshot> get currentSnapshot => const Stream.empty();` line.

### Step 3: Run tests to make sure nothing is broken

Run: `flutter test`
Expected: All existing tests pass (TestScale change is additive)

### Step 4: Commit

```
feat: add shared TestDe1 helper and snapshot emission to TestScale
```

---

## Task 2: Write failing tests for scale disconnect during shot

**Files:**
- Create: `test/controllers/shot_controller_test.dart`

### Step 1: Write the test file

This test file needs a `_TestDe1Controller` that wraps our `TestDe1` so `connectedDe1()` works, and uses `MockScaleController` (from `test/helpers/mock_scale_controller.dart`) enhanced with a controllable `weightSnapshot` stream.

We need to extend `MockScaleController` locally to also provide a controllable `weightSnapshot` stream and `currentConnectionState` getter.

```dart
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/persistence_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/models/data/profile.dart';
import 'package:reaprime/src/models/data/shot_snapshot.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:rxdart/rxdart.dart';

import '../helpers/test_de1.dart';
import '../helpers/test_scale.dart';

// ---------------------------------------------------------------------------
// Test-local helpers
// ---------------------------------------------------------------------------

class _FakeDiscoveryService implements DeviceDiscoveryService {
  @override
  Stream<List<Device>> get devices => const Stream.empty();
  @override
  Future<void> initialize() async {}
  @override
  Future<void> scanForDevices() async {}
  @override
  void stopScan() {}
}

/// De1Controller that exposes a TestDe1 via connectedDe1().
class _TestDe1Controller extends De1Controller {
  final TestDe1 testDe1;

  _TestDe1Controller({
    required super.controller,
    required this.testDe1,
  });

  @override
  De1Interface connectedDe1() => testDe1;

  @override
  Stream<De1Interface?> get de1 =>
      BehaviorSubject<De1Interface?>.seeded(testDe1).stream;
}

/// ScaleController with controllable weight stream and connection state.
class _TestScaleController extends ScaleController {
  final BehaviorSubject<ConnectionState> _connectionSubject;
  final BehaviorSubject<WeightSnapshot> _weightSubject = BehaviorSubject();
  final TestScale _testScale;

  _TestScaleController({
    required TestScale testScale,
    ConnectionState initialState = ConnectionState.connected,
  })  : _connectionSubject = BehaviorSubject.seeded(initialState),
        _testScale = testScale;

  @override
  Stream<ConnectionState> get connectionState => _connectionSubject.stream;

  @override
  ConnectionState get currentConnectionState => _connectionSubject.value;

  @override
  Stream<WeightSnapshot> get weightSnapshot => _weightSubject.stream;

  @override
  Scale connectedScale() => _testScale;

  void emitWeight(double weight, {double weightFlow = 0.0}) {
    _weightSubject.add(WeightSnapshot(
      timestamp: DateTime.now(),
      weight: weight,
      weightFlow: weightFlow,
    ));
  }

  void simulateDisconnect() {
    _connectionSubject.add(ConnectionState.disconnected);
  }

  void dispose() {
    _connectionSubject.close();
    _weightSubject.close();
  }
}

class _MockPersistenceController extends PersistenceController {
  _MockPersistenceController() : super(storageService: _NullStorageService());
}

/// Minimal StorageService that does nothing.
class _NullStorageService implements StorageService {
  // Implement all required methods as no-ops.
  // (PersistenceController constructor needs a StorageService but
  // ShotController never calls it directly during a shot.)
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Profile _simpleProfile({double? targetVolume}) => Profile(
      id: 'test',
      title: 'Test Profile',
      steps: [
        ProfileStep(
          name: 'step1',
          pressure: 9,
          flow: null,
          seconds: 30,
          volume: null,
          weight: null,
          temperature: 93,
          sensor: TemperatureSensor.coffee,
          transition: Transition.fast,
          limiter: null,
          exit: null,
        ),
      ],
      targetWeight: 36,
      targetVolume: targetVolume,
      targetVolumeCountStart: 0,
      type: ProfileType.pressure,
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ShotController – scale disconnect mid-shot', () {
    late TestDe1 testDe1;
    late _TestDe1Controller de1Controller;
    late _TestScaleController scaleController;
    late TestScale testScale;

    setUp(() {
      final discoveryService = _FakeDiscoveryService();
      final deviceController = DeviceController([discoveryService]);
      testDe1 = TestDe1();
      de1Controller = _TestDe1Controller(
        controller: deviceController,
        testDe1: testDe1,
      );
      testScale = TestScale();
      scaleController = _TestScaleController(testScale: testScale);
    });

    tearDown(() {
      scaleController.dispose();
    });

    test('disables SAW when scale disconnects during pouring', () {
      fakeAsync((async) {
        // Emit initial weight so withLatestFrom has a value
        scaleController.emitWeight(0.0);
        async.flushMicrotasks();

        final shot = ShotController(
          scaleController: scaleController,
          de1controller: de1Controller,
          persistenceController: _MockPersistenceController(),
          targetProfile: _simpleProfile(),
          targetYield: 36.0,
          bypassSAW: false,
          weightFlowMultiplier: 1.0,
          volumeFlowMultiplier: 0.3,
        );
        async.flushMicrotasks();

        // Drive to pouring state
        testDe1.emitStateAndSubstate(
            MachineState.espresso, MachineSubstate.preparingForShot);
        scaleController.emitWeight(0.0);
        async.flushMicrotasks();

        testDe1.emitStateAndSubstate(
            MachineState.espresso, MachineSubstate.pouring);
        scaleController.emitWeight(0.0);
        async.flushMicrotasks();

        // Now disconnect the scale
        scaleController.simulateDisconnect();
        async.flushMicrotasks();

        // Emit weight that would normally trigger SAW (above 36g target)
        scaleController.emitWeight(40.0, weightFlow: 2.0);
        testDe1.emitStateAndSubstate(
            MachineState.espresso, MachineSubstate.pouring);
        async.flushMicrotasks();

        // Machine should NOT have been told to stop — SAW is disabled
        expect(testDe1.requestedStates, isEmpty);

        shot.dispose();
      });
    });

    test('does not crash when scale disconnects and timer stop is attempted',
        () {
      fakeAsync((async) {
        scaleController.emitWeight(0.0);
        async.flushMicrotasks();

        final shot = ShotController(
          scaleController: scaleController,
          de1controller: de1Controller,
          persistenceController: _MockPersistenceController(),
          targetProfile: _simpleProfile(),
          targetYield: 36.0,
          bypassSAW: false,
          weightFlowMultiplier: 1.0,
          volumeFlowMultiplier: 0.3,
        );
        async.flushMicrotasks();

        // Drive to pouring
        testDe1.emitStateAndSubstate(
            MachineState.espresso, MachineSubstate.preparingForShot);
        scaleController.emitWeight(0.0);
        async.flushMicrotasks();

        testDe1.emitStateAndSubstate(
            MachineState.espresso, MachineSubstate.pouring);
        scaleController.emitWeight(0.0);
        async.flushMicrotasks();

        // Disconnect scale
        scaleController.simulateDisconnect();
        async.flushMicrotasks();

        // Machine ends the shot normally (user presses stop or profile ends)
        testDe1.emitStateAndSubstate(
            MachineState.espresso, MachineSubstate.pouringDone);
        async.flushMicrotasks();

        // Should reach stopping state without crashing
        // (stopTimer would have thrown before the fix)
        async.elapse(const Duration(seconds: 5));

        shot.dispose();
      });
    });

    test('SAW still works normally when scale stays connected', () {
      fakeAsync((async) {
        scaleController.emitWeight(0.0);
        async.flushMicrotasks();

        final shot = ShotController(
          scaleController: scaleController,
          de1controller: de1Controller,
          persistenceController: _MockPersistenceController(),
          targetProfile: _simpleProfile(),
          targetYield: 36.0,
          bypassSAW: false,
          weightFlowMultiplier: 1.0,
          volumeFlowMultiplier: 0.3,
        );
        async.flushMicrotasks();

        // Drive to pouring
        testDe1.emitStateAndSubstate(
            MachineState.espresso, MachineSubstate.preparingForShot);
        scaleController.emitWeight(0.0);
        async.flushMicrotasks();

        testDe1.emitStateAndSubstate(
            MachineState.espresso, MachineSubstate.pouring);
        scaleController.emitWeight(0.0);
        async.flushMicrotasks();

        // Weight exceeds target — SAW should fire
        scaleController.emitWeight(40.0, weightFlow: 2.0);
        testDe1.emitStateAndSubstate(
            MachineState.espresso, MachineSubstate.pouring);
        async.flushMicrotasks();

        expect(testDe1.requestedStates, contains(MachineState.idle));

        shot.dispose();
      });
    });
  });
}
```

**Note on _NullStorageService:** Uses `noSuchMethod` to stub all StorageService methods. ShotController never calls persistence during a shot — it only records data. This avoids writing 20+ stub methods for an interface we don't exercise. If `flutter analyze` flags this, replace with explicit stubs.

### Step 2: Run tests to verify they fail

Run: `flutter test test/controllers/shot_controller_test.dart`
Expected: The tests should either fail (SAW fires when it shouldn't) or throw (connectedScale() crash). This confirms the bug exists.

**Important:** The test file references helpers and constructors that may need adjustment based on actual imports (e.g., `Profile` constructor, `StorageService` import path). Fix compilation errors first, then verify the tests fail for the *right* reason (scale disconnect not handled), not for import errors.

### Step 3: Commit

```
test: add failing tests for scale disconnect during shot
```

---

## Task 3: Implement scale disconnect recovery in ShotController

**Files:**
- Modify: `lib/src/controllers/shot_controller.dart`

### Step 1: Add `_scaleLost` flag and connection state listener

Add these fields and wire up the listener in the constructor:

```dart
// New fields (add near other state fields):
bool _scaleLost = false;
StreamSubscription<device.ConnectionState>? _scaleConnectionSubscription;
```

In the constructor, after setting up `_snapshotSubscription` in the scale-connected branch (after line 78), add:

```dart
// Monitor scale connection state during shot
_scaleConnectionSubscription = scaleController.connectionState.listen((state) {
  if (state == device.ConnectionState.disconnected && !_scaleLost) {
    if (_state != ShotState.idle && _state != ShotState.finished) {
      _scaleLost = true;
      _log.warning(
        'Scale disconnected during shot (state: ${_state.name}). '
        'Stop-at-weight disabled for remainder of this shot.',
      );
    }
  }
});
```

### Step 2: Gate all scale usage on `!_scaleLost`

In `_handleStateTransition`, replace every `scale != null` check with `scale != null && !_scaleLost`:

**Line 183** (preparingForShot tare+resetTimer):
```dart
if (_bypassSAW == false && scale != null && !_scaleLost) {
```

**Line 199** (preinfusion tare+startTimer):
```dart
if (_bypassSAW == false && scale != null && !_scaleLost) {
```

**Line 219** (SAW weight checks during pouring):
```dart
if (_bypassSAW == false && scale != null && !_scaleLost) {
```

**Line 277** (stopTimer in stopping state):
```dart
if (_bypassSAW == false && scale != null && !_scaleLost) {
```

### Step 3: Cancel subscription in dispose

In `dispose()`, add:

```dart
_scaleConnectionSubscription?.cancel();
```

### Step 4: Run the failing tests

Run: `flutter test test/controllers/shot_controller_test.dart`
Expected: All three tests pass.

### Step 5: Run full test suite

Run: `flutter test`
Expected: All tests pass.

### Step 6: Run analyze

Run: `flutter analyze`
Expected: No new issues.

### Step 7: Commit

```
fix: disable stop-at-weight when scale disconnects mid-shot
```

---

## Task 4: Verify with MCP (if app is running)

If the app can be started in simulate mode, verify the fix end-to-end:

1. Start app with `app_start` (connectDevice: "MockDe1", connectScale: "MockScale")
2. Start an espresso shot
3. Disconnect the scale mid-shot (via `devices_disconnect` or similar)
4. Confirm the shot continues without crashing
5. Confirm logs show the "Scale disconnected during shot" warning

If the app can't be run, skip this task.

### Step 1: Commit (if any adjustments were needed)

```
fix: adjustments from MCP verification
```

---

## Task 5: Archive plan

**Files:**
- Move: `doc/plans/2026-04-06-shot-scale-disconnect.md` → `doc/plans/archive/shot-scale-disconnect/`

### Step 1: Move plan to archive

```bash
mkdir -p doc/plans/archive/shot-scale-disconnect
mv doc/plans/2026-04-06-shot-scale-disconnect.md doc/plans/archive/shot-scale-disconnect/
```

### Step 2: Commit

```
chore: archive shot-scale-disconnect plan
```
