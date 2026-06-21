# Native hot-water stop-at-weight (scale tare)

## Goal

Bring the espresso stop-at-weight behaviour to hot water: when hot water is
dispensed and a scale is connected, tare the scale and stop the dispense once
the (flow-projected) scale weight reaches the configured target.

The target is the configured hot-water `volume` (ml treated as g) — i.e.
`HotWaterData.volume` is reused as the gram target.

## Native design

Hot water is **always started externally** here (GHC / physical button / REST /
skin) — `requestState(MachineState.hotWater)` is never called from native UI. So
the feature must detect *externally-started* hot water and stop it at weight,
reacting to the machine entering `hotWater` rather than initiating the pour.

### Pieces

1. **`lib/src/controllers/hot_water_stop.dart`** — pure decision logic.
   `HotWaterStopState` + `nextHotWaterStop(state, input)` → wait | clear | stop.
   The per-frame rule: once the machine is seen pouring hot water and the
   post-tare reading has settled, project `weight + flow * lookahead` and stop
   when it reaches the target. No I/O, fully unit-tested.

2. **`lib/src/controllers/hot_water_sequencer.dart`** — long-lived service (like
   `SteamSequencer`, created in `main.dart`). Wires `De1Controller` +
   `ScaleController` + `SettingsController`:
   - On the machine entering `hotWater`, if eligible (setting on, scale
     connected, `gatewayMode != full`, target volume > 0): **tare the scale**
     and arm.
   - On each scale weight frame, run `nextHotWaterStop`; on `stop`,
     `requestState(idle)`.
   - Disarm when the machine leaves `hotWater` or disconnects.

3. **`stopHotWaterAtWeight` setting** (default **true**) and
   **`hotWaterFlowMultiplier`** (default 0.3 s lookahead) — across
   `SettingsService` (+keys), `SettingsController`, `MockSettingsService`,
   `settings_handler` GET/POST, `rest_v1.yml`, and settings export/import.

### Authority / safety

We do **not** mutate the DE1's hot-water volume/duration (we can't anyway — the
pour is externally started and the FW latches its targets at entry). The scale
stop projects the weight a short time ahead so it fires just before the target;
the DE1's own volume/time stop stays as a **safe backstop** for the no-scale /
weight-never-climbs cases.

The tare is trusted only once the scale is *observed* to settle near zero — so a
stale pre-tare reading (e.g. a mug still on the platter) can't false-stop; if the
tare never lands, the monitor never arms and the DE1's native stop takes over.

### Projection multiplier

The stop projects `weight + weightFlow * hotWaterFlowMultiplier`, the same shape
as the espresso stop-at-weight in `ShotSequencer` (`weight + weightFlow *
weightFlowMultiplier`), but with its **own** multiplier: hot water dispenses with
a different pump/flow profile than espresso, so the stop-latency lookahead is a
separate, independently-tunable setting (default 0.3 s).

### Gateway mode

In `full` gateway mode a skin owns the machine, so the native sequencer stays
inert to avoid a double-stop. In `tracking`/`disabled` it arms. This mirrors
`ShotSequencer`'s `bypassSAW = gatewayMode == full`.

## Test tiers

- **Unit**: `hot_water_stop_test.dart` (decision table), `hot_water_sequencer_test.dart`
  (arm/tare/stop wiring, tare confirmation, consecutive dispenses), settings
  round-trip + export/import.
- **Integration**: `hot_water_sequencer_integration_test.dart` — real
  controllers + MockDe1/MockScale through to a stop.
- **End-to-end**: `.agents/skills/decent-app/scenarios/hot-water-stop-at-weight.md`
  — simulate machine+scale, PUT state/hotWater, observe return to idle.
