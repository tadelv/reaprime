# Bengle milk probe + Steam Sequencer + Steam recording

> **Design source of truth:** `[[Bengle/ReaPrime Integration#Step 7 — Milk probe + Steam Sequencer (design 2026-05-18)]]` in the Obsidian vault. This plan turns that design into an implementation sequence — read the integration note first for rationale and rejected alternatives.

## Context

Bundles three concerns under one effort:

1. **Bengle internal milk probe.** Optional hardware (jack on the machine, wired thermistor); FW reads the ADC and exposes temperature over the existing transport.
2. **Stop-at-temperature for steam.** New `SteamSettings.stopAtTemperature` field; FW-autonomous when machine is Bengle and the active stop-source is the internal probe, app-driven otherwise.
3. **Steam recording.** Closes the P3 `SteamingRecord` ask from `ReaPrime/TODO.md`. Mirrors `ShotRecord` shape and lifecycle.

The unifying entry point is a new `SteamSequencer` — analogue of `ShotSequencer`. It earns its weight by owning probe-source resolution, app-side stop (with bypass for FW-autonomous case), per-frame snapshot collection, and record finalization on state-exit.

## Approach

> **Scope reality:** FW is not ready. No real milk-probe discovery, no real FW autonomous stop. This effort lands the API surface + scaffolding so skin developers can adapt now, and so the future FW drop slots in as: (a) publish the `stopAtTemperatureTarget` MMR address, (b) ship a probe device implementation (Bengle internal or 3rd-party). Today, all FW-gated paths are stubs/no-ops; `SteamSnapshot.milkTemperature` will be `null` in practice until probe support exists.

Six surface changes (already locked in the integration note):

1. `SteamSettings` gains `stopAtTemperature: double` (`0.0 = off`).
2. `/api/v1/machine/capabilities` — **no change.** Universal feature; presence-of-probe gated via `/sensors`.
3. `/api/v1/sensors` — transparent extension (any registered probe appears here; today nothing registers).
4. New `/api/v1/steams` REST mirror of shots (list, ids, latest, get, put-annotations, delete).
5. `PersistenceController.steamsChanged` mirror of `shotsChanged`.
6. **No new live WS topic** — live steaming view = existing machine snapshot WS + `/ws/v1/sensors/<id>/snapshot`.

Architecture: bridge + adapter pattern (matches `BengleVirtualScale` / `BengleSawBridge`):

- `BengleMilkProbe implements Sensor` — adapter scaffold; wraps Bengle probe signals when they exist. Today the underlying signal streams are empty/never-emit on real `Bengle` (only `MockBengle` synthesises for tests).
- `BengleProbeBridge` — listens to `De1Controller.de1` + Bengle's `probeAttached` stream; registers/unregisters adapter via `SensorController`. Today the stream never emits on real `Bengle`; bridge stays inert until FW lands.
- `BengleSteamStopBridge` — single writer, reflects `stopAtTemperature` into Bengle MMR (debounced, generation-token, re-asserts on Bengle reconnect). Mirrors `BengleSawBridge`. Today writes to a stub MMR address (`0x00000000`) with log-once gate; flip-test pins the address.
- `SteamSequencer` — top-level controller, wired in `main.dart` with `De1Controller` + `SensorController` + `WorkflowController` + `PersistenceController`.

### Stop-source resolution

The sequencer decides per-steam whether to stop in-app or defer to FW via:

```
useFwAutonomousStop =
    machine is Bengle
 && steamSettings.stopAtTemperature > 0
 && bengleProbeAttached
 && fwSupportsStopAtTempMmr   // derived: BengleSteamMmr.stopAtTemperatureTarget.address != 0x00000000
```

When `false`, the sequencer takes the app-side path: if any sensor is registered in `SensorController` AND its latest sample ≥ target, call `requestState(idle)`. **Today every term except `steamSettings.stopAtTemperature > 0` is false on real hardware**, so the predicate is `false` and the app-side branch is taken — but with no registered probe, no stop fires either. This is the intended scaffolding state. The future-FW path (`useFwAutonomousStop = true`) and the future-3rd-party-probe path (app-side stop with a registered sensor) are exercised only in tests via `MockBengle` / `TestSensor`.

