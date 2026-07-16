# Fix #431: Zombie-link teardown fires on live connection + crash cluster

## Problem

Three distinct but related bugs share a common error-handling path in the BLE transport layer:

### #431 — Zombie-link teardown on live connection (P0, regression)

`UnifiedDe1Transport.connect()` (PR #416) checks if the BLE transport already reports `connected` and unconditionally tears down the "stale" link before reconnecting. This fires on **live** connections — e.g. when skin download activity or debug-view entry triggers a reconnect cycle — causing an unnecessary disconnect + auto-reconnect (~1.5s downtime).

**Log evidence (2026-07-10, m50mini):**
```
INFO  UnifiedDe1Transport-D9:11:0B:E6:9F:86 - Transport already connected; tearing down stale link before reconnect to avoid no-op-reconnect push death
FINE  BLETransport-D9:11:0B:E6:9F:86 - disconnect
WARNING BLETransport-D9:11:0B:E6:9F:86 - Transport disconnected: unknown
SEVERE StatusPublisher - emit error: kind=machineDisconnected
```

### Crash cluster — uncaught exceptions from expected error paths

**iOS `cdd48b30` (28ev FATAL) + `f7e3bc89` (19ev FATAL) + `21b6c4a7` (36ev FATAL):** Same iPad Pro M4 user/session. Acaia Lunar scale disconnects (connection timeout) → `AcaiaScale._sendHeartbeat()` fires from `Timer.periodic` → `_transport.write()` throws `DeviceNotConnectedException` via `_handleGattError` → exception is **uncaught** (fire-and-forget timer callback) → Flutter zone error handler → Crashlytics FATAL.

**Android `60b12216` (12ev NON_FATAL) + `38d02b06` (5ev FATAL):** BLE write to DE1 (setProfile) times out after 10s in universal_ble queue → `TimeoutException` propagates uncaught through `WorkflowDeviceSync` → Crashlytics. The `_onOperationTimeout` handler in `UniversalBleTransport` clears the queue and `rethrow`s, but the caller's `catch (e, st)` block catches it and retries — however the Crashlytics recording happens at the zone level before the catch.

### universal_ble GH #1 — GATT-133 surfaced as unknownError

Android GATT-133 (`GATT_ERROR`) is surfaced as `UniversalBleException(code: unknownError, message: "Failed to write", details: 133)`. Our `_handleGattError` treats ALL `unknownError` as permanent disconnect → declares link dead. But 133 is often transient (stale connection state, resource exhaustion, concurrent radio ops). The fork already retries 133 at the native `connect()` level (commit `ca9c127`), but NOT at the `write()`/`read()` level.

**Reference (not source of truth):** flutter_blue_plus surfaces 133 as `disconnect_reason_code: 133, disconnect_reason_string: ANDROID_SPECIFIC_ERROR` and leaves retry to the app developer. Their FAQ says: "There is no 100% solution. The recommended solution is to catch the error, and retry." Broader Android BLE best practice (crickshaw.dev, devsflow.ca): serialize ops, close failed GATT handles, jittered exponential backoff retry.

## Plan

### Phase 1: Fix #431 — probe before teardown (reaprime)

**File:** `lib/src/models/device/impl/de1/unified_de1/unified_de1_transport.dart`

**Change:** Before tearing down the "stale" link, probe the OS-level connection state. Only tear down if the OS confirms the link is dead. If the OS says `connected`, skip the teardown and proceed with `_bleConnect()` directly (the cancel-before-replace in `subscribe()` already handles re-subscription safely).

**Interface note:** `getConnectionState()` is defined on `BLETransport`, not `DataTransport`. Since `UnifiedDe1Transport` holds a `DataTransport`, we need to cast to `BLETransport` in the `wasConnected` path. This is safe because the `wasConnected` check already requires `transportType == TransportType.ble`, which guarantees the transport is a `BLETransport`.

```
Current:
  wasConnected = (transportType == ble && connectionState == connected)
  if (wasConnected) → disconnect() → connect() → _bleConnect()

New:
  wasConnected = (transportType == ble && connectionState == connected)
  if (wasConnected):
    final bleTransport = _transport as BLETransport
    probe OS connection state via bleTransport.getConnectionState() (with 2s timeout)
    if OS says connected → skip teardown, log "link is live, skipping stale-link teardown"
    if OS says disconnected/connecting/disconnecting → proceed with teardown (existing path)
    if probe fails/times out (inconclusive) → proceed with teardown (existing path, safe default)
```

**Rationale:** The teardown was added to fix a real bug (no-op-reconnect push death — stateInfo stops delivering on re-subscribe against a zombie link). But it's too aggressive — it fires on every `connect()` while connected, even when the link is healthy. The probe adds a 2s timeout check (same as `_linkProbeTimeout` in `UniversalBleTransport`) that distinguishes "zombie link" from "live link."

**Success criteria:**
- Unit test: `connect()` while transport reports `connected` AND OS probe returns `connected` → teardown does NOT fire → `_bleConnect()` runs without prior disconnect
- Unit test: `connect()` while transport reports `connected` AND OS probe returns `disconnected` → teardown DOES fire (existing behavior preserved)
- Unit test: `connect()` while transport reports `connected` AND OS probe throws → teardown DOES fire (safe default)

### Phase 2: Fix crash cluster — catch expected exceptions in fire-and-forget paths (reaprime)

**File 1:** `lib/src/models/device/impl/acaia/acaia_scale.dart`

**Change:** Wrap `_sendHeartbeat()` body in try/catch for `DeviceNotConnectedException`. The heartbeat is a periodic timer callback — if the scale is disconnected, the write will throw. Catch it, log fine, and let the watchdog/disconnect cascade handle the cleanup (it already does — `_checkWatchdog` calls `disconnect()` which cancels the timers).

**Async exception note:** `_transport.write()` returns `Future<void>`. The `DeviceNotConnectedException` is thrown inside the async function (after `await UniversalBle.write(...)` completes with an error), so a synchronous `try/catch` around the call will NOT catch it. The fix must either:

```dart
// Option 1: async + await (preferred — handles both heartbeat + config writes)
void _sendHeartbeat() {
  unawaited(_sendHeartbeatAsync());
}

Future<void> _sendHeartbeatAsync() async {
  try {
    await _transport.write(_serviceUuid, _writeCharUuid, _encode(0x00, _heartbeatPayload),
        withResponse: _useWriteResponse);
  } on DeviceNotConnectedException {
    _log.fine('Heartbeat write failed — scale disconnected');
    return; // Don't start config timer if heartbeat failed
  }
  _configTimer?.cancel();
  _configTimer = Timer(const Duration(seconds: 1), () {
    unawaited(_sendConfigWrite());
  });
}

Future<void> _sendConfigWrite() async {
  try {
    await _transport.write(_serviceUuid, _writeCharUuid, _encode(0x0C, _configPayload),
        withResponse: _useWriteResponse);
  } on DeviceNotConnectedException {
    _log.fine('Config write failed — scale disconnected');
  }
}
```

The `_configTimer` callback also calls `_transport.write()` fire-and-forget — it needs the same try/catch treatment since it fires 1s later in a separate timer callback.

**File 2:** `lib/src/services/ble/universal_ble_transport.dart` — no change. `_handleGattError` should remain `Never` (it always throws). The fix is at the caller site (File 1).

**Other fire-and-forget paths to audit:** `DecentScale` (BLE impl) has an `async` `Timer.periodic` heartbeat with a connection-state guard at the top — it's less vulnerable but should be audited for uncaught exceptions from `_requestBatteryData()`. The `_configTimer` inside `AcaiaScale._sendHeartbeat()` is a separate `Timer` callback that also calls `_transport.write()` fire-and-forget — it needs the same treatment (shown in the code above).

**File 3:** `lib/src/controllers/workflow_device_sync.dart` (verify only)

**Check:** The `WorkflowDeviceSync._drain()` method already catches `DeviceNotConnectedException` (line 126) and generic `catch (e, st)` (line 128). The `TimeoutException` from the queue is NOT a `DeviceNotConnectedException` — it falls through to the generic catch. Verify the generic catch doesn't re-throw or let the exception escape to the zone. If it does, add explicit `TimeoutException` handling.

**Success criteria:**
- Unit test: `AcaiaScale._sendHeartbeat()` when transport throws `DeviceNotConnectedException` → no uncaught exception, log message emitted, timers continue (watchdog will handle cleanup)
- Verify `WorkflowDeviceSync._drain()` catches `TimeoutException` without propagation

### Phase 3: Fix universal_ble GH #1 — surface GATT-133 as identifiable error (universal_ble fork)

**File:** `android/src/main/kotlin/com/nnavideck/universal_ble/UniversalBlePlugin.kt` (or equivalent)

**Change:** When `onCharacteristicWrite` reports `status=133`, surface it as a distinct error code instead of collapsing to `unknownError`. Options:

- **Option A (minimal):** Add the GATT status code to the error message (e.g. `"Failed to write (GATT status: 133)"`) so `_handleGattError` in reaprime can parse it. Simple but fragile (string parsing).
- **Option B (proper):** Add a new `UniversalBleErrorCode.gattError` (or `gattStatus`) that carries the raw status code as a field. More work but type-safe.

**Decision:** Option B — add `UniversalBleErrorCode.gattError` with the status code in the message/details. Then in reaprime's `_handleGattError`, handle `gattError` with status 133 as a transient error: clear the queue, log a warning, and rethrow as a `BleTimeoutException` (which triggers the existing retry-and-reconnect recovery in `UnifiedDe1Transport`) instead of declaring the link dead.

**No native retry for read/write.** Surface the error code only; let the Dart caller decide retry vs. disconnect. Rationale:
- flutter_blue_plus (used as reference) does NOT retry read/write at the native level — they surface `android-code: 133` to Dart and let the app catch + retry. Their FAQ: "The recommended solution is to catch the error, and retry."
- The Dart caller has context the native layer lacks: a profile upload is a stateful multi-write sequence (header → indexed frames → tail). Blindly retrying one write mid-sequence would corrupt the firmware receive state machine. `WorkflowDeviceSync` already handles this — it catches failures and re-drives the entire upload from the header.
- The fork already has native retry for `connect()` GATT 133 (commit `ca9c127`), which is safe because connect is a single atomic operation. Read/write are not — they can be part of a sequence.
- Broader Android BLE best practice (crickshaw.dev, devsflow.ca) also recommends application-level retry with jittered backoff, not native-level retry on individual operations.

**Note:** The fork already has native-level GATT 133 retry at `connect()` time (commit `ca9c127`). This phase extends the error-surfacing to `write()`/`read()` level — giving the Dart caller enough information to retry vs. disconnect.

**Success criteria:**
- Test in universal_ble: `onCharacteristicWrite(status=133)` → Dart receives `UniversalBleException(code: gattError, ...)` not `unknownError`
- Test in reaprime: `_handleGattError` with `gattError` + status 133 → throws `BleTimeoutException` (retryable), NOT `DeviceNotConnectedException` (permanent)

### Phase 4: Crashlytics noise reduction — Queue Cancelled exceptions

**File:** `lib/src/services/telemetry/firebase_crashlytics_telemetry_service.dart` (verify)

**Check:** The `21b6c4a7` crash is `Exception: Queue Cancelled` from `Queue.dispose()` completing pending futures with an error. This is a normal side-effect of disconnect (clearing the BLE queue). Verify the telemetry forwarder filters this out or that the caller catches it. The existing SEVERE-level filter (PR #288) should drop WARNING-level events, but `Queue.dispose()` completes futures with `Exception('Queue Cancelled')` which may be recorded as a Flutter error before the filter applies.

**Success criteria:**
- Verify `Queue Cancelled` exceptions are not reaching Crashlytics after Phase 2 fixes (the heartbeat catch should prevent the cascade that triggers the queue disposal)

## Resolved decisions

1. **Pigeon regeneration:** Regenerate pigeon files in the universal_ble fork as part of Phase 3 (not deferred).
2. **DecentScale scope:** Keep scope tight — only fix AcaiaScale heartbeat. DecentScale BLE heartbeat already has a connection-state guard and recent edits flipped the heartbeat flag to false. Do not touch.
3. **Fork version:** Bump the universal_ble fork version after adding `gattError`, and update the reaprime `pubspec.yaml` dependency to point to the new version.

## Implementation order

1. **Phase 1** (reaprime) — fix #431, the P0 regression. Standalone, no universal_ble changes needed.
2. **Phase 2** (reaprime) — fix crash cluster. Standalone, prevents FATAL crashes from expected error paths.
3. **Phase 3** (universal_ble fork + reaprime) — upstream error code improvement. Requires fork changes + reaprime consumer updates.
4. **Phase 4** (verify) — confirm noise reduction after Phases 1-3.

## Files to change

| Phase | File | Change |
|-------|------|--------|
| 1 | `lib/src/models/device/impl/de1/unified_de1/unified_de1_transport.dart` | Add OS probe before stale-link teardown |
| 1 | `test/unit/models/unified_de1_transport_resubscribe_test.dart` (or new test) | Add probe-before-teardown tests |
| 2 | `lib/src/models/device/impl/acaia/acaia_scale.dart` | Catch `DeviceNotConnectedException` in `_sendHeartbeat()` |
| 2 | `test/` (new or existing scale test) | Add heartbeat-on-disconnected test |
| 2 | `lib/src/controllers/workflow_device_sync.dart` | Verify `TimeoutException` is caught (may need explicit catch) |
| 3 | `~/development/work/universal_ble/android/...` | Surface GATT-133 as `gattError` code |
| 3 | `~/development/work/universal_ble/lib/src/universal_ble_pigeon/...` | Add `gattError` to error code enum |
| 3 | `lib/src/services/ble/universal_ble_transport.dart` | Handle `gattError` with retry instead of permanent disconnect |
| 3 | `test/universal_ble_transport_recovery_test.dart` | Add GATT-133 write failure test |

## What NOT to change

- `_handleGattError` return type stays `Never` — it always throws. The fix is at caller sites.
- `_onOperationTimeout` `rethrow` stays — the caller needs to know the operation timed out. The fix is ensuring callers catch it.
- The zombie-link detection system (`_probeAndDeclareIfDead`, `_declareLinkDead`, advert watch) stays — it's a good safety net. The fix is making the `UnifiedDe1Transport.connect()` teardown path smarter, not removing the detection.
- The `Queue` in universal_ble stays as-is — the write coalescing and per-device queue are correct.

## Testing strategy

| Tier | What | How |
|------|------|-----|
| Unit | `UnifiedDe1Transport.connect()` probe-before-teardown | Mock `BLETransport` with controllable `getConnectionState()` + `connectionState` stream |
| Unit | `AcaiaScale._sendHeartbeat()` on disconnected transport | Mock transport that throws `DeviceNotConnectedException` on write |
| Unit | `_handleGattError` with `gattError` code | Fake `UniversalBlePlatform` that throws `gattError` on write |
| Integration | Full zombie-link scenario: connect → sleep → wake → reconnect | `flutter test` with simulated devices (`--dart-define=simulate=1`) |
| End-to-end | Verify on m50mini hardware after deploy | `sb-dev` + manual wake/sleep cycle, check logs for "skipping stale-link teardown" |
