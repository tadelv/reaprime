# Connectivity Layer Hardening

Roadmap + task list for hardening and simplifying the device connectivity layer. Combines findings from two independent code reviews plus a cross-affect analysis that groups issues by structural coupling and sequences them for lowest-risk execution.

**How to read this doc:**

1. [Coupling map](#coupling-map) — clusters the 31 issues by what actually binds them together.
2. [Cross-affect insights](#cross-affect-insights) — non-obvious interactions that dictate ordering.
3. [Landmines](#landmines) — audits required *before* touching certain items.
4. [Attack plan](#attack-plan) — phased execution, Phase 0–6.
5. [Task list](#task-list) — the 31 items, grouped by severity, tagged with cluster labels.

---

## Coupling map

Five clusters. Two keystones (A, B) carry most of the leverage. Fixing keystones in isolation resolves many downstream items for free.

### Cluster A — State authority (THE gravitational center)

**Items:** #4, #6, #7 (partial), #8, #9, #14, #18

Too many sources of truth for connection state:

- `_machineConnected` / `_scaleConnected` flags
- `de1Controller.de1` stream
- `scaleController.connectionState` stream
- `_isConnecting` / `_isConnectingMachine` / `_isConnectingScale`
- `earlyMachineConnect` / `earlyScaleConnect` `Future<void>?`
- transport-level `connectionState`

All disagree across async gaps. Fixing them one-by-one = whack-a-mole. Derive state from streams once → cluster collapses.

### Cluster B — Scan API shape

**Items:** #22, #21, #11, #10, #17, #23

#22 (scan returns before completion, errors swallowed) is the disease. #21 (the 8-line race comment) admits it in-line. #11/#10 are scan-ownership/cancellation consequences. #17/#23 duplicate bookkeeping around scan results. Fix `scanForDevices()` signature + completion semantics → cluster collapses.

### Cluster C — Connection-hang chain

**Items:** #2, #3, #5, #31

`UnifiedDe1` lifecycle + timeout discipline. MMR hang (#2) acute. Relisten throw (#3) is reconnect twin. Debounce race (#5) is teardown twin. #31 (top-level connect timeout) is belt-and-braces once point fixes land. One reconnect integration test validates all four.

### Cluster D — God-class structural

**Items:** #15, #16, #19

#16 (7 verbs) and #19 (nested subs) are **symptoms** of #15 (965-line god-class). Do not attack the verbs first — factoring without state cleanup = dragging bugs into new classes.

### Cluster E — Isolated / independent

- #1 profile guard — surgical, 5-line fix
- #12 transport `_nativeConnectionSub` leak — loose couple to #3 (reconnect twin)
- #13 `ScaleController.dispose()` — standalone
- #20 name-vs-deviceId — data-migration wrinkle (see landmines)
- #24–#30 — hygiene, independent

---

## Cross-affect insights

Non-obvious interactions that force ordering:

1. **State authority is the center of gravity.** Fixing #4/#6/#8/#9 independently = four patches, four new edge cases. Single `combineLatest(de1, scale, scanState, currentOp)` pass = all four vanish. Biggest leverage in the whole doc.
2. **#22 is the disease; #21 is its symptom.** Any workaround comment or race elsewhere traces back to scan not having a proper `Future<ScanResult>` return. Fix shape, not symptoms.
3. **God-class split (#15) is tempting to do first — don't.** Splitting before state derivation means factoring around the wrong seams. Do state first; the split almost writes itself.
4. **#16 ("7 connect verbs") is a symptom, not a target.** Don't consolidate methods until state is derived — wrong factoring, future regret.
5. **#3 (relisten throw) + #12 (transport sub leak) are reconnect-path twins.** Neither surfaces on first connect; both hurt on cycle #2+. Same test catches both.
6. **#5 (debounce race) becomes trivial *after* #25 (typed exceptions).** `catch (e) if (e is DeviceNotConnectedException)` beats string-compare. Order: #25 before #5.
7. **#2 MMR timeout + #31 end-to-end timeout are layered defenses.** #2 alone → narrower hang window. #31 alone → still 30s+ hang per attempt. Need both; #2 first because it's the actual bug.
8. **#7 (early-connect guards) + #18 (`Future<void>?` as state) are the same issue** from opposite ends. Replace with explicit `enum ConnectingState`. Do together.
9. **Error emission ordering (#8) is a consequence of phase being published rather than derived.** Once phase is `combineLatest`-derived, "publish phase then emit error" inversion becomes structurally impossible. Free win from Cluster A.
10. **#9 (`scaleOnly` dropped) has product semantics.** Concurrent scan-for-scale during machine-connect may hurt real BLE. Confirm product intent before coding — correct answer may be "queue it," not "allow concurrent."

---

## Landmines

Check before you touch:

- **#20 name → deviceId migration.** `_disconnectedAt` may be persisted; settings may key preferred devices by name. Silent key change = loss of user's preferred-device selection. Audit `PreferencesService` / `SettingsService` / `SharedPreferences` keys before renaming.
- **#9 `scaleOnly` concurrency.** Product decision, not just code. Confirm intent before implementing.
- **#3 relisten fix.** If `UnifiedDe1` is instantiated fresh per connection (not reused), the bug is cosmetic. If reused, it's acute. Verify lifecycle in `BluePlusDiscoveryService` / `De1Controller` before picking fix (broadcast controllers vs recreate-per-connect vs assert-single-use).

---

## Attack plan

Phased for lowest-risk execution. Phase 0 is a hard prerequisite. Phases 1 and 2 can run in parallel.

### Phase 0 — Safety net (prerequisite)

Integration tests in `test/` using `MockDe1` / `TestScale` covering:

- Happy connect (scan → machine → scale → ready)
- Machine `onConnect` throws → recover, retry possible
- Scale `onConnect` throws → flag not stuck true (#4 regression)
- Reconnect on same `UnifiedDe1` instance (#3 + #12 regression)
- Disconnect mid-scan + mid-connect (#5, #6, #7 regression)
- Dropped MMR notify during connect (#2 regression)
- Scan-start error (adapter off / permission denied) (#22 regression)
- Two devices with same advertised name (#20 regression)

Without these, every later phase is blind. Use `tdd-workflow` skill.

### Phase 1 — Stop the bleeding (surgical, shippable as patch)

Independent fixes, no refactor commitment. Small diffs, can ship independently.

- **#1** profile guard reorder (`_currentProfile` assigned after `_sendProfile` succeeds)
- **#2** MMR read timeout + typed error
- **#25** typed exceptions for `connectedDe1()` / `connectedScale()` (enables #5 later)
- **#26** logging in swallowed catches (observability before refactor)

### Phase 2 — Keystone A: state derivation (biggest leverage)

One coherent change. Collapses Cluster A.

1. Make `scanForDevices()` return `Future<ScanResult>` with proper error propagation (#22).
2. Pick `deviceStream` as single device source; delete `matchedDeviceResults` + `asBroadcastStream` re-wrap (#14, #17).
3. Derive `ConnectionStatus` from `combineLatest(de1Controller.de1, scaleController.connectionState, scanState, currentOperation)`. Delete `_machineConnected`, `_scaleConnected`, `earlyMachineConnect`, `earlyScaleConnect`; replace with `enum ConnectingState` (#7, #18).
4. Single `_publishStatus` path; delete `_emit` dual path (#8).

**After Phase 2:** #4, #6, #8, #9 (pending product call), #14, #17, #18, #21 resolved or trivialized.

### Phase 3 — Keystone B: scan ownership

Collapses remaining Cluster B items.

- `ScanSession` object with start/cancel/complete + `Future<ScanReport>` (#11, #22 plumbing).
- Linux refresh-scan owns its own lane; external `stopScan` only cancels its own owner (#10).
- Dedupe pre-scan cleanup to one layer (#23).

### Phase 4 — God-class split (now mechanical)

With state derived and scan ownership explicit, factoring seams are obvious.

- `ScanOrchestrator` (built on Phase 3's `ScanSession`)
- `PolicyResolver` (Preferred / Auto / Picker / Idle)
- `EarlyConnectWatcher` (#7, #19)
- `ConnectionManager` reduced to coordinator (~200 lines)
- #16 consolidation falls out naturally

### Phase 5 — Transport + lifecycle hygiene

Closes Cluster C remainder and Cluster E reconnect pair.

- **#12** cancel `_nativeConnectionSub` in `disconnect()` across 3 transports
- **#3** `UnifiedDe1` raw-stream controller discipline (after lifecycle audit — see landmines)
- **#31** end-to-end connect timeout
- **#5** debounce cancellation (easy now thanks to #25)
- **#13** `ScaleController.dispose()`

### Phase 6 — Polish

- **#20** name → deviceId (after migration audit)
- **#24** named constants (`connection_timings.dart`)
- **#27–#30** ScanReport adapter state, `devices` getter caching, adapter multicast, state-machine doc

### Start-here recommendation

Run **Phase 0 + Phase 1 in parallel.** Phase 0 builds the safety net; Phase 1 ships user-visible bug fixes without committing to a refactor direction. Do not touch Phase 2 without Phase 0 tests landed — it's the highest-leverage change and also the highest-risk without coverage.

---

## Task list

Ordered by severity; tagged with cluster labels (A/B/C/D/E) and phase. Tick items as they land.

## Architecture snapshot

```
[Discovery Services] → [DeviceController] → [ConnectionManager] → [Device Controllers]
     ↑                       ↑                      ↑
BluePlusDiscovery        DeviceScanner        ConnectionPhase stream
UniversalBle            unified device        ConnectionStatus / error
SerialService           stream + scan         preferred-device policy
SimulatedDevice
```

Core flow (`ConnectionManager.connect()`): scan → early connect on stream hits → full 15s BLE scan → apply policy (Preferred > Auto > Picker > Idle) → scale phase after machine connects.

Files in scope:

- `lib/src/controllers/connection_manager.dart` (orchestrator, ~965 lines)
- `lib/src/controllers/device_controller.dart`
- `lib/src/controllers/scale_controller.dart`
- `lib/src/controllers/de1_controller.dart`
- `lib/src/controllers/de1_state_manager.dart`
- `lib/src/models/device/device.dart`, `device_scanner.dart`
- `lib/src/models/device/impl/de1/unified_de1/unified_de1.dart` (+ `.mmr.dart`, `_transport.dart`)
- `lib/src/services/blue_plus_discovery_service.dart`
- `lib/src/services/ble/linux_ble_discovery_service.dart`
- `lib/src/services/ble/blue_plus_transport.dart`, `android_blue_plus_transport.dart`, `linux_blue_plus_transport.dart`
- `lib/src/services/device_matcher.dart`
- `lib/src/controllers/connection_error.dart`

---

## P0 — Ship-blockers (functional bugs)

### [ ] 1. `setProfile` guard poisoned by failed upload — `[E · Phase 1]`

**File:** `unified_de1.dart` `setProfile` (`_currentProfile == profile` guard).

`_currentProfile` is assigned **before** `_sendProfile` is awaited. If the upload throws mid-way (BLE timeout after header, before tail), `_currentProfile` already equals the new profile. The next retry with the identical `Profile` instance hits the guard and silently no-ops. Machine keeps running on a half-loaded profile; caller sees success.

Equality itself is correct (`Profile extends Equatable`, deep field equality over steps and sub-objects). The defect is ordering, not equality.

**Fix options:** assign `_currentProfile` only after `_sendProfile` succeeds; or clear it on throw; or track "successfully uploaded" separately from "last attempted".

---

### [ ] 2. `_mmrRead` hangs `onConnect` forever on dropped notify — `[C · Phase 1]`

**File:** `unified_de1.mmr.dart:20–32`.

`_mmr.firstWhere(...)` has no timeout. A single dropped MMR notify (firmware glitch, BLE drop between write and notify) during connect leaves the Future pending forever. Call chain: `onConnect` → `connectToDe1` → `connectMachine` → `_connectImpl`, all awaited. `_isConnecting` stays `true`; ConnectionManager is permanently wedged until app restart.

**Fix:** add a bounded timeout + typed error; propagate so `connectMachine` can fail cleanly and release `_isConnecting`.

Also: `_unpackMMRInt` indexes `buffer[i]` without bounds check — if `firstWhere` `orElse` returns `[]` it throws `RangeError`.

---

### [ ] 3. `UnifiedDe1` raw stream controllers are single-subscription — `[C · Phase 5]`

**File:** `unified_de1.dart` (`_rawInputController`, `_rawMessageController`, ~lines 213, 231). No `dispose()`.

`initRawStream()` is called from every `onConnect()`. On the second connect attempt against the same `UnifiedDe1` instance, a second `listen` on a non-broadcast `StreamController` throws `"Bad state: Stream has already been listened to"`. Reconnect crashes.

**Fix:** broadcast controllers + proper `dispose()`; or recreate controllers per connect; or assert single-use and construct a new instance per connection attempt (verify current lifecycle).

---

### [ ] 4. `ScaleController` flag set before `onConnect` verified — `[A · Phase 2]`

**File:** `connection_manager.dart` `connectScale` (~line 823) and `scale_controller.dart`.

`_scaleConnected = true` is set before verifying the connection succeeded. If `onConnect` throws, flag stays `true`, and subsequent `connect()` calls skip the scale phase entirely.

Also: `scale_controller.dart:29–31` subscribes to `scale.currentSnapshot` before `await scale.onConnect()`. Snapshots (BehaviorSubject replays) are processed while public `connectionState` says disconnected.

**Fix:** set flags after success only; derive connection state from the device stream, not a parallel flag (see P1 #6).

---

### [ ] 5. Shot-settings debounce races disconnect — `[C · Phase 5]`

**File:** `de1_controller.dart` `_processShotSettingsUpdate` / `_shotSettingsDebounce` (~lines 150–177).

100ms debounce timer fires after `_onDisconnect()` has nulled `_de1`. Every `connectedDe1()` call inside the async callback throws the raw string `"De1 not connected yet"`, unhandled from the timer. Worse: if teardown overlaps a new connection, stale settings from the previous session can be applied to the new machine.

**Fix:** cancel debounce timer before nulling `_de1`; guard with a generation token; or `await` any in-flight update before teardown.

---

## P1 — State-sync & concurrency

### [ ] 6. `_machineConnected` / `_scaleConnected` flags diverge from real state — `[A · Phase 2]`

**File:** `connection_manager.dart:85–90`, `133–163`.

Flags are separate from actual `connectionState` streams. Divergence windows:

- `onConnect()` throws after flag set → flag stuck true (see #4).
- Async gap between device disconnect and `_machineDisconnectSub` listener firing → flag true while machine already gone.
- Race inside `_connectImpl` when machine already connected.

Scan reports can claim "machine connected" going into scale phase when it isn't.

**Fix:** eliminate `_machineConnected` / `_scaleConnected` flags. Derive from `de1Controller.de1` / `scaleController.connectionState` streams at read time.

---

### [ ] 7. Early-connect race in `_connectImpl` stream listener — `[A · Phase 2]`

**File:** `connection_manager.dart` `_connectImpl` (~lines 437–475).

`final sub = deviceScanner.deviceStream.skip(1).listen(...)` subscribes *after* `scanForDevices()` kicks off. Race between subscription setup and first device emission → device missed or processed twice.

Separately: `earlyMachineConnect` / `earlyScaleConnect` guards are not atomic with the async `_connectMachineTracked` call. Second emission can slip through the gap; `connectMachine`'s `_isConnectingMachine` guard catches it but the tracker result is lost → inaccurate scan report.

**Fix:** buffer seen device IDs, replace nullable `Future<void>?` with explicit `enum ConnectingState { idle, scanning, connecting }`, ensure subscription is live before scan starts.

---

### [ ] 8. Error emission ordering is fragile — `[A · Phase 2]`

**File:** `connection_manager.dart` `_publishStatus` / `_emit`.

Two paths: `_publishStatus` has phase-clearing logic, `_emit` bypasses it. Order matters — must publish phase *then* emit error or the error gets stripped. Comments explain the invariant but it's a bug magnet.

**Fix:** unify into a single error emission path with phase-aware logic. Remove `_emit` or make it a thin wrapper.

---

### [ ] 9. `scaleOnly` reconnect silently dropped during machine-connect — `[A · Phase 2, pending product call]`

**File:** `connection_manager.dart` `connect()` `_isConnecting` guard (~lines 384–391).

`De1StateManager._triggerScaleScan()` fires `connect(scaleOnly: true)` after machine wake. If a full connect is running, `_isConnecting` drops it. Scale auto-reconnect after machine sleep can no-op depending on timing.

**Fix:** allow `scaleOnly` to queue or run concurrently; or return a future the caller can await.

---

### [ ] 10. Linux refresh-scan collides with ConnectionManager early-stop — `[B · Phase 3]`

**File:** `linux_ble_discovery_service.dart:372–383` + `connection_manager.dart:654`.

`_runRefreshScan` side-effect starts `FlutterBluePlus.startScan`. `ConnectionManager._checkEarlyStop` calls `DeviceController.stopScan` → Linux service `stopScan` → mid-flight refresh aborted, BlueZ cache in uncertain state. Retries silently fail.

**Fix:** coordinate scan ownership; refresh scan should not be externally stoppable, or early-stop should skip Linux refresh in progress.

---

### [ ] 11. `BluePlusDiscoveryService` early-stop leaks `_isScanning=true` up to 15s — `[B · Phase 3]`

**File:** `blue_plus_discovery_service.dart:199–202`.

`Future.delayed(Duration(seconds: 15), () => stopScan())` is uncancellable. External `stopScan()` doesn't clear the pending timer; `_isScanning` stays true blocking new scans.

**Fix:** use `Timer` (cancellable), or skip the redundant stop when already stopped.

---

## P2 — Resource safety / leaks

### [ ] 12. `_nativeConnectionSub` never cancelled on `disconnect()` — `[E · Phase 5]`

**File:** `blue_plus_transport.dart:19,28`, `android_blue_plus_transport.dart:44,63`, `linux_blue_plus_transport.dart:55,66`.

All three transports cancel+recreate `_nativeConnectionSub` at the start of `connect()` but never in `disconnect()`. Late `disconnected` events from FlutterBluePlus after our `disconnect()` keep firing the callback into an already-used `BehaviorSubject`. Reconnect accumulates subscriptions.

**Fix:** cancel in `disconnect()`; guard `BehaviorSubject.add` against post-close emissions.

---

### [ ] 13. `ScaleController.dispose()` is empty — `[E · Phase 5]`

**File:** `scale_controller.dart:26`.

`_connectionController` (BehaviorSubject) and `_weightSnapshotController` (broadcast) are never closed. Downstream listeners never see completion.

**Fix:** close both in `dispose()`; audit other controllers for the same pattern.

---

### [ ] 14. `deviceStream` getter re-wraps on every call — `[A · Phase 2]`

**File:** `device_controller.dart:54`.

`_deviceStream.asBroadcastStream()` is a getter (not cached). Each call creates a new broadcast wrapper with its own subscription to the `BehaviorSubject` — multiple underlying subscriptions with replay semantics accumulate.

**Fix:** expose `.stream` directly (BehaviorSubject is already broadcast-compatible via its stream), or cache the broadcast wrapper.

---

## P3 — Structure / simplification

### [ ] 15. `ConnectionManager` is a 965-line god-class — `[D · Phase 4]`

Break down approximate sections:

- Connection status/state management (~150 lines)
- `_connectImpl` (~600 lines) — scan, early connect, policy, report
- Connect machine/scale methods (~100 lines)
- Disconnect handling (~50 lines)
- Debug/test helpers (~50 lines)

**Fix:** split `_connectImpl` into:

- `_runFullScan()` — scan lifecycle
- `_setupEarlyConnect()` — subscription management
- `_applyMachinePolicy()` — connection decision
- `_applyScalePolicy()` — scale-only logic
- `_emitScanReport()` — already separate, just call

Collaborator classes for status/state, scan orchestration, policy application.

---

### [ ] 16. Too many connect verbs with subtly different signatures — `[D · Phase 4]`

`connect()`, `connectMachine()`, `connectScale()`, `_connectMachineTracked()`, `_connectScaleTracked()`, `_connectImpl()`, `_connectScalePhase()` — 7 methods doing similar things.

**Fix:** after #15, consolidate into a clear orchestrator + per-device internal helpers with single responsibility each.

---

### [ ] 17. Duplicate device tracking — three sources of truth — `[B · Phase 2]`

`matchedDeviceResults` Map, `deviceScanner.devices`, and the `deviceStream` subscription callback all represent "devices seen during scan". Ambiguous which is authoritative.

**Fix:** pick one. `deviceStream` throughout is the natural choice.

---

### [ ] 18. Nullable `Future<void>?` as state flag — `[A · Phase 2]`

`earlyMachineConnect`, `earlyScaleConnect` — using `Future<void>?` to track "in progress". Obscures intent.

**Fix:** explicit `enum ConnectingState { idle, scanning, connecting }` (see #7).

---

### [ ] 19. Nested stream subscriptions hard to trace — `[D · Phase 4]`

`_connectImpl` subscribes to `deviceStream`, callback may trigger `connectMachine()` which subscribes to machine streams internally. Leak-prone.

**Fix:** falls out of #15 / #18 — flatten subscription ownership to the outer orchestrator.

---

### [ ] 20. Disconnect detection keyed on `device.name`, not `deviceId` — `[E · Phase 6, migration audit first]`

**File:** `device_controller.dart:162–195`.

`_previousDeviceNames`, `_disconnectedAt` keyed by name. Two devices with the same advertised name (two DE1s on bench) get cross-attributed. Device that reconnects with a different name (firmware update) is never cleaned from `_disconnectedAt` — 24h cleanup mitigates but semantics are wrong.

**Fix:** key by `deviceId`.

---

### [ ] 21. Over-commented workaround in scan-start race — `[B · Phase 2, collapses with #22]`

```dart
// Start the scan and subscribe to scanningStream concurrently so we
// can race the "scanning started" signal against an error from
// scanForDevices() (which may reject asynchronously on permission /
// adapter failures). Without the race, awaiting scanForDevices first
// would miss the scanning=true emission, and awaiting the stream
// first would hang if the scan never started.
```

8-line comment describing a workaround, not business logic. Signal that the underlying API shape is wrong.

**Fix:** have `scanForDevices()` return a proper result (started-or-error) so callers don't need the race. Related to #22.

---

### [ ] 22. `DeviceController.scanForDevices` returns before scan completes; errors swallowed — `[B · Phase 2, keystone]`

**File:** `device_controller.dart:99–150`.

Method returns after the early `_scanningStream.add(true)`; the Future from the `Future.wait` body is only surfaced via `.timeout(...).then(onError: _log.warning)`. Scan-start errors (adapter off, permission denied) are silently logged. ConnectionManager sees a successful scan with zero devices.

**Fix:** await the actual scan completion; propagate errors to caller; document whether `scanningStream.firstWhere((s) => !s)` or the returned Future is the canonical "done" signal.

---

### [ ] 23. `BluePlusDiscoveryService` pre-scan cleanup blocks scan start — `[B · Phase 3]`

**File:** `blue_plus_discovery_service.dart:119–131` (also duplicated in `device_controller.dart:102–116`).

Both layers iterate cached devices and await `connectionState.first.timeout(2s)` before scan starts. Up to 2s × N devices of latency added to every scan. Logic duplicated at two layers.

**Fix:** do cleanup lazily in parallel; pick one layer to own it.

---

## P4 — Nits / hygiene

### [ ] 24. Replace magic numbers with named constants — `[E · Phase 6]`

- 15s scan: `Duration(seconds: 15)` (`blue_plus_discovery_service.dart:199`)
- 10s disconnect-expectation TTL (`connection_manager.dart:311`)
- 2s connection-state timeout (`device_controller.dart:106,122`)
- 30s scan timeout, 200ms settle delay (`device_controller.dart:140,144`)
- 500ms profile download guard (`unified_de1.dart:302`)
- 100ms shot-settings debounce (`de1_controller.dart`)

Proposed constants (co-locate in `ConnectionManager` or a new `connection_timings.dart`):

```dart
static const scanDuration = Duration(seconds: 15);
static const earlyConnectTimeout = Duration(seconds: 30);
static const disconnectExpectationTTL = Duration(seconds: 10);
```

---

### [ ] 25. Replace raw `String` throws with typed exceptions — `[E · Phase 1, unblocks #5]`

`connectedDe1()` and `connectedScale()` throw raw string literals (`"De1 not connected yet"`). Callers must `catch (Object)`. No typed handling.

**Fix:** `DeviceNotConnectedException` (or similar).

---

### [ ] 26. Add logging to all swallowed catches — `[E · Phase 1]`

Currently: `} catch (_) {}` with no log, no handling. At minimum:

```dart
} catch (e, st) {
  _log.warning('Early scale connect failed', e, st);
}
```

---

### [ ] 27. Populate `ScanReport` adapter-state fields — `[E · Phase 6]`

**File:** `connection_manager.dart:853–854`.

`adapterStateAtStart` and `adapterStateAtEnd` are hardcoded to `AdapterState.unknown`. Fields exist for diagnostics but are never set.

**Fix:** capture real adapter state at both boundaries.

---

### [ ] 28. `DeviceController.devices` getter rebuilds list via `fold` on every call — `[E · Phase 6]`

**File:** `device_controller.dart:56–60`. Called in telemetry + scan cleanup hot paths.

**Fix:** cache with dirty flag, or invalidate on stream add/remove.

---

### [ ] 29. Adapter-state multicast only from first `BleDiscoveryService` — `[E · Phase 6]`

**File:** `device_controller.dart:82–89`.

If two BLE adapters / services present, non-first contributions are lost. Default `AdapterState.unknown` indistinguishable from "no BLE service present".

**Fix:** merge adapter states; or document single-adapter assumption explicitly.

---

### [ ] 30. Document ConnectionPhase state machine — `[E · Phase 6]`

`ConnectionPhase` enum (`idle` / `scanning` / `connectingMachine` / `connectingScale` / `ready`) is clear but transitions are scattered across `_connectImpl`, `connectMachine`, `connectScale`, disconnect listeners.

**Fix:** add a state diagram to `doc/DeviceManagement.md` or inline docstring; make illegal transitions impossible in code.

---

### [ ] 31. Add connect-operation timeouts end-to-end — `[C · Phase 5]`

No top-level timeout on `connectMachine` / `connectScale`. Combined with #2 (`_mmrRead` hang), this means there are multiple hang points. Even after #2 is fixed, a belt-and-braces timeout on the full connect call is warranted.

---

## Cross-references

- `doc/DeviceManagement.md` — overlapping scan sources already documented (DeviceDiscoveryView on permission grant, StatusTile manual scale reconnect, De1StateManager machine wake, ConnectionManager `connect()`). #10 and #11 are the concrete interference cases.
- Profile equality (`Profile extends Equatable`) is correct; see #1 for the ordering defect around the guard.