Explicit `stopSourceId` selection is out of scope (see Out of scope). "First registered sensor wins" is the rule until multi-probe complaint.

### Snapshot collection

- **Source:** DE1 `shotSample` stream (existing). Rate = whatever the machine emits; no resampling.
- **Window:** sequencer starts collecting on entry to `steam` state; stops on exit *and* not in any pouring sub-state (see Record lifecycle).
- **Milk temperature:** at snapshot construction, sequencer reads the latest value from the **first** sensor registered in `SensorController` (insertion order). If no sensor is registered, `milkTemperature` is `null`. No interpolation; latest-known-value is fine.
- **`SteamSnapshot` = machine fields (steamTemperature/Flow/Pressure, requestedState, substate) + `milkTemperature?`** — analogue to `ShotSnapshot` combining machine + weight.

### Record lifecycle

- **Open:** on entry to `MachineState.steam`.
- **Finalize:** when state is no longer `steam` **and** not in a pouring sub-state. Persists via `PersistenceController.recordSteam`, emits `steamsChanged`.
- **Discard:** machine disconnect mid-steam → discard, do not persist a half-record. Transitions to `sleep`/`error` finalize the same as `idle` (record what was captured).

## Files to change

### New

- `lib/src/models/data/steam_record.dart` — `SteamRecord { id, timestamp, measurements: List<SteamSnapshot>, workflow, annotations? }`.
- `lib/src/models/data/steam_snapshot.dart` — `SteamSnapshot { timestamp, steamTemperature, steamFlow, steamPressure, requestedState, substate, milkTemperature? }`.
- `lib/src/models/device/impl/bengle/bengle_milk_probe.dart` — `BengleMilkProbe implements Sensor` adapter.
- `lib/src/controllers/bengle_probe_bridge.dart` — `BengleProbeBridge` (register/unregister into SensorController).
- `lib/src/controllers/bengle_steam_stop_bridge.dart` — `BengleSteamStopBridge` (FW reflection).
- `lib/src/controllers/steam_sequencer.dart` — `SteamSequencer` (orchestrator).
- `lib/src/services/webserver/steams_handler.dart` — REST surface for steam records (mirror `shots_handler.dart`).
- `lib/src/services/database/tables/steam_tables.dart` — Drift tables.
- `lib/src/services/database/daos/steam_dao.dart` — DAO.
- `lib/src/services/database/mappers/steam_mapper.dart` — Drift ↔ domain mapping.
- Test files mirroring each new file under `test/`.

### Modified

- `lib/src/models/data/workflow.dart` — add `stopAtTemperature` to `SteamSettings` + `toJson`/`fromJson`/`copyWith`/`==`/`hashCode`/`defaults`.
- `lib/src/models/device/impl/bengle/bengle_mmr.dart` — add `BengleSteamMmr` enum (or extend `BengleScaleMmr` namespace convention) with `stopAtTemperatureTarget` entry. Stub address `0x00000000`; `scaledFloat` **unsigned**, scale factor 10 (decicelsius on wire); range 0..80 °C. **Set/get target only** — this MMR is not a probe-detection mechanism; probe discovery/data transport is unknown and may end up being a separate characteristic.
- `lib/src/models/device/impl/bengle/bengle.dart` — add `setStopAtTemperatureTarget(double)` / `getStopAtTemperatureTarget()` + probe-attached signal stream + probe-temperature signal stream. All three are cache-only-with-log-once until FW publishes addresses.
- `lib/src/models/device/bengle_interface.dart` — add the three abstract methods/streams above.
- `lib/src/models/device/impl/bengle/mock_bengle.dart` — implement all three: probe-attached default `true` (configurable for tests), synthesised probe temperature during steam state, honor `stopAtTemperature` (call `requestState(idle)` when synthesised temp reaches target).
- `lib/src/controllers/sensor_controller.dart` — add `register(Sensor)` / `unregister(String deviceId)`; merge bridge-registered with `DeviceController`-sourced (dedupe by `deviceId`).
- `lib/src/controllers/persistence_controller.dart` — add `recordSteam(SteamRecord)` + `steamsChanged: Stream<void>`.
- `lib/src/services/storage/storage_service.dart` (+ Drift impl) — add steam record CRUD.
- `lib/src/services/database/database.dart` — register new tables + DAO.
- `lib/src/services/webserver/webserver_service.dart` — register `SteamsHandler.addRoutes`.
- `lib/main.dart` — wire `BengleProbeBridge`, `BengleSteamStopBridge`, `SteamSequencer`.
- `assets/api/rest_v1.yml` — `stopAtTemperature` field on SteamSettings schema; full `/steams` paths (mirror shots). Same commit as code per CLAUDE.md.
- `doc/Api.md` — reflect new REST surface.

