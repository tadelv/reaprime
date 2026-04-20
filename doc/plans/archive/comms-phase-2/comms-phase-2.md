# Comms Hardening — Phase 2 Implementation Plan

Execution plan for Phase 2 of `doc/plans/comms-harden.md`: **state derivation**, the Cluster A keystone.

After Phase 2, roadmap items 4, 6, 7, 8, 14, 17, 18, 21, and 22 resolve or trivialise in a single coherent pass. Item 9 (`scaleOnly` concurrency) has product semantics — kept at current behavior and flagged as a separate follow-up.

## Why this one is the keystone

Five parallel sources of truth for "am I / is the device connected" drift across async gaps, every patch on one flag risks inconsistency with another, and the error-emission path has two entry points that *must* be called in the right order or errors get stripped. Collapsing to stream-derived state is the single highest-leverage change in the whole roadmap — once state is derived, the god-class split (Phase 4) becomes mechanical and the resource-safety items (Phase 5) become easy to reason about.

---

## Pre-work findings

Checked the current code before writing this plan.

### Parallel state sources (`connection_manager.dart:85–89`)

```dart
bool _isConnecting = false;          // guard for top-level connect()
bool _isConnectingMachine = false;   // guard inside connectMachine
bool _isConnectingScale = false;     // guard inside connectScale
bool _machineConnected = false;      // parallel to de1Controller.de1 stream
bool _scaleConnected = false;        // parallel to scaleController.connectionState
```

Plus two nullable futures used as flags (`_connectImpl` around line 422):

```dart
Future<void>? earlyMachineConnect;
Future<void>? earlyScaleConnect;
```

Plus a "current phase" inside `ConnectionStatus` that is published explicitly on every transition rather than derived.

### Error-emission duality (`connection_manager.dart:166–273`)

`_emit(ConnectionError)` appends an error to current status; `_publishStatus(next)` has phase-gated clearing logic (clearing phases, sticky errors, identity check). Two entry points + the comments say they must be called in a specific order to preserve errors across phase transitions. This is exactly the fragility roadmap item 8 calls out.

### Scan API shape (`device_controller.dart:99–150`)

`scanForDevices()` returns `Future<void>`. It synchronously adds `true` to `_scanningStream`, kicks off a `Future.wait` over services inside a `Completer`, and returns before the scan completes. Service-level errors are swallowed via `catch (e, st) { _log.warning(...) }` inside the `map`, and the `completer.future.timeout(30s).then(..., onError: _log.warning)` drains them silently. Callers rely on `scanningStream.firstWhere((s) => !s)` for the done signal — the 15-line race comment in `connection_manager.dart` around line 480 admits this is awkward.

### Who consumes `status` and `currentStatus`

- `lib/src/device_discovery_feature/device_discovery_view.dart` — UI
- `lib/src/shared/connection_error_banner.dart` — UI
- `lib/src/onboarding_feature/steps/scan_step.dart` — UI
- `lib/src/services/webserver/devices_handler.dart` — WebSocket event source (`status.skip(1).listen(...)` at line 63, and `currentStatus` snapshot at line 146)

The webserver handler matters: any change in status-emission semantics (order, frequency) shows up on the WebSocket stream. Behavior tests at `test/controllers/connection_manager_test.dart` observe the public stream, not the flags — good for us.

### Existing test surface

`test/controllers/connection_manager_test.dart` is ~1170 lines and exercises status transitions, ScanReport, early-stop, adapter-state recovery, and the sticky/transient error machinery through the public API. None of it reads the private flags directly. That keeps the refactor observable through tests.

---

## Goals

After Phase 2:

- `ConnectionStatus.phase` is **derived**, not published. `combineLatest(de1Stream, scaleStream, scanState, operationState)` produces the current phase; status updates happen automatically when any input changes.
- Five boolean flags replaced with a single `ConnectingOperation` enum (`idle` / `scanning` / `connectingMachine` / `connectingScale` / similar). No more `_machineConnected`, `_scaleConnected`, or `earlyMachineConnect`/`earlyScaleConnect` nullable futures.
- One error-emission path. `_emit` collapses into `_publishStatus` (or equivalent); the sticky/transient logic keeps working but isn't duplicated.
- `DeviceScanner.scanForDevices()` returns a `Future<ScanResult>` that completes when the scan completes and propagates service-level errors. Callers no longer need the `scanningStream.firstWhere` race dance.
- `deviceStream` is the single source of truth for scan results. `matchedDeviceResults` and `deviceScanner.devices` fold into it.

