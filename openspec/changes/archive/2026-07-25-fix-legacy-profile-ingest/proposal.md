## Why

Eleven of the bundled default profiles send the machine something other than what the profile describes. The clearest single symptom: `Default1.json` runs its last four frames at **75 °C and 54 °C**. de1app's `default.tcl` declares `espresso_temperature 90.0`, and no espresso profile declines to 54 °C.

This was found by comparing the corpus against Decenza's built-ins, which derive these frames through de1app's own builders. 63 titles are common to both apps; **52 are already machine-equivalent** once encoding is normalised (absent/`""`/`0` unified, the axis a frame's pump does not drive ignored, a zero-value limiter treated as absent). The remaining **11 all have an established cause**, and every one of them is fixed by re-ingesting from de1app — three of them only after the tool is repaired.

### Cause 1 — `tools/ingest_profiles.py` copies de1app's stale `advanced_shot`

de1app's `save_profile` writes that array out of the *global* `::settings`, so a `settings_2a`/`2b` file ships whatever frames were loaded when it was last saved. de1app never reads them back for those types — it regenerates from the scalars at load time. The tool takes them at face value.

There is a guard, at `tools/ingest_profiles.py:113`, but it is conditioned on the wrong thing:

```python
settings_type = result.get("settings_profile_type", "")
if not steps and settings_type in ("settings_2a", "settings_2b"):
    raise ValueError(f"Legacy {settings_type} profile with no advanced_shot steps. ...")
```

It rejects a legacy profile only when `advanced_shot` is **empty** — but the failure mode is that it is *populated, with the wrong content*. The guard cannot fire on any file that needs it.

**Verified, not inferred.** Running the tool today against de1app `main` reproduces three shipped files **byte-identically**, stale frames and all:

| Profile | de1app `advanced_shot` | tool output vs shipped |
|---|---|---|
| `7g basket` | populated (stale) | **byte-identical** |
| `Classic Italian espresso` | populated (stale) | **byte-identical** |
| `Preinfuse then 45ml of water` | populated (stale) | **byte-identical** |

For these three, fixing the guard fixes the corpus directly.

**The same mistake is made a second time, on the stop targets — and this one changes the cup more than the frames do.** de1app carries two parallel sets of target fields, and which set is authoritative depends on the profile type:

| | `settings_2a` / `2b` | `settings_2c` / `2c2` |
|---|---|---|
| authoritative | `final_desired_shot_weight`, `final_desired_shot_volume` | `final_desired_shot_weight_advanced`, `final_desired_shot_volume_advanced`, `..._count_start` |

de1app's `settings_to_advanced_list()` leaves the `_advanced` fields alone for `2c`; for `2a`/`2b` it overwrites them from the plain counterparts. The tool reads the `_advanced` spelling unconditionally, so for every legacy profile it takes a value de1app would have discarded:

| Profile | de1app type | authoritative | reaprime uses |
|---|---|---|---|
| `Classic Italian espresso` | `settings_2a` | **36 g** | **60 g** |
| `7g basket` | `settings_2a` | 35 g | 36 g |
| `Preinfuse then 45ml of water` | `settings_2b` | 36 g | 0 g (no stop) |
| `Gentle and sweet` | `settings_2a` | 36 ml | 0 ml (no stop) |

A shot stopping at 60 g instead of 36 g is a different drink by a wider margin than any frame difference in this document. `0` is worse in a different way — it removes the stop entirely.

This also explains the `type` field reading `advanced` on profiles de1app types `pressure` or `flow`: the tool treats every profile as advanced, and then reads advanced-only fields accordingly. Fixing the frames without fixing this would leave the corpus brewing the right curve into the wrong cup.

### Cause 2 — two profiles entered the corpus by a different route

`Default` and `Gentle and sweet` are **not** explained by the above, and it is worth being exact about that. de1app's `default.tcl` and `Gentle and sweet.tcl` have carried `advanced_shot {}` since at least 2020, so the tool **refuses them today** — correctly, via that same guard. Yet both ship with six frames of content the tool could not have produced.

`doc/plans/archive/default-profiles-curation/curation.md` records how: profiles were "pulled from **Visualizer + de1app copy-exports**". A Visualizer upload carries whatever frames the uploader's de1app had in memory, which for a simple profile is the same global-`::settings` array — the same corruption, arriving by a different path. The `1` suffix on `Default1.json` and `Gentle_and_sweet1.json` is consistent with a separate import that collided with an existing name.

Fixing the guard does **not** fix these two. Implementing synthesis does, by making them ingestible from de1app for the first time.

### Cause 3 — de1app issue #350 shadows the A-Flow profiles

The A_Flow plugin seeds its profiles only when the file is absent, and de1app's distribution already places a 6-frame copy of four of them in the data directory — so the plugin's 9-frame versions are never installed and cannot self-correct.

**Verified the same way:** running the tool on `de1plus/profiles/A-Flow____default-dark.tcl` reproduces our shipped file byte-identically at 6 frames; running it on `de1plus/plugins/A_Flow/profiles/A-Flow____default-dark.tcl` yields 9. The tool is fine here — it was pointed at the shadowed directory. The fifth profile, `default-light`, is not shadowed in de1app and is simply missing from our corpus.

### Cause 4 — one profile is a stale harvest from an older de1app

`Cleaning/Forward Flush x5` is `settings_2c`, so its stored frames *are* authoritative and none of the causes above applies. It ships 9 frames against de1app's 10 — ours has lost `Pressure rise 1 start`.

**Verified:** running the tool against de1app `main` today produces the correct 10 frames, so this is simply a copy taken from an older de1app and never refreshed. Re-ingestion fixes it; no tool change is involved.

### Cause 5 — one slot holds a different profile entirely

`advanced_spring_lever.json` is titled `Advanced spring lever` but is **not** de1app's profile of that name. de1app's is `settings_2c`, authored `Decent`, five frames at **88 °C**, opening `2s infuse` and closing `maintain flow`. Ours is authored **John Weiss**, five frames at **90 °C**, opening `infuse` and closing `flow limit`, with an extra `pressure limit` frame.

Those are Weiss's frame names — and de1app ships a *separate* profile, `Weiss advanced spring lever`, at 90 °C. **We already ship that one, correctly**: our `Weiss_advanced_spring_lever.json` matches de1app and Decenza exactly, all four frames.

So this is not a corrupted copy of `Advanced spring lever`; it is a third, Visualizer-sourced Weiss variant that landed in the wrong slot during curation, where it displaced de1app's actual profile. The `John Weiss` attribution in our file — against de1app's `Decent` — is the tell, and the curation notes record exactly that attribution being applied.

**Put plainly, the corpus ships Weiss's profile twice and de1app's `Advanced spring lever` not at all.** Both files sit at 90 °C, both use Weiss's frame vocabulary — `infuse` / `rise and hold` / `decline` / `flow limit` — and they differ only in values:

| | `advanced_spring_lever.json` | `Weiss_advanced_spring_lever.json` |
|---|---|---|
| author | John Weiss | Decent |
| frames | 5 (extra `pressure limit`) | 4 |
| infuse | 20 s @ 6 ml/s | 10 s @ 8 ml/s |
| decline | to 4 bar over 20 s | to 6 bar over 30 s |
| flow limit | 1.0 ml/s | 1.5 ml/s |

Two variants of one profile under two names, while the profile whose name one of them borrowed — 88 °C, opening `2s infuse`, closing `maintain flow` — is absent. That is what a collision looks like, and it is why this reads as an accident rather than a curation choice.

**Verified:** re-ingesting `de1plus/profiles/Advanced spring lever.tcl` produces the correct five frames at 88 °C, authored `Decent`, matching Decenza. Nothing is lost by doing so, because the genuine Weiss profile is already present under its own title.

### The eleven

| Profile | reaprime | correct | cause |
|---|---|---|---|
| `7g basket` | 4 frames | 5 | 1 — stale `advanced_shot`, tool-reproduced |
| `Classic Italian espresso` | 5 frames | 4 | 1 — stale `advanced_shot`, tool-reproduced |
| `Preinfuse then 45ml of water` | 6 frames | 3 | 1 — stale `advanced_shot`, tool-reproduced |
| `Default` | 88 → **75** → **54** | 90/88 flat | 2 — foreign import |
| `Gentle and sweet` | 88 → **78.5** → **67** | 88 flat | 2 — foreign import |
| `A-Flow / default-dark` | 6 frames | 9 | 3 — de1app #350 |
| `A-Flow / default-medium` | 6 frames | 9 | 3 — de1app #350 |
| `A-Flow / default-very-dark` | 6 frames | 9 | 3 — de1app #350 |
| `A-Flow / default-like-dflow` | 6 frames | 9 | 3 — de1app #350 |
| `A-Flow / default-light` | **absent** | 9 | 3 — de1app #350 |
| `Cleaning/Forward Flush x5` | 9 frames | 10 | 4 — stale harvest |
| `Advanced spring lever` | Weiss variant, 90 °C | de1app's, 88 °C | 5 — wrong profile in the slot |

### Separately — beverage type is flattened, losing tea and filter

15 further profiles differ from de1app not in what they brew but in what they say they are. `tools/ingest_profiles.py` maps three de1app types onto one:

```python
BEVERAGE_TYPE_MAP = {"filter":"pourover", "tea":"pourover", "tea_portafilter":"pourover", "descale":"cleaning"}
VALID_BEVERAGE_TYPES = {"espresso","calibrate","cleaning","manual","pourover"}
```

de1app has all three. Its shipped profiles use `tea_portafilter` (15 files), `pourover` (7), `filter` (2) and `tea` (1) as distinct values, and `tea_portafilter` is formally declared in `de1plus/app_metadata.tcl` alongside `espresso`, `cleaning` and `calibrate`. So thirteen tea profiles and two filter profiles arrive here labelled pour-over.

No evidence was found that de1app *brews* differently on beverage type — its uses are display text (`profile_type_text`) and the shot-file label — so this is information loss rather than a wrong shot. It still costs users the ability to tell a tea portafilter profile from a pour-over one, in an app that ships thirteen of them.

**This needs an app-side change, not only a tool change, and the order matters.** `BeverageType` is a Dart enum of exactly those five values (`lib/src/models/data/profile.dart:133`), and `_parseBeverageType` falls back to **`espresso`** for anything it does not recognise. Emitting `tea_portafilter` into the corpus before the enum accepts it would turn thirteen tea profiles into espresso profiles — a worse outcome than the current flattening.

**This was partly diagnosed already, and bounded too narrowly.** `doc/plans/archive/default-profiles-curation/audit.md` has the mechanism in its own words — "de1app's `advanced_shot` is garbage", "our import took the stale `advanced_shot`" — and flags the converter as "worth a look". It then scopes it:

> "**Scope: contained to the 3 levers.** A scan of all espresso profiles for the pour-over step pattern found only the 3 levers + `Preinfuse_then_45ml_of_water`"

A scan for one known step *pattern* only finds profiles whose stale frames happen to be that pour-over list; it cannot see a profile whose stale frames are merely the wrong temperature. The lever trio was re-ported and is now clean — `Cremina`, `Traditional lever machine` and `Two spring lever machine to 9 bar` all compare equivalent today. The rest of the class was never found, and `Preinfuse then 45ml of water` was identified but not fixed.

## What Changes

- **Re-condition the guard** in `tools/ingest_profiles.py` on the profile *type*, not on the absence of steps. For `settings_2a`/`2b` the stored `advanced_shot` is never authoritative, populated or not.
- **Resolve the target fields by profile type too.** Read `final_desired_shot_weight` / `final_desired_shot_volume` for `settings_2a`/`2b`, and the `_advanced` spellings only for `settings_2c`. This is de1app's own runtime rule, in the switch that decides when the shot stops — `de1plus/device_scale.tcl:1322` for weight and `de1plus/de1_de1.tcl:862` for volume, both `settings_2c { ...advanced } default { ...plain }`. Carry the resolved profile `type` (`pressure`/`flow`/`advanced`) accordingly rather than marking everything `advanced`.
- **Implement step synthesis** for those types, porting de1app's `pressure_to_advanced_list` / `flow_to_advanced_list` from `de1plus/profile.tcl` — the piece the current error message already names as missing. Without it the tool can only refuse, and five profiles have no path into the corpus.
- **Re-ingest the five simple profiles** from de1app and check in the corrected JSON.
- **Re-ingest all five A-Flow profiles from `de1plus/plugins/A_Flow/profiles/`**, not `de1plus/profiles/`. Adds `default-light`; updates four from 6 frames to 9. No tool change needed for this — only the source path.
- **Add a source-provenance guard**: when the same profile title exists in both a base and a plugin/editor directory and the two disagree, fail and name both paths rather than silently picking one.
- **Re-ingest `Cleaning/Forward Flush x5` and `Advanced spring lever`** from de1app. Neither needs a tool change — the current tool already produces the correct output for both.
- **Carry `tea`, `tea_portafilter` and `filter` through instead of flattening them to `pourover`.** Extend the `BeverageType` enum, keep the wire spelling `tea_portafilter` (see design — Dart naming does not round-trip it for free), drop those three entries from `BEVERAGE_TYPE_MAP`, and re-ingest the 15 affected profiles. The enum change lands first, or the tea profiles become espresso.
- **Add a regression test** asserting no bundled `settings_2a`/`2b` profile carries frames inconsistent with its own scalars.
- **BREAKING for users:** in effect, yes — eleven bundled profiles change what they send to the machine. That is the point, but anyone who has copied one into their own library keeps the old version, so a migration decision is required (see design).

## On the displaced Weiss variant

`Advanced spring lever` is restored to de1app's profile, so the variant currently occupying that name leaves the corpus. This is not a judgement that it is a worse profile — it is that it is a *different* profile wearing a name that belongs to another, while its own correct copy (`Weiss advanced spring lever`) is already shipped alongside it.

If the variant is wanted, keeping it is additive and needs only a title that distinguishes it from **both** existing entries. That is a separate decision and no reason to hold this change: the corpus matching de1app is the goal, and a third profile under a third name does not conflict with it.

## Capabilities

### New Capabilities
- `default-profile-ingest`: Correctness and provenance of the bundled default profile corpus — which de1app source directory each profile is harvested from, how legacy `settings_2a`/`2b` profiles have their frames derived rather than copied, and the guards that stop a future harvest silently reintroducing stale or shadowed content.

### Modified Capabilities
<!-- The de1app *import* path is unaffected: de1app_importer.dart scans profiles_v2
     JSON and tcl_parser.dart never touches advanced_shot, so the frame/target
     defects are contained to the corpus-building tool.

     The beverage-type work does reach the app: BeverageType (lib/src/models/data/
     profile.dart) gains values, and _parseBeverageType / toJson must round-trip the
     de1app wire spellings. Behaviour keyed on beverage type — the cleaning/calibrate
     "scaleless" branch in app.dart and de1_state_manager.dart — is unchanged; the new
     values behave like espresso and pourover do. -->

## Impact

- **`tools/ingest_profiles.py`** — the type-keyed guard, the synthesis port, type-resolved stop targets, the beverage-type passthrough, the provenance check.
- **`lib/src/models/data/profile.dart`** — `BeverageType` gains `tea`, `teaPortafilter`, `filter`; `_parseBeverageType` and `toJson` must map `teaPortafilter` ↔ `tea_portafilter` explicitly rather than relying on `.name`.
- **`lib/src/models/data/profile_hash.dart`** — beverage type is part of the profile hash, so the 15 retyped profiles change hash. Check what that invalidates before landing.
- **`assets/defaultProfiles/`** — 25 files rewritten (10 content, 15 beverage type), one added (`A-Flow____default-light.json`).
- **`assets/defaultProfiles/manifest.json`** — one new entry.
- **`test/profiles/`** — a regression test beside the existing `default_profiles_bundled_test.dart`.
- **Migration** — `default_profiles_migration_test.dart` implies a path already exists for corpus changes; whether corrected profiles should reach users who already hold a copy is a decision this change must make, not inherit.
- **Unchanged** — the runtime import path (`de1app_importer.dart`, `tcl_parser.dart`, `profile_v2_parser.dart`), all profile handling in the app, and the DE1 upload path.
- **Upstream, not blocking** — de1app [#350](https://github.com/decentespresso/de1app/issues/350) tracks the A-Flow shadowing. Harvesting from the plugin directory makes this project correct regardless of how it resolves; the provenance guard keeps that true if the canonical directory later moves.
- **Cross-check available** — Decenza (`Kulitorum/Decenza`) regenerates these frames through de1app's own builders and can supply reference JSON for all eleven, so the synthesis port can be validated against a second implementation rather than only against itself.
