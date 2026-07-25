# Baseline: reproduction of the finding

Recorded while executing tasks 1.1-1.4. Every claim below is the output of a command,
not an inference.

## Source revisions

| Repo | Path | Revision | Date |
|---|---|---|---|
| de1app | `~/Development/GitHub/de1app` | `fe5cf40ca1da20ea6ed5622827b6736db39ac2d2` | 2026-07-20 |
| A_Flow (plugin submodule, checked out) | `de1plus/plugins/A_Flow` | `e1a4d871272e20e7b9e3d904389f472c757be683` | 2026-04-19 |
| A_Flow (pinned by de1app `fe5cf40`) | `de1plus/plugins/A_Flow` | `4c3ab3738910a301dadc3898d5a2a42b44edcd26` | - |
| A_Flow (profile_editors submodule) | `de1plus/profile_editors/A_Flow` | `e1a4d871272e20e7b9e3d904389f472c757be683` | 2026-04-19 |

The working checkout of `de1plus/plugins/A_Flow` is ahead of the commit de1app pins.
The only difference across the two revisions in `profiles/` is an added
`profile_editor A_Flow` line in each of the five files, which the ingest tool does not
read. Verified: `A-Flow____default-dark.tcl` ingests byte-identically from either
revision. The corpus rebuild is therefore reproducible from de1app `fe5cf40` regardless
of which of these two A_Flow revisions is checked out.

Both `de1plus/plugins/A_Flow` and `de1plus/profile_editors/A_Flow` are at the same
commit, confirming design D3's note that either path serves.

## 1.1 - The tool reproduces three shipped files byte-identically

Ingesting from `de1plus/profiles/` and diffing against `assets/defaultProfiles/`:

| Profile | Result |
|---|---|
| `7g basket.tcl` -> `7g_basket.json` | byte-identical |
| `Classic Italian espresso.tcl` -> `Classic_Italian_espresso.json` | byte-identical |
| `Preinfuse then 45ml of water.tcl` -> `Preinfuse_then_45ml_of_water.json` | byte-identical |

These three came through the tool, and the tool would produce them again today.

## 1.2 - The tool refuses `default.tcl` and `Gentle and sweet.tcl`

Both fail with:

```
Legacy settings_2a profile with no advanced_shot steps. These require step synthesis
from flat fields, which is not implemented.
```

Both carry `advanced_shot {}` in every de1app commit that touched them, back to the
oldest reachable (2020-10-22). Neither shipped `Default1.json` (6 frames) nor
`Gentle_and_sweet1.json` (6 frames) could have come from this tool.

Relevant scalars, confirming the stop-target defect:

| | `default.tcl` | `Gentle and sweet.tcl` |
|---|---|---|
| `settings_profile_type` | `settings_2a` | `settings_2a` |
| `espresso_temperature` | 90.0 | 88.0 |
| `final_desired_shot_weight` | 36 | 36 |
| `final_desired_shot_volume` | 36 | 36 |
| `final_desired_shot_weight_advanced` | 36 | 135 |
| `final_desired_shot_volume_advanced` | 0 | 135 |

## 1.3 - The A-Flow source-path effect

`A-Flow____default-dark.tcl`, same tool, two source directories:

| Source | Frames |
|---|---|
| `de1plus/profiles/` | 6 - byte-identical to shipped `A-Flow____default-dark.json` |
| `de1plus/plugins/A_Flow/profiles/` | 9 |

`de1plus/profiles/` holds four A-Flow files; the plugin directory holds five. The
missing one is `A-Flow____default-light.tcl`.

## 2.6 - The four known stop targets

After the port, ingesting from de1app `fe5cf40`:

| Profile | shipped today | after | de1app authoritative field |
|---|---|---|---|
| `Classic Italian espresso` | 60 g | 36 g | `final_desired_shot_weight` |
| `7g basket` | 36 g | 35 g | `final_desired_shot_weight` |
| `Preinfuse then 45ml of water` | 0 g (no stop) | 36 g | `final_desired_shot_weight` |
| `Gentle and sweet` | 0 ml (no stop) | 36 ml | `final_desired_shot_volume` |

Frame counts land where the proposal predicted: `7g basket` 5, `Classic Italian
espresso` 4, `Preinfuse then 45ml of water` 3, `Default` 6, `Gentle and sweet` 5.
`Default` derives to 90 / 88 throughout - no 75 or 54 anywhere.

## 2.7 - Cross-check against Decenza

Decenza's bundled JSON ships `"steps": []` for simple profiles - it stores the scalars
and generates at activation - so there is no reference frame list to diff against
directly. Its `profile_sync` developer tool does materialise them, running the real
C++ generators over the same de1app `.tcl` files:

```
Decenza-Desktop/build/Qt_6_11_1_for_macOS_Debug/profile_sync \
    <de1app>/de1plus/profiles <out> --sync
```

