# ConnectionState Refactor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a `discovered` state to ConnectionState and propagate ConnectionState through the transport layer, replacing `Stream<bool>`.

**Architecture:** Two-phase refactor. Phase 1 adds the `discovered` enum value and updates all seeds/listeners. Phase 2 changes `DataTransport.connectionState` from `Stream<bool>` to `Stream<ConnectionState>`, eliminating duplicated bool→enum mapping in ~15 device implementations.

**Tech Stack:** Dart/Flutter, RxDart BehaviorSubjects, flutter_blue_plus, universal_ble

**Design doc:** `doc/plans/2026-03-06-connection-state-refactor-design.md`

---

## Phase 1: Add `discovered` state

### Task 1: Add `discovered` to ConnectionState enum

**Files:**
- Modify: `lib/src/models/device/device.dart:17`

**Step 1: Add the enum value**

Change:
```dart
enum ConnectionState { connecting, connected, disconnecting, disconnected }
```
To:
```dart
enum ConnectionState { discovered, connecting, connected, disconnecting, disconnected }
```

**Step 2: Run analyze**

Run: `flutter analyze`
Expected: Warnings about non-exhaustive switch statements (De1Controller) — these will be fixed in the next tasks.

---

### Task 2: Update De1Controller switch statement

**Files:**
- Modify: `lib/src/controllers/de1_controller.dart:92-102`

**Step 1: Add discovered case**

Change:
```dart
switch (connectionData) {
  case ConnectionState.connecting:
    _log.info("device $_de1 connecting");
  case ConnectionState.connected:
    _log.info("device $_de1 connected");
  case ConnectionState.disconnecting:
    _log.info("device $_de1 disconnecting");
  case ConnectionState.disconnected:
    _log.info("device $_de1 disconnected, resetting");
    _onDisconnect();
}
```
To:
```dart
switch (connectionData) {
  case ConnectionState.discovered:
    _log.info("device $_de1 discovered");
  case ConnectionState.connecting:
    _log.info("device $_de1 connecting");
  case ConnectionState.connected:
    _log.info("device $_de1 connected");
  case ConnectionState.disconnecting:
    _log.info("device $_de1 disconnecting");
  case ConnectionState.disconnected:
    _log.info("device $_de1 disconnected, resetting");
    _onDisconnect();
}
```

**Step 2: Run analyze**

Run: `flutter analyze`
Expected: PASS (or remaining warnings from other files)

---

### Task 3: Update ScaleController

**Files:**
- Modify: `lib/src/controllers/scale_controller.dart:86-87` and `lib/src/controllers/scale_controller.dart:120-126`

**Step 1: Change seed from `disconnected` to `discovered`**

Change line 86-87:
```dart
final BehaviorSubject<ConnectionState> _connectionController =
    BehaviorSubject.seeded(ConnectionState.disconnected);
```
To:
```dart
final BehaviorSubject<ConnectionState> _connectionController =
    BehaviorSubject.seeded(ConnectionState.discovered);
```

**Step 2: Update `_processConnection` to ignore `discovered`**

Change lines 120-126:
```dart
_processConnection(ConnectionState d) {
  log.info('scale connection update: ${d.name}');
  _connectionController.add(d);
  if (d == ConnectionState.disconnected) {
    _onDisconnect();
  }
}
```
To:
```dart
_processConnection(ConnectionState d) {
  log.info('scale connection update: ${d.name}');
  _connectionController.add(d);
  if (d == ConnectionState.disconnected) {
    _onDisconnect();
  }
  // ConnectionState.discovered is ignored — it means "not yet connected",
  // not "lost connection". Only disconnected triggers cleanup.
}
```

**Step 3: Run analyze and tests**

Run: `flutter analyze && flutter test`

---

### Task 4: Update UnifiedDe1 connection state mapping

**Files:**
- Modify: `lib/src/models/device/impl/de1/unified_de1/unified_de1.dart:54-57`

**Step 1: Add stateful bool→ConnectionState mapping**