### Codebase comment cleanups (drive-by, same PR)

Forward-looking comments from before the bundle was scoped:

- `lib/src/models/device/bengle_interface.dart:9` — drop "milk probe" from capability-mixin enumeration; mention probe lives in `/sensors`.
- `lib/src/models/device/impl/bengle/bengle_mmr.dart:4` — adjust comment ("milk probe" no longer in this enum).
- `lib/src/models/device/impl/bengle/mock_bengle.dart:17` — same.
- `assets/api/rest_v1.yml:218, 3667` — remove "milk probe" from forward-looking cap-list comments.

## Implementation sequence (TDD-friendly)

Each chunk leaves the tree green (`flutter analyze` + `flutter test`).

1. **`SteamSettings.stopAtTemperature` field** — pure model change. Add field + JSON round-trip + `copyWith`/`==`/`hashCode` tests. Default `0.0` in `SteamSettings.defaults()`.
2. **`SteamRecord` + `SteamSnapshot` domain models** — mirror `ShotRecord`/`ShotSnapshot` shape. JSON round-trip tests with and without `milkTemperature`.
3. **Drift schema + DAO + mapper** — `steam_tables.dart` adds two tables: `SteamRecords` (id, timestamp, workflow JSON, annotations JSON) and `SteamSnapshots` (FK steamRecordId, timestamp, steamTemperature, steamFlow, steamPressure, requestedState, substate, milkTemperature NULLABLE). `steam_dao.dart`, `steam_mapper.dart`. Bump `AppDatabase.schemaVersion` by 1 and add a forward-only migration step that creates the two tables (no backfill). DAO tests cover insert + load round-trip with and without `milkTemperature`.
4. **`PersistenceController.recordSteam` + `steamsChanged`** — extend controller, unit-test stream emission on `recordSteam` call.
5. **`BengleSteamMmr.stopAtTemperatureTarget` enum entry + `Bengle.setStopAtTemperatureTarget` cache-and-log stub** — stub address `0x00000000`, unsigned scaledFloat (scale 10), range 0..80 °C, `_logStopAtTempStubOnce` per-session log gate (mirror SAW's `_logSawStubOnce`). Pin test asserts `BengleSteamMmr.stopAtTemperatureTarget.address == 0x00000000` — flips intentionally when FW publishes and forces review.
6. **`BengleInterface` abstract surface** — `setStopAtTemperatureTarget` / `getStopAtTemperatureTarget` / `stopAtTemperatureTarget` stream + `probeAttached` stream + `probeTemperature` stream. Stream semantics mirror SAW: `BehaviorSubject` for `stopAtTemperatureTarget` (replays last cached value, seeded with default), `BehaviorSubject<bool>` for `probeAttached` (seeded `false`), `PublishSubject<double>` for `probeTemperature` (no replay; latest-only consumers should track themselves). On real `Bengle`, `probeAttached` stays `false` and `probeTemperature` never emits — FW signal source TBD. `MockBengle` implements the synth path for tests.
7. **`BengleMilkProbe` adapter** — `Sensor` impl wrapping Bengle's probe signals. Unit tests on `data` stream + `connectionState` semantics (probe-attach lifecycle, not machine-connect).
8. **`SensorController.register` / `unregister`** — API addition + dedupe-by-deviceId merge. **Bridge-registered wins** when the same `deviceId` is also produced by `DeviceController` (bridge has fuller signal — knows probe-attach state, not just BLE presence). Document on the method. Unit tests covering: bridge-registered alone, DeviceController-sourced alone, both with same id (assert bridge instance is exposed), register/unregister churn.
9. **`BengleProbeBridge`** — listen to `De1Controller.de1` + Bengle's `probeAttached` stream; register/unregister adapter. Tests with mocked controllers covering: probe attach mid-session, probe detach mid-session, machine disconnect with probe attached.
10. **`BengleSteamStopBridge`** — mirror `BengleSawBridge` test structure. Debounce, re-assert on reconnect, generation-token cancellation on disconnect.
11. **`SteamSequencer`** — orchestrator. Unit tests cover: stop-source predicate truth table (the four terms in `useFwAutonomousStop`), app-side stop fires when first registered sensor crosses target (use `TestSensor`), no-probe case (no stop fires, sequencer is inert on the stop path), snapshot collection accumulates `shotSample` frames during `steam`, `milkTemperature` populated from first registered sensor or `null` when empty, record finalize on state-exit (steam→idle, steam→sleep, steam→error), record discard on machine disconnect mid-steam.
12. **`SteamSequencer` integration** — end-to-end with real `MockBengle` + real `SensorController` + real `PersistenceController` (in-memory `AppDatabase`) + fake `WorkflowController`. Drive a full simulated steam: state→steam, frames flow in, state→idle, assert `SteamRecord` persisted with expected snapshot count and (since no probe registered) all `milkTemperature: null`.
13. **REST `SteamsHandler`** — mirror `ShotsHandler` routes. Integration tests via in-memory db.
14. **Spec + doc** — `assets/api/rest_v1.yml` paths + `stopAtTemperature` schema; `doc/Api.md` entries. Smoke-test via `sb-dev` + curl per `.agents/skills/decent-app/verification.md`.
15. **`main.dart` wiring** — instantiate bridges + sequencer; verify cold-boot smoke (`sb-dev start --simulate`). No unit tests at this layer; smoke-only.
16. **Comment cleanups** — the four spots flagged above.

## Test plan

- **Unit:** each new file gets its own test (numbered with sequence above).
- **Integration:** `SteamSequencer` with real `MockBengle`, real `SensorController` with `BengleProbeBridge`, fake `WorkflowController` — drive through a full simulated steaming session, assert `SteamRecord` shape on finalization.
- **REST:** `steams_handler_test.dart` mirroring `shots_handler_test.dart` (in-memory `AppDatabase`, CRUD assertions).
- **End-to-end smoke (`sb-dev`):** new scenario file `.agents/skills/decent-app/scenarios/bengle-milk-probe-steam-stop.md`:
  - Simulate Bengle with probe attached (default).
  - PUT workflow with `stopAtTemperature: 65.0`.
  - `requestState(steam)`. Verify probe appears in `/sensors`.
  - Subscribe `/ws/v1/sensors/<probeId>/snapshot`, watch temp rise.
  - Verify machine returns to `idle` (MockBengle's autonomous stop fires).
  - `GET /api/v1/steams/latest` — verify SteamRecord with `milkTemperature` on frames near the end.
- **Pin tests:** `BengleSteamMmr.stopAtTemperatureTarget.address == 0x00000000` until FW publishes — flip-test forces review when address fills in.

## Out of scope (deferred)

- FW MMR addresses (probe presence, probe temperature notify, stopAtTemperature target) — all `0x00000000` + log-once + cache-only.
- Explicit stop-source selection (`SteamSettings.stopSourceId`) — default rule sufficient until multi-probe complaint.
- Multi-probe per-frame recording (`additionalProbeReadings` field) — additive future extension.
- `StopAtTemperatureCapability` mixin refactor — defer until a non-Bengle machine ships with an integrated milk probe.
- Sensor API simplification — rejected for this effort.
- UI work (realtime steaming view, history-of-steams tile) — record surface only; UI is a separate effort.

## Branch + completion

- Branch: `feature/bengle-milk-temp` (current).
- Completion: PR to `main` after each chunk lands green and end-to-end smoke passes. Commit chain mirrors SAW (small focused commits per chunk where natural; bundle when the diff is small).
- Pre-merge: archive this plan doc to `doc/plans/archive/bengle-milk-probe-and-steam-sequencer/` per CLAUDE.md.
