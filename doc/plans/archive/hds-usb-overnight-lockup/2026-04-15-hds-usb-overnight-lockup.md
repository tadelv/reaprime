# HDS USB overnight lockup (#75) — fix plan

*Created: 2026-04-15*
*Branch: `fix/hds-usb-overnight-lockup`*
*Linked: [#75](https://github.com/tadelv/reaprime/issues/75), Roadmap Tier 1 (HDS watchdog, rescan dedup)*

## Symptoms

- User leaves HDS connected via USB-C on Android. After 20+ hours, Bridge stops receiving live weight updates.
- Dashboard still reports the scale as "connected".
- "Disconnect" button on dashboard does nothing.
- HDS LCD keeps updating (firmware and sensor are healthy; the tablet-side pipeline is frozen).
- Fix requires a restart of the app *and* a power cycle of the HDS.

## Evidence from `hds-usb-overnight-conn-lost-duplicated-scan/R1-logs/log.txt`

1. **`LateInitializationError` on every scale disconnect** (lines 70860, 71946, etc.):
   ```
   WARNING De1StateManager - Failed to disconnect scale:
   LateInitializationError: Field '_stringSubscription@...' has not been initialized.
   ```
   This is catastrophic: `disconnect()` throws partway and `_transport.disconnect()` is never called → USB port handle is leaked → dashboard button is non-functional.

2. **USB bus path churn across suspend/resume**: HDS appears at `/dev/bus/usb/001/005 → /010 → /007 → /005`. Every Android selective-suspend renumbers the device.

3. **Duplicate devices in scan result** (lines 73152, 76410):
   ```
   current devices: [UnifiedDe1, HDSSerial, DecentScale, DecentScale]
   ```
   Multiple `DecentScale` instances from BLE; and in some scans the `HDSSerial` precedes a stale `UnifiedDe1`. Identity is not stable across rescans.

4. **Missing notification watchdog**: `AndroidSerialPort._port.inputStream` (from `usb_serial`) can silently stop emitting after Android USB selective suspend. No `onError`, no `onDone`, no timeout. `HDSSerial` has no keep-alive or "no-data for N seconds" detection.

## Root causes

### RC1 — `HDSSerial.disconnect()` throws before closing the port
`lib/src/models/device/impl/decent_scale/scale_serial.dart:32-37`:
```dart
disconnect() async {
  _connectionSubject.add(ConnectionState.disconnected);
  _transportSubscription.cancel();
  _stringSubscription.cancel();          // <-- late field, never initialized
  await _transport.disconnect();          // <-- unreachable
}
```
`_stringSubscription` is `late` but only assigned inside the commented-out block at lines 61–70. Any call to `disconnect()` crashes with `LateInitializationError` before the transport is closed.

### RC2 — No keep-alive / watchdog for HDS serial reads
Weight data flows exclusively from `_port.inputStream` events. There is no:
- periodic enable/keep-alive write (the BLE `DecentScale` sends a heartbeat every 4 s for exactly this reason)
- no-data-in-N-seconds watchdog
- USB wake-lock or autosuspend opt-out

After Android autosuspends the CH340 endpoint, the stream goes silent. `ConnectionState` remains `connected` (no error fires), so the UI and `ConnectionManager` think everything is fine.

### RC3 — Stale HDS instances leaked by identity churn
`HDSSerial.deviceId` is `_transport.name`, which is `_device.deviceName` — the `/dev/bus/usb/001/NNN` path. Every Android suspend/resume cycle renumbers the device and produces a fresh `HDSSerial` in `DeviceController`. Combined with RC1 (ports never released), old instances accumulate and hold dead file descriptors. This also drops the `preferredScaleId` match on rescans (logs: `preferred scale /dev/bus/usb/001/010 NOT found`).

### ~~RC4 — BLE+USB discovery collision~~ (dropped)
~~If the same physical scale advertises BLE *and* is connected via USB, `BluePlusDiscoveryService` returns it as `DecentScale` and `SerialServiceAndroid` returns it as `HDSSerial`. `DeviceController` does not dedupe across services.~~

**Dropped:** BLE MAC and USB composite ID (`hds:vid:pid:serial`) are fundamentally different identifier spaces — `DeviceController` can't match them by `deviceId`. The duplicate `DecentScale` entries in logs are most likely two physical BLE scales, not a cross-transport collision. If this does turn out to be a real issue, it needs a name-based heuristic, not ID dedup — and that's a separate investigation.

## Out of scope

- DecentScale BLE-side duplication (two distinct `DecentScale` entries from BLE with two distinct MACs) — that's a user with two scales, not a bug, and is orthogonal to #75.
- Desktop (libserialport) HDS lockups — same class of bug potentially, but no field reports and no overnight desktop logs. Apply the same watchdog there, skip the Android-specific wake-lock work.
- `SensorBasket` / `DebugPort`, which share the transport but are not in #75's scope.

## Approach

Five layers. Layer 0 builds the test infra the remaining layers need. Ship each as a self-contained commit so we can bisect if a later layer regresses.

### Layer 0 — Controllable mock scale for smoke testing **[prerequisite]**

**Problem:** `MockScale` (`lib/src/models/device/impl/mock_scale/mock_scale.dart`) is a fire-and-forget `Timer.periodic` — no way to externally trigger a data stall, disconnect, or reconnect. `TestScale` (`test/helpers/test_scale.dart`) has `setConnectionState()` and `emitSnapshot()` but only works in unit tests, not the running app. Without controllable mock devices, we can't smoke-test the watchdog (Layer 2) or rescan (Layer 3) via `sb-dev` + `curl`.

**Approach:**

1. Make `MockScale` controllable by adding methods: `simulateDataStall()` (pauses the timer), `simulateResume()` (resumes), `simulateDisconnect()` (emits `disconnected` state, stops timer). Keep the existing auto-weight-emission as default behavior so nothing changes for normal simulate mode.
2. Expose debug control via a new handler `lib/src/services/webserver/debug_handler.dart` (only registered when `simulate=1`):
   - `POST /api/v1/debug/scale/stall` — pause weight emission
   - `POST /api/v1/debug/scale/resume` — resume
   - `POST /api/v1/debug/scale/disconnect` — simulate disconnect
   - `POST /api/v1/debug/scale/reconnect` — simulate reconnect (re-add to device list + emit connected)
3. Guard: handler is a no-op / returns 404 when not in simulate mode.

**Verification:**
- Unit: `test/unit/devices/mock_scale_controllable_test.dart` — exercise stall/resume/disconnect on `MockScale` directly.
- Smoke: `sb-dev start --simulate`, `curl -X POST localhost:8080/api/v1/debug/scale/stall`, confirm weight stream stops, `curl -X POST localhost:8080/api/v1/debug/scale/resume`, confirm stream resumes.

### Layer 1 — Unblock disconnect (RC1) **[trivial, ship first]**

**File:** `lib/src/models/device/impl/decent_scale/scale_serial.dart`

1. Make `_stringSubscription` nullable (`StreamSubscription<String>? _stringSubscription;`) and guard with `?.cancel()`. Do the same for `_transportSubscription` for symmetry (it's always assigned in `onConnect`, but `disconnect()` may race before that).
2. Wrap `_transport.disconnect()` in a try/finally so future exceptions can't skip port release.
3. Guard against re-entrant `disconnect()` with an `_isDisconnecting` flag (mirror `DecentScale.disconnect()` at `lib/src/models/device/impl/decent_scale/scale.dart:110`).

**Verification:**
- Unit: new test `test/unit/devices/hds_serial_disconnect_test.dart` — construct `HDSSerial` with a mock `SerialTransport`, call `disconnect()` *without* first calling `onConnect()`, assert no throw and `transport.disconnect()` was invoked.
- E2E: simulate mode start → trigger scale disconnect via `/api/v1/scale/disconnect` → log should no longer contain the `LateInitializationError`. Not covered by simulate (MockScale), so also run against the dev Android target once after Layer 3 lands.

### Layer 2 — HDS stream watchdog (RC2)

**File:** `lib/src/models/device/impl/decent_scale/scale_serial.dart`

Add a lightweight data-freshness watchdog inside `HDSSerial`:

1. On each inbound weight frame, stamp `_lastDataAt = DateTime.now()`.
2. Start a `Timer.periodic(Duration(seconds: 2))` in `onConnect()` that checks `now - _lastDataAt`:
   - `< 6s` → healthy, no-op.
   - `6s..12s` → log a warning, re-send the `[0x03, 0x20, 0x01]` enable command. One retry only; don't spam.
   - `> 12s` → log severe, call `disconnect()`. `ConnectionManager` will observe the `disconnected` state and pick it up on the next scale reconnect flow (which is already wired via `De1StateManager - Scale disconnected after sleep, triggering device scan`).
3. Cancel the timer in `disconnect()`.

**Thresholds rationale:** HDS LCD updates at ~10 Hz; a 6-second gap is already three orders of magnitude longer than normal and unambiguously broken. Keep the thresholds as `const` at the top of the class so they're easy to tune.

**Verification:**
- Unit: `test/unit/devices/hds_serial_watchdog_test.dart` using `fake_async` — feed snapshots for 5 s, then stop; advance time, assert retry write is issued at >6 s and disconnect at >12 s. Pattern already used in `test/unit/devices/acaia_scale_test.dart`.
- Field: enable `FINE` logging on the Android target, unplug HDS data line (leaves power) while the app is running, confirm the watchdog fires and `ConnectionManager` re-scans.

### Layer 3 — Stable HDS identity + dedup (RC3)

**Files:**
- `lib/src/services/serial/serial_service_android.dart`
- `lib/src/services/serial/serial_service_desktop.dart` (for parity)
- `lib/src/models/device/impl/decent_scale/scale_serial.dart`

1. **Stable `deviceId`**: change `HDSSerial.deviceId` from the bus path to `"hds:${vid}:${pid}:${serial}"`. Use `UsbDevice.serial` on Android and `SerialPort.serialNumber` on desktop. Fallback to the old bus-path string if serial is null so upgrades don't lose `preferredScaleId`. Migration note: on upgrade, the first scan after update will treat the scale as a "new" preferred scale — document in the PR body, not worth a migration shim.
2. **Scan-time dedup**: in `SerialServiceAndroid._performScan()`, after building the list of new `UsbDevice`s to inspect, skip any whose post-detection `deviceId` already lives in `_devices`. Same in `SerialServiceDesktop._performScan()`.
3. **Orphan GC**: when a previously-seen `_devices` entry is absent from `UsbSerial.listDevices()` for two consecutive scans, force-disconnect and remove it. This cleans up the leaked `/dev/bus/usb/001/010` ghost instances.

**Verification:**
- Unit: `test/unit/services/serial_service_android_dedup_test.dart` (fake `UsbSerial.listDevices()`), exercise rescan scenarios: path change with same serial, new serial, orphan cleanup. The Android service currently has no unit tests — this fix creates the opportunity.
- Smoke: `sb-dev start --simulate`, `curl` `/api/v1/devices/scan` multiple times, confirm no duplicate HDSSerial entries. Manual Android smoke test for real USB path changes.

### Layer 4 — Android USB wake-lock + selective-suspend opt-out (RC2, supporting)

**Files:** `android/app/src/main/AndroidManifest.xml`, possibly a tiny native helper.

This is the hand-wavy layer. Research before committing:

1. Is `usb_serial`'s `UsbDeviceConnection.setInterface()` enough to keep CH340 out of autosuspend, or do we need to poke `/sys/bus/usb/devices/.../power/control`? (Not writable from an unprivileged app.)
2. Does adding `FLAG_KEEP_SCREEN_ON` on the scale debug view, or a `PARTIAL_WAKE_LOCK` while the HDS is connected, prevent the observed freeze? On Teclast tablets we already hold the foreground service alive; verify whether a wake lock is independently needed.
3. Reference: https://source.android.com/docs/core/power/device-idle — doze mode restrictions; https://developer.android.com/reference/android/hardware/usb/UsbManager .

Execution: spike on the tablet first, decide yes/no, then bake the outcome into the plan. **Layers 1–3 ship regardless of this layer's outcome.**

## Step sequence

1. **Checkout `fix/hds-usb-overnight-lockup`** *(done)*.
2. Implement Layer 0 (controllable MockScale + debug handler). Run `flutter test`, `flutter analyze`. Commit.
3. Implement Layer 1. Run `flutter test test/unit/devices/`, `flutter analyze`. Commit.
4. Implement Layer 2. Same verification. Commit.
5. Smoke-test Layers 1–2 via `scripts/sb-dev.sh`: start simulate, `curl` debug/scale/stall, confirm watchdog fires; `curl` debug/scale/disconnect, confirm reconnect flow. Commit any fixes.
6. Implement Layer 3. Full `flutter test` + analyze. Commit.
7. Smoke-test Layer 3 via `sb-dev`: `curl` `/api/v1/devices/scan` several times, confirm no duplicate entries.
8. **Manual Android smoke test on the Teclast (or equivalent)**: plug HDS, wait for scale connection, use for a few shots, sleep overnight, check (a) weight still updates, (b) watchdog hasn't fired spuriously, (c) no duplicate `HDSSerial` instances accumulated. Capture `~/Download/REA1/log.txt`.
9. Spike on Layer 4. Decide whether to include.
10. Move this plan to `doc/plans/archive/hds-usb-overnight-lockup/` when the branch is done.
11. Leave the branch open, no PR.

## Files to change

Implementation:
- `lib/src/models/device/impl/mock_scale/mock_scale.dart` — Layer 0 (controllable methods)
- `lib/src/services/webserver/debug_handler.dart` *(new)* — Layer 0 (simulate-mode debug endpoints)
- `lib/src/services/webserver/webserver_service.dart` — Layer 0 (register debug handler when simulate)
- `lib/src/models/device/impl/decent_scale/scale_serial.dart` — Layers 1, 2, 3
- `lib/src/services/serial/serial_service_android.dart` — Layer 3
- `lib/src/services/serial/serial_service_desktop.dart` — Layer 3
- *(maybe)* `android/app/src/main/AndroidManifest.xml` — Layer 4

Tests:
- `test/unit/devices/mock_scale_controllable_test.dart` *(new)* — Layer 0
- `test/unit/devices/hds_serial_disconnect_test.dart` *(new)* — Layer 1
- `test/unit/devices/hds_serial_watchdog_test.dart` *(new)* — Layer 2
- `test/unit/services/serial_service_android_dedup_test.dart` *(new)* — Layer 3

## Risks

- **Layer 2 false positives**: if the watchdog fires during a legitimate quiescent period (e.g. empty platter after tare), and triggers a disconnect, we regress. Mitigation: only react to elapsed time since last *actual* inbound frame, and the HDS continuously streams even when nothing is on it.
- **Layer 3 migration**: changing `deviceId` invalidates `preferredScaleId` once. Users will auto-reconnect on next scan anyway; document in the PR. If we want zero user-visible impact, add a one-shot migration that rewrites the setting on first startup, but that's probably overkill.
- **Layer 4 complexity**: Android doze / USB suspend is fussy and manufacturer-specific. Don't let this layer delay layers 1–3. Ship them separately if Layer 4 gets stuck.

## Open questions

- Does the issue also reproduce on a non-Teclast Android host? Reporter `@allofmeng` would be the one to confirm; worth asking on the issue thread once Layers 1–3 land.
- Is `[0x03, 0x20, 0x01]` the correct "start weight reporting" command for the HDS firmware currently in the field? Confirm against decentespresso/de1app reference and/or HDS firmware source if accessible.