Change:
```dart
@override
Stream<ConnectionState> get connectionState => _transport.connectionState.map(
  (e) => e ? ConnectionState.connected : ConnectionState.disconnected,
);
```
To:
```dart
bool _hasBeenConnected = false;

@override
Stream<ConnectionState> get connectionState => _transport.connectionState.map(
  (e) {
    if (e) {
      _hasBeenConnected = true;
      return ConnectionState.connected;
    }
    return _hasBeenConnected
        ? ConnectionState.disconnected
        : ConnectionState.discovered;
  },
);
```

**Step 2: Run analyze and tests**

Run: `flutter analyze && flutter test`

---

### Task 5: Update all scale implementation seeds

All scale implementations use the same pattern. Change `BehaviorSubject.seeded(ConnectionState.connecting)` to `BehaviorSubject.seeded(ConnectionState.discovered)` in each file.

**Files (seed line numbers):**
- Modify: `lib/src/models/device/impl/bookoo/miniscale.dart:35`
- Modify: `lib/src/models/device/impl/difluid/difluid_scale.dart:48`
- Modify: `lib/src/models/device/impl/skale/skale2_scale.dart:54`
- Modify: `lib/src/models/device/impl/felicita/arc.dart:39`
- Modify: `lib/src/models/device/impl/smartchef/smartchef_scale.dart:39`
- Modify: `lib/src/models/device/impl/decent_scale/scale.dart:49`
- Modify: `lib/src/models/device/impl/atomheart/atomheart_scale.dart:46`
- Modify: `lib/src/models/device/impl/eureka/eureka_scale.dart:46`
- Modify: `lib/src/models/device/impl/varia/varia_aku_scale.dart:51`
- Modify: `lib/src/models/device/impl/blackcoffee/blackcoffee_scale.dart:40`
- Modify: `lib/src/models/device/impl/hiroia/hiroia_scale.dart:40`
- Modify: `lib/src/models/device/impl/acaia/acaia_scale.dart:54`
- Modify: `lib/src/models/device/impl/acaia/acaia_pyxis_scale.dart:58`

**Step 1: In each file, change the seed**

Change (in each file):
```dart
BehaviorSubject.seeded(ConnectionState.connecting);
```
To:
```dart
BehaviorSubject.seeded(ConnectionState.discovered);
```

**Do NOT change:**
- Mock devices (`mock_de1.dart`, `mock_scale.dart`) — they seed with `ConnectionState.connected` which is correct for pre-connected mocks.

**Step 2: Run analyze and tests**

Run: `flutter analyze && flutter test`

---

### Task 6: Update sensor and serial scale seeds

**Files:**
- Modify: `lib/src/models/device/impl/sensor/debug_port.dart:19`
- Modify: `lib/src/models/device/impl/sensor/sensor_basket.dart:19`
- Modify: `lib/src/models/device/impl/decent_scale/scale_serial.dart:19`

**Step 1: Change seeds from `connecting` to `discovered`**

In each file, change:
```dart
BehaviorSubject.seeded(ConnectionState.connecting);
```
To:
```dart
BehaviorSubject.seeded(ConnectionState.discovered);
```

**Step 2: Run analyze and tests**

Run: `flutter analyze && flutter test`

---

### Task 7: Update test files

**Files:**
- Modify: `test/devices_handler_test.dart:406`
- Modify: `test/devices_ws_test.dart:389`

**Step 1: Update test seeds that use `ConnectionState.connecting`**

In `test/devices_handler_test.dart:406`, change:
```dart
initialState: ConnectionState.connecting,
```
To:
```dart
initialState: ConnectionState.discovered,
```

In `test/devices_ws_test.dart:389`, same change:
```dart
initialState: ConnectionState.connecting,
```
To:
```dart
initialState: ConnectionState.discovered,
```

**Step 2: Run all tests**

Run: `flutter test`
Expected: PASS

---

### Task 8: Update documentation

**Files:**
- Modify: `doc/DeviceManagement.md:388-390` (enum definition)
- Modify: `doc/DeviceManagement.md:668-669` (BehaviorSubject example)

**Step 1: Update enum definition in docs**

