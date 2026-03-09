# Connection Manager Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Centralize all device connection policy into a single `ConnectionManager`, eliminating scattered connection logic across 6+ locations.

**Architecture:** New `ConnectionManager` owns preferred device matching, DE1→scale serialization, preference saving, and ambiguity resolution. De1Controller/ScaleController become pure executors. All callers (UI, API, De1StateManager) go through ConnectionManager.

**Tech Stack:** Dart/Flutter, RxDart (BehaviorSubject), fake_async for tests

**Design doc:** `doc/plans/2026-03-08-connection-manager-design.md`
**Problem statement:** `doc/plans/2026-03-07-connection-management-refactor.md`

---

## Task 1: ConnectionStatus Model

**Files:**
- Create: `lib/src/controllers/connection_manager.dart`
- Create: `test/controllers/connection_manager_test.dart`

### Step 1: Create the model types

Create `lib/src/controllers/connection_manager.dart` with:

```dart
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:reaprime/src/models/device/scale.dart';

enum ConnectionPhase {
  idle,
  scanning,
  connectingMachine,
  connectingScale,
  ready,
}

enum AmbiguityReason {
  machinePicker,
  scalePicker,
}

class ConnectionStatus {
  final ConnectionPhase phase;
  final List<De1Interface> foundMachines;
  final List<Scale> foundScales;
  final AmbiguityReason? pendingAmbiguity;
  final String? error;

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
    String? Function()? error,
  }) {
    return ConnectionStatus(
      phase: phase ?? this.phase,
      foundMachines: foundMachines ?? this.foundMachines,
      foundScales: foundScales ?? this.foundScales,
      pendingAmbiguity: pendingAmbiguity != null ? pendingAmbiguity() : this.pendingAmbiguity,
      error: error != null ? error() : this.error,
    );
  }
}
```

### Step 2: Write basic model test

Create `test/controllers/connection_manager_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/controllers/connection_manager.dart';

void main() {
  group('ConnectionStatus', () {
    test('defaults to idle with empty lists', () {
      const status = ConnectionStatus();
      expect(status.phase, ConnectionPhase.idle);
      expect(status.foundMachines, isEmpty);
      expect(status.foundScales, isEmpty);
      expect(status.pendingAmbiguity, isNull);
      expect(status.error, isNull);
    });

    test('copyWith preserves fields not overridden', () {
      const status = ConnectionStatus(phase: ConnectionPhase.scanning);
      final updated = status.copyWith(phase: ConnectionPhase.ready);
      expect(updated.phase, ConnectionPhase.ready);
      expect(updated.foundMachines, isEmpty);
    });

    test('copyWith can null out optional fields', () {
      const status = ConnectionStatus(
        pendingAmbiguity: AmbiguityReason.machinePicker,
        error: 'something',
      );
      final cleared = status.copyWith(
        pendingAmbiguity: () => null,
        error: () => null,
      );
      expect(cleared.pendingAmbiguity, isNull);
      expect(cleared.error, isNull);
    });
  });
}
```

### Step 3: Run tests

Run: `flutter test test/controllers/connection_manager_test.dart`
Expected: 3 passing tests.

### Step 4: Commit

```
feat: add ConnectionStatus model for connection manager
```

---

## Task 2: Test Helpers — Mock Controllers

**Files:**
- Create: `test/helpers/mock_de1_controller.dart`
- Create: `test/helpers/mock_scale_controller.dart`
- Modify: `test/helpers/mock_settings_service.dart` (check if sufficient)

These follow the project pattern of custom test implementations (no mockito).

### Step 1: Create MockDe1Controller

Look at existing `_TestDe1Controller` in `test/controllers/display_controller_test.dart` for the pattern. Create a reusable version:

```dart
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/models/device/de1_interface.dart';
import 'package:rxdart/rxdart.dart';

class MockDe1Controller extends De1Controller {
  MockDe1Controller({required DeviceController controller})
      : super(controller: controller);

  final List<De1Interface> connectCalls = [];
  bool shouldFailConnect = false;

  final BehaviorSubject<De1Interface?> _de1Subject = BehaviorSubject.seeded(null);

  @override
  Stream<De1Interface?> get de1 => _de1Subject.stream;

  @override
  Future<void> connectToDe1(De1Interface de1Interface) async {
    connectCalls.add(de1Interface);
    if (shouldFailConnect) {
      throw Exception('Mock connection failure');
    }
    _de1Subject.add(de1Interface);
  }

  void setDe1(De1Interface? de1) => _de1Subject.add(de1);

  void dispose() => _de1Subject.close();
}
```

