# Review: `feature/quick-connect-45`

83 files, +2376/−43 lines. 2079 tests pass, 0 analyzer errors.

---

## P0 — Migration is never persisted; `sameMetadata` blocks enrichment

**Files:** `remembered_devices_controller.dart:55-61`, `remembered_device.dart:49-50`

```dart
// controller initialize():
if (d.implementation == null || d.transportType == null) {
    _registry[d.id] = d.migrate(DeviceMatcher.implementationForName); // in-memory only
    migrated++;
}
// Never calls _persist() after migration.
```

Migrated records never touch disk. If `implementationForName` returns null
(e.g. HDS serial name `"Half Decent Scale (USB)"` or WiFi
`"Half Decent Scale (WiFi)"` — neither is in the matcher), the record enters
the registry with `implementation: null`. The next launch re-runs inference
but the persisted JSON still lacks the new fields, so it re-migrates every
launch forever.

Compounding this: when a live device with enriched metadata reconnects,
`_remember()` calls `sameMetadata()` which compares **only `name` + `type`** —
the new fields are ignored. So even after a successful connection with full
metadata, the record is deemed "identical" and returns early without updating
the registry:

```dart
bool sameMetadata(RememberedDevice other) =>
    other.name == name && other.type == type;
```

**Consequence:** Any name not in `DeviceMatcher.implementationForName` has
`implementation: null` permanently, disabling quick-connect for those devices
on every launch after the first. Names in the matcher (DE1, Decent Scale)
migrate in-memory each launch but never persist — quick-connect works only
because `_connectImpl` re-infers on every boot, never writing it back.

### Proposed fix

1. Include `implementation` and `transportType` in `sameMetadata`:

```dart
bool sameMetadata(RememberedDevice other) =>
    other.name == name &&
    other.type == type &&
    other.implementation == implementation &&
    other.transportType == transportType;
```

2. Persist after migration in `initialize()`:

```dart
if (migrated > 0) {
    await _persist();
}
```

3. When `_remember()` replaces an existing record that was previously thin
   (migrated but not from a live device), also persist immediately rather
   than waiting for a metadata-change to trigger the write.

---

## P1 — No identity check during quick-connect (design requirement)

**Files:** `universal_ble_discovery_service.dart:269-279`, design doc lines 218-228

The design explicitly requires:

> After `transport.connect()` + `device.onConnect()`, verify the device
> identity. For machines: compare `v13Model` against the stored
> `implementation`. If identity doesn't match, disconnect and return null.

`UnifiedDe1.onConnect()` reads `v13Model` with the MMR sequence and logs a
warning when `model >= 128` ("may be Bengle"), but never rejects the
connection. `tryQuickConnect` constructs the device from the persisted
`DeviceImplementation` (e.g. `unifiedDe1`) and calls `device.onConnect()`.
If a Bengle is advertising as `"DE1"` and the old record inferred
`unifiedDe1`, the quick-connect returns a `UnifiedDe1` for a Bengle machine
— wrong capabilities, wrong behavior.

### Proposed fix

After `onConnect()` returns successfully, read `machineInfo.model` (already
populated in `_info`) and compare against the remembered `implementation`:

```dart
if (device is Machine) {
    final model = device.machineInfo.model;
    final expectedBengle = impl == DeviceImplementation.bengle;
    final actualBengle = model == DecentMachineModel.Bengle.name;
    if (expectedBengle != actualBengle) {
        // Identity mismatch: constructed class doesn't match hardware.
        await device.disconnect();
        await transport.dispose();
        return null;
    }
}
```

---

## P2 — `tryQuickConnect` invoked only during full connect, not scale-only or recovery

**File:** `connection_manager.dart:529`

```dart
if (!scaleOnly && rememberedDevices != null) {
    final qcMachineConnected = await _tryQuickConnectMachine();
    ...
}
```

The `!scaleOnly` guard means quick-connect never runs during scale-only scans
or the preferred-scale reconnect loop (`_maybeSchedulePreferredScaleReconnect`
→ `connect(scaleOnly: true)`). The design says quick-connect should run in
"all connect cycles (startup, manual reconnect, recovery mode)." The
highest-value case — transient BLE drop recovery — currently never
quick-connects the scale because the recovery loop fires `connect(scaleOnly:
true)`.

### Proposed fix

Extend quick-connect to the scale-only path:

```dart
// In _connectImpl, after the scaleOnly guard:
if (scaleOnly && rememberedDevices != null) {
    final qcScaleConnected = await _tryQuickConnectScale();
    if (qcScaleConnected) {
        _publishStatus(currentStatus.copyWith(phase: ConnectionPhase.ready));
        return;
    }
}
```