Compared per frame after normalising the way the proposal describes (absent / `""` /
`0` unified, the axis a frame's pump does not drive ignored, a zero-value limiter
treated as absent): name, pump, transition, sensor, temperature, seconds, driven axis,
volume, exit condition, limiter - plus editor type, both stop targets, and the
preinfuse frame count.

| Profile | Frames | Result |
|---|---|---|
| `7g basket` | 5 | agree |
| `Classic Italian espresso` | 4 | agree |
| `Preinfuse then 45ml of water` | 3 | agree |
| `Default` | 6 | agree |
| `Gentle and sweet` | 5 | agree |

### The same check across all 89 de1app profiles

Run over every `.tcl` in `de1plus/profiles/`, 80 agree and 9 disagree. None of the nine
is attributable to the synthesis port:

- **Four A-Flow profiles** - frame count 6 vs 9. Expected: `profile_sync` scans
  `../plugins/*/profiles/` automatically and lets the plugin copy win, while this run
  pointed the ingest tool at `de1plus/profiles/`. This is cause 3, fixed by task 4.2.
- **Four precision differences** (`Cleaning/Forward Flush x5`, `Easy blooming - active
  pressure decline`, `Extractamundo Dos!`, `TurboTurbo`) - for example `pressure
  5.999999999999996` against `6.00`. The noisy literal is in de1app's own file;
  Decenza's serialiser rounds to two decimals and the ingest tool preserves the source
  value. Pre-existing behaviour, unrelated to this change, and identical to what the
  corpus already ships.
- **`Test/profile_editor_demo`** - `target_weight` 0 vs 36. That de1app file carries no
  `final_desired_shot_weight*` field at all; Decenza substitutes its own 36 g default.
  Not a bundled profile here.

### A third check, free: seven profiles de1app already derived for us

Seven bundled profiles were already typed `pressure` or `flow` before this change and
already carried generator-shaped frames — they entered the corpus through the
Visualizer / copy-export route, which means de1app's own `sync_from_legacy` produced
them. They are an oracle nobody had to build:

`Traditional lever machine`, `Trendy 6 bar low pressure shot`, `Two spring lever
machine to 9 bar`, `Flow profile for milky drinks`, `Flow profile for straight
espresso`, `GHC/manual flow control`, `GHC/manual pressure control`.

Running the port over their de1app `.tcl` sources reproduces all seven
**value-for-value**: same frame count, names, pumps, transitions, temperatures,
durations, targets and editor type. The only differences are number formatting
(`"2"` against `"2.0"`, and `""` against `"0.0"` on the axis a frame's pump does not
drive — de1app's `ifexists` returns an empty string there, which is exactly the
behaviour the port was written against).

None of the seven is rewritten by this change; they are left as they are.

## Result: reaprime against Decenza, before and after

Decenza's own corpus is 89/89 in sync with de1app (`profile_sync` compare mode), and it
resolves A-Flow from the plugin directory too. Comparing the two bundled corpora by
machine equivalence — absent / `""` / `0` unified, the axis a frame's pump does not
drive ignored, a zero-value limiter treated as absent:

| | machine-equivalent | differ | reaprime-only |
|---|---|---|---|
| before | 33 | 29 | 8 |
| after | **59** | **4** | 8 |

The four remaining differences are float literals in de1app's own `.tcl` files -
`9.999999999999993` against Decenza's `10.0`, and so on. Decenza's serialiser rounds to
two decimals; the ingest tool preserves the source value. They are not a behaviour
difference: the DE1 encodes a frame's driven axis as one byte in 1/16 steps,
`(0.5 + value * 16).toInt()` (`unified_de1.profile.dart:57`), and every differing pair
encodes to the same byte.

**So for every profile both apps ship, they now send the machine identical bytes.**

The eight reaprime-only profiles are deliberate additions with no de1app counterpart:
the four `Baseline` variants, `D-Flow / default`, `I Can't Believe It's Not Filter`,
`PSPH` and `Soup 58`.

### Known divergences between the two implementations

Neither is reachable by any de1app-shipped profile, but both are worth knowing before a
new profile is ingested. The port follows de1app in both cases, per design D1.

- de1app emits the temperature-boost frame whenever `temp_bump_time_seconds` > 0,
  independent of `preinfusion_time`; Decenza only emits it when `preinfusion_time` > 0
  and clamps its length to `min(2, preinfusion_time)`. They differ only for a profile
  with temperature stepping enabled and `preinfusion_time` under 2 seconds.
- With temperature stepping disabled, de1app sets all four frame temperatures from
  `espresso_temperature`; Decenza sets them from `espresso_temperature_0`. Identical
  wherever the two scalars agree, which they do throughout de1app's corpus.