### Step 2: Create MockScaleController

```dart
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/models/device/scale.dart';

class MockScaleController extends ScaleController {
  MockScaleController({required DeviceController controller})
      : super(controller: controller);

  final List<Scale> connectCalls = [];
  bool shouldFailConnect = false;

  @override
  Future<void> connectToScale(Scale scale) async {
    connectCalls.add(scale);
    if (shouldFailConnect) {
      throw Exception('Mock scale connection failure');
    }
  }
}
```

**Note:** The exact shape of these mocks may need adjustment when implementing — ScaleController's constructor sets up the auto-connect listener which we'll eventually remove. For now, the mock may need to override that behavior or we may need to check if the constructor's listener causes issues in tests. Adjust as needed.

### Step 3: Run existing tests to verify mocks don't break anything

Run: `flutter test`
Expected: All existing tests still pass.

### Step 4: Commit

```
test: add reusable MockDe1Controller and MockScaleController test helpers
```

---

## Task 3: ConnectionManager — Skeleton with Status Stream

**Files:**
- Modify: `lib/src/controllers/connection_manager.dart`
- Modify: `test/controllers/connection_manager_test.dart`

### Step 1: Write test for initial status

```dart
import 'package:fake_async/fake_async.dart';

// Add to existing test file:
group('ConnectionManager', () {
  late DeviceController deviceController;
  late MockDe1Controller de1Controller;
  late MockScaleController scaleController;
  late SettingsController settingsController;
  late ConnectionManager connectionManager;

  setUp(() {
    final discoveryService = MockDeviceDiscoveryService();
    deviceController = DeviceController([discoveryService]);
    de1Controller = MockDe1Controller(controller: deviceController);
    scaleController = MockScaleController(controller: deviceController);
    settingsController = SettingsController(MockSettingsService());
    connectionManager = ConnectionManager(
      deviceController: deviceController,
      de1Controller: de1Controller,
      scaleController: scaleController,
      settingsController: settingsController,
    );
  });

  test('initial status is idle', () {
    fakeAsync((async) {
      async.flushMicrotasks();
      // Access current status from the BehaviorSubject
      expect(connectionManager.currentStatus.phase, ConnectionPhase.idle);
    });
  });
});
```

### Step 2: Run test — expect failure

Run: `flutter test test/controllers/connection_manager_test.dart`
Expected: FAIL — `ConnectionManager` class not yet defined.

### Step 3: Implement ConnectionManager skeleton

Add to `lib/src/controllers/connection_manager.dart`:

```dart
import 'dart:async';
import 'package:rxdart/rxdart.dart';
import 'package:reaprime/src/controllers/de1_controller.dart';
import 'package:reaprime/src/controllers/device_controller.dart';
import 'package:reaprime/src/controllers/scale_controller.dart';
import 'package:reaprime/src/settings/settings_controller.dart';

class ConnectionManager {
  final DeviceController deviceController;
  final De1Controller de1Controller;
  final ScaleController scaleController;
  final SettingsController settingsController;

  final BehaviorSubject<ConnectionStatus> _statusSubject =
      BehaviorSubject.seeded(const ConnectionStatus());

  Stream<ConnectionStatus> get status => _statusSubject.stream;
  ConnectionStatus get currentStatus => _statusSubject.value;

  ConnectionManager({
    required this.deviceController,
    required this.de1Controller,
    required this.scaleController,
    required this.settingsController,
  });

  Future<void> connectMachine(De1Interface machine) async {
    // TODO: Task 4
  }

  Future<void> connectScale(Scale scale) async {
    // TODO: Task 5
  }

  Future<void> connect({/* BuildContext? uiContext */}) async {
    // TODO: Task 6
  }

  Future<void> disconnectMachine() async {
    // TODO
  }

  Future<void> disconnectScale() async {
    // TODO
  }

  void dispose() {
    _statusSubject.close();
  }
}
```

### Step 4: Run test — expect pass

Run: `flutter test test/controllers/connection_manager_test.dart`
Expected: PASS

### Step 5: Commit

```
feat: add ConnectionManager skeleton with status stream
```

---

## Task 4: ConnectionManager — connectMachine()

**Files:**
- Modify: `lib/src/controllers/connection_manager.dart`
- Modify: `test/controllers/connection_manager_test.dart`

### Step 1: Write tests for connectMachine