At line ~388, change the enum definition to include `discovered`:
```dart
enum ConnectionState { discovered, connecting, connected, disconnecting, disconnected }
```

**Step 2: Update BehaviorSubject example**

At line ~669, change:
```dart
BehaviorSubject.seeded(ConnectionState.disconnected);
```
To:
```dart
BehaviorSubject.seeded(ConnectionState.discovered);
```

**Step 3: Add lifecycle description**

Near the enum definition, add the lifecycle:
```
discovered → connecting → connected → disconnecting → disconnected
```
With brief descriptions:
- `discovered` — device created by discovery service, never connected
- `disconnected` — was connected, connection lost or explicitly closed

---

### Task 9: Run full test suite and commit

**Step 1: Run full verification**

Run: `flutter analyze && flutter test`
Expected: Both PASS with no issues

**Step 2: Commit Phase 1**

```bash
git add -A
git commit -m "Add discovered state to ConnectionState enum

Add discovered as the initial device lifecycle state to distinguish
'not yet connected' from 'was connected, lost connection'. This fixes
the ScaleController bug where an initial disconnected state from the
transport would trigger _onDisconnect() and kill a connection that
was still establishing.

Lifecycle: discovered → connecting → connected → disconnecting → disconnected"
```

---

## Phase 2: Propagate ConnectionState through DataTransport

### Task 10: Update DataTransport interface

**Files:**
- Modify: `lib/src/models/device/transport/data_transport.dart:9`

**Step 1: Change Stream type**

Change:
```dart
Stream<bool> get connectionState;
```
To:
```dart
Stream<ConnectionState> get connectionState;
```

**Step 2: Add import**

Add at the top of `data_transport.dart`:
```dart
import 'package:reaprime/src/models/device/device.dart';
```

**Step 3: Run analyze**

Run: `flutter analyze`
Expected: MANY errors — all transport implementations and consumers need updating. This is expected.

---

### Task 11: Update BLE transport implementations

**Files:**
- Modify: `lib/src/services/ble/blue_plus_transport.dart`
- Modify: `lib/src/services/ble/android_blue_plus_transport.dart`
- Modify: `lib/src/services/ble/linux_blue_plus_transport.dart`
- Modify: `lib/src/services/ble/universal_ble_transport.dart`

#### BluePlusTransport (`blue_plus_transport.dart`)

**Step 1: Add import**

Add:
```dart
import 'package:reaprime/src/models/device/device.dart' as device;
```

**Step 2: Change subject type and seed**

Change line 14:
```dart
final BehaviorSubject<bool> _connectionStateSubject = BehaviorSubject<bool>.seeded(false);
```
To:
```dart
final BehaviorSubject<device.ConnectionState> _connectionStateSubject =
    BehaviorSubject<device.ConnectionState>.seeded(device.ConnectionState.discovered);
```

**Step 3: Update native connection listener (line 25-28)**

Change:
```dart
_nativeConnectionSub = _device.connectionState.listen((state) {
  _connectionStateSubject
      .add(state == BluetoothConnectionState.connected);
});
```
To:
```dart
_nativeConnectionSub = _device.connectionState.listen((state) {
  _connectionStateSubject.add(
    state == BluetoothConnectionState.connected
        ? device.ConnectionState.connected
        : device.ConnectionState.disconnected,
  );
});
```

**Step 4: Update connectionState getter (line 42)**

Change:
```dart
Stream<bool> get connectionState => _connectionStateSubject.stream;
```
To:
```dart
Stream<device.ConnectionState> get connectionState => _connectionStateSubject.stream;
```

**Step 5: Update disconnect error fallback (line 50)**

Change:
```dart
_connectionStateSubject.add(false);
```
To:
```dart
_connectionStateSubject.add(device.ConnectionState.disconnected);
```

#### AndroidBluePlusTransport (`android_blue_plus_transport.dart`)

Same pattern as BluePlusTransport. Apply identical changes to:
- Line 41: subject type and seed
- Lines 54-57: native connection listener
- Line 113: connectionState getter
- Line 121: disconnect error fallback

#### LinuxBluePlusTransport (`linux_blue_plus_transport.dart`)

