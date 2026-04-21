# Comms Hardening — Phase 5 Implementation Plan

Execution plan for Phase 5 of `doc/plans/comms-harden.md`: transport + lifecycle hygiene. Resolves Cluster C's remaining items and the reconnect-path items from Cluster E.

Four roadmap items in scope: **5, 12, 13, 31**.

## Pre-work findings

### Item 5 — shot-settings debounce races disconnect

`lib/src/controllers/de1_controller.dart:142–149`:

```dart
Future<void> _shotSettingsUpdate(De1ShotSettings data) async {
  _shotSettingsDebounce?.cancel();
  _shotSettingsDebounce = Timer(const Duration(milliseconds: 100), () async {
    _log.info('Processing shot settings update (debounced)');
    await _processShotSettingsUpdate(data);
  });
}
```

`_onDisconnect` cancels `_shotSettingsDebounce` at line 116 — good. But if the 100 ms timer has **already fired** and the closure body is mid-flight in `_processShotSettingsUpdate`, cancelling the timer does nothing. The closure keeps awaiting `connectedDe1().getSteamFlow()` etc., each of which now throws `DeviceNotConnectedException` (Phase 1, item 25) because `_de1` was nulled in `_onDisconnect`. The exception leaks out of the timer callback as an unhandled async error.

**Fix:** generation token. Increment `_connectionGeneration` in `_onDisconnect`; the debounce closure captures the generation at scheduling time and bails out early if it no longer matches. Also wrap the `_processShotSettingsUpdate` body in a try/catch that swallows `DeviceNotConnectedException` specifically (now a typed exception, so the catch is precise). Activates Gap E test from Phase 0.

### Item 12 — transport `_nativeConnectionSub` never cancelled in disconnect()

Three files:
- `lib/src/services/ble/blue_plus_transport.dart:59–66`
- `lib/src/services/ble/android_blue_plus_transport.dart:147+`
- `lib/src/services/ble/linux_blue_plus_transport.dart:164+`

Each cancels `_nativeConnectionSub` at the **start** of `connect()` (good — re-using the transport for a reconnect cycles the subscription) but none cancels it in `disconnect()`. Late `disconnected` events from the FlutterBluePlus stream fire after our own `disconnect()` call and hit a `BehaviorSubject.add` on a controller we've already processed, accumulating subscriptions over repeated connect/disconnect cycles.

**Fix:** add `_nativeConnectionSub?.cancel();` at the start of `disconnect()` in all three files. Null out afterwards so a subsequent `connect()` sees a clean state. Three-line change × 3 files.

### Item 13 — ScaleController.dispose is empty

`lib/src/controllers/scale_controller.dart:27`:

```dart
void dispose() {}
```

`_connectionController` (`BehaviorSubject<ConnectionState>`) and `_weightSnapshotController` (`StreamController<WeightSnapshot>.broadcast()`) are never closed. Subscribers never see `onDone`. Minor today (ScaleController is app-wide, disposed only on app shutdown), but resource-leak pattern worth fixing now — part of the Cluster E lifecycle hygiene.

**Fix:** close both subjects in `dispose()`. Guard with `isClosed` so repeated disposes are safe. Also cancel `_scaleSnapshot` / `_scaleConnection` subscriptions if they're live.

### Item 31 — end-to-end connect timeout

`ConnectionManager.connect`, `connectMachine`, `connectScale` have no top-level timeout. Phase 1's item 2 fix bounded the MMR-read hang at 2 s, but other transport-level operations (`de1Controller.connectToDe1(machine)` which internally awaits `_bleConnect()` + service discovery + MMR info reads; `scaleController.connectToScale(scale)` with its own `onConnect()`) can in principle hang on a misbehaving device.

The MMR timeout we have today is the acute protection; the end-to-end timeout is the belt-and-braces that prevents any *other* hang from wedging `_isConnecting`.

**Fix:** wrap `de1Controller.connectToDe1(machine)` in `.timeout(const Duration(seconds: 30))` inside `connectMachine`; same for scale. On timeout, emit `machineConnectFailed` / `scaleConnectFailed` with a distinct suggestion ("Device took too long to respond. Try again, and if the problem persists power-cycle the device."). The timeout fires as a `TimeoutException` which is already caught by the existing `catch (e)` — needs a small classification tweak in `_buildConnectError` to identify it cleanly.

**Timeout value choice.** Real-hardware connect currently observed at 3–10 s on tablet (4.0 s typical, up to 9.9 s with GATT 133 retries). 30 s is ~3× the worst-case observed and leaves headroom for slow BLE adapters. Value lives in a named constant.

---

## Goals

After Phase 5:

- Shot-settings debounce no longer leaks exceptions on disconnect (item 5).
- Transport subscriptions lifecycle-clean across reconnect cycles (item 12).
- `ScaleController` disposes its subjects (item 13).
- `connectMachine` / `connectScale` fail loudly after 30 s instead of hanging (item 31).
- Gap E placeholder test from Phase 0 activates as a live regression check.

## Non-goals

- Transport-level `_nativeConnectionSub` *re-subscription* on disconnect — cancelling is enough; we don't need to proactively detect the "device vanished while app-initiated-disconnecting" case.
- Connect timeout for `ConnectionManager.connect()` as a whole (the 15 s scan + variable connect path makes a single-number budget messy; the per-device timeouts on `connectMachine`/`connectScale` cover the real hang risk).
- Any change to `DisconnectExpectations` TTL (separate concern, already has a 10 s TTL that works).

---

## Landmines

