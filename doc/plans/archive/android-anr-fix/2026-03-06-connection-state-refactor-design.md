# ConnectionState Refactor Design

## Problem

`ConnectionState` has four values: `connecting`, `connected`, `disconnecting`, `disconnected`. The `disconnected` state is overloaded — it means both "device discovered, never connected" and "was connected, connection lost." This causes:

1. **ScaleController disconnect bug:** When a scale's transport emits an initial `false` (BehaviorSubject seed), the device maps it to `disconnected`, and `ScaleController._processConnection` calls `_onDisconnect()` — killing a connection that was still establishing.
2. **Ambiguous semantics:** Controllers can't distinguish "not yet connected" from "lost connection" without tracking state history themselves.

Additionally, `DataTransport.connectionState` uses `Stream<bool>`, forcing every device implementation (~15 scales + DE1) to independently map `bool → ConnectionState`. This duplicated logic is error-prone.

## Solution

Two changes, committed separately:

### Commit 1: Add `discovered` state to ConnectionState enum

Add `discovered` as the initial state in the device lifecycle:

```
discovered → connecting → connected → disconnecting → disconnected
```

- `discovered` — device created by discovery service, never connected
- `disconnected` — was connected, connection lost or explicitly closed

**Changes:**

| Area | Change |
|------|--------|
| `device.dart:17` | Add `discovered` to enum: `{ discovered, connecting, connected, disconnecting, disconnected }` |
| All scale impls (~15) | Change `BehaviorSubject.seeded(ConnectionState.connecting)` → `BehaviorSubject.seeded(ConnectionState.discovered)` |
| Sensor impls (2) | Same seed change |
| `DecentScaleSerial` | Same seed change |
| `ScaleController` | Seed `_connectionController` with `discovered` instead of `disconnected`; `_processConnection` ignores `discovered` |
| `De1Controller` | Add `case ConnectionState.discovered:` to switch (no-op, log only) |
| `DeviceController.scanForDevices` | `state != ConnectionState.connected` check unchanged — `discovered` devices correctly filtered |
| `UnifiedDe1` | Map initial transport `false` → `discovered`, subsequent `false` → `disconnected` (stateful) |
| `DevicesStateAggregator` | Uses `.name` — `"discovered"` serializes automatically |
| Mock devices | Keep `ConnectionState.connected` seed (they represent pre-connected mocks) |
| Tests | Update seeds in test helpers where applicable |
| Docs | Update `DeviceManagement.md`, `CLAUDE.md` |

### Commit 2: Propagate ConnectionState through DataTransport

Replace `Stream<bool>` with `Stream<ConnectionState>` on the transport interface, eliminating bool→enum mapping in every device.

**Changes:**

| Area | Change |
|------|--------|
| `DataTransport` | `Stream<bool> get connectionState` → `Stream<ConnectionState> get connectionState` |
| `BLETransport` | Inherits change from `DataTransport` |
| `SerialTransport` | Inherits change from `DataTransport` |
| `BluePlusTransport` | Map `flutter_blue_plus` connection state to `ConnectionState` at boundary; seed with `discovered` |
| `LinuxBluePlusTransport` | Same |
| `AndroidBluePlusTransport` | Same |
| `UniversalBleTransport` | Same |
| All scale impls (~15) | Remove manual bool→enum mapping; listen to `_transport.connectionState` directly for `ConnectionState` values instead of filtering `where(!state)` |
| `UnifiedDe1` | Remove `.map((e) => e ? connected : disconnected)`; pass through transport's `ConnectionState` directly |
| `UnifiedDe1Transport` | Change `Stream<bool> get connectionState` → `Stream<ConnectionState>`; update `_transport.connectionState.first != true` checks to use `ConnectionState` |
| `DecentScaleSerial` | Update to use `ConnectionState` from serial transport |
| Sensor impls | Sensors use `SerialTransport` — update accordingly |

**Transport mapping (at BLE boundary):**

```dart
// In BLE transport implementations:
_nativeConnectionSub = _device.connectionState.listen((state) {
  _connectionStateSubject.add(
    state == BluetoothConnectionState.connected
      ? ConnectionState.connected
      : ConnectionState.disconnected,
  );
});
```

The transport seeds with `ConnectionState.discovered`. The BLE library only emits connected/disconnected, so those are the only two values the transport maps. The `connecting`/`disconnecting` transitions remain the responsibility of device implementations (emitted in `onConnect()`/`disconnect()` methods).

**Scale implementation simplification (typical pattern, before → after):**

Before:
```dart
final BehaviorSubject<ConnectionState> _connectionStateController =
    BehaviorSubject.seeded(ConnectionState.connecting);

Future<void> onConnect() async {
  if (await _transport.connectionState.first == true) return;
  _connectionStateController.add(ConnectionState.connecting);
  await _transport.connect();
  disconnectSub = _transport.connectionState
      .where((state) => !state)
      .listen((_) { disconnect(); });
  // ... setup ...
  _connectionStateController.add(ConnectionState.connected);
}
```

After:
```dart
final BehaviorSubject<ConnectionState> _connectionStateController =
    BehaviorSubject.seeded(ConnectionState.discovered);

Future<void> onConnect() async {
  if (await _transport.connectionState.first == ConnectionState.connected) return;
  _connectionStateController.add(ConnectionState.connecting);
  await _transport.connect();
  disconnectSub = _transport.connectionState
      .where((state) => state == ConnectionState.disconnected)
      .listen((_) { disconnect(); });
  // ... setup ...
  _connectionStateController.add(ConnectionState.connected);
}
```

## Commit Order

1. **Commit 1** (enum + discovered state) is self-contained and fixes the immediate bug
2. **Commit 2** (transport refactor) builds on commit 1 and simplifies the codebase

## Testing

- Existing tests updated to use new enum value
- `flutter test` must pass after each commit
- `flutter analyze` must pass after each commit
- Manual verification: connect to DE1 + scale from discovery view, confirm scale stays connected