## Non-goals

Deliberately out of scope for Phase 2, scheduled later:

- Splitting `ConnectionManager` into collaborator classes (roadmap item 15 — Phase 4).
- Consolidating the seven connect verbs (item 16 — Phase 4).
- Transport-layer resource cleanup (items 12, 13, 31 — Phase 5).
- Changing `scaleOnly` concurrency semantics (item 9 — product decision; preserve current "drop during full connect" behavior in Phase 2).

---

## Landmines

Verify before touching:

1. **WebSocket event frequency.** Derived status can emit more often than today's explicit `_publishStatus` calls (e.g. every stream tick). Audit `status.skip(1).listen(...)` in `devices_handler.dart` — if it fires an outbound WS event per status update, a chatty derived stream is a regression for clients. Mitigation: `distinct()` downstream, or emit from a `scan`/`shareReplay` operator to deduplicate.
2. **Order of emission.** Tests at `connection_manager_test.dart` around `group('error surfacing', ...)` assert phase + error emission ordering. A `combineLatest` derivation emits whenever any upstream ticks — the test's expected sequence may need rewriting to *what state is observed* rather than *what order emissions arrive in*.
3. **ScanReport coupling.** `_emitScanReport(...)` reads `matchedDeviceResults` to build the report. If we fold `matchedDeviceResults` into `deviceStream`, we need to reconstruct per-device attempt results (succeeded / failed / not-attempted) some other way. Plan: keep a lightweight per-scan tracker that lives only for the duration of a scan, populated from the scan-result future.
4. **Early-stop bookkeeping.** `_checkEarlyStop(earlyStopEnabled)` reads `_machineConnected && _scaleConnected`. Must be rewritten against derived state without re-introducing flag-equivalents.
5. **`markExpectingDisconnect` TTL.** `_expectingDisconnectFor` + `_expectingDisconnectTimers` is separate state not covered by Phase 2. Leave as-is; but verify it still interacts correctly with derived stream-state (suppression happens in the disconnect listener, which still fires from streams today).
6. **Behavior of simultaneous scans.** Two subscribers to a `scanForDevices()` that returns `Future<ScanResult>` — does the second call share the first's scan or start a new one? Today's code serialises via `_isConnecting`. Post-refactor, document serialisation explicitly (same Future shared, or reject concurrent) and test it.

---

## Delivery strategy

Two PRs into `integration/comms-phase-2`, merged into main as a single PR afterward. Phase 0 safety-net-style tests land in each PR alongside the change they cover rather than as a separate PR.

```
main
└── integration/comms-phase-2
    ├── feature/comms-phase-2-scan-api          # PR A
    └── feature/comms-phase-2-state-derivation  # PR B
```

PR B depends on PR A conceptually but not mechanically — PR A is shippable standalone.

---

## PR A — Scan API cleanup (roadmap items 22, 21; partial 17)

**Branch:** `feature/comms-phase-2-scan-api`. **Est. size:** ~250 lines code + ~100 lines test.

### Changes

1. `lib/src/models/device/device_scanner.dart` — abstract.

   ```dart
   abstract class DeviceScanner {
     Stream<List<Device>> get deviceStream;
     Stream<bool> get scanningStream;
     List<Device> get devices;
     Future<ScanResult> scanForDevices();  // was Future<void>
     void stopScan();
     Stream<AdapterState> get adapterStateStream;
   }

   class ScanResult {
     final List<Device> matchedDevices;  // snapshot at scan completion
     final ScanTerminationReason terminationReason;
     final Duration duration;
     const ScanResult({...});
   }
   ```

   `ScanTerminationReason` already exists on `ScanReport` — reuse it.