```dart
group('connectMachine', () {
  test('delegates to De1Controller and saves preference', () async {
    await settingsController.loadSettings();
    final machine = MockDe1(); // Use existing test DE1 or create one

    await connectionManager.connectMachine(machine);

    expect(de1Controller.connectCalls, [machine]);
    expect(settingsController.preferredMachineId, machine.deviceId);
  });

  test('does not save preference on failure', () async {
    await settingsController.loadSettings();
    de1Controller.shouldFailConnect = true;
    final machine = MockDe1();

    expect(
      () => connectionManager.connectMachine(machine),
      throwsException,
    );
    expect(settingsController.preferredMachineId, isNull);
  });

  test('rejects concurrent connection attempts', () async {
    await settingsController.loadSettings();
    final machine = MockDe1();

    // Start first connection (will complete)
    final first = connectionManager.connectMachine(machine);
    // Start second immediately — should be rejected
    final second = connectionManager.connectMachine(machine);

    await first;
    // second should complete without calling connectToDe1 again
    await second;
    expect(de1Controller.connectCalls.length, 1);
  });

  test('emits connectingMachine then ready phases', () async {
    await settingsController.loadSettings();
    final machine = MockDe1();
    final phases = <ConnectionPhase>[];
    connectionManager.status.listen((s) => phases.add(s.phase));

    await connectionManager.connectMachine(machine);

    expect(phases, contains(ConnectionPhase.connectingMachine));
    expect(phases.last, ConnectionPhase.ready);
  });
});
```

**Note:** You'll need a `MockDe1` — a simple implementation of `De1Interface` for testing. Check if the existing `_TestDe1` from `test/controllers/display_controller_test.dart` can be extracted or create a minimal one in `test/helpers/`. It needs at minimum a `deviceId` getter and to implement enough of `De1Interface` to compile.

### Step 2: Run tests — expect failure

Run: `flutter test test/controllers/connection_manager_test.dart`
Expected: FAIL

### Step 3: Implement connectMachine

```dart
bool _isConnectingMachine = false;

Future<void> connectMachine(De1Interface machine) async {
  if (_isConnectingMachine) return;
  _isConnectingMachine = true;

  _statusSubject.add(currentStatus.copyWith(
    phase: ConnectionPhase.connectingMachine,
    error: () => null,
  ));

  try {
    await de1Controller.connectToDe1(machine);
    await settingsController.setPreferredMachineId(machine.deviceId);
    _statusSubject.add(currentStatus.copyWith(phase: ConnectionPhase.ready));
  } catch (e) {
    _statusSubject.add(currentStatus.copyWith(
      phase: ConnectionPhase.idle,
      error: () => e.toString(),
    ));
    rethrow;
  } finally {
    _isConnectingMachine = false;
  }
}
```

### Step 4: Run tests — expect pass

Run: `flutter test test/controllers/connection_manager_test.dart`
Expected: PASS

### Step 5: Commit

```
feat: implement ConnectionManager.connectMachine with guard and preference saving
```

---

## Task 5: ConnectionManager — connectScale()

**Files:**
- Modify: `lib/src/controllers/connection_manager.dart`
- Modify: `test/controllers/connection_manager_test.dart`

### Step 1: Write tests for connectScale

Mirror the connectMachine tests but for scale:

```dart
group('connectScale', () {
  test('delegates to ScaleController and saves preference', () async {
    await settingsController.loadSettings();
    final scale = TestScale(); // from test/helpers/test_scale.dart

    await connectionManager.connectScale(scale);

    expect(scaleController.connectCalls, [scale]);
    expect(settingsController.preferredScaleId, scale.deviceId);
  });

  test('does not save preference on failure', () async {
    await settingsController.loadSettings();
    scaleController.shouldFailConnect = true;
    final scale = TestScale();

    expect(
      () => connectionManager.connectScale(scale),
      throwsException,
    );
    expect(settingsController.preferredScaleId, isNull);
  });

  test('rejects concurrent scale connection attempts', () async {
    await settingsController.loadSettings();
    final scale = TestScale();

    final first = connectionManager.connectScale(scale);
    final second = connectionManager.connectScale(scale);

    await first;
    await second;
    expect(scaleController.connectCalls.length, 1);
  });

  test('emits connectingScale phase', () async {
    await settingsController.loadSettings();
    final scale = TestScale();
    final phases = <ConnectionPhase>[];
    connectionManager.status.listen((s) => phases.add(s.phase));

    await connectionManager.connectScale(scale);

    expect(phases, contains(ConnectionPhase.connectingScale));
  });
});
```

### Step 2: Run tests — expect failure

### Step 3: Implement connectScale

