# Plan: Fix imported shot frame numbers + profile target_volume_count_start

**Issues:** [#262](https://github.com/tadelv/reaprime/issues/262), [#263](https://github.com/tadelv/reaprime/issues/263)
**Date:** 2026-06-03
**Status:** #263 implemented — frame reconstruction done. #262 pending.

---

## #263 — Imported shots have all frame 0

### Root cause

The DE1 app history format (both TCL `.shot` and v2 `.json`) does **not** include frame/step-index in time-series data. It stores only: `elapsed`, `pressure`, `flow`, `temperature`, `weight`.

Both parsers hardcode `profileFrame: 0`:

- `lib/src/import/parsers/shot_v2_json_parser.dart:186` — `profileFrame: 0`
- `lib/src/import/parsers/tcl_shot_parser.dart:140` — `profileFrame: 0`

The profile *is* available in the parsed shot (imported from `json['profile']` or synthesized from settings), so we have the step durations. We just don't use them.

### Fix: Reconstruct frame from step durations + elapsed time

In both `_parseSnapshots()`:

1. Extract step durations from the parsed profile
2. Pre-compute cumulative end-times per step (accumulated `seconds`)
3. For each snapshot, binary-search elapsed time into the step time window

**Algorithm (per parser):**

```
steps = parsed profile steps
cumulativeEnds = []
cumulative = 0
for each step:
    cumulative += step.seconds
    cumulativeEnds.add(cumulative)

for each snapshot i:
    elapsed_sec = elapsed[i]
    frame = find first index where cumulativeEnds[index] >= elapsed_sec
    (last step has no exit — always maps to last frame index)
```

**Edge cases:**
- Steps with exit conditions (pressure/flow over X) — use `seconds` as approximation. Better than always-0.
- Missing profile / 0 steps — keep `profileFrame: 0` (current behavior)
- Single-step profile — always frame 0
- Step with `seconds: "0"` (e.g., best_practice "Extraction start") — frame advances instantly; skip such zero-duration steps in the cumulative accumulation (or treat as 0-width — handled naturally by the algorithm since elapsed won't match until next step)

**Files changed:**
- `lib/src/import/parsers/shot_v2_json_parser.dart`
- `lib/src/import/parsers/tcl_shot_parser.dart`

**Tests:**
- `test/import/shot_v2_json_parser_test.dart` — add test with multi-step profile, verify frame assignments
- `test/import/tcl_shot_parser_test.dart` — same for TCL format
- `test/import/de1app_importer_test.dart` — existing integration test verifies import flow still works

---

## #262 — Londinium target_volume_count_start wrong

### Root cause

Bundled `assets/defaultProfiles/Londonium.json` has `"target_volume_count_start": "0"`.

In de1app, volume counting starts **after** the infusion step. Londinium steps:
- 0: Fill start (2s)
- 1: Fill (25s)
- 2: Infuse (12s)
- 3: Pressure Up — pour begins

Correct value: `3`.

### Impact

- Londinium has `target_volume: 0.0` so stop-at-volume doesn't trigger, BUT:
  - Accumulated volume in shot history is inflated (includes fill + infusion flow)
  - Users who set a custom target_volume on Londinium get broken stop-at-volume

- 45 bundled profiles have `target_volume_count_start` that may differ from de1app convention. **17** of those have `target_volume > 0` (actual stop-at-volume users).

### Fix

1. **Fix Londinium:** Change `target_volume_count_start` from `"0"` → `"3"`
2. **Audit remaining profiles with target_volume > 0:** For each profile, determine the correct frame where extraction/pour begins and fix if wrong

### How to determine correct value

For espresso profiles: count frames from 0 until the step where extraction actually starts (typically after preinfusion/infusion/fill completes). This is the step where `pump` changes to the main extraction mode (e.g., "pressure" with target > preinfusion pressure, or flow-based extraction).

Heuristic (per profile):
1. Find the first step where the pump transitions from preinfusion/fill to extraction
2. This is typically the step AFTER "infuse", "preinfusion", "fill", or similar named step
3. Verify against de1app source if uncertain

For non-espresso profiles (tea, filter): `target_volume_count_start` should point to the frame where the main water delivery begins (after bloom/infusion).

**Profiles to fix (target_volume > 0, likely wrong tvc):**

| Profile | Current tvc | Likely correct | Rationale |
|---------|-------------|----------------|-----------|
| Londonium.json | 0 | 3 | After infusion (frame 2) |
| Blooming_allonge.json | 0 | 3 | After bloom+rise (frames 0-2) |
| rao_allonge.json | 0 | 1 | After preinfusion (frame 0) |
| tea_in_a_basket.json | 0 | ? | Tea profile — different convention |
| Filter_20.json | 1 | ? | Filter — verify against de1app |
| best_practice.json | 3 | 3 | Looks correct (prefill→fill→compress→drip→pressurize→extraction) |

**Files changed:**
- `assets/defaultProfiles/Londonium.json` — fix tvc
- Other `.json` files in `assets/defaultProfiles/` as audit determines

**Tests:**
- Unit test that loads Londinium.json and verifies `target_volume_count_start == 3`

---

## Implementation order

1. **#263 first** — frame reconstruction in parsers (code change, testable)
2. **#262 second** — profile data fixes (data change, simpler)

---

## Verification

- `flutter test test/import/` — parser tests
- `flutter analyze` — static analysis
- Manual: import a de1app shot, verify history viewer shows correct stage labels
- Manual: load Londinium profile, run simulated shot, verify volume counting starts at frame 3
