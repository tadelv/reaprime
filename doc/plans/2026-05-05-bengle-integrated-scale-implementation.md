# Bengle integrated scale — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Land Bengle integrated-scale API surface end-to-end on `MockBengle`, with stubs in place for real Bengle pending FW wire identifiers.

**Architecture:** See companion design doc `doc/plans/2026-05-05-bengle-integrated-scale.md`. Briefly: Bengle exposes a `BengleVirtualScale extends Scale` adapter; `ConnectionManager` auto-connects it after machine connect; existing `/api/v1/scale/*` and `/ws/v1/scale/snapshot` work unchanged. `IntegratedScaleCapability` mixin on `UnifiedDe1` carries the real-Bengle wire path with stubbed (null) endpoint identifiers. `MockBengle` integrates `MockDe1`'s simulated flow into weight directly (no mixin). SAW stays in `ShotController` software path.

**Tech Stack:** Dart / Flutter, RxDart `BehaviorSubject`, `package:logging`, Drift (untouched here), shelf web server. Tests via `flutter test`. End-to-end via `scripts/sb-dev.sh` + `curl`/`websocat`.

**Branch:** `feat/bengle-integrated-scale` (already checked out). PR at the end. Use TDD per `.claude/skills/tdd-workflow/`.

---

## Task ordering principle

Tracer-bullet: get the smallest user-visible end-to-end path working first (capabilities flag + mock weight stream over WS), then layer on tare, precedence, real-Bengle stubs, and docs. Each task ends with `flutter analyze` + relevant `flutter test` before commit.

Numbering follows a strict sequence; do not reorder. After each task, the working tree should be green (analyze + tests pass).

---

## Task 1 — Capabilities endpoint advertises `integratedScale`

**Files:**
- Modify: `lib/src/services/webserver/de1handler.dart:31-37`
- Modify: `test/services/webserver/de1handler_cup_warmer_test.dart` (rename or extend) → split into `de1handler_capabilities_test.dart` covering both `cupWarmer` and `integratedScale`. If renaming feels heavy, just add `integratedScale` cases inside the existing `de1handler_cup_warmer_test.dart` — it already has the harness.

**Step 1: Add failing test in the existing capabilities group**

In `test/services/webserver/de1handler_cup_warmer_test.dart`, inside the `group('GET /api/v1/machine/capabilities', () { ... })` block, add:

```dart
test('returns integratedScale when a Bengle is connected', () async {
  await connectMockBengle();
  final res = await get('/api/v1/machine/capabilities');
  final body = jsonDecode(res.body);
  expect(body['capabilities'], contains('integratedScale'));
});

test('does not return integratedScale on plain DE1', () async {
  await connectMockDe1();
  final res = await get('/api/v1/machine/capabilities');
  final body = jsonDecode(res.body);
  expect(body['capabilities'], isNot(contains('integratedScale')));
});
```

(`connectMockBengle` / `connectMockDe1` helpers already exist in the test file.)

**Step 2: Run test to verify it fails**

```
flutter test test/services/webserver/de1handler_cup_warmer_test.dart
```
Expected: two new tests fail (`integratedScale` not in caps).

**Step 3: Add the capability**

In `lib/src/services/webserver/de1handler.dart` line 33-34, after the `cupWarmer` add:

```dart
if (de1 is BengleInterface) caps.add('integratedScale');
```