```dart
bool _isConnectingScale = false;

Future<void> connectScale(Scale scale) async {
  if (_isConnectingScale) return;
  _isConnectingScale = true;

  _statusSubject.add(currentStatus.copyWith(
    phase: ConnectionPhase.connectingScale,
    error: () => null,
  ));

  try {
    await scaleController.connectToScale(scale);
    await settingsController.setPreferredScaleId(scale.deviceId);
    _statusSubject.add(currentStatus.copyWith(phase: ConnectionPhase.ready));
  } catch (e) {
    // Scale failure is non-blocking — emit ready if machine is connected, else idle
    _statusSubject.add(currentStatus.copyWith(
      phase: ConnectionPhase.ready, // scale failure doesn't block
      error: () => null, // swallow scale errors silently
    ));
  } finally {
    _isConnectingScale = false;
  }
}
```

**Design note:** Scale connection failure is silent and non-blocking per design. The phase goes to `ready` (not `idle`) because the machine may already be connected. Adjust the phase logic based on whether a machine is currently connected — check `de1Controller.de1` stream.

### Step 4: Run tests — expect pass

### Step 5: Commit

```
feat: implement ConnectionManager.connectScale with guard and preference saving
```

---

## Task 6: ConnectionManager — connect() Machine Phase

This is the main orchestration method. Split into machine phase (this task) and scale phase (next task).

**Files:**
- Modify: `lib/src/controllers/connection_manager.dart`
- Modify: `test/controllers/connection_manager_test.dart`

### Step 1: Write tests for machine phase

```dart
group('connect() — machine phase', () {
  test('no preferred, 1 machine found — auto-connects', () async {
    await settingsController.loadSettings();
    final machine = MockDe1();
    discoveryService.addDevice(machine);

    await connectionManager.connect();

    expect(de1Controller.connectCalls, [machine]);
    expect(settingsController.preferredMachineId, machine.deviceId);
  });

  test('no preferred, 0 machines — emits error', () async {
    await settingsController.loadSettings();

    await connectionManager.connect();

    expect(connectionManager.currentStatus.phase, ConnectionPhase.idle);
    // No machines found, status reflects this
    expect(connectionManager.currentStatus.foundMachines, isEmpty);
  });

  test('no preferred, many machines, no uiContext — emits machinePicker ambiguity', () async {
    await settingsController.loadSettings();
    discoveryService.addDevice(MockDe1(id: 'machine-1'));
    discoveryService.addDevice(MockDe1(id: 'machine-2'));

    await connectionManager.connect(); // no uiContext

    expect(connectionManager.currentStatus.pendingAmbiguity, AmbiguityReason.machinePicker);
    expect(connectionManager.currentStatus.foundMachines.length, 2);
    expect(de1Controller.connectCalls, isEmpty); // didn't connect — waiting for user
  });

  test('preferred machine found — connects directly', () async {
    await settingsController.loadSettings();
    await settingsController.setPreferredMachineId('preferred-machine');
    final machine = MockDe1(id: 'preferred-machine');
    discoveryService.addDevice(machine);

    await connectionManager.connect();

    expect(de1Controller.connectCalls, [machine]);
  });

  test('preferred machine not found, other machines available, no uiContext — emits machinePicker', () async {
    await settingsController.loadSettings();
    await settingsController.setPreferredMachineId('missing-machine');
    discoveryService.addDevice(MockDe1(id: 'other-machine'));

    await connectionManager.connect();

    expect(connectionManager.currentStatus.pendingAmbiguity, AmbiguityReason.machinePicker);
  });

  test('emits scanning phase during scan', () async {
    await settingsController.loadSettings();
    final phases = <ConnectionPhase>[];
    connectionManager.status.listen((s) => phases.add(s.phase));

    await connectionManager.connect();

    expect(phases.first, ConnectionPhase.scanning);
  });
});
```

### Step 2: Run tests — expect failure

### Step 3: Implement connect() machine phase

