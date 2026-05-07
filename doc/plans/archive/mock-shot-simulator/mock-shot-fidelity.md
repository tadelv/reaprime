# Mock Shot Fidelity — Simulated Shot Engine

Make simulated machines (MockDe1, MockBengle) convincingly follow loaded profiles so skin creators can develop and test without hardware. No coffee extraction physics — visual believability derived from profile step targets and real-machine behavioral patterns.

**Status:** design complete, awaiting implementation.

## What changes

The mock shot simulation engine (`_simulateEspresso` / `_simulateWithProfile` in `mock_de1.dart`, integrated scale in `mock_bengle.dart`) gets rewritten to:

1. **Handle `skipStep`** — `requestState(MachineState.skipStep)` advances to the next profile step instead of killing the shot.
2. **Emit correct substates** — `preparingForShot` (first ~2s) → `preinfusion` (frames < `targetVolumeCountStart`) → `pouring` (frames ≥ `targetVolumeCountStart`) → `pouringDone` (end) → `idle`.
3. **Model flow→pressure coupling** — flow responds near-instantly to targets; pressure lags via damped puck-resistance model.
4. **Produce believable weight** — flat during preinfusion, climbs at ~80% of integrated flow during extraction (MockBengle integrated scale).
5. **Respect `transition` (fast/smooth)** — `fast` jumps target immediately, `smooth` interpolates over step duration.
6. **Step through profile** — walk steps sequentially by elapsed time, honor weight exit conditions, emit `skipStep` when weight target reached.

## Design decisions

### 1. Profile-following engine

The simulator owns a `_currentStepIndex` and `_stepElapsedMs` (already present). Every 100ms tick:

- If `_stepElapsedMs` ≥ `step.seconds * 1000` → advance to next step (`stepIndex++`, reset elapsed). If no more steps → end shot.
- `skipStep` is received from `ShotController` via `requestState(MachineState.skipStep)` — the mock does **not** self-trigger on weight conditions. Weight-based step exit is `ShotController`'s responsibility (it reads scale weight, projects, and calls `skipStep`). The mock simply advances the step index when `skipStep` is requested.
- Derive `targetFlow` and `targetPressure` from the step:
  - `ProfileStepFlow` → `targetFlow = step.flow`, `targetPressure = unconstrained`
  - `ProfileStepPressure` → `targetPressure = step.pressure`, `targetFlow = unconstrained`
- Apply `transition` shaping:
  - `fast` → target = step value immediately.
  - `smooth` → interpolate from previous target to step value over step duration.
- `targetMixTemperature` / `targetGroupTemperature` = step's `temperature`. Simple convergence as today.

### 2. Substate derivation

| Condition | Substate |
|-----------|----------|
| First 2s of espresso state | `preparingForShot` |
| `_currentStepIndex < profile.targetVolumeCountStart` | `preinfusion` |
| `_currentStepIndex ≥ profile.targetVolumeCountStart` and shot is active | `pouring` |
| Shot ended, pressure decay | `pouringDone` (3 ticks) → `idle` |

The `MachineState` remains `espresso` throughout; only substate changes.

`profileFrame` in emitted `MachineSnapshot` = `_currentStepIndex` (not the FW internal counter — the mock owns this).

### 3. Flow→Pressure coupling model

```
// Per tick (100ms):
targetFlow       = from profile step + transition shaping
targetPressure   = from profile step + transition shaping (or ∞ if flow step)

// Resistance grows over extraction (puck compression)
resistance       = baseResistance × (1 + resistanceGrowth × stepProgress)
                  where stepProgress = _stepElapsedMs / (step.seconds * 1000)
                  clamped to [baseResistance, baseResistance × (1 + resistanceGrowth)]

// Flow responds fast (pump-driven)
reportedFlow     += (targetFlow - reportedFlow) × flowResponseRate

// Pressure lags behind flow (puck-mediated)
unboundedPressure = reportedFlow × resistance
reportedPressure  += (unboundedPressure - reportedPressure) × pressureDamping

// If step constrains pressure, clamp flow to respect it
if step is ProfileStepPressure and reportedPressure ≥ targetPressure:
    reportedFlow = targetPressure / resistance  // flow rate that maintains target pressure
    reportedPressure = targetPressure
```

