# Design — Weight-flow estimator rework (Kalman)

- **Issue:** [#417](https://github.com/tadelv/reaprime/issues/417)
- **Split-out (deferred):** [#420](https://github.com/tadelv/reaprime/issues/420) — SAW lead decomposition
- **Status:** design agreed (review-driven), not yet implemented
- **Date:** 2026-07-08

## Problem

`weightFlow` (from `ScaleController`) feeds three consumers: the SAW stop projection (`ShotSequencer`), the live/recorded flow graph, and post-stop yield refinement (`_refineStoppingYield`). It has two structural faults and one root cause.

1. **Oscillation.** The pipeline is `FlowCalculator` (endpoint difference over a 600 ms window — `flow = (last.weight − first.weight) / windowSpan`, using only the two boundary samples and discarding everything between) followed by a *second* `MovingAverage(10)`. Endpoint-differencing over the ~2–6 samples a window holds is noise-sensitive, so even after double smoothing the flow oscillates. Measured on shot `b6dbd239`: mean 5.27 g/s, **stdev 0.40 (±8%)**, sample-to-sample |Δ| up to 1.08 g/s (~20%).
2. **Unsigned flow → dead code.** `FlowCalculator` returns `flow.abs()`, so `weightFlow` is never negative. But `ShotSequencer._refineStoppingYield` gates cup-removal detection on `weightFlow < -_removalFlowThreshold`. That branch is **currently dead** — the settling logic was written for signed flow the calculator cannot produce.
3. **Root cause of the variable-timing mishandling:** `MovingAverage` is **count-based**, so at a jittery BLE rate its effective *window duration* drifts.

### What this is NOT

Stops already land accurately — shot `b6dbd239`: target 38.4 g → actual 38.0 g (**0.4 g**). This is a flow-**quality** and latent-**bug** fix, not a stop-accuracy fix. That framing drives every scope decision below.

## Non-goals

- **SAW lead decomposition** (`scaleDripLag + estimatorLag + transportLag + userTrim`, runtime transport-lag measurement, `weightFlowMultiplier` rename) → **#420**. It's robustness insurance against a platform/BLE-stack change, not a felt problem; deferred until there's a concrete trigger.
- **Offline learning from a corpus of shots.** The estimator is signal-processing — recovering flow from noisy weight — and is essentially invariant to the coffee (dose, grind, profile don't change the scale's noise or the differencing math). There is near-zero shot-to-shot signal to learn. Adaptation is **online only** (see P1).

## P0 — Diagnostics (throwaway spike)

**Why it's needed.** Persisted shots are recorded at machine cadence (~3.7 Hz), *downsampled* from the Decent scale's native ~10 Hz (`decent_scale/scale.dart:44`). At 3.7 Hz a 600 ms window holds ~2 samples, so every differentiator (endpoint-diff, LSLR, …) collapses to the same result — stored shots **cannot** characterize the native-rate signal or validate an estimator choice. An attempt to compare methods offline on the stored trace was inconclusive for exactly this reason.

**Form: spike, not a shipped feature.**

- Add a temporary log line in `ScaleController._processSnapshot` dumping raw `timestamp,weight` (pre-`FlowCalculator`; the native-rate signal is `scale.currentSnapshot`, a `Stream<ScaleSnapshot>`).
- Flash to the test tablet (m50mini), capture 2–3 real shots, pull the raw log, analyze offline.
- **Delete the capture code.** No settings flag, no debug endpoint, no schema change — a permanent capture surface was explicitly rejected as gold-plating.

**Exit criterion:** enough raw native-rate data to set the Kalman noise priors and validate it against ground truth. The raw traces become golden-fixture inputs for P1 tests.

## P1 — Estimator rework

Replace `FlowCalculator` **and** the second-stage `MovingAverage(10)` with a single **1-D constant-velocity Kalman filter** on state `[weight, flow]`.

### Why Kalman (not LSLR, not a low-pass)

The goal is an estimator with **online self-adaptation** baked in — not an offline learning loop (rejected above) and not a fixed filter. A constant-velocity Kalman with *fixed* `Q`/`R` is, after gain settles, just a fixed low-pass wearing a costume. What earns it:

- **Adaptive measurement noise `R`**, tracked from innovation/residual variance:
  - clean scale → small residuals → `R` shrinks → filter trusts the scale → snappy, low-lag flow;
  - disturbance (cup tap, portafilter knock, drip splat, a hand steadying the cup) → residuals spike → `R` grows → filter distrusts the transient → flow stays smooth instead of lurching.
- **Fixed process noise `Q`** from real flow dynamics (0–10 g/s, bounded ramp rate). We adapt *trust in the sensor*, not the physics model. (Adapting both `Q` and `R` is unstable to tune and was rejected.)

### Properties that fall out

- **Signed flow** as a state variable → no `.abs()`, un-breaks the `_refineStoppingYield` cup-removal branch.
- **Variable `dt`** in every predict step (the state-transition matrix depends on the real inter-sample interval) → fixes the count-based-window bug directly.
- **Hard filter re-init at tare** (re-seed weight to current, flow to 0, covariance high) — replaces the `_flowSettleUntil` suppress-window hack with a principled reset at the weight discontinuity.
- **Multi-scale support for free, on two axes:** adaptive `R` auto-calibrates its baseline to whatever scale's noise floor is connected (so no per-scale `R` table — which reaprime couldn't cleanly key anyway, having only `Device.name`); variable-`dt` handles a slower scale's larger intervals. *(Note: physical drip lag per scale — `scaleDripLag` — is a different quantity, handled in #420, not by the estimator.)*

### Stop-accuracy coupling — named risk

P1 is **not** isolated from stops, despite the "clean split" from #420. The SAW stop is `weight + flow × multiplier ≥ target`, and the current `multiplier = 1.0` was implicitly tuned to the *old* estimator's ~0.8 s effective lag (600 ms endpoint window + `MovingAverage(10)`). A snappier Kalman (~0.2–0.3 s lag) reports less-delayed flow. At steady pour the magnitude is similar, so most shots barely move — but on **declining-flow endings** (tapering pours, decline profiles) a laggy estimator over-reports flow and stops *early*, while a snappy one stops *later* → yield can drift up a gram or two. The rollout below exists to **measure** this, not assume it away.

## Rollout — feature-flagged, two-phase

Using the existing flag foundation (`FeatureFlag` enum + `defaultFeatureFlagValues`, the settings-triad pattern):

- **Phase 1 — opt-in / default OFF.** Validation window; only opted-in users' stops can change. Capture actual-vs-target yield with the Kalman on vs off.
- **Phase 2 — opt-out / default ON**, then retire the flag once stable.

This is the *inverse* of how the step-exit arbiter shipped (default-ON immediately, because it was a pure bugfix with no downside). The estimator swap earns a default-OFF validation window **because** of the stop-timing risk. The **signed-flow fix rides the same flag** but is low-risk — it only affects post-stop yield refinement, not stop timing.

## Acceptance gate

"Done" is **not** "the graph looks smoother." Flip the default only if, across **≥10 opt-in shots**:

- **(a)** mean |actual − target yield| ≤ the current baseline (~0.4–1 g, measured in the same window on the old estimator) — *no stop regression*;
- **(b)** flow-trace sample-to-sample stdev meaningfully below the ±8% baseline;
- **(c)** `weightFlow` goes negative on a real cup-lift (removal branch proven live).

## Testing (no hardware)

- **Golden fixtures:** feed the Kalman the P0 raw traces, assert deterministic output (settling, lag, smoothness).
- **Synthetic inputs:** step, ramp, and tap/spike signals asserting settling time, lag bound, and disturbance rejection (the adaptive-`R` behavior).
- Kalman is a pure deterministic unit → ideal for TDD; mirrors existing mock/sim test conventions.

## Key files

| File | Role |
|------|------|
| `lib/src/controllers/scale_controller.dart` | `_processSnapshot` (P0 capture point + P1 estimator swap); `tare()` re-init / `_flowSettleUntil` hack to replace |
| `lib/src/controllers/weight_flow_calculator.dart` | the endpoint-diff `FlowCalculator` being replaced |
| `lib/src/util/moving_average.dart` | count-based MA being dropped |
| `lib/src/controllers/shot_sequencer.dart` | `_refineStoppingYield` dead removal branch; SAW projection (coupling surface) |
| `lib/src/settings/feature_flags.dart` | add the P1 flag here |
| `lib/src/models/device/impl/decent_scale/scale.dart:44` | native ~10 Hz rate |

## Build sequence

1. **P0 spike** — raw-capture branch, capture 2–3 shots, analyze, delete capture code.
2. **P1 estimator** (TDD from P0 fixtures) — Kalman class (adaptive `R`, fixed `Q`, variable `dt`), signed flow, tare re-init; swap it into `ScaleController`, drop `FlowCalculator` + `MovingAverage(10)`.
3. **Feature flag** — add to `FeatureFlag`, default OFF; gate the estimator selection in `ScaleController`.
4. **Validation** — opt-in on real shots, capture yield-vs-target, check the acceptance gate.
5. **Flip default → ON** (opt-out), then retire the flag a release later.

## Open decisions resolved during review

| # | Decision |
|---|----------|
| Scope | Split — this issue = flow only; lead decomposition → #420 |
| P0 form | Throwaway spike, delete after; no shipped capture surface |
| Continuous improvement | Online self-adaptation only; offline corpus-learning rejected |
| Estimator | 1-D constant-velocity Kalman |
| Adaptation | Adaptive `R` (innovation-based), fixed `Q`; both-adaptive rejected |
| Signed flow | Yes — un-breaks removal branch |
| dt / tare | Variable `dt`; hard re-init at tare |
| Rollout | Feature flag: opt-in (OFF) → validate → opt-out (ON) → retire |
| Acceptance | Yield-no-regression + noise-reduction + negative-flow-on-lift; not graph aesthetics |