```dart
Future<void> connect({/* BuildContext? uiContext */}) async {
  // Emit scanning
  _statusSubject.add(const ConnectionStatus(phase: ConnectionPhase.scanning));

  // Scan (full, unfiltered)
  await deviceController.scanForDevices(autoConnect: false);

  // Collect results
  final devices = deviceController.devices;
  final machines = devices.whereType<De1Interface>().toList();
  final scales = devices.whereType<Scale>().toList();

  _statusSubject.add(ConnectionStatus(
    phase: ConnectionPhase.scanning,
    foundMachines: machines,
    foundScales: scales,
  ));

  // Machine phase
  final preferredMachineId = settingsController.preferredMachineId;

  if (machines.isEmpty) {
    _statusSubject.add(ConnectionStatus(
      phase: ConnectionPhase.idle,
      foundMachines: machines,
      foundScales: scales,
    ));
    return;
  }

  De1Interface? target;

  if (preferredMachineId != null) {
    target = machines.cast<De1Interface?>().firstWhere(
      (m) => m!.deviceId == preferredMachineId,
      orElse: () => null,
    );
  }

  if (target == null && machines.length == 1) {
    target = machines.first;
  }

  if (target != null) {
    await connectMachine(target);
    // Continue to scale phase (Task 7)
    await _connectScalePhase(scales: scales);
  } else {
    // Multiple machines, no clear target — need user input
    _statusSubject.add(ConnectionStatus(
      phase: ConnectionPhase.idle,
      foundMachines: machines,
      foundScales: scales,
      pendingAmbiguity: AmbiguityReason.machinePicker,
    ));
  }
}
```

**Note on scan timing:** `DeviceController.scanForDevices()` returns a `Future` but devices appear asynchronously on the device stream during the scan. The implementation may need to wait for the scan timeout or listen to the scanning stream to know when the scan is complete. Check `DeviceController.scanForDevices` return behavior — it may complete before all devices are discovered. You may need to await `deviceController.scanningStream.firstWhere((s) => !s)` to wait for scan completion.

### Step 4: Run tests — expect pass

### Step 5: Commit

```
feat: implement ConnectionManager.connect() machine phase with preferred device policy
```

---

## Task 7: ConnectionManager — connect() Scale Phase

**Files:**
- Modify: `lib/src/controllers/connection_manager.dart`
- Modify: `test/controllers/connection_manager_test.dart`

### Step 1: Write tests for scale phase

```dart
group('connect() — scale phase', () {
  test('preferred scale found — connects silently after machine', () async {
    await settingsController.loadSettings();
    final machine = MockDe1();
    final scale = TestScale(id: 'preferred-scale');
    await settingsController.setPreferredScaleId('preferred-scale');
    discoveryService.addDevice(machine);
    discoveryService.addDevice(scale);

    await connectionManager.connect();

    expect(de1Controller.connectCalls.length, 1);
    expect(scaleController.connectCalls, [scale]);
  });

  test('no preferred, 1 scale found — connects silently', () async {
    await settingsController.loadSettings();
    final machine = MockDe1();
    final scale = TestScale();
    discoveryService.addDevice(machine);
    discoveryService.addDevice(scale);

    await connectionManager.connect();

    expect(scaleController.connectCalls, [scale]);
  });

  test('no preferred, many scales, no uiContext — skips scale', () async {
    await settingsController.loadSettings();
    final machine = MockDe1();
    discoveryService.addDevice(machine);
    discoveryService.addDevice(TestScale(id: 'scale-1'));
    discoveryService.addDevice(TestScale(id: 'scale-2'));

    await connectionManager.connect(); // no uiContext

    expect(scaleController.connectCalls, isEmpty);
    // Machine still connected
    expect(de1Controller.connectCalls.length, 1);
  });

  test('preferred scale not found — does nothing', () async {
    await settingsController.loadSettings();
    await settingsController.setPreferredScaleId('missing-scale');
    final machine = MockDe1();
    discoveryService.addDevice(machine);

    await connectionManager.connect();

    expect(scaleController.connectCalls, isEmpty);
    // Phase is still ready (machine connected)
    expect(connectionManager.currentStatus.phase, ConnectionPhase.ready);
  });

  test('scale failure does not affect machine connection', () async {
    await settingsController.loadSettings();
    scaleController.shouldFailConnect = true;
    final machine = MockDe1();
    final scale = TestScale();
    discoveryService.addDevice(machine);
    discoveryService.addDevice(scale);

    await connectionManager.connect();

    expect(de1Controller.connectCalls.length, 1);
    expect(connectionManager.currentStatus.phase, ConnectionPhase.ready);
  });
});
```

### Step 2: Run tests — expect failure

### Step 3: Implement scale phase

```dart
Future<void> _connectScalePhase({
  required List<Scale> scales,
  /* BuildContext? uiContext, */
}) async {
  final preferredScaleId = settingsController.preferredScaleId;

  if (scales.isEmpty) return;

  Scale? target;

  if (preferredScaleId != null) {
    target = scales.cast<Scale?>().firstWhere(
      (s) => s!.deviceId == preferredScaleId,
      orElse: () => null,
    );
    if (target == null) return; // preferred not found — do nothing
  }

  if (target == null && scales.length == 1) {
    target = scales.first;
  }

  if (target != null) {
    await connectScale(target);
  }
  // else: multiple scales, no preference, no uiContext → skip silently
  // Skins can read foundScales from status and resolve via connectScale()
}
```

