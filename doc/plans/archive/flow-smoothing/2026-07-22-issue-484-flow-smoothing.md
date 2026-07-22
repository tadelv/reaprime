# Design — #484 weight-flow smoothing regression

- **Issue:** [#484](https://github.com/tadelv/reaprime/issues/484)
- **Related:** [#420](https://github.com/tadelv/reaprime/issues/420) — SAW lead decomposition
- **Date:** 2026-07-22
- **Status:** implemented; real-hardware allonge and SAW validation pending

## Problem

The Kalman estimator introduced for #417 now supplies one `weightFlow` value to two consumers with conflicting requirements:

- control decisions need low latency;
- charts, shot history, WebSocket clients, and Visualizer need visual stability.

The regression reproduces in both shot pairs attached to #484. Mean absolute change between active consecutive stored flow samples is:

| Profile | de1app | Decent.app | Ratio |
|---|---:|---:|---:|
| Filter3 | 0.035 g/s | 0.437 g/s | 12.3× |
| Espresso | 0.060 g/s | 0.219 g/s | 3.7× |

Five recent shots from `192.168.12.57` reproduce the same Decent.app range at 3.7–4.4 Hz: mean `|Δflow|` is 0.37–0.54 g/s.

## Root cause

The Kalman regression test compares Kalman output against `FlowCalculator` alone. The production legacy path was `FlowCalculator(600ms) + MovingAverage(10)`, so the benchmark omitted its second smoothing stage.

On `test/fixtures/shot1_native_trace.csv`:

- current Kalman: 13.1% standard deviation / mean;
- actual legacy pipeline: 9.9%;
- actual legacy mean `|Δflow|`: 0.099 g/s.

PR #437 then relaxed Kalman smoothing to address filtered-weight lag. Raw weight now bypasses the Kalman, but the noisier tuning remains visible through `weightFlow`.

The de1app source also separates fast, slow, and SAW flow estimates in `de1plus/device_scale.tcl`; Decent.app currently uses one value for every role.

## Design

### Split control and display flow

Extend `WeightSnapshot` with an internal `controlWeightFlow` value:

- Kalman output becomes `controlWeightFlow`;
- `FlowCalculator(600ms) + MovingAverage(10)` becomes public `weightFlow`;
- `controlWeightFlow` defaults to `weightFlow` when omitted;
- `controlWeightFlow` is excluded from JSON serialization.

This keeps existing shot, REST, WebSocket, skin, plugin, import, and database contracts unchanged.

Use control flow for:

- `ShotSequencer` projected-weight SAW and per-step weight exits;
- `ShotSequencer._refineStoppingYield` removal, spike, and settle detection;
- hot-water projected-weight stopping.

Use display flow for:

- shot measurements and history;
- REST/WebSocket scale snapshots;
- realtime UI and charts;
- Visualizer upload;
- exported/imported shot data.

### Retire the feature flag

Remove `FeatureFlag.kalmanFlow` and its Advanced Settings toggle. Kalman becomes the fixed internal control estimator, while the legacy smoothing pipeline becomes the fixed public display estimator. Retaining the toggle would give it ambiguous semantics and allow unsigned legacy flow back into control decisions.

### Runtime display tuning

Add ephemeral debug routes:

- `GET /api/v1/debug/flow-smoothing`
- `POST /api/v1/debug/flow-smoothing`

Payload:

```json
{
  "windowMs": 600,
  "movingAverageSamples": 10
}
```

The POST route validates positive bounded integers, applies both values atomically, and resets only the display estimator. Values are process-local and never persisted. Kalman parameters are not exposed.

Debug routes remain compile-time gated by the existing `simulate` Dart define. A real-hardware tuning build can use `--dart-define=simulate=0`: the value registers debug routes but selects no simulated device types.

Update `assets/api/rest_v1.yml` with the debug contract in the same change.

### Offline analysis tool

Add a standard-library-only `tools/analyze_weight_flow.py` that:

- accepts a server base URL and one or more shot IDs;
- fetches each full `/api/v1/shots/{id}` record;
- reports sample count, median cadence, active-flow mean `|Δflow|`, p95 `|Δflow|`, and second-difference noise;
- emits CSV and standalone SVG plots.

Persisted shots are sufficient to score and plot display output. They are not suitable for replaying alternate smoothing parameters because machine-driven persistence downsamples the native scale stream.

## Sequencer cadence

Do not change shot sampling cadence in #484.

`ShotSequencer` is intentionally machine-driven and combines each machine snapshot with the latest scale value. Driving it from whichever stream is fastest would repeatedly process stale machine snapshots and complicate state transitions, profile-frame exits, volume integration, and persistence. A fixed 10 Hz timer would manufacture duplicate samples.

A future #420 refactor may split event handling:

- machine stream for lifecycle, profile frames, volume, and persistence;
- native scale stream for SAW and post-stop decisions.

That change is independent of this display regression.

## Test-first implementation sequence

1. Correct the golden benchmark to include the full legacy pipeline and demonstrate that current public Kalman output exceeds the agreed display threshold.
2. Add `WeightSnapshot.controlWeightFlow` compatibility tests:
   - omitted value falls back to `weightFlow`;
   - JSON output remains unchanged;
   - imported historical snapshots receive the fallback.
3. Add `ScaleController` tests proving:
   - display mean `|Δflow| ≤ 0.12 g/s` on the native fixture;
   - control flow remains the existing signed Kalman result;
   - tare resets both estimators;
   - runtime tuning resets only display smoothing.
4. Add divergent-value controller tests proving SAW, hot-water stopping, and stopping-yield refinement consume control flow rather than display flow.
5. Add debug handler tests for GET, valid atomic update, invalid bounds/types, and estimator reset.
6. Implement the smallest changes that satisfy those tests.
7. Remove the Kalman feature flag, settings toggle, and obsolete selection branches.
8. Add the offline analysis tool and test its metric calculation against a small local fixture.

## Verification

### Automated

- Relevant controller, handler, serialization, and tool tests pass.
- Display flow mean `|Δflow| ≤ 0.12 g/s` on the native fixture.
- Existing Kalman control-flow golden behavior remains unchanged.
- `flutter analyze` passes.
- Full `flutter test` passes.

### Real hardware

1. Build once with debug routes enabled and connect to the real machine and scale.
2. Use the debug API to tune without rebuilding.
3. Pull a long allonge shot before and after tuning.
4. Run `tools/analyze_weight_flow.py` and inspect its SVG plots.
5. Require at least 75% lower mean `|Δflow|` than the current Decent.app baseline for the comparable active-flow section.
6. Pull one SAW shot and require final yield within 1 g of target.

Filter3 is not required; an allonge provides the long-running low-flow trace needed to expose chart chatter.

## Non-goals

- Native-rate shot persistence.
- Fastest-stream or timer-driven `ShotSequencer` sampling.
- SAW lead decomposition or runtime transport-lag measurement.
- Public API exposure of control flow.
- Persistent user-facing smoothing settings.
- Runtime tuning of Kalman parameters.

## Implementation verification

- Native fixture display mean `|Δflow|`: within the 0.12 g/s gate.
- Existing Kalman control output: unchanged (`0.2597772268251356` mean `|Δflow|` on the fixture).
- `flutter analyze`: clean.
- `flutter test`: 2461 tests passed.
- Python analysis-tool test: passed.
- Simulated REST smoke: GET, valid POST, invalid POST, hot reload, and state retention passed.
- Real-hardware allonge steady-tail mean `|Δflow|`: 0.049 g/s versus 0.276 g/s on the preceding comparable shot, an 82% reduction.
- First real-hardware SAW result: 53.8 g against 52.5 g target (+1.3 g); one more SAW validation shot is required for the ±1 g gate.

Update the #484 tracking item after the remaining SAW validation.