Same pattern. Apply identical changes to:
- Line 52: subject type and seed
- Lines 65-68: native connection listener
- Line 154: connectionState getter
- Line 162: disconnect error fallback

#### UniversalBleTransport (`universal_ble_transport.dart`)

**Step 1: Add import**

Add:
```dart
import 'package:reaprime/src/models/device/device.dart' as device;
```

**Step 2: Change subject type and seed (lines 13-15)**

Change:
```dart
final BehaviorSubject<bool> _connectionStateSubject = BehaviorSubject.seeded(
  false,
);
```
To:
```dart
final BehaviorSubject<device.ConnectionState> _connectionStateSubject =
    BehaviorSubject.seeded(device.ConnectionState.discovered);
```

**Step 3: Update subscription type (line 17)**

Change:
```dart
StreamSubscription<bool>? _connectionStateSubscription;
```
To:
```dart
StreamSubscription<device.ConnectionState>? _connectionStateSubscription;
```

**Step 4: Update connect() listener (lines 25-29)**

The `UniversalBle.connectionStream` returns `Stream<bool>`. Change:
```dart
_connectionStateSubscription = UniversalBle.connectionStream(
  _device.deviceId,
).listen((d) {
  _connectionStateSubject.add(d);
});
```
To:
```dart
_connectionStateSubscription = UniversalBle.connectionStream(
  _device.deviceId,
).listen((d) {
  _connectionStateSubject.add(
    d ? device.ConnectionState.connected : device.ConnectionState.disconnected,
  );
});
```

**Step 5: Update connectionState getter (lines 37-38)**

Change:
```dart
Stream<bool> get connectionState =>
    _connectionStateSubject.asBroadcastStream();
```
To:
```dart
Stream<device.ConnectionState> get connectionState =>
    _connectionStateSubject.asBroadcastStream();
```

**Step 6: Update disconnect error fallback (line 55)**

Change:
```dart
_connectionStateSubject.add(false);
```
To:
```dart
_connectionStateSubject.add(device.ConnectionState.disconnected);
```

**Step 7: Run analyze**

Run: `flutter analyze`
Expected: Remaining errors in device implementations and UnifiedDe1Transport — fixed in next tasks.

---

### Task 12: Update UnifiedDe1 and UnifiedDe1Transport

**Files:**
- Modify: `lib/src/models/device/impl/de1/unified_de1/unified_de1.dart:54-57`
- Modify: `lib/src/models/device/impl/de1/unified_de1/unified_de1_transport.dart:23, 274, 344, 373`

#### UnifiedDe1 (`unified_de1.dart`)

**Step 1: Remove stateful mapping, pass through directly**

Replace the `_hasBeenConnected` field and mapping (added in Task 4) with a direct pass-through:

```dart
@override
Stream<ConnectionState> get connectionState => _transport.connectionState;
```

Remove the `bool _hasBeenConnected = false;` field.

#### UnifiedDe1Transport (`unified_de1_transport.dart`)

**Step 1: Add import**

Add:
```dart
import 'package:reaprime/src/models/device/device.dart' as device;
```

**Step 2: Change connectionState type (line 23)**

Change:
```dart
Stream<bool> get connectionState => _transport.connectionState;
```
To:
```dart
Stream<device.ConnectionState> get connectionState => _transport.connectionState;
```

**Step 3: Update connection checks (lines 274, 344, 373)**

Change each occurrence of:
```dart
if (await _transport.connectionState.first != true) {
```
To:
```dart
if (await _transport.connectionState.first != device.ConnectionState.connected) {
```

**Step 4: Run analyze**

Run: `flutter analyze`

---

### Task 13: Update all scale implementations — transport listener changes

All scale implementations follow the same pattern. In each file, update the `onConnect()` method to use `ConnectionState` instead of `bool` when interacting with the transport.