---

## P2 — Quick-connected devices never registered with discovery service — invisible to API/UI

**Files:** `universal_ble_discovery_service.dart:249-289`, `serial_service_desktop.dart:163-205`, `serial_service_android.dart:100-138`

When `tryQuickConnect` succeeds, it returns the `Device` to the caller but
never adds it to the service's internal `_devices` map, never emits it on the
device stream, and never subscribes to its `connectionState` for
removal-on-disconnect. `DeviceController.tryQuickConnect` returns the device
to `ConnectionManager._tryQuickConnectMachine/Scale`, which adopts it — but
`DeviceController.devices` (the list used by the REST API, WebSocket, and
device selection UI) still shows no live device.

Consequence in `buildAvailabilityDeviceList` (devices_handler.dart:536-543):
the quick-connected device is absent from `liveDevices` but present in
`remembered`, so it surfaces as `available: false` — alongside the live
(adopted) connection. The device selection widget never shows it, and WS
commands that look up by `deviceId` from `DeviceController.devices` fail with
"Device not found."

### Proposed fix

Each service's `tryQuickConnect` should, on success, register the device in
`_devices`, emit on the stream, and wire a `connectionState` subscription
that removes it on disconnect — mirroring the `_deviceScanned` pattern.

For BLE:

```dart
// In tryQuickConnect, after successful quick-connect:
_devices[deviceId] = device;
_deviceStreamController.add(_devices.values.toList());
_connections[deviceId] = device.connectionState.listen((state) {
    if (state == ConnectionState.disconnected) {
        _devices.remove(deviceId);
        _deviceStreamController.add(_devices.values.toList());
    }
});
```

For serial desktop: add `_portPathToDevice[portPath] = device` and emit
`_machineSubject.add(_devices.values.toList())` after setting up the
connection state listener.

---

## P2 — Serial quick-connect leaks transport/port resources on mismatch or failure

**Files:** `serial_service_desktop.dart:163-205`, `serial_service_android.dart:100-138`

Desktop: `_detectDevice` calls `_portPathToTransport[id] = transport` at line
422. When the detected device's `implementation` doesn't match (line 189), the
code calls `device?.disconnect()` but never removes the entry from
`_portPathToTransport` or `_portPathToDeviceId`. For an HDSSerial,
`disconnect()` closes the transport but doesn't call `dispose()`, so the
native port handle lingers. The periodic reconcile scanner never re-probes
because `_portPathToDevice` already contains the path entry.

Android: `_detectDevice` opens a USB port via `device.create()`. On mismatch,
`device?.disconnect()` is called, but `AndroidSerialPort.disconnect()` closes
the port without calling `dispose()`, leaving the port handle. The transport
is not tracked in any service map, so there's no reconcile interference — but
the native USB port may not cleanly release.

Also, scale disconnect on mismatch is destructive for the BLE Decent Scale:
`DecentScale.disconnect()` sends a power-off command, turning the physical
scale off. If the identity check fails (wrong scale at a remembered ID), this
power-off is unnecessary and makes the scale unavailable for the subsequent
scan fallback.

### Proposed fix

1. On mismatch or `onConnect()` failure, call
   `_portPathToTransport.remove(id)?.dispose()` (desktop) or
   `transport.dispose()` (Android) instead of `device.disconnect()`.

2. For the BLE scale mismatch path, use
   `DisconnectHandoffScale.disconnectForHandoff()` when the scale supports it
   (releases the connection without power-off), or better, just call
   `transport.dispose()` since the transport was created just for this attempt
   and no permanent connection was established.

---

## P3 — `DecentScale.onConnect()` silently swallows connection failures

**File:** `decent_scale/scale.dart:218-233`

```dart
} catch (e) {
    _log.warning('Failed to initialize scale: $e');
    subscription?.cancel();
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _notificationWatchdog?.cancel();
    _connectionStateController.add(ConnectionState.disconnected);
    try {
        await _device.disconnect();
    } catch (_) {}
    // no rethrow
}
```

This means `tryQuickConnect` → `_connectWithRetry` → `device.onConnect()`
reports success for a scale that quietly disconnected during initialization.
The scale is returned as "connected" to `ConnectionManager`, which adopts it
and publishes `ready`. The user sees a connected scale that isn't actually
receiving weight data.

### Proposed fix

`DecentScale.onConnect()` should rethrow after cleanup so `tryQuickConnect`
can detect the failure and either retry (for GATT errors) or return null:

