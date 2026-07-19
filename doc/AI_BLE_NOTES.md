# AI BLE Notes

Read this when changing BLE transport, scanning, connection lifecycle, GATT error handling, or transport abstractions. Skip it for pure REST/WS, UI, profile, or plugin changes.

## Source Of Truth

- Transport interfaces: `lib/src/models/device/data_transport.dart`, `lib/src/models/device/ble_transport.dart`.
- BLE transport: `lib/src/services/ble/universal_ble_transport.dart` (cross-platform via `universal_ble` package).
- Connection orchestration: `lib/src/controllers/connection/connection_manager.dart`.
- Device discovery + matching: `lib/src/services/device_matcher.dart`, `lib/src/services/device_discovery/`.
- Error filtering: `lib/src/services/crashlytics_error_filter.dart`.

## Hard Rules

- Never import 3rd-party BLE libraries (e.g. `universal_ble`) outside `lib/src/services/ble/`. Wrap library-specific types (errors, events) in domain types at the transport boundary.
- All BLE operations use 128-bit UUID format for maximum platform compatibility.
- Throttle rapid characteristic reads to avoid overwhelming the Bluetooth stack.
- Always cancel stream subscriptions in `dispose()` methods.
- Scale write paths must catch `DeviceNotConnectedException` at their lowest-level write helper so the exception doesn't escape from fire-and-forget Timer callbacks.

## Transport Architecture

The single BLE transport is `UniversalBleTransport` in `lib/src/services/ble/universal_ble_transport.dart`, wrapping the `universal_ble` package. It implements the `DataTransport` interface: `connect()`, `disconnect()`, `dispose()`, `read(uuid)`, `write(uuid, data)`, `writeWithResponse(uuid, data)`, `subscribe(uuid)`, `connectionState` stream.

`UnifiedDe1Transport` wraps `UniversalBleTransport` and adds MMR read/write on top of raw characteristic I/O. It provides `rawData` stream, `readMmr()`, `writeMmr()`, and typed connection guards (`DeviceNotConnectedException.machine()` on read/write when disconnected).

## Connection Flow

`ConnectionManager.connect()` orchestrates the full connect sequence:
1. Scan for devices
2. Apply preferred-device policy (`PolicyResolver`)
3. Connect machine (`connectMachine()`)
4. Connect scale (`connectScale()`)
5. Emit `ready` status

`StatusPublisher` drives `ConnectionStatus` stream with phases: `idle` → `scanning` → `connectingMachine` → `connectingScale` → `ready`.

## Footgun #1: GATT-133 on Cold Boot

**Symptom:** `Unknown Error 133` on first connect after app restart. Second scan/connect succeeds normally.

**Root cause:** Android BLE stack (`BluetoothGatt.gattStatus = 133 = GATT_ERROR`) busy during connect init. Not a device problem — the `connect()` call itself fails before any characteristic I/O.

**Fix pattern:** `EarlyConnectWatcher` already retries; the 2nd attempt succeeds.

**Status:** The early-connect watcher handles this. Not a code bug — an Android BLE stack behavior.

## Footgun #2: Listener Stacking on Reconnect

**Symptom:** Duplicate WebSocket state messages, `currentSnapshot` emits duplicates.