2. `lib/src/controllers/device_controller.dart` — rewrite `scanForDevices()` to await service scans and surface their errors:

   ```dart
   @override
   Future<ScanResult> scanForDevices() async {
     _scanningStream.add(true);
     final start = DateTime.now();
     try {
       await Future.wait(_services.map((s) => s.scanForDevices()));
       // ...cleanup + baseline sync...
       return ScanResult(
         matchedDevices: List.unmodifiable(devices),
         terminationReason: ScanTerminationReason.completed,
         duration: DateTime.now().difference(start),
       );
     } finally {
       _scanningStream.add(false);
     }
   }
   ```

   No more `Completer`, no more `timeout(30s).then(onError: ...)` silent drain.

   **Partial-failure semantics.** `ScanResult` carries a `failedServices` list so a user with BLE off but serial working still sees their USB DE1. One service throwing no longer torpedoes the whole scan.

   ```dart
   class ScanResult {
     final List<Device> matchedDevices;
     final List<ServiceScanFailure> failedServices; // per-service errors
     final ScanTerminationReason terminationReason;
     final Duration duration;
     const ScanResult({...});
   }

   class ServiceScanFailure {
     final String serviceName;
     final Object error;
     final StackTrace stackTrace;
   }
   ```

   `DeviceController.scanForDevices` iterates services, catches each service's throw into `failedServices`, and always completes with a `ScanResult`. Logs individual failures at `warning` for observability.

   Only catastrophic failures — the scan couldn't even start (adapter hard-failure with no other service configured) — surface as a top-level throw. That path stays as today so `MockDeviceScanner.failNextScanWith` keeps working: in a scanner with only one service (the mock), "all services failed" is indistinguishable from a catastrophic throw, and ConnectionManager's existing classify-and-emit logic takes over.

3. `lib/src/controllers/connection_manager.dart` — update `_connectImpl` to await the new `Future<ScanResult>` directly; delete the `scanningStream.firstWhere((s) => !s)` race and the 15-line comment around line 480.

4. `test/helpers/mock_device_scanner.dart` — `scanForDevices()` returns a `ScanResult`. Keep `failNextScanWith` for error-path tests.

### Tests

- Existing 1170-line `connection_manager_test.dart` suite must stay green.
- New: a `device_controller_test.dart` group that injects a failing `DeviceDiscoveryService` and asserts the error propagates out of `scanForDevices()` instead of being `_log.warning`-ed away. This is the piece we deferred from Phase 0 Gap D.

### Success criteria

- `flutter test`: full suite green (951 + new service-error test).
- `flutter analyze`: clean on touched files.
- `scanningStream.firstWhere` race comment deleted.
- Real-hardware smoke on tablet: scan → connect still behaves the same (no timing regressions in the ~15.7 s scan duration we measured during Phase 1).

---

## PR B — State derivation keystone (roadmap items 4, 6, 7, 8, 14, 17, 18)

**Branch:** `feature/comms-phase-2-state-derivation`. **Est. size:** ~400–500 lines code + ~200 lines test (net: likely a reduction, since `_publishStatus` gating code + flag plumbing goes away).

### Changes

1. **New `ConnectingOperation` enum.**

   ```dart
   enum ConnectingOperation {
     idle,
     scanning,
     connectingMachineEarly,   // early-connect during scan
     connectingMachine,        // post-scan policy phase
     connectingScaleEarly,
     connectingScale,
     // (concrete phases — may collapse `Early` + non-early if they're
     //  observably equivalent to downstream consumers; audit first.)
   }
   ```

   Replaces `_isConnecting`, `_isConnectingMachine`, `_isConnectingScale`, and the `Future<void>?` early-connect flags. One mutator path — a `_setOperation(ConnectingOperation)` private method plus a `try/finally` in each connect path.

2. **Derive `ConnectionStatus.phase` via `Rx.combineLatest4`.**

   ```dart
   late final Stream<ConnectionStatus> _derivedStatus = Rx.combineLatest4(
     de1Controller.de1,                        // De1Interface?
     scaleController.connectionState,          // ConnectionState
     deviceScanner.scanningStream,             // bool
     _operationSubject.stream,                 // ConnectingOperation
     _computePhase,
   ).distinct(); // coalesce duplicate emissions

   ConnectionStatus _computePhase(
     De1Interface? de1, ConnectionState scale, bool scanning, ConnectingOperation op) {
     final phase = ...; // pure function
     return _currentStatusSnapshot.copyWith(phase: () => phase);
   }
   ```

   `_statusSubject` switches from `BehaviorSubject.seeded(...)` to a `shareReplay(maxSize: 1)` over the derived stream. `currentStatus` becomes `_statusSubject.value` as today, just sourced differently.

3. **Delete `_machineConnected` / `_scaleConnected`.** Any read site rewrites to either:
   - A local `final snapshot = await <stream>.first` inside async code, or
   - A cached `_latestDe1`/`_latestScaleState` field populated by the subscription we already have in `_listenForDisconnects`.