**Files (all in `lib/src/models/device/impl/`):**
- `bookoo/miniscale.dart`
- `difluid/difluid_scale.dart`
- `skale/skale2_scale.dart`
- `felicita/arc.dart`
- `smartchef/smartchef_scale.dart`
- `decent_scale/scale.dart`
- `atomheart/atomheart_scale.dart`
- `eureka/eureka_scale.dart`
- `varia/varia_aku_scale.dart`
- `blackcoffee/blackcoffee_scale.dart`
- `hiroia/hiroia_scale.dart`
- `acaia/acaia_scale.dart`
- `acaia/acaia_pyxis_scale.dart`

**For each file, apply these two changes:**

**Change 1: Update the "already connected?" guard**

Change:
```dart
if (await _transport.connectionState.first == true) {
  return;
}
```
To:
```dart
if (await _transport.connectionState.first == ConnectionState.connected) {
  return;
}
```

**Change 2: Update the disconnect listener**

Change:
```dart
StreamSubscription<bool>? disconnectSub;
// ...
disconnectSub = _transport.connectionState
    .where((state) => !state)
    .listen((_) {
```
To:
```dart
StreamSubscription<ConnectionState>? disconnectSub;
// ...
disconnectSub = _transport.connectionState
    .where((state) => state == ConnectionState.disconnected)
    .listen((_) {
```

**Special case — `decent_scale/scale.dart`:**

This file has a different pattern (line 55, 67-72). Change:
```dart
if (await _device.connectionState.first == true) {
  return;
}
```
To:
```dart
if (await _device.connectionState.first == ConnectionState.connected) {
  return;
}
```

And the subscription (line 67-72):
```dart
subscription = _device.connectionState
    .where((state) => !state)
    .listen((_) {
```
To:
```dart
subscription = _device.connectionState
    .where((state) => state == ConnectionState.disconnected)
    .listen((_) {
```

Also change the subscription type (line 55):
```dart
StreamSubscription<bool>? subscription;
```
To:
```dart
StreamSubscription<ConnectionState>? subscription;
```

**Step (after all files): Run analyze**

Run: `flutter analyze`

---

### Task 14: Update DecentScaleSerial

**Files:**
- Modify: `lib/src/models/device/impl/decent_scale/scale_serial.dart`

The serial scale uses `SerialTransport` which also inherits from `DataTransport`. Update any `bool` references for transport connection state.

Check `onConnect()` for any `_transport.connectionState` usage and update to use `ConnectionState` values instead of `bool`.

**Step 1: Run analyze to find remaining issues**

Run: `flutter analyze`

---

### Task 15: Update sensor implementations (if needed)

**Files:**
- Modify: `lib/src/models/device/impl/sensor/debug_port.dart`
- Modify: `lib/src/models/device/impl/sensor/sensor_basket.dart`

Sensors use `SerialTransport`. They don't currently listen to `_transport.connectionState` — they manage their own state and listen to `_transport.readStream` for errors/done. Check if they reference `_transport.connectionState` anywhere and update if so.

**Step 1: Run analyze to confirm**

Run: `flutter analyze`
Expected: No sensor-related errors (sensors don't reference transport connection state)

---

### Task 16: Update UnifiedDe1 `ready` stream

**Files:**
- Modify: `lib/src/models/device/impl/de1/unified_de1/unified_de1.dart:219`

**Step 1: Update ready stream**

Change:
```dart
Stream<bool> get ready => _transport.connectionState.asBroadcastStream();
```
To:
```dart
Stream<bool> get ready => _transport.connectionState
    .map((state) => state == ConnectionState.connected)
    .asBroadcastStream();
```

**Step 2: Run analyze**

Run: `flutter analyze`

---

### Task 17: Run full test suite and commit

**Step 1: Run full verification**

Run: `flutter analyze && flutter test`
Expected: Both PASS

**Step 2: Commit Phase 2**

```bash
git add -A
git commit -m "Propagate ConnectionState through DataTransport

Replace Stream<bool> with Stream<ConnectionState> on DataTransport,
BLETransport, and SerialTransport interfaces. BLE transports now map
library-specific connection states to ConnectionState at the boundary.

This eliminates duplicated bool→enum mapping across ~15 device
implementations and ensures a single source of truth for connection
state throughout the transport chain."
```
