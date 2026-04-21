# Comms Hardening — Phase 4 Implementation Plan

Execution plan for Phase 4 of `doc/plans/comms-harden.md`: the **god-class split** of `ConnectionManager`. Resolves Cluster D (items 15, 16, 19) plus picks up the residual "partial" on item 7.

After Phase 4, `ConnectionManager` is a coordinator (~200 lines) delegating to focused collaborator classes. The 7-verb connect zoo collapses to a clear public API. Nested subscriptions become explicit dependencies.

## Pre-work findings

`ConnectionManager` is now 1043 lines (grew 78 lines via Phase 2+3 additions — `_queuedScaleOnly` and tracked-latest plumbing). Post-Phase-2/3 state, the responsibilities I can identify:

| # | Responsibility | Approx. LoC | Candidate collaborator |
|---|----------------|-------------|------------------------|
| 1 | Status + error gatekeeping (`_publishStatus`, `_emit`, sticky-error rules, `_clearError`) | ~100 | `StatusPublisher` |
| 2 | Disconnect-expectation tracking (`markExpectingDisconnect`, `_consumeExpectingDisconnect`, TTL timers) | ~30 | `DisconnectExpectations` |
| 3 | Disconnect listeners + handlers (`_listenForDisconnects`, `_handleScaleDisconnect`, `_handleMachineDisconnect`, `_latestDe1`/`_latestScaleState`) | ~80 | `DisconnectSupervisor` |
| 4 | Scan + policy orchestration (`_connectImpl`, `_connectScalePhase`, `_checkEarlyStop`) | ~300 | `ScanOrchestrator` + `PolicyResolver` |
| 5 | Connect primitives (`connectMachine`, `connectScale`, `_connectMachineTracked`, `_connectScaleTracked`) | ~140 | stays on `ConnectionManager` or moves to a `ConnectAction` helper |
| 6 | Early-connect stream subscription (embedded in `_connectImpl`) | ~80 | `EarlyConnectWatcher` |
| 7 | Scan-report building (`_emitScanReport`, `_formatScanReport`, `_seedTracker`, `_MatchedDeviceTracker`) | ~100 | `ScanReportBuilder` |
| 8 | Adapter-state listener (`_listenForAdapter`) | ~20 | stays on `ConnectionManager` (it's only a dispatcher) |
| 9 | Concurrent-connect queue (`_queuedScaleOnly`, drain loop) | ~30 | stays on the public coordinator |
| 10 | Disconnect flows (`disconnectMachine`, `disconnectScale`) | ~30 | stays |
| 11 | Debug helpers (`debugEmitError`, `debugSetPhase`, `debugNotifyXDisconnected`) | ~40 | stay |

Plus 2 nested `StreamSubscription` setups: the scan-time `deviceStream.skip(1).listen(...)` inside `_connectImpl` (the early-connect watcher), and two `listen()` calls in `_listenForDisconnects`. Both are candidates for the extract (#19).

The 7 connect verbs today:

```
connect({scaleOnly})              public API, queue-handling outer layer
_executeConnect(scaleOnly)        private, wraps one pass of _connectImpl
_connectImpl({scaleOnly})         300-line workhorse
connectMachine(m)                 public, connects one machine
connectScale(s)                   public, connects one scale
_connectMachineTracked(m, tr)     internal, wraps connectMachine + tracker
_connectScaleTracked(s, tr)       internal, wraps connectScale + tracker
_connectScalePhase(scales, tr)    internal, applies scale policy post-scan
```

`_connectMachineTracked` / `_connectScaleTracked` exist purely to record per-device results on the ScanReport tracker. `_connectScalePhase` is a scale-policy branch of `_connectImpl`. All three can be absorbed into the right collaborator.

## Goals

After Phase 4:

- `ConnectionManager` ≤ 250 lines. Pure coordinator — wires collaborators, exposes public API (`connect`, `connectMachine`, `connectScale`, `disconnectMachine`, `disconnectScale`, `status`, `scanReportStream`, `markExpectingDisconnect`, `dispose`).
- Collaborators as plain Dart classes in `lib/src/controllers/connection/` (new subfolder). Each class ≤ 200 lines, single responsibility.
- Connect verbs collapse to three public: `connect`, `connectMachine`, `connectScale`. Internal trackers disappear (result recording moves into the scan orchestrator).
- Nested stream subscriptions — both `deviceStream` (early-connect) and `de1`/`scale` (disconnect supervision) — live on dedicated classes with explicit `dispose`.
- No observable change to the public API. Existing tests continue to pass.

## Non-goals

- Making `ConnectionStatus.phase` fully derived via `Rx.combineLatest` (still deferred — the tracked-latest approach from Phase 2 is adequate).
- Changing `scaleOnly` concurrency semantics further (already landed in Phase 2).
- Touching `DeviceController` or the discovery services.
- Surfacing `ScanResult.failedServices` in `ScanReport` — a small follow-up for later.

---

## Landmines

1. **ConnectionManager test suite (~1170 lines).** Many tests reach into public API only but some use `debugEmitError` / `debugSetPhase` / `debugNotifyXDisconnected`. Those hooks must survive the refactor — route them through the new collaborators without exposing implementation details.
2. **WebSocket event frequency.** `devices_handler.dart:63` subscribes to `connectionManager.status.skip(1)` and emits a WS event per status update. Emission cadence must not change — the collaborators send through `StatusPublisher`, which in turn writes to the single `_statusSubject`.
3. **Disconnect ordering.** `_listenForDisconnects` is called from the constructor. The listeners are active from the moment the manager is constructed, BEFORE any connect. Moving to a `DisconnectSupervisor` means instantiating it in the constructor and wiring its dispose into `ConnectionManager.dispose`. Order matters — if a disconnect event fires during construction, the supervisor must be ready.
4. **`_queuedScaleOnly` drain loop.** The queue drain runs `_executeConnect(true)` inside a `finally`. If the drain itself extracted to a collaborator, the finally-ordering invariant (drain even on throw) must be preserved.
5. **Scan-scoped tracker map.** `matchedDeviceResults` lives for the duration of one `_connectImpl` call. `ScanOrchestrator` should own the tracker (including its teardown); `PolicyResolver` reads it read-only when it records attempts.
6. **Private-to-public API leakage.** `_MatchedDeviceTracker` is a private class. Moving it to a separate file means either making it package-private (still private in Dart) or defining it on the collaborator that owns scan state. Stays internal to the scan-orchestrator module.

---

## Delivery strategy

Three sub-PRs. Each self-contained, small enough for single-PR review, keeps `flutter test` green throughout. Each also has a tablet smoke pass.

```
integration/comms-harden-rest
├── feature/comms-phase-4-leaf-extractions   # PR 4a
├── feature/comms-phase-4-early-connect-watcher  # PR 4b
└── feature/comms-phase-4-scan-orchestrator  # PR 4c
```

### PR 4a — leaf extractions (low-risk, mechanical)

Extract the three simplest collaborators, no behavior change:

1. **`StatusPublisher`** (`lib/src/controllers/connection/status_publisher.dart`). Owns `_statusSubject`, `_publishStatus` gating, sticky-error rules, `_emit`, `_clearError`. `ConnectionManager` holds a `StatusPublisher` and delegates. The public `status` + `currentStatus` getters proxy.
2. **`DisconnectExpectations`** (`lib/src/controllers/connection/disconnect_expectations.dart`). Owns `_expectingDisconnectFor` set + `_expectingDisconnectTimers` map + TTL constant. Exposes `mark(deviceId)`, `consume(deviceId) -> bool`, `dispose()`. `ConnectionManager.markExpectingDisconnect` becomes a single-line proxy.
3. **`ScanReportBuilder`** (`lib/src/controllers/connection/scan_report_builder.dart`). Owns the `_MatchedDeviceTracker` class + `_emitScanReport` + `_formatScanReport` + `_seedTracker`. Takes the scan-start time on construction, accepts device appearances + attempt results, emits a `ScanReport` through `ConnectionManager._scanReportSubject`.

**Est. size:** ~400 LoC moved, 150 LoC of glue/proxies. Net: probably −100 LoC on `ConnectionManager`.

**Tests:** full suite continues to pass. Add focused tests for `StatusPublisher` and `DisconnectExpectations` (both are pure logic, easy to unit-test).

### PR 4b — early-connect watcher + disconnect supervisor

Two stream-subscription-owning classes extracted. Fixes item 19.

1. **`EarlyConnectWatcher`** (`lib/src/controllers/connection/early_connect_watcher.dart`). Takes `deviceStream` + preferred IDs + `(started, pending)` trackers internally. Owns the `deviceStream.skip(1).listen(...)` subscription. Exposes `start()` to begin watching and `awaitPending()` to block for in-flight early-connect Futures. Disposed automatically at scan end.
2. **`DisconnectSupervisor`** (`lib/src/controllers/connection/disconnect_supervisor.dart`). Takes `de1Controller.de1` + `scaleController.connectionState` + `DisconnectExpectations` (from PR 4a) + `StatusPublisher`. Owns the two `listen()` subs + `_latestDe1` + `_latestScaleState`. Emits `machineDisconnected` / `scaleDisconnected` errors on unexpected drops, publishes `phase: idle` on machine disconnect.

**Est. size:** ~300 LoC moved, 80 LoC of wiring. Net: probably −150 LoC on `ConnectionManager`.

**Tests:** move disconnect-related tests to target the supervisor directly where it makes sense; keep behavior tests on `ConnectionManager`.

### PR 4c — scan orchestrator + policy + verb collapse

The big one. Extracts `ScanOrchestrator` and `PolicyResolver`; consolidates the 7-verb zoo.

1. **`ScanOrchestrator`** (`lib/src/controllers/connection/scan_orchestrator.dart`). Owns `_connectImpl`'s body — scan, early-connect wiring (via `EarlyConnectWatcher` from PR 4b), ScanResult collection, scan-report emission (via `ScanReportBuilder` from PR 4a). Returns a result object with `(machines, scales, report)` or similar.
2. **`PolicyResolver`** (`lib/src/controllers/connection/policy_resolver.dart`). Pure-function layer: given `(machines, scales, preferredMachineId, preferredScaleId, scaleOnly)`, returns one of:
   - `PolicyAction.connectMachine(De1Interface)` — auto-connect this one.
   - `PolicyAction.machinePicker(List<De1Interface>)` — emit ambiguity.
   - `PolicyAction.connectScale(Scale)` — auto-connect this one.
   - `PolicyAction.scalePicker(List<Scale>)` — emit ambiguity.
   - `PolicyAction.idle(Reason)` — nothing to do.
3. **Verb collapse.** The eight internal methods collapse to:
   - Public: `connect({scaleOnly})`, `connectMachine(machine)`, `connectScale(scale)`, `disconnectMachine()`, `disconnectScale()`.
   - Internal: one `_executeConnect(scaleOnly)` that runs orchestrator → policy → connect primitives.

**Est. size:** ~500 LoC moved, 150 LoC of glue. Net: probably −300 LoC on `ConnectionManager`. Final `ConnectionManager` should land near ~250 LoC.

**Tests:** heaviest test-refactor pass. Many assertions shift from "internal method X was called" to "status stream emitted sequence Y". Where possible, test `PolicyResolver` (pure function) directly.

---

## Success criteria (Phase 4 overall)

- `ConnectionManager` ≤ 250 LoC post-4c.
- `flutter test`: full suite green (956 pass, 2 skip baseline).
- `flutter analyze`: clean on all new files.
- Real-hardware smoke on tablet after each sub-PR: connect / disconnect / reconnect cycle, profile ping-pong, scan report correct. Targets: connect ≤ 5 s, reconnect ≤ 5 s, no `Bad state` / `MmrTimeoutException` / doubled-emission errors.
- Public API unchanged: `devices_handler.dart` WebSocket emission shape identical; no downstream tests break.

---

## Open questions

1. **Collaborator subfolder location.** `lib/src/controllers/connection/` proposed. Alternatives: `lib/src/controllers/connection_manager/`, or flat in `lib/src/controllers/`. Preference?
2. **Expose collaborators publicly or keep package-private?** Private is cleaner (the public API stays thin). But if any consumer needs, e.g., a `StatusPublisher` to inject, we'd need to expose. I don't see consumers today; suggest private-default.
3. **PolicyResolver as pure function vs class?** A class with one `resolve()` method is overkill; a top-level function `ConnectPolicy resolvePolicy(...)` would be more ergonomic. Suggest function.
4. **Per-PR tablet smoke vs one smoke at the end of 4c?** I lean per-PR (caught two real-hardware issues in earlier phases). Modest overhead; catches regressions before they compound.
5. **Rollback path if 4c review surfaces issues.** 4a + 4b can land independently and provide value even if 4c is reworked. That's the point of the split.

Answer these and I kick off PR 4a.