```dart
} catch (e) {
    _log.warning('Failed to initialize scale: $e');
    subscription?.cancel();
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _notificationWatchdog?.cancel();
    _connectionStateController.add(ConnectionState.disconnected);
    try {
        await _device.disconnect();
    } catch (_) {}
    rethrow;
}
```

**Risk:** This changes the behavior of `DecentScale.onConnect()` for the
existing scan path as well (`connectToScale` calls `scale.onConnect()` and
already catches exceptions). The existing catch in `connectToScale` handles
both the connection-error and post-connect-failure cases identically
(cancel subscriptions, emit disconnected, rethrow), so the existing path is
safe.

---

## P3 — Missing HDS name mappings in `implementationForName`

**File:** `device_matcher.dart:59-108`

`DeviceMatcher.implementationForName` has no entries for
`"Half Decent Scale (USB)"` → `hdsSerial` or
`"Half Decent Scale (WiFi)"` → `hdsWifi`. These are the `.name` values
returned by `HDSSerial.name` and `HDSWifi.name`. Old remembered records with
these display names (from the live device registration path) will never infer
their implementation, leaving `implementation: null` permanently.

### Proposed fix

Add the two entries to `implementationForName`:

```dart
if (name == 'Half Decent Scale (USB)') return DeviceImplementation.hdsSerial;
if (name == 'Half Decent Scale (WiFi)') return DeviceImplementation.hdsWifi;
```

---

## P3 — `_connectWithRetry` has an unused `transport` parameter

**File:** `universal_ble_discovery_service.dart:306-321`

```dart
Future<void> _connectWithRetry(
    UniversalBleTransport transport,  // never referenced
    Device device,
) async { ... }
```

Remove it or suppress the lint. Not a bug, but dead code in a new method.

### Proposed fix

Drop the unused `transport` parameter and update the call site.

---

## Coverage gaps

No tests exercise these paths:

| Path | Consequence |
|------|-------------|
| ConnectionManager quick-connect success / partial success / fallback | No integration test for the core new code path |
| BLE `tryQuickConnect` GATT-133 retry success / second-attempt failure | Only null-return contract tests exist |
| Serial `tryQuickConnect` port-found / mismatch / port-gone | Untested |
| `adoptDevice()` / `adoptScale()` lifecycle (connected state, disconnect handling) | No controller-level test |
| Migration persisted after controller init | Existing controller tests never verify the persisted JSON after init |
| `_remember` enriches a previously-thin (migrated) record | Test only exercises identical/no-change path |

### Proposed approach

1. **ConnectionManager integration tests:** Use `MockDeviceScanner` with
   configurable `quickConnectResult` and `rememberedDevices` pre-seeded via a
   `RememberedDevicesController` backed by a `MockSettingsService`:

   - Both quick-connected → phase=ready, no scan call
   - Machine only → scan called with `effectiveScaleOnly=true`
   - Neither → scan called normally
   - Scale-only connect → quick-connects scale when `rememberedDevices` set

2. **BLE quick-connect unit tests:** Mock `UniversalBlePlatform` to simulate
   connect success, GATT-133 (one retry success), GATT-133 (both fail), and
   `getSystemDevices` cache miss (Apple path). Assert the returned Device and
   the cleanup path (transport.dispose called on failure).

3. **`adoptDevice` / `adoptScale` tests:** Call each method with a
   `TestDe1`/`TestScale`, verify `de1Controller.de1` / `scaleController.connectedScale`
   returns the adopted device, simulate a disconnect on the device's
   `connectionState` stream, and assert the controller clears the reference
   and emits null / disconnected.

4. **Migration persistence test:** Initialize a `RememberedDevicesController`
   with old-style JSON (no `implementation`/`transportType`), verify the
   persisted JSON after `initialize()` contains the new fields with inferred
   values.

---

## Summary

| # | Priority | Finding |
|---|----------|---------|
| 1 | P0 | Migration not persisted; `sameMetadata` ignores new fields — old records stuck with nulls forever |
| 2 | P1 | No identity check after BLE quick-connect — wrong device class on misrepresented name |
| 3 | P2 | Quick-connect only runs in full connect, not scale-only / recovery |
| 4 | P2 | Quick-connected devices absent from `DeviceController.devices` — invisible to API/UI |
| 5 | P2 | Serial port/transport leak on mismatch or failure |
| 6 | P3 | `DecentScale.onConnect()` silently swallows failures — disconnected scale reported as connected |
| 7 | P3 | Missing HDS name-to-implementation mappings in `DeviceMatcher.implementationForName` |
| 8 | P3 | Unused `transport` parameter in `_connectWithRetry` |
| 9 | — | No integration/controller tests for the quick-connect code paths |