Constants (from shot history, tuned for visual believability):

```
baseResistance    = 2.5   // bar/(mL/s) — pressure per unit flow during extraction
resistanceGrowth  = 0.3   // 30% increase over step (puck compression)
flowResponseRate  = 0.7   // per-tick convergence toward flow target
pressureDamping   = 0.3   // per-tick convergence toward pressure equilibrium
```

### 4. Weight accumulation (MockBengle integrated scale)

```
if _currentStepIndex < profile.targetVolumeCountStart:
    weight = 0  // preinfusion — water absorbed, no output
else:
    weight += reportedFlow × dt × extractionEfficiency
    extractionEfficiency = 0.80  // ~80% of input water emerges as espresso
```

Tare resets `_tareOffset`. Weight = `_accumulatedWeight - _tareOffset`. A `BehaviorSubject` streams weight to WS clients (already implemented).

### 5. skipStep handling

`skipStep` is **inbound only** — `ShotController` decides when to skip based on scale weight projection. The mock never self-triggers on weight conditions.

When `requestState(MachineState.skipStep)` is called during `espresso` state:

- `_currentStepIndex++`
- `_stepElapsedMs = 0`
- Stay in espresso state
- Simulation continues from current flow/pressure values into new step's targets
- `transition=fast` behavior for the first tick (jump to new target, then resume normal dynamics)

This matches real DE1 behavior: `ShotController` calls `skipStep` when `projectedWeight ≥ step.weight`, and the machine advances to the next step on the next frame.

### 6. What doesn't change

- **Temperature model** — keep simple convergence. Skins don't react to ±0.5 °C wobbles. Sensor-aware rates are future polish.
- **Steam/hot-water simulation** — unchanged. This work is espresso-shot only.
- **Idle snapshot emission** — unchanged.
- **MockScale, MockSensorBasket** — unchanged.

## Shot history mining (2026-05-07)

Mined 30 random shots from m50mini.home:8080. 15 usable for efficiency calculation.

| Metric | Value | Notes |
|--------|-------|-------|
| Extraction efficiency | median 0.50, mean 0.57 | Coarse grind skews low; default set to 0.80 for normal use |
| Resistance (p/f) | median 2.03 bar/(mL/s) | During pouring phase only; wide variance from grind changes |
| Flow range (pouring) | 0.1–8.2 mL/s | Median 2.1 |

Constants chosen conservatively toward visual believability over statistical accuracy — Vid's coarse-grind shots aren't representative of the average skin creator's profile. Base resistance bumped to 2.5 to produce more typical pressure curves; efficiency bumped to 0.80.

## Implementation order

1. **Substate derivation** — wire `_currentStepIndex` vs `targetVolumeCountStart`. Small change, immediate skin impact.
2. **skipStep** — handle the `MachineState.skipStep` case in `requestState`. Unblocks weight-exit testing.
3. **Flow→Pressure coupling** — add resistance/damping constants, rewrite `_simulateWithProfile` internals.
4. **transition shaping** — fast vs smooth interpolation of targets.
5. **Weight accumulation** — only count after `targetVolumeCountStart`, apply extraction efficiency.
6. **Verify skipStep integration** — confirm `ShotController`'s existing `skipStep` call works end-to-end with MockBengle weight accumulation (no mock-side trigger needed).

## Testing

- Unit tests: verify substate transitions, skipStep advance, weight accumulation start/stop at `targetVolumeCountStart`, pressure doesn't exceed profile step target.
- Integration: `sb-dev start --connect-machine MockDe1` + POST profile + PUT espresso, verify WS snapshot stream emits correct substates.
- SAW profile: POST a profile with weight exit conditions, verify skipStep fires when weight reaches target.