4. **Unify error path.** Delete `_emit`; add errors via the same publish path used for phase. The sticky/transient gating lives in `_computePhase`'s wrapper (or in a dedicated `_mergeError(prev, next)` helper). `_classifyScanError`, `_buildConnectError`, `markExpectingDisconnect` machinery stays as-is — only the emission site changes.

5. **Collapse `matchedDeviceResults` onto `deviceStream`.** Inside `_connectImpl`, use `deviceScanner.deviceStream.value` (or a parameter from PR A's `ScanResult`) as the canonical snapshot. The per-device attempt tracker stays, but becomes a scan-scoped `Map<String, _ConnectionAttempt>` owned by the `_connectImpl` closure, not a long-lived field.

6. **Early-connect state machine.** The current implementation sets `earlyMachineConnect = _connectMachineTracked(...)` and later `await earlyMachineConnect`. Rewrite as:

   ```dart
   enum EarlyConnectStage { notAttempted, inFlight, completed }
   // tracked per device-type (machine, scale) inside _connectImpl
   ```

   Plus an awaitable handle (the underlying Future). The outer `await` waits on all in-flight early connects before proceeding. No nullable-Future-as-flag.

### Tests

Expected heavy rewrites in `connection_manager_test.dart`:

- Tests that assert specific `_publishStatus` call sequences may need to assert *observed status sequences on the stream* instead. These are equivalent under the new design but the test-facing API changes.
- Tests that reach into private state via debug hooks (`debugEmitError`) stay if still useful — `debugEmitError` remains; it just funnels into the same single-path emission.
- New: a test that toggles `de1Controller.de1` stream directly and asserts `ConnectionStatus.phase` updates without any `_publishStatus` call — proves the derivation is real.
- New: Gap F-style test for `ScaleController` failure recovery without the `_scaleConnected` flag (already exists as Gap A; update to confirm same behavior post-refactor).

### Success criteria

- `flutter test`: full suite green, including at least one new "derived phase" test that would fail on pre-refactor code.
- `flutter analyze`: clean on all touched files.
- `_machineConnected`, `_scaleConnected`, `_isConnecting{,Machine,Scale}`, `earlyMachineConnect`, `earlyScaleConnect` all removed. A `git grep` in the PR description confirms zero occurrences remain.
- `_emit` method removed.
- Real-hardware smoke on tablet: happy connect + two reconnect cycles + profile ping-pong + disconnect — all with no behavior change versus the Phase 1 baseline recorded on 2026-04-20.

---

## Migration risks + mitigations

| Risk | Mitigation |
|------|------------|
| Status stream emits more frequently after derivation → WebSocket flood | `.distinct()` on the derived stream; audit `devices_handler.dart` emission shape in the PR |
| Test rewrites break the 1170-line suite | Land the refactor in tight chunks; keep `flutter test` green at every commit (micro-commits encouraged inside the feature branch) |
| Ambiguity handling (AmbiguityReason) accidentally changes emission point | Treat ambiguity as part of the ConnectionStatus snapshot, published through the same derived stream |
| Scan-policy regressions (preferred > auto > picker > idle) | Policy logic stays in `_connectImpl`; only its *state inputs* change. Preserve the full path with integration tests |
| Webserver WebSocket clients see a different event shape | `ConnectionStatus` schema stays identical; only internal wiring changes. Spec doc at `assets/api/websocket_v1.yml` does not need updating |

---

## Decisions (previously open questions)

Locked in before kick-off:

1. **Scan concurrency contract — share.** Two concurrent `scanForDevices()` calls share the first caller's Future; the second awaits the same `ScanResult`. Deduplication happens in `DeviceController`. Document + test this.
2. **Partial scan-error semantics.** `ScanResult.failedServices` carries per-service failures so a user with BLE off but serial working still sees their USB DE1. Top-level throw reserved for catastrophic cases — see the Scan API section above.
3. **`foundMachines` / `foundScales` stay as snapshots.** Stream-derived is cleaner but introduces WebSocket emission-frequency risk; revisit in Phase 4 as part of the god-class split.
4. **`ConnectingOperation` is internal.** Downstream consumers see only `ConnectionPhase`. Collapse `Early` vs non-`Early` variants if they're observably equivalent; keep the distinction inside the enum only if early-stop bookkeeping needs it.
5. **PR B stays as one coherent change.** The state-derivation + error-path + flag removal are tightly coupled; splitting them creates intermediate states where the code is half-refactored.

Ready to kick off PR A.