### Step 4: Run tests — expect pass

### Step 5: Commit

```
feat: implement ConnectionManager scale phase — silent, non-blocking
```

---

## Task 8: Wire ConnectionManager in main.dart

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/src/app.dart` (route injection)

### Step 1: Create ConnectionManager in main.dart

Add after ScaleController creation (~line 252):

```dart
final connectionManager = ConnectionManager(
  deviceController: deviceController,
  de1Controller: de1Controller,
  scaleController: scaleController,
  settingsController: settingsController,
);
```

Pass it to the web server and to the app widget, alongside existing controllers.

### Step 2: Pass to routes that need it

Update `app.dart` route generation to pass `connectionManager` to:
- `DeviceDiscoveryView` / `PermissionsView` (wherever the discovery flow starts)
- `SettingsTile` (via the home screen)
- Debug views (`SampleItemListView`)

### Step 3: Pass to web server

Add `connectionManager` parameter to `startWebServer()` and thread it to `DevicesHandler`.

### Step 4: Run `flutter analyze` and `flutter test`

Expected: No analyzer errors, all tests pass.

### Step 5: Commit

```
feat: wire ConnectionManager into app initialization and routing
```

---

## Task 9: Migrate DeviceDiscoveryView

**Files:**
- Modify: `lib/src/device_discovery_feature/device_discovery_view.dart`

This is the largest migration. The view currently owns ~500 lines of connection logic.

### Step 1: Replace connection logic with ConnectionManager

The view should:
1. Accept `ConnectionManager` as a constructor parameter
2. In `initState()`: call `connectionManager.connect(uiContext: context)` (or equivalent)
3. Listen to `connectionManager.status` stream for UI state:
   - `scanning` → show progress indicator
   - `connectingMachine` / `connectingScale` → show "Connecting..." state
   - `ready` → navigate to home/skin
   - `pendingAmbiguity: machinePicker` → show device selection dialog
   - `pendingAmbiguity: scalePicker` → show scale selection dialog
   - `error` → show error state with retry button
4. Device selection dialog calls `connectionManager.connectMachine(selected)` or `connectionManager.connectScale(selected)`
5. Retry button calls `connectionManager.connect(uiContext: context)` again

### Step 2: Remove all of the following from the view

- `_autoConnectDeviceId` field and logic
- `_connectingDeviceId` field and logic
- `_startDirectConnect()` method
- `_fallbackToFullScan()` method
- `_startNormalScanWithTimeout()` method
- Direct calls to `de1Controller.connectToDe1()` and `scaleController.connectToScale()`
- Direct calls to `deviceController.scanForSpecificDevices()`
- The `_discoverySubscription` device stream listener (ConnectionManager handles this now)

### Step 3: Handle uiContext for dialogs

**Design decision:** The `BuildContext` parameter for showing dialogs has a few options:
- **Option A:** ConnectionManager accepts a `BuildContext` and shows dialogs itself — mixes UI into business logic.
- **Option B (recommended):** ConnectionManager emits `pendingAmbiguity` status, and the view reacts by showing dialogs. This keeps ConnectionManager UI-free.

With Option B, the view's `StreamBuilder` on `connectionManager.status` handles:
```dart
if (status.pendingAmbiguity == AmbiguityReason.machinePicker) {
  // Show machine picker with status.foundMachines
  // On selection: connectionManager.connectMachine(selected)
}
```

### Step 4: Run `flutter analyze` and `flutter test`

### Step 5: Commit

```
refactor: simplify DeviceDiscoveryView to use ConnectionManager
```

---

## Task 10: Migrate SettingsTile

**Files:**
- Modify: `lib/src/home_feature/tiles/settings_tile.dart`

### Step 1: Replace `_handleScan` / `_searchAndConnect`

Replace the entire scan+wait+connect logic with:

```dart
Future<void> _handleScan(BuildContext context) async {
  setState(() => _isScanning = true);
  await widget.connectionManager.connect();
  if (mounted) setState(() => _isScanning = false);
}
```

The ConnectionManager handles everything: scanning, preferred device matching, connection.

If the status shows `pendingAmbiguity`, SettingsTile can show a dialog (or this can be handled at a higher level).

### Step 2: Remove hardcoded delay, manual device selection logic

Remove:
- `Future.delayed(Duration(seconds: 10))` / `45` scan wait
- Manual `deviceController.devices` queries
- Direct `controller.connectToDe1()` calls
- The `DeviceSelectionWidget` dialog (or move it to be triggered by status ambiguity)

### Step 3: Update constructor to accept ConnectionManager

### Step 4: Run `flutter analyze` and `flutter test`

### Step 5: Commit

```
refactor: simplify SettingsTile scan to use ConnectionManager
```

---

## Task 11: Migrate De1StateManager

**Files:**
- Modify: `lib/src/controllers/de1_state_manager.dart`

### Step 1: Replace `_triggerScaleScan()`

Currently (lines ~560-580):
```dart
void _triggerScaleScan() {
  if (_isScanningSscales) return;
  _isScanningSscales = true;
  _deviceController.scanForDevices(autoConnect: true);
  // ... wait for scale connection with timeout
}
```

Replace with:
```dart
void _triggerScaleScan() {
  _connectionManager.connect(); // no uiContext — headless
}
```

The ConnectionManager handles scanning, preferred device matching, and scale connection. No need for the `_isScanningSscales` guard — ConnectionManager has its own concurrent connection guard.

### Step 2: Add ConnectionManager as a constructor dependency

Update De1StateManager constructor and its creation in `app.dart` `initState()`.

### Step 3: Remove `_isScanningSscales` field and related logic

### Step 4: Run `flutter analyze` and `flutter test`

### Step 5: Commit

```
refactor: De1StateManager delegates to ConnectionManager for scale reconnect
```

---

## Task 12: Migrate DevicesHandler

**Files:**
- Modify: `lib/src/services/webserver/devices_handler.dart`

### Step 1: Update scan command

Replace:
```dart
// scan command
await _deviceController.scanForDevices(autoConnect: connect);
```

With:
```dart
await _connectionManager.connect();
```

This gives API clients preferred-device-aware scanning — the core API parity fix.

### Step 2: Update connect command

Replace:
```dart
// _connectDevice dispatch
switch (device.type) {
  case DeviceType.machine:
    await _de1Controller.connectToDe1(device as De1Interface);
  case DeviceType.scale:
    await _scaleController.connectToScale(device as Scale);
  ...
}
```

With:
```dart
switch (device.type) {
  case DeviceType.machine:
    await _connectionManager.connectMachine(device as De1Interface);
  case DeviceType.scale:
    await _connectionManager.connectScale(device as Scale);
  case DeviceType.sensor:
    await (device as Sensor).onConnect(); // sensors unchanged
}
```

### Step 3: Add ConnectionStatus to WebSocket stream

Add `connectionManager.status` as a subscription source in `DevicesStateAggregator`. Include `connectionStatus` field in the snapshot JSON:

```json
{
  "timestamp": "...",
  "devices": [...],
  "scanning": true,
  "connectionStatus": {
    "phase": "connectingMachine",
    "foundMachines": [...],
    "foundScales": [...],
    "pendingAmbiguity": null,
    "error": null
  }
}
```

### Step 4: Update DevicesHandler constructor to accept ConnectionManager

### Step 5: Run `flutter analyze` and `flutter test test/devices_handler_test.dart`

### Step 6: Commit

```
refactor: DevicesHandler delegates to ConnectionManager, exposes ConnectionStatus on WebSocket
```

---

## Task 13: Remove ScaleController Auto-Connect & DeviceController shouldAutoConnect

This is the cleanup step — safe to do only after all callers are migrated.

**Files:**
- Modify: `lib/src/controllers/scale_controller.dart`
- Modify: `lib/src/controllers/device_controller.dart`
- Modify: `lib/main.dart` (remove preferredScaleId listener propagation)

### Step 1: Remove ScaleController auto-connect listener

Remove from ScaleController constructor:
```dart
_deviceStreamSubscription = _deviceController.deviceStream.listen((devices) async {
  // ... auto-connect logic
});
```

Remove fields: `_preferredScaleId`, `_deviceStreamSubscription`, the `preferredScaleId` setter.

ScaleController becomes a pure executor: just `connectToScale()` and `disconnectScale()`.

### Step 2: Remove DeviceController shouldAutoConnect

Remove from DeviceController:
- `bool _autoConnect` field
- `bool get shouldAutoConnect` getter
- The temporary `_autoConnect = autoConnect` override in `scanForDevices()`
- The `autoConnect` parameter from `scanForDevices()` signature (always just scans)

Update all `scanForDevices(autoConnect: ...)` call sites to remove the parameter. The only remaining caller should be ConnectionManager's `connect()`.

### Step 3: Remove preferredScaleId listener in main.dart

Remove:
```dart
settingsController.addListener(() {
  scaleController.preferredScaleId = settingsController.preferredScaleId;
});
```

ConnectionManager reads preferences directly from SettingsController.

### Step 4: Run `flutter analyze` and `flutter test`

Expected: All tests pass. Some existing tests may need updating if they used `autoConnect` parameter.

### Step 5: Commit

```
refactor: remove auto-connect from ScaleController and shouldAutoConnect from DeviceController
```

---

## Task 14: Fix Debug Views

**Files:**
- Modify: `lib/src/sample_feature/sample_item_list_view.dart`
- Modify: `lib/src/sample_feature/sample_item_details_view.dart`
- Modify: `lib/src/sample_feature/scale_debug_view.dart`

### Step 1: Update SampleItemListView

Add two action buttons per device in the list:
- **Inspect** — navigates to debug detail view, calls `device.onConnect()` there
- **Connect** — calls `connectionManager.connectMachine(device)` or `connectionManager.connectScale(device)`

Accept `ConnectionManager` as a constructor parameter.

### Step 2: Fix ScaleDebugView — remove onConnect from build

Current bug: `widget.scale.onConnect()` is called in `build()` — runs on every rebuild.

Change to: the view receives the scale but does NOT call `onConnect()` in build. Instead:
- If navigated via "Inspect" button: caller calls `scale.onConnect()` before navigation, or the view calls it once in `initState()`
- If navigated via "Connect" button: the ConnectionManager already connected it

```dart
@override
void initState() {
  super.initState();
  if (!_alreadyConnected) {
    widget.scale.onConnect();
  }
}
```

Or simpler: pass a boolean `inspect` parameter. If true, call `onConnect()` in `initState()`. If false (already connected via ConnectionManager), skip.

### Step 3: Same pattern for De1DebugView

De1DebugView currently receives an already-connected machine. Add the same inspect/connect distinction.

### Step 4: Run `flutter analyze`

### Step 5: Commit

```
fix: debug views use Inspect/Connect pattern, remove onConnect from build
```

---

## Task 15: Remove scanForSpecificDevices from DeviceController

**Files:**
- Modify: `lib/src/controllers/device_controller.dart`

### Step 1: Check for remaining callers

Search codebase for `scanForSpecificDevice` and `scanForSpecificDevices`. After Task 9 (DeviceDiscoveryView migration), there should be no callers.

### Step 2: Remove the methods

Remove `scanForSpecificDevice()` and `scanForSpecificDevices()` from DeviceController.

### Step 3: Run `flutter analyze` and `flutter test`

### Step 4: Commit

```
refactor: remove unused scanForSpecificDevice(s) from DeviceController
```

---

## Task 16: Integration Verification

### Step 1: Run full test suite

```bash
flutter test
```

Expected: All tests pass.

### Step 2: Run static analysis

```bash
flutter analyze
```

Expected: No issues.

### Step 3: Run app in simulate mode

```bash
flutter run --dart-define=simulate=1
```

Verify:
- App starts and shows discovery/connection flow
- Simulated DE1 connects automatically (single device)
- Scale connects after DE1
- Home screen loads
- Settings tile scan button works
- Device management page shows correct preferred devices

### Step 4: Verify via MCP tools (if available)

```
app_start with connectDevice: "MockDe1", connectScale: "MockScale"
machine_get_state — verify connected
devices_list — verify both devices show connected
```

### Step 5: Commit any fixes found during integration

---

## Task Order Summary

| Task | What | Depends on |
|------|------|-----------|
| 1 | ConnectionStatus model | — |
| 2 | Mock controller test helpers | — |
| 3 | ConnectionManager skeleton | 1, 2 |
| 4 | connectMachine() | 3 |
| 5 | connectScale() | 3 |
| 6 | connect() machine phase | 4 |
| 7 | connect() scale phase | 5, 6 |
| 8 | Wire in main.dart/app.dart | 7 |
| 9 | Migrate DeviceDiscoveryView | 8 |
| 10 | Migrate SettingsTile | 8 |
| 11 | Migrate De1StateManager | 8 |
| 12 | Migrate DevicesHandler | 8 |
| 13 | Remove old auto-connect logic | 9, 10, 11, 12 |
| 14 | Fix debug views | 8 |
| 15 | Remove scanForSpecificDevices | 9, 13 |
| 16 | Integration verification | all |

Tasks 9-12 and 14 are independent of each other and can be parallelized.