**Root cause (fixed in PR #246):** `UnifiedDe1Transport.connect()` re-ran `_bleConnect()` → re-`subscribe()`d all characteristics without disconnecting first. `cancelWhenDisconnected` never fired, so listeners stacked → every notification delivered twice.

**Fix:** `CharSubscriptions` helper (cancel-before-replace per characteristic UUID). Unit-tested.

**Verification:** Cannot reproduce in unit/simulate. Rely on Crashlytics + `DuplicateBleSubscription` telemetry to confirm the path fires.

## Footgun #3: USB Charger Dedup

**Symptom:** `BatteryController` writing `setUsbChargerMode` every 60s unconditionally (~2665 writes/2 days).

**Root cause:** DE1 FW re-enables the charger on its own. The periodic write only matters while discharging.

**Fix (PR #246):** `shouldWriteChargerMode()` in `charging_logic.dart`: write-on-change, re-assert "off" every 5min while discharging, skip otherwise. Reset last-applied on disconnect.

## Gone-Device Error Handling

`UniversalBleTransport._handleGattError()` catches `UniversalBleException` with gone-device codes:
`characteristicNotFound`, `deviceNotFound`, `serviceNotFound`, `connectionTerminated`, `deviceDisconnected`, `unknownError`.

On hit: emits `disconnected`, drains the queue, throws `DeviceNotConnectedException`.

The `isBenignFrameworkError()` filter in `crashlytics_error_filter.dart` suppresses these from `FlutterError.onError` — but scale-level catches at the write helper are defense-in-depth.

## BLE Scanning

- Device discovery uses unfiltered scans with name-based matching (`DeviceMatcher`).
- Service verification during `onConnect()` via `BleServiceIdentifier`.
- `ScanStateGuardian` guards against overlapping scans and tracks adapter state.
- `ScanOrchestrator` manages single-scan lifecycle.

## Comms-Layer Patterns

Three reusable idioms from the comms-harden effort:

1. **Tracked-latest over `Rx.combineLatest`** — for single-writer derived state, capture each stream's latest value into a field and route everything through one `_computeStatus()` method. Avoids hidden reentrancy.

2. **Queue-with-coalesce** for concurrent ops of the same kind — one shared `Completer`, drain in the `finally` of the in-flight op (see `scaleOnly` reconnect in `ConnectionManager`). Cleaner than mutex + retry.

3. **Generation token + cancellable Timer/Completer** for debounce-across-disconnect races — bump the generation in the disconnect path, capture it in the debounce closure, bail if it changed when the timer fires (see `De1Controller._shotSettingsDebounce`).

## Troubleshooting

| Symptom | First place to look |
|---------|---------------------|
| GATT-133 on first connect, works on retry | `EarlyConnectWatcher` — 2nd attempt should succeed. |
| Duplicate state messages | Listener stacking. Check `CharSubscriptions` is cancel-before-replace. |
| Scale write exceptions escaping to framework | Scale write path missing `DeviceNotConnectedException` catch. Add at `_writeCommand` / `_safeWrite`. |
| BLE scan overlaps | `ScanStateGuardian` — check adapter state tracking. |
| `TimeoutException` in `universal_ble/queue.dart` | May relate to zombie-link (#431) or concurrent BLE write contention (#423). |
| `PlatformException: Location services required` | Android location permissions not granted. Onboarding check or troubleshooting wizard (#125/#126). |

## Android USB Attach Recovery

`SerialServiceAndroid` implements the optional `DeviceAttachNotifier`
capability. Attach events are non-replaying hints and may carry incomplete
metadata; serial scanning and detection remain the support filter. Android can
broadcast attach before the CDC interface is usable, so
`AttachReconnectCoordinator` coalesces bursts and waits a configurable 500 ms
before invoking the normal connection policy.

Only a missing preferred machine enables this path. The attempt therefore uses
remembered-device quick-connect first, retains scan fallback, and cannot open a
picker when no preference exists. If the immediate attempt finds nothing or
fails, the coordinator explicitly re-arms normal machine recovery. BLE, Wi-Fi,
simulated-device, and scale-only behavior do not expose attach events.

## Quick Connect

`tryQuickConnect` on `UniversalBleDiscoveryService` connects to a known
device by ID without scanning. GATT-133 (cold-boot Android, Teclast) is
handled by a single retry with a 1s delay inside `_connectWithRetry`:

```
await device.onConnect().timeout(10s)
  catch BleConnectException:
    wait 1s
    disconnect
    await device.onConnect().timeout(10s)  // one retry only
```

If both attempts fail, `tryQuickConnect` returns null and the scan fallback
runs. The `EarlyConnectWatcher` does its own retry during the scan.

On Apple (iOS/macOS), `getSystemDevices` is used to find the peripheral in
the system cache. If not cached, returns null immediately (no timeout waste).
On Android/Linux/Windows, direct `UniversalBle.connect(deviceId)` works.

The identity check happens during `onConnect()` — for machines, `v13Model`
is read and compared against the expected `DeviceImplementation`.

## Focused Tests

```sh
flutter test test/services/ble/
flutter test test/controllers/connection/
```

## Profile Upload Safety

### Firmware Latch: ProfileDownloadInProgress

The DE1 firmware sets `ProfileDownloadInProgress` on header write and clears it
on tail write + flash commit. If the upload dies mid-sequence (GATT timeout,
connection drop), the latch stays set indefinitely. While latched:
- The machine silently ignores all start requests.
- The group-head LED pulses magenta (~2 Hz).
- The only recovery is a complete profile upload.

### Two Cache Layers

| Cache | Location | Cleared on | Effect |
|-------|----------|------------|--------|
| Sync `_lastPushedProfile` | `WorkflowDeviceSync` | Disconnect, upload failure | Prevents redundant uploads within one connection |
| Device `_currentProfile` | `UnifiedDe1` | Every `onConnect()`, every upload start | Prevents redundant uploads within one device session |

Both must be cleared on connection edges. The sync cache is cleared by
`_onDe1Change(null)` which runs on disconnect. The device cache is cleared
in `UnifiedDe1.onConnect()` before the `_info` guard.

### Startup Ordering

The on-connect profile push is triggered by `De1Controller.initSettled`, which
fires after machine readiness + startup defaults complete. This replaces the
single-shot `_setDe1Defaults` path whose failures were swallowed.

Generation tokens in both `De1Controller` (`_connectionGeneration`) and
`WorkflowDeviceSync` (`_generation`) guard against stale init completions
from a disconnected generation.

## Keeping Notes Fresh

Add lessons that would have saved debugging time: new footguns, thread-safety constraints, connection-lifecycle changes, non-obvious symptoms, and cross-transport dependencies. Prune stale claims. Prefer fewer, sharper notes over long background.

## Connection Policy (PR #476)

Two intents govern how `ConnectionManager` starts a connect cycle:

- **automatic `connect()`**: Used by startup, machine recovery, and USB-attach
  recovery. Remembers-machine quick-connect, connects preferred devices during
  the scan, and stops scanning early once preferences are satisfied. Fastest
  restoration of the expected configuration.
- **explicit `scanAndConnect()`**: Used by the launcher scan page, REST/WS
  scan commands (when `connect=true`), and explicit retry buttons. Completes
  full discovery before policy runs, never quick-connects during the scan,
  and never stops early. Preserves working machine/scale slots.

Slot policy: machine and scale are independently fillable. Occupied slots are
never replaced automatically by a scan. A missing slot auto-connects its
preferred device when found. Without a preferred ID, exactly one candidate
auto-connects; more than one produces ambiguity.

Session continuation: when a scan produces ambiguity (`machinePicker` or
`scalePicker`), a `ConnectionSelectionSession` holds the immutable scan
snapshot. `selectMachine()` and `selectScale()` resolve the session-owned
candidate object (never the caller-supplied reference) and continue with
retained scale candidates — no additional scan fires. `cancelSelectionSession()`
clears pending ambiguity, finalises the report as cancelled, and re-arms
scale reacquisition.

Preferred-scale watch: the persistent background scale watch pauses while
scale ambiguity is pending so it cannot auto-connect the old preferred scale
while the user is choosing. Successful explicit scale selection persists the
new preferred ID and the watch re-arms after session completion or cancellation.

Live-machine quick-connect guard: `_machineConnected` prevents quick-connect
from re-adopting a fresh object for the same already-connected peripheral.
This avoids spurious DE1 disconnect/re-attach cycles.