(Yes — both `cupWarmer` and `integratedScale` gate on the same type today. That's correct: every Bengle has both.)

**Step 4: Run tests**

```
flutter test test/services/webserver/de1handler_cup_warmer_test.dart
flutter analyze
```
Expected: all green.

**Step 5: Commit**

```bash
git add lib/src/services/webserver/de1handler.dart test/services/webserver/de1handler_cup_warmer_test.dart
git commit -m "feat(bengle): advertise integratedScale capability"
```

---

## Task 2 — Add `weightSnapshot` getter to `BengleInterface`

**Files:**
- Modify: `lib/src/models/device/bengle_interface.dart`

**Step 1: Extend the interface**

Add to `BengleInterface`:

```dart
/// Live snapshot stream from the integrated scale.
///
/// Real `Bengle` wires this to `IntegratedScaleCapability.weightSnapshot`
/// (notify endpoint TBD with FW). `MockBengle` synthesises weight by
/// integrating `MockDe1`'s simulated flow.
Stream<ScaleSnapshot> get weightSnapshot;

/// Tare the integrated scale. Subsequent snapshots have weight relative
/// to this zero.
Future<void> tareIntegratedScale();
```

Add the necessary import: `import 'scale.dart';` (for `ScaleSnapshot`).

**Step 2: Run analyze (will fail — implementations missing)**

```
flutter analyze
```
Expected: errors in `bengle.dart` and `mock_bengle.dart` ("Missing concrete implementations").

That's the test for this step — the type system. We'll implement next tasks.

**Step 3: Commit (interface only — broken-build commit OK on a feature branch since the next task fixes it; alternatively combine with Task 3)**

Decision: **combine with Task 3** to keep the tree green per task. Skip the commit here; carry the change forward.

---

## Task 3 — `MockBengle` flow-integrated weight stream + tare

**Files:**
- Create: `test/models/device/impl/bengle/mock_bengle_scale_test.dart`
- Modify: `lib/src/models/device/impl/bengle/mock_bengle.dart`

**Step 1: Write failing tests**

Create `test/models/device/impl/bengle/mock_bengle_scale_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/impl/bengle/mock_bengle.dart';

void main() {
  group('MockBengle integrated scale', () {
    late MockBengle bengle;

    setUp(() async {
      bengle = MockBengle();
      await bengle.onConnect();
    });

    tearDown(() async {
      await bengle.onDisconnect();
    });

    test('emits weightSnapshot after connect', () async {
      final snapshot = await bengle.weightSnapshot.first
          .timeout(const Duration(seconds: 2));
      expect(snapshot.batteryLevel, 100);
      expect(snapshot.weight, isA<double>());
    });

    test('weight rises during simulated espresso shot', () async {
      // Capture weight before shot
      final pre = await bengle.weightSnapshot.first
          .timeout(const Duration(seconds: 2));

      await bengle.requestState(MachineState.espresso);
      // Let the simulator integrate flow for ~2 seconds
      await Future.delayed(const Duration(seconds: 2));
      await bengle.requestState(MachineState.idle);

      final post = await bengle.weightSnapshot.first
          .timeout(const Duration(seconds: 2));
      expect(post.weight, greaterThan(pre.weight));
    });

    test('tareIntegratedScale zeroes the next emit', () async {
      await bengle.requestState(MachineState.espresso);
      await Future.delayed(const Duration(seconds: 1));
      await bengle.requestState(MachineState.idle);

      // Read current weight, tare, expect next emit ~ 0
      await bengle.weightSnapshot.first;
      await bengle.tareIntegratedScale();
      // tareIntegratedScale should immediately re-emit with weight 0.
      final next = await bengle.weightSnapshot.first
          .timeout(const Duration(seconds: 2));
      expect(next.weight.abs(), lessThan(0.01));
    });

    test('disconnect closes the snapshot stream', () async {
      await bengle.onDisconnect();
      // BehaviorSubject after close should not allow new listeners to await
      await expectLater(
        bengle.weightSnapshot.first.timeout(const Duration(milliseconds: 100)),
        throwsA(anything),
      );
    });
  });
}
```

**Step 2: Run tests to verify they fail**

```
flutter test test/models/device/impl/bengle/mock_bengle_scale_test.dart
```
Expected: all four tests fail (`weightSnapshot` / `tareIntegratedScale` not implemented).

**Step 3: Implement on `MockBengle`**

Replace `mock_bengle.dart` with:

```dart
import 'dart:async';

import 'package:reaprime/src/models/device/bengle_interface.dart';
import 'package:reaprime/src/models/device/impl/mock_de1/mock_de1.dart';
import 'package:reaprime/src/models/device/machine.dart';
import 'package:reaprime/src/models/device/scale.dart';
import 'package:rxdart/rxdart.dart';

class MockBengle extends MockDe1 implements BengleInterface {
  MockBengle({super.deviceId = 'MockBengle'});

  @override
  String get name => 'MockBengle';

  // --- cup warmer ---
  double _cupWarmerTemp = 0.0;

  @override
  Future<void> setCupWarmerTemperature(double celsius) async {
    _cupWarmerTemp = celsius.clamp(0.0, 80.0).toDouble();
  }

  @override
  Future<double> getCupWarmerTemperature() async => _cupWarmerTemp;

  // --- integrated scale ---
  final BehaviorSubject<ScaleSnapshot> _weight = BehaviorSubject();
  StreamSubscription<MachineSnapshot>? _flowSub;
  double _accumulatedWeight = 0.0;
  double _tareOffset = 0.0;
  DateTime? _lastSampleTime;

  @override
  Stream<ScaleSnapshot> get weightSnapshot => _weight.stream;

  @override
  Future<void> tareIntegratedScale() async {
    _tareOffset = _accumulatedWeight;
    _emit();
  }

  void _emit() {
    if (_weight.isClosed) return;
    _weight.add(ScaleSnapshot(
      timestamp: DateTime.now(),
      weight: _accumulatedWeight - _tareOffset,
      batteryLevel: 100,
    ));
  }

  @override
  Future<void> onConnect() async {
    await super.onConnect();
    _accumulatedWeight = 0.0;
    _tareOffset = 0.0;
    _lastSampleTime = null;
    _emit();
    _flowSub = currentSnapshot.listen(_integrateFlow);
  }

  void _integrateFlow(MachineSnapshot s) {
    final now = s.timestamp;
    final last = _lastSampleTime;
    _lastSampleTime = now;
    if (last == null) return;
    final dtSec = now.difference(last).inMilliseconds / 1000.0;
    if (dtSec <= 0) return;
    _accumulatedWeight += s.flow * dtSec;
    _emit();
  }

  @override
  Future<void> onDisconnect() async {
    await _flowSub?.cancel();
    _flowSub = null;
    if (!_weight.isClosed) {
      await _weight.close();
    }
    await super.onDisconnect();
  }

  @override
  MachineInfo get machineInfo => MachineInfo(
        version: '1.0',
        model: 'Bengle',
        serialNumber: '110010101',
        groupHeadControllerPresent: true,
        extra: {'voltage': 220, 'refillKit': false},
      );
}
```

Notes for the implementer:
- `MachineSnapshot` is the existing type from `machine.dart` — it has `flow` (double, mL/s) and `timestamp` (DateTime).
- `BehaviorSubject` re-emits the latest value to new listeners — convenient for the WS handler that connects after some time.

**Step 4: Run tests**

```
flutter test test/models/device/impl/bengle/mock_bengle_scale_test.dart
flutter analyze
```
Expected: green.

**Step 5: Commit**

```bash
git add lib/src/models/device/bengle_interface.dart lib/src/models/device/impl/bengle/mock_bengle.dart test/models/device/impl/bengle/mock_bengle_scale_test.dart
git commit -m "feat(bengle): integrated scale weight stream + tare on MockBengle"
```

---

## Task 4 — `BengleVirtualScale` adapter

**Files:**
- Create: `lib/src/models/device/impl/bengle/bengle_virtual_scale.dart`
- Create: `test/models/device/impl/bengle/bengle_virtual_scale_test.dart`

**Step 1: Write failing tests**

Create the test file:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/bengle/mock_bengle.dart';
import 'package:reaprime/src/models/device/impl/bengle/bengle_virtual_scale.dart';

void main() {
  group('BengleVirtualScale', () {
    late MockBengle bengle;
    late BengleVirtualScale scale;

    setUp(() async {
      bengle = MockBengle();
      scale = BengleVirtualScale(bengle);
      await bengle.onConnect();
    });

    tearDown(() async {
      await bengle.onDisconnect();
    });

    test('proxies the machine weightSnapshot stream', () async {
      final snap = await scale.currentSnapshot.first
          .timeout(const Duration(seconds: 2));
      expect(snap.batteryLevel, 100);
    });

    test('tare delegates to machine.tareIntegratedScale', () async {
      // Bring weight off zero first via simulated shot
      // ... (omitted for brevity — copy the shot pattern from mock_bengle_scale_test)
      await scale.tare();
      final next = await scale.currentSnapshot.first
          .timeout(const Duration(seconds: 2));
      expect(next.weight.abs(), lessThan(0.01));
    });

    test('deviceId is derived from the machine', () {
      expect(scale.deviceId, 'bengle-internal-${bengle.deviceId}');
    });

    test('name is "Bengle scale"', () {
      expect(scale.name, 'Bengle scale');
    });

    test('connectionState mirrors machine connectionState', () async {
      // MockBengle's connectionState is inherited from MockDe1; default state
      // should be connected after onConnect().
      final state = await scale.connectionState.first
          .timeout(const Duration(seconds: 1));
      expect(state, ConnectionState.connected);
    });

    test('display + timer methods are no-ops and resolve', () async {
      await scale.sleepDisplay();
      await scale.wakeDisplay();
      await scale.startTimer();
      await scale.stopTimer();
      await scale.resetTimer();
    });

    test('onConnect and onDisconnect are no-ops on the adapter', () async {
      await scale.onConnect();
      await scale.disconnect();
    });
  });
}
```

**Step 2: Run tests**

```
flutter test test/models/device/impl/bengle/bengle_virtual_scale_test.dart
```
Expected: fails — file doesn't exist yet.

**Step 3: Implement adapter**

Create `lib/src/models/device/impl/bengle/bengle_virtual_scale.dart`:

```dart
import 'dart:async';

import 'package:reaprime/src/models/device/bengle_interface.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/scale.dart';

/// Adapter that exposes a Bengle's integrated scale to [ScaleController]
/// as a regular [Scale]. Lifecycle is owned by the underlying machine —
/// onConnect / disconnect on this adapter are no-ops.
class BengleVirtualScale extends Scale {
  final BengleInterface _machine;

  BengleVirtualScale(this._machine);

  @override
  String get deviceId => 'bengle-internal-${_machine.deviceId}';

  @override
  String get name => 'Bengle scale';

  @override
  DeviceType get type => DeviceType.scale;

  @override
  Stream<ConnectionState> get connectionState => _machine.connectionState;

  @override
  Stream<ScaleSnapshot> get currentSnapshot => _machine.weightSnapshot;

  @override
  Future<void> tare() => _machine.tareIntegratedScale();

  @override
  Future<void> sleepDisplay() async {}
  @override
  Future<void> wakeDisplay() async {}

  @override
  Future<void> startTimer() async {}
  @override
  Future<void> stopTimer() async {}
  @override
  Future<void> resetTimer() async {}

  // Lifecycle is owned by the machine. Adapter is connect-by-construction.
  @override
  Future<void> onConnect() async {}
  @override
  Future<void> disconnect() async {}
}
```

Verify the `Scale` / `Device` superclasses' abstract members against the existing `MockScale` and `DecentScale` impls — copy any missing override. (The list above matches the existing scales.)

**Step 4: Run tests**

```
flutter test test/models/device/impl/bengle/bengle_virtual_scale_test.dart
flutter analyze
```
Expected: green.

**Step 5: Commit**

```bash
git add lib/src/models/device/impl/bengle/bengle_virtual_scale.dart test/models/device/impl/bengle/bengle_virtual_scale_test.dart
git commit -m "feat(bengle): BengleVirtualScale adapter routing through ScaleController"
```

---

## Task 5 — `ConnectionManager` auto-connects virtual scale (no precedence yet)

**Files:**
- Modify: `lib/src/controllers/connection_manager.dart` (post-machine-connect hook around line 449-499 and the scale-policy interactions around 422-445)
- Create: `test/integration/connection_manager_bengle_scale_auto_connect_test.dart`

**Step 1: Failing integration test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/connection_manager.dart';
// + harness imports (mirror any existing ConnectionManager test under test/controllers/)

void main() {
  group('ConnectionManager + Bengle integrated scale', () {
    test('auto-connects BengleVirtualScale after Bengle connect '
         'when no external scale is preferred or available',
        () async {
      // Arrange: ConnectionManager with simulated Bengle preferred,
      // no external scales discovered.
      // Act: call connect()
      // Assert: ScaleController.currentConnectionState == connected
      // Assert: scaleController.connectedScale().deviceId starts with
      //         'bengle-internal-'
      // (Fill in concrete harness; mirror existing ConnectionManager tests
      //  e.g. test/controllers/connection_manager_*.dart)
    });
  });
}
```

(Implementer: pick the existing ConnectionManager test that's closest to a "machine-only connect" scenario and clone its harness.)

**Step 2: Run tests** — fails.

**Step 3: Implement**

In `connection_manager.dart`, after `connectMachine` succeeds (around line 449-499 — find the spot just *after* the existing connect logic returns), add:

```dart
Future<void> _maybeAttachBengleVirtualScale(De1Interface machine) async {
  if (machine is! BengleInterface) return;
  if (_scaleController.currentConnectionState == ConnectionState.connected) {
    // External scale already connected — leave it. Precedence work in Task 6.
    return;
  }
  final virtual = BengleVirtualScale(machine);
  try {
    await _scaleController.connectToScale(virtual);
  } catch (e, st) {
    _log.warning('Failed to attach Bengle virtual scale', e, st);
  }
}
```

Wire the call from the right spot inside `connectMachine` after the success path. The exact insertion line will depend on local structure — find where `_de1Controller.attach(machine)` (or similar) is called, and call `_maybeAttachBengleVirtualScale(machine)` immediately after.

Add the necessary imports at the top of the file:

```dart
import 'package:reaprime/src/models/device/bengle_interface.dart';
import 'package:reaprime/src/models/device/impl/bengle/bengle_virtual_scale.dart';
```

**Step 4: Run tests + analyze.**

**Step 5: Commit**

```bash
git add lib/src/controllers/connection_manager.dart test/integration/connection_manager_bengle_scale_auto_connect_test.dart
git commit -m "feat(bengle): auto-connect virtual scale on machine connect"
```

---

## Task 6 — External scale takes precedence

**Files:**
- Modify: `lib/src/controllers/connection_manager.dart`
- Create: `test/integration/connection_manager_bengle_scale_precedence_test.dart`

**Step 1: Failing test (two cases in one file)**

```dart
test('external scale connecting after Bengle swaps the virtual out', () async {
  // Arrange: machine connected as Bengle, virtual scale attached.
  // Act: discover + connect an external MockScale.
  // Assert: scaleController.connectedScale().deviceId == external scale id.
});

test('external scale disconnecting reattaches the virtual scale', () async {
  // Arrange: Bengle + external scale, external is the active scale.
  // Act: disconnect external scale (machine still connected).
  // Assert: scaleController.connectedScale().deviceId starts with
  //         'bengle-internal-'.
});
```

**Step 2: Run** — fails.

**Step 3: Implement**

`ScaleController.connectToScale` already swaps the active scale on next call (it calls `_onDisconnect` first). Case 1 falls out for free *if* the existing scale-policy path runs `connectToScale(external)` after `_maybeAttachBengleVirtualScale` has run. Verify the order in `_applyScalePolicy` — if it swaps out the virtual cleanly, no change needed.

Case 2 — the reattach-on-external-disconnect — needs a listener. Add to `ConnectionManager` initialisation:

```dart
_scaleConnectionListener = _scaleController.connectionState.listen((s) async {
  if (s != ConnectionState.disconnected) return;
  final machine = _de1Controller.connectedMachineOrNull;
  if (machine is BengleInterface) {
    await _maybeAttachBengleVirtualScale(machine);
  }
});
```

Cancel in `dispose`.

(If `connectedMachineOrNull` doesn't exist, add a small accessor on `De1Controller` mirroring the existing `connectedDe1OrNull` pattern.)

**Step 4: Run tests** — both green.

**Step 5: Commit**

```bash
git add lib/src/controllers/connection_manager.dart test/integration/connection_manager_bengle_scale_precedence_test.dart
git commit -m "feat(bengle): external scale takes precedence over virtual"
```

---

## Task 7 — Real `Bengle` carries the capability mixin (stub identifiers)

**Files:**
- Create: `lib/src/models/device/impl/de1/unified_de1/integrated_scale_capability.dart`
- Modify: `lib/src/models/device/impl/bengle/bengle_mmr.dart` (add `scaleTare` stub)
- Modify: `lib/src/models/device/impl/bengle/bengle.dart` (mix in capability, override onConnect/onDisconnect)
- Create: `test/unit/models/device/impl/de1/unified_de1/integrated_scale_capability_test.dart`

**Step 1: Failing unit test**

```dart
// test/unit/.../integrated_scale_capability_test.dart
//
// Verify the mixin compiles and exposes:
//   - weightSnapshot (Stream<ScaleSnapshot>)
//   - tareIntegratedScale() Future<void>
//   - initIntegratedScale() / disposeIntegratedScale()
//
// Use the same protected-surface harness as
// test/unit/.../protected_surface_test.dart (cup warmer style).
```

Mirror the cup-warmer protected-surface test harness for shape.

**Step 2: Run** — fails.

**Step 3: Implement**

Create `integrated_scale_capability.dart`:

```dart
part of 'unified_de1.dart';

enum BengleScaleEndpoint implements LogicalEndpoint {
  weight,
  control;

  @override
  String? get uuid => null; // FW slot TBD
  @override
  String? get representation => null; // FW slot TBD
  @override
  String get name => toString().split('.').last;
}

mixin IntegratedScaleCapability on UnifiedDe1 {
  final BehaviorSubject<ScaleSnapshot> _bengleWeight = BehaviorSubject();
  StreamSubscription<ByteData>? _bengleWeightSub;
  double _bengleTareOffset = 0.0;

  Stream<ScaleSnapshot> get weightSnapshot => _bengleWeight.stream;

  Future<void> initIntegratedScale() async {
    final weightStream = notificationsForOrNull(BengleScaleEndpoint.weight);
    if (weightStream == null) return; // wire not configured yet
    _bengleWeightSub = weightStream.listen(_handleWeightFrame);
  }

  Future<void> disposeIntegratedScale() async {
    await _bengleWeightSub?.cancel();
    _bengleWeightSub = null;
    if (!_bengleWeight.isClosed) {
      await _bengleWeight.close();
    }
  }

  Future<void> tareIntegratedScale() async {
    final controlEndpoint = BengleScaleEndpoint.control;
    if (controlEndpoint.uuid == null && controlEndpoint.representation == null) {
      // Not yet wired in FW — silently no-op so calls don't throw on
      // real hardware until FW lands. MockBengle has its own impl.
      return;
    }
    await writeEndpoint(
      controlEndpoint,
      _encodeTareCommand(),
      withResponse: false,
    );
    final last = _bengleWeight.valueOrNull;
    if (last != null) _bengleTareOffset = last.weight;
  }

  void _handleWeightFrame(ByteData frame) {
    // FW frame layout TBD. Placeholder — real parsing lands when FW publishes
    // the frame spec. For now, leave unimplemented to surface clearly if
    // anyone wires the notify endpoint without parsing landing.
    log.warning('IntegratedScaleCapability: weight frame received but '
        'parser not implemented yet (FW spec TBD)');
  }

  List<int> _encodeTareCommand() => const [];
}
```

Notes:
- `notificationsForOrNull` may need to be added to the protected surface — if the existing `notificationsFor` throws when wire is null, add a nullable variant. Check existing protected-surface helpers first; if `notificationsFor` already returns `null` for a null wire, use it directly.
- `BehaviorSubject` needs `import 'package:rxdart/rxdart.dart';` if using `part of`, the import goes in `unified_de1.dart`.

Add `BengleMmr.scaleTare`:

```dart
// In bengle_mmr.dart
static const scaleTare = MmrAddress(
  address: 0x00000000, // TBD
  kind: MmrValueKind.uint32,
  // null/no bounds
);
```

Modify `bengle.dart`:

```dart
class Bengle extends UnifiedDe1
    with IntegratedScaleCapability
    implements BengleInterface {
  Bengle({required super.transport});

  // ... existing overrides ...

  @override
  Future<void> onConnect() async {
    await super.onConnect();
    await initIntegratedScale();
  }

  @override
  Future<void> onDisconnect() async {
    await disposeIntegratedScale();
    await super.onDisconnect();
  }
}
```

**Step 4: Run tests + analyze**

```
flutter test test/unit/models/device/impl/de1/unified_de1/integrated_scale_capability_test.dart
flutter analyze
flutter test  # full sweep — important, this touches UnifiedDe1's part-of graph
```
Expected: green.

**Step 5: Commit**

```bash
git add lib/src/models/device/impl/de1/unified_de1/integrated_scale_capability.dart \
        lib/src/models/device/impl/bengle/bengle_mmr.dart \
        lib/src/models/device/impl/bengle/bengle.dart \
        lib/src/models/device/impl/de1/unified_de1/unified_de1.dart \
        test/unit/models/device/impl/de1/unified_de1/integrated_scale_capability_test.dart
git commit -m "feat(bengle): IntegratedScaleCapability mixin (wire identifiers stubbed)"
```

---

## Task 8 — OpenAPI spec + `doc/Api.md` reflect `integratedScale`

**Files:**
- Modify: `assets/api/rest_v1.yml` (capabilities response example)
- Modify: `doc/Api.md:53-55`

**Step 1: Edit spec**

Find the response schema/example for `GET /api/v1/machine/capabilities` in `rest_v1.yml`. Update example to `["cupWarmer", "integratedScale"]` and update the description to enumerate both values.

**Step 2: Edit `doc/Api.md`**

Update the row:

```markdown
| GET | `/api/v1/machine/capabilities` | List capability identifiers (`cupWarmer`, `integratedScale`) supported by the connected machine | |
```

**Step 3: Smoke check** — no tests, but run the spec validator if present in the repo (search the `Makefile` or `pubspec.yaml` for an OpenAPI lint target).

**Step 4: Commit**

```bash
git add assets/api/rest_v1.yml doc/Api.md
git commit -m "docs(api): include integratedScale in capabilities"
```

---

## Task 9 — `doc/DeviceManagement.md` precedence note

**Files:**
- Modify: `doc/DeviceManagement.md`

**Step 1: Append a short section**

Add (near the existing scale-connection paragraph):

```markdown
### Bengle integrated scale

When a Bengle is the connected machine, its integrated scale is auto-connected
to `ScaleController` as a virtual `BengleVirtualScale`. External scales (HDS,
Decent, Acaia, etc.) take precedence: connecting an external scale swaps the
virtual one out; disconnecting the external scale (while the machine remains
connected) reattaches the virtual.

Capability discovery: `GET /api/v1/machine/capabilities` includes
`"integratedScale"` when a Bengle is connected. Skins should use this flag
to gate "internal scale" UX hints.
```

**Step 2: Commit**

```bash
git add doc/DeviceManagement.md
git commit -m "docs: document Bengle integrated-scale auto-connect + precedence"
```

---

## Task 10 — End-to-end scenario file

**Files:**
- Create: `.agents/skills/streamline-bridge/scenarios/bengle-integrated-scale.md`

**Step 1: Write the scenario**

Mirror the format of an existing scenario file under that directory (`ls .agents/skills/streamline-bridge/scenarios/`). Cover the demo from the design doc:

1. `sb-dev start --simulate=1 --machine=bengle` (or equivalent env setup — check existing simulate flag conventions).
2. `curl :8080/api/v1/machine/capabilities` → assert response contains `integratedScale`.
3. `websocat ws://localhost:8080/ws/v1/scale/snapshot` (background process).
4. `curl -X PUT :8080/api/v1/scale/tare` → next snapshot weight ≈ 0.
5. `curl -X PUT :8080/api/v1/de1/state/espresso` → weight rises during simulated shot.
6. With workflow target weight 36 g, shot transitions to `idle` when weight ≥ 36.

**Step 2: Run the scenario manually once.** Capture any drift between expected and actual.

**Step 3: Commit**

```bash
git add .agents/skills/streamline-bridge/scenarios/bengle-integrated-scale.md
git commit -m "docs(scenarios): bengle integrated-scale end-to-end recipe"
```

---

## Task 11 — Final sweep + PR prep

**Step 1: Full test + analyze**

```
flutter analyze
flutter test
```
Expected: green.

**Step 2: Archive design + remove implementation plan**

Per CLAUDE.md (close-of-work checklist):

```bash
mkdir -p doc/plans/archive/bengle-integrated-scale
git mv doc/plans/2026-05-05-bengle-integrated-scale.md \
       doc/plans/archive/bengle-integrated-scale/2026-05-05-bengle-integrated-scale.md
rm doc/plans/2026-05-05-bengle-integrated-scale-implementation.md
```

(Implementation plan is not archived — commits + design doc are the durable record.)

**Step 3: Commit archival**

```bash
git add doc/plans/
git commit -m "docs: archive bengle integrated-scale design"
```

**Step 4: Push branch + open PR**

Wait for explicit user instruction before pushing (per CLAUDE.md: "Do not push to remote or create PRs until the user explicitly instructs you to").

When instructed:

```bash
git push -u origin feat/bengle-integrated-scale
gh pr create --base main --title "feat(bengle): integrated scale capability + virtual scale routing" \
  --body "$(cat <<'EOF'
## What
- New `IntegratedScaleCapability` mixin on `UnifiedDe1` (stub wires until FW lands).
- `BengleVirtualScale` adapter routing the integrated scale through `ScaleController`.
- `ConnectionManager` auto-connects the virtual scale on Bengle connect; external scales take precedence.
- `MockBengle` integrates simulated flow into weight for end-to-end demo.
- `/api/v1/machine/capabilities` now lists `integratedScale`.

## Why
Step 5 of the Bengle integration roadmap. Lands the API surface so skins and `ShotController` can drive the integrated scale; real hardware support reduces to filling in FW wire identifiers.

## Test plan
- Unit + integration tests for capability, adapter, auto-connect, precedence.
- End-to-end scenario `.agents/skills/streamline-bridge/scenarios/bengle-integrated-scale.md`.
EOF
)"
```

---

## Files inventory

**Created:**
- `lib/src/models/device/impl/de1/unified_de1/integrated_scale_capability.dart`
- `lib/src/models/device/impl/bengle/bengle_virtual_scale.dart`
- `test/unit/models/device/impl/de1/unified_de1/integrated_scale_capability_test.dart`
- `test/models/device/impl/bengle/mock_bengle_scale_test.dart`
- `test/models/device/impl/bengle/bengle_virtual_scale_test.dart`
- `test/integration/connection_manager_bengle_scale_auto_connect_test.dart`
- `test/integration/connection_manager_bengle_scale_precedence_test.dart`
- `.agents/skills/streamline-bridge/scenarios/bengle-integrated-scale.md`

**Modified:**
- `lib/src/models/device/bengle_interface.dart`
- `lib/src/models/device/impl/bengle/bengle.dart`
- `lib/src/models/device/impl/bengle/bengle_mmr.dart`
- `lib/src/models/device/impl/bengle/mock_bengle.dart`
- `lib/src/models/device/impl/de1/unified_de1/unified_de1.dart` (part-of registration)
- `lib/src/controllers/connection_manager.dart`
- `lib/src/services/webserver/de1handler.dart`
- `test/services/webserver/de1handler_cup_warmer_test.dart` (extend with `integratedScale` cases)
- `assets/api/rest_v1.yml`
- `doc/Api.md`
- `doc/DeviceManagement.md`

**Archived after merge prep:**
- `doc/plans/2026-05-05-bengle-integrated-scale.md` → `doc/plans/archive/bengle-integrated-scale/`

---

## Out of scope (do not do in this PR)

- Bengle FW wire identifiers / frame parser. Stubs only.
- Hardware SAW MMR.
- Multi-scale concurrent streams (P2 follow-up logged in ReaPrime TODO).
- LED strip (step 6) and milk probe (step 7).
- "Internal scale" UX hints in skins.