1. **Gap E test existed as a placeholder** (`test/controllers/de1_controller_test.dart`). Activating it needs a real `_processShotSettingsUpdate` call path or a tightly mocked `TestDe1` that can fake `shotSettings` stream. May require extending `TestDe1` with a controllable shot-settings stream.
2. **Transport-level disconnect() doesn't always get called.** Three scenarios:
   - App-initiated disconnect (`UnifiedDe1.disconnect()` → transport.disconnect). Covered.
   - Device-initiated disconnect (BLE drop). The native stream emits `disconnected`; our subscription sees it and propagates. We're NOT in `disconnect()` here. But the subscription still exists and still works.
   - App shutdown. `dispose()` chain. Needs to cover transport subscription cleanup too.
   So cancelling in `disconnect()` fixes the reconnect-cycle leak but not the BLE-drop case. That's fine — on BLE drop, the subscription IS still the live channel reporting the drop. It'd get cancelled next time `connect()` runs.
3. **TimeoutException is already an `Exception`.** `_buildConnectError` runs via `catch (e)` in `connectMachine`/`connectScale` without inspecting type; if we want a distinct suggestion string for timeout, we need a typed check. Alternative: use a single message for all connect failures — simpler, less helpful.
4. **ScaleController.dispose() caller.** Who calls it today? Probably `main.dart` shutdown path, possibly widget tests. Need to grep before assuming.
5. **Scale-connection-state listener subscription** (`_scaleConnection` at line 13). Already set up; already cancelled in `_onDisconnect` at line 54. So a proper dispose needs to cancel subscriptions first, then close subjects.

---

## Delivery strategy

One PR — the four items are narrow and touch different files, but together form a coherent "lifecycle hygiene" theme.

**Branch:** `feature/comms-phase-5-lifecycle-hygiene` off `integration/comms-harden-rest`. **Est. size:** ~150 LoC + ~80 LoC test, across 5 files (`de1_controller.dart`, three `*_transport.dart`, `scale_controller.dart`, and the test file).

### Per-item scope

1. **Item 5 — debounce generation token.**
   - Add `int _connectionGeneration = 0;` to `De1Controller`.
   - Increment it in `_onDisconnect()`.
   - `_shotSettingsUpdate` captures `_connectionGeneration` when scheduling the timer; the timer body bails if the value has changed.
   - `_processShotSettingsUpdate` wrapped in `try { ... } on DeviceNotConnectedException catch (_) { /* expected during teardown */ }` as defence-in-depth.
   - Activate `test/controllers/de1_controller_test.dart` placeholder with a real test that (a) uses `fake_async` to advance the debounce, (b) nulls `_de1` mid-closure, and (c) asserts no unhandled error leaks from the timer.

2. **Item 12 — transport disconnect cancels sub.** For each of the three transport files:
   - Add `_nativeConnectionSub?.cancel(); _nativeConnectionSub = null;` at the start of `disconnect()`.
   - Tests are hard to write without a BLE mock. Rely on code review + tablet smoke (the transport leak only matters on reconnect cycles, already covered by our disconnect+reconnect smoke pass).

3. **Item 13 — ScaleController.dispose proper.**
   - Cancel `_scaleSnapshot?.cancel()` / `_scaleConnection?.cancel()`.
   - Close both controllers with `isClosed` guard.
   - Grep callers, confirm no use-after-dispose risk.

4. **Item 31 — end-to-end connect timeout.**
   - Add `static const _connectTimeout = Duration(seconds: 30);` on `ConnectionManager`.
   - Wrap the `await de1Controller.connectToDe1(...)` call in `connectMachine` with `.timeout(_connectTimeout)`.
   - Same for `scaleController.connectToScale(...)` in `connectScale`.
   - Extend `_buildConnectError` to check `if (exception is TimeoutException)` and surface a distinct suggestion.
   - Add a targeted test that uses a fake controller hanging forever on `connectToDe1` and asserts `machineConnectFailed` with timeout-flavoured details after 30 s (run via `fake_async`).

### Tests

- Activate Gap E (`test/controllers/de1_controller_test.dart`): debounce-race regression.
- New test for item 31 timeout: `connect_timeout_test` style, possibly as a group inside `connection_manager_test.dart`.
- Existing 80-test ConnectionManager suite + 11 PolicyResolver tests + collaborator unit tests stay green.

---

## Success criteria

- `flutter test`: full suite green (980 → 982-ish after 2 new + Gap E activation). Gap E placeholder count drops from 2 to 1.
- `flutter analyze`: clean on all changed files.
- Real-hardware smoke on tablet: multiple disconnect+reconnect cycles to exercise item 12 (expect no "late disconnected event fires on closed subject" SEVERE in logs). Normal connect timing unaffected by item 31 (30 s budget is well above observed real-hardware 3–10 s).

---

## Open questions

1. **Does `main.dart` dispose `ScaleController`?** If not, item 13's fix is theoretical only. Worth confirming, still worth doing.
2. **Timeout value for item 31.** 30 s proposed — anyone's instinct different? GATT 133 retries can push to ~12 s; 30 s gives headroom without feeling sluggish.
3. **Should item 12 also close the transport's `BehaviorSubject` in some teardown?** It's owned by the transport, not per-connect. Today nothing disposes the transport itself — device instances are cached by discovery services. Out of scope for Phase 5; revisit as part of a transport-dispose audit later.
4. **Gap E test strategy.** Real path (debounce timer + disconnect mid-flight) or synthetic (call `_processShotSettingsUpdate` directly with `_de1` nulled)? The real path exercises the generation-token logic; the synthetic is cheaper. Lean real.

Answer (or confirm) these and I kick off the single sub-PR.
