# Transport / device lifetime audit

Branch: `fix/transport-lifetime-audit` · TODO ref: `^transport-lifetime-audit` (P1)

## Background & what changed during investigation

The TODO promoted this P3→P1 on the basis of Crashlytics `8caae7dc`
(`UnifiedDe1Raw.initRawStream` — "Stream has already been listened to"),
asserting the comms-harden #3 guard "isn't closing the hole" and that the
real fix is option (b) "fresh transport+device+controllers per reconnect."

**That premise is stale.** Verified 2026-05-25:

- At commit `d7dba8d` (v0.5.14) `initRawStream()` had **no** guard; the guard
  was added later by `20e5d8e6` (comms-harden #3).
- Crash `8caae7dc` has `lastSeenVersion: 0.5.14`, **zero events on any
  0.6.x/0.7.x** build (current release v0.7.3). The events the TODO note read
  were all pre-guard. The guard closed the hole. Trigger was
  `ScaleDebugView(inspect:true)` calling `onConnect()` in `initState`.
- No reconnect-accumulation leak from `dispose()` not being called: BLE
  `connect()` cycles `_nativeConnectionSub` (cancel+reassign) and `subscribe()`
  uses `cancelWhenDisconnected`. So option (b)'s churn is unjustified.

**The real, current, user-visible bug** (surfaced from m50mini.home live logs):
duplicate WebSocket state messages. Root cause:
`AndroidBluePlusTransport.connect()` (and `BluePlusTransport`) returns early
when `_device.isConnected` ("Already connected, skipping connect") — *no
disconnect occurred*. But `UnifiedDe1Transport.connect()` always runs
`_bleConnect()` afterward, which re-`subscribe()`s all 6 characteristics.
Because no disconnect fired, `cancelWhenDisconnected` never cancelled the prior
`onValueReceived.listen` callbacks → two live listeners per characteristic →
`_stateSubject.add` fires twice per notification → `currentSnapshot`
(no `.distinct()`) emits twice → duplicate state over WS. Triggered by the
GATT-133 retry / BLE-timeout recovery reconnect paths.

Also found (deferred, not this PR): `BatteryController._tick()` writes
`setUsbChargerMode` every 60s unconditionally (~2665 writes/2 days). The
periodic write is **intentional** — DE1 FW re-enables the charger, so keeping
the tablet discharging requires periodic re-assertion. Optimisation (write-on-
change while charging, keep periodic re-assert while discharging) tracked
separately.

## Scope (user-approved)

1. **Fix duplicate characteristic subscriptions** (the real bug).
2. **Typed connection guards** (salvaged core of the mmrRead sub-task).
3. **dispose() wiring** (end-of-life hygiene — see churn note).

Out of scope: option (b) reconnect rewrite; USB-charger write optimisation;
the `_mmrRead` adapter-state pre-check (redundant — `writeWithResponse`
already guards connection state, and the 2s timeout is on the notify-wait).

## Phase 1 — Idempotent characteristic subscriptions (headline fix)

Make `subscribe()` idempotent per characteristic so a re-subscribe without an
intervening disconnect replaces rather than stacks.

- `BluePlusTransport`, `AndroidBluePlusTransport`, `LinuxBluePlusTransport`:
  add `final Map<String, StreamSubscription> _charSubs = {}` keyed by
  `characteristicUUID`. In `subscribe()`: cancel + remove any existing entry
  for that UUID before `onValueReceived.listen`, then store the new sub.
  (`cancelWhenDisconnected` still handles the real-disconnect case; the map
  handles the no-disconnect re-subscribe case.)
- `UniversalBleTransport`: different API (`subscribeNotifications`/
  `unsubscribe`). Track subscribed `serviceUUID/characteristicUUID` in a Set;
  `unsubscribe` before re-subscribing if already present.
- Tests: build a fake BLE transport, subscribe twice for the same
  characteristic without a disconnect, push one notification, assert the
  callback fires exactly once. Add a higher-level test asserting
  `currentSnapshot` does not emit duplicates after a no-op reconnect.

## Phase 2 — Typed connection guards (trivial)

`UnifiedDe1Transport.read` / `write` / `writeWithResponse` currently
`throw ("de1 not connected")`. Replace with
`throw DeviceNotConnectedException.machine()` (already defined in
`models/errors.dart`, already modelled by `ConnectionManager`). Update any
test asserting the raw string.

## Phase 3 — dispose() wiring (hygiene — higher churn, separable)

**Churn note:** adding `dispose()` to the `DataTransport` interface forces it
onto `UniversalBleTransport` + `AndroidSerialPort` (currently lack it) and ~6
test fakes that `implements DataTransport`. Higher churn than the TODO's
"bounded trivial win" implied, and there's no current crash/leak signal.
Recommend it can split to a follow-up PR if Phase 1+2 are wanted sooner.

- Add `Future<void> dispose()` to `DataTransport`. Implement everywhere
  (the 3 BLE transports already have `void dispose()` → widen to async
  `@override`; desktop serial already async; add to universal_ble, android
  serial, and the test fakes as no-ops/minimal).
- `UnifiedDe1Transport.dispose()`: cancel `_transportSubscription` + all
  `_charSubs`, close the 6 `BehaviorSubject`s, then `await _transport.dispose()`.
- `UnifiedDe1.dispose()`: close `_rawMessageController` + `_rawInputController`,
  then dispose the transport. `Bengle.dispose()` override → dispose capability
  state, then `super.dispose()`.
- Wiring: call `device.dispose()` when a device is permanently removed from the
  discovery `_devices` cache (verify removal semantics don't dispose-then-reuse
  the same instance) and/or on `ConnectionManager`/app shutdown. **Never** on
  reconnect — cached transports are reused.
- Tests: dispose is idempotent; subjects report `isClosed`; no double-dispose.

## Verification

- `flutter test` (full suite, 1135+) + `flutter analyze` after each phase.
- End-to-end: `scripts/sb-dev.sh` simulate, open the DE1 state WebSocket,
  force a no-op reconnect path, confirm single (not duplicated) state frames.
- **Tablet smoke before claiming done** — this is a connectivity-layer change;
  CI + unit tests miss native-stream + platform-timing regressions
  (per `feedback_real_hw_smoke`).
- Then update `ReaPrime/TODO.md`: mark `8caae7dc` resolved, rescope
  `^transport-lifetime-audit`, record the real findings. Check `doc/Api.md` /
  `doc/DeviceManagement.md` for needed updates.
