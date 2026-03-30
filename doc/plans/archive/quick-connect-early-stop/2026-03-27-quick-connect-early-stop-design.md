# Quick Connect with Early Scan Stop

**Issue:** #45 (partial — focused on early scan termination)
**Date:** 2026-03-27

## Problem

BLE scan always runs for its full duration (15s on most platforms, 12s+delays on Linux) even when all preferred devices have already been discovered and connected. This wastes time and battery, especially on the common case where a user's known machine and scale are nearby and advertising.

Additionally, `ConnectionManager` has two near-identical scan flows — `connect()` and `scanAndConnectScale()` — with duplicated early-connect logic.

## Solution

1. Add `stopScan()` capability through the discovery stack
2. Unify `connect()` and `scanAndConnectScale()` into a single `connect({bool scaleOnly})` method
3. Stop the scan early when all wanted preferred devices are connected
4. Extract a `DeviceScanner` interface from `DeviceController` for testability
5. Remove dead `scanForSpecificDevices()` code

## Design

### 1. `DeviceScanner` interface

Extract what `ConnectionManager` needs from `DeviceController` into an interface:

```dart
abstract class DeviceScanner {
  Stream<List<Device>> get deviceStream;
  Stream<bool> get scanningStream;
  List<Device> get devices;
  Future<void> scanForDevices();
  void stopScan();
}
```

`DeviceController` implements `DeviceScanner`. `ConnectionManager` constructor takes `DeviceScanner` instead of `DeviceController`.

### 2. `stopScan()` down the stack

**`DeviceDiscoveryService` interface:** Add `void stopScan()`.

**Implementations:**
- `BluePlusDiscoveryService`: Cancel the 15s `Future.delayed`, call `FlutterBluePlus.stopScan()`. The existing `cancelWhenScanComplete` listener cleanup still works since `stopScan()` triggers scan completion.
- `LinuxBleDiscoveryService`: Cancel delay, call `FlutterBluePlus.stopScan()`. Queued devices still get processed after scan stops (existing post-scan logic).
- `UniversalBleDiscoveryService`: Call `UniversalBle.stopScan()`.
- `SerialServiceAndroid`, `SerialServiceDesktop`: No-op (port enumeration is instant).
- `SimulatedDeviceService`: No-op or cancel delay.

**`DeviceController.stopScan()`:** Calls `stopScan()` on all services. The existing `Future.wait` + `whenComplete` in `scanForDevices()` handles emitting `scanning: false` when services complete.

### 3. Unified `connect({bool scaleOnly = false})`

Merge `scanAndConnectScale()` into `connect()`:

```
connect({bool scaleOnly = false})
  1. Determine wanted set from preferences + scaleOnly flag
  2. Start scan
  3. Watch device stream — early-connect preferred devices as they appear
  4. On each early-connect success, check: all wanted devices connected?
     -> yes: deviceScanner.stopScan()
  5. Wait for scan to stop (either early or natural completion)
  6. If !scaleOnly: apply machine preference policy
  7. Apply scale preference policy
```

**Early-stop conditions:**

| Preferred machine | Preferred scale | scaleOnly | Stop scan when |
|---|---|---|---|
| set | set | false | both connected |
| set | not set | false | machine connected |
| not set | set | false | scale connected |
| not set | not set | false | never (full scan) |
| -- | set | true | scale connected |
| -- | not set | true | never (full scan) |

### 4. Remove dead code

- `scanForSpecificDevices()` from `DeviceDiscoveryService` interface and all 7 implementations
- `scanAndConnectScale()` from `ConnectionManager`

### 5. Update callers

- `de1_state_manager.dart:304` — `scanAndConnectScale()` -> `connect(scaleOnly: true)`
- `status_tile.dart:333` — `scanAndConnectScale()` -> `connect(scaleOnly: true)`

## Testing

### New: `MockDeviceScanner`

Implements `DeviceScanner` with:
- Controllable device emissions via `addDevice()` / `removeDevice()`
- Controllable scan lifecycle (start/stop)
- Records `stopScan()` calls for verification

### New test cases

- Preferred machine only set -> `stopScan()` called when machine connects
- Preferred scale only set -> `stopScan()` called when scale connects
- Both preferred set -> `stopScan()` called only after both connect
- No preferences set -> `stopScan()` never called, full scan completes naturally
- `scaleOnly: true` -> machine preference policy skipped, `stopScan()` on scale connect
- `scaleOnly: true`, no preferred scale -> full scan, scale policy still applied

### Existing tests

Update to use `MockDeviceScanner` instead of real `DeviceController` + `MockDeviceDiscoveryService`. All current test scenarios (auto-connect, picker ambiguity, concurrent connection guards, phase emissions, error handling) remain — they test `ConnectionManager` logic that doesn't change.

## What this does NOT change

- `discoverServices()` still runs on every BLE connect (required for protocol detection)
- `DeviceMatcher` name matching still runs for every discovered device
- Preferred device storage format unchanged (bare ID strings)
- Full scan still runs when no preferences are set
- No changes to Linux-specific BlueZ workarounds (device queueing, settle delays)
