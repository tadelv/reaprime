# Default Profiles — P0 Audit (#242)

Generated from `assets/defaultProfiles/` — 73 files. Signature = approximate execution-field hash (dup detection within the set; not the Dart profileHash).

Files in manifest: 73 · files on disk: 73

## P2 dup-group decisions (user-confirmed)

- **G1 Sencha≡Sensha:** drop `..._Tsuyuhikari_Sensha.json` (misspelled, garbled
  note), keep `Sencha`. Remove from manifest + retire hash.
- **G2 Bug Bite Oolong≡oolong dark:** drop `Tea_portafilter__Blue_Willow_Black_Honey_Oolong.json`
  (Blue-Willow copy, untuned), keep generic `tea_portafilter_oolong_dark.json`.
- **G3 Chinese green≡white tea:** ~~keep both~~ → **drop white tea**, keep
  Chinese green. ("Keep both" is impossible: byte-identical content → identical
  content-hash `id` → they collide in storage; only one record can exist. Removed
  `tea_portafilter_white.json` + manifest entry.)
- **G4 lever trio:** keep all three, restore de1app distinct params —
  Traditional 9 bar, Trendy **6 bar**, Two-spring **temp 94**. Content change → M2.
- **G5 milky≡straight:** restore de1app params (milky 88°C/hold 1.2, straight
  92°C/2.0). Content change → M2.

**Applied:** G1 + G2 removals done (manifest 73→71, files deleted); authors
advanced_spring_lever→John Weiss, cremina→Denis (KafaTek); icbinf+rohan-soup→Rohan
(ICBINF confirmed Rohan over the stale "Joe D." note).

**Blocked on user-supplied Visualizer JSON** (decided source):
- Lever trio re-port (G4) — de1app `advanced_shot` is garbage, need real JSON.
- Baseline • Medium Contact • 6 Bar (new profile).
- Milky-drinks differentiation (G5) — align to de1app intent (88°C/gentler).
- Correct notes for icbinf / rohan-soup / psph (shared wrong "Joe D." copy-paste).

**P3 migration** built after content is final (retire-list needs exact Dart
profileHashes of the removed/changed profiles — computed via a Dart helper).

## ⚠ Lever-trio corruption (deeper than param drift)

de1app's lever profiles are `settings_2a` **simple-pressure** profiles (real
intent in `espresso_pressure`/preinfusion/decline fields), but their TCL also
carries a **stale `advanced_shot`** field full of pour-over steps
(Prewet/Main water #1+#2/Drain, pump=flow, 99/97/95°C) that contradicts the
9-bar intent. Our import took the stale `advanced_shot` → all three lever JSONs
contain pour-over steps, not lever-pressure behavior. (That's why they grouped
as an identical-signature dup.)

- **Scope: contained to the 3 levers.** A scan of all espresso profiles for the
  pour-over step pattern found only the 3 levers + `Preinfuse_then_45ml_of_water`
  (the latter is legitimately a water profile). Other espresso profiles imported
  with sensible steps.
- **Fix is a re-port, not a param edit:** de1app's `advanced_shot` is the garbage,
  so it can't be the source. Correct lever JSON must be authored from the
  simple-pressure settings (9 / 6 / two-spring) or sourced from Visualizer, then
  verified via `sb-dev`. → blocked on sourcing decision.
- **Importer implication:** whatever produced these defaults preferred de1app's
  `advanced_shot` even for `settings_2a` profiles where it's stale. Worth a look
  at the import path separately (out of scope for this curation).

By contrast, **milky (G5)** has a structurally-sound pressure profile
(preinfusion/rise-and-hold/decline) — only the params need aligning to
differentiate it from straight espresso. Surgical, feasible without re-port.

## Content duplicates (identical execution signature)

- sig `3006d6ea3e19`: `Tea_portafilter__Blue_Willow_Tsuyuhikari_Sencha.json` (Tea portafilter/Sencha) · `Tea_portafilter__Blue_Willow_Tsuyuhikari_Sensha.json` (Tea portafilter/Blue Willow: Tsuyuhikari Sensha)
- sig `594e982af215`: `Flow_profile_for_milky_drinks.json` (Flow profile for milky drinks) · `Flow_profile_for_straight_espresso.json` (Flow profile for straight espresso)
- sig `89644945500d`: `tea_portafilter_chinese_green.json` (Tea portafilter/Chinese green) · `tea_portafilter_white.json` (Tea portafilter/white tea)
- sig `b83d917bfe62`: `Traditional_lever_machine.json` (Traditional lever machine) · `Trendy_6_bar_low_pressure_shot.json` (Trendy 6 bar low pressure shot) · `Two_spring_lever_machine_to_9_bar.json` (Two spring lever machine to 9 bar)
- sig `fc2f34589438`: `Tea_portafilter__Blue_Willow_Black_Honey_Oolong.json` (Tea portafilter/Bug Bite Oolong) · `tea_portafilter_oolong_dark.json` (Tea portafilter/oolong dark)

## Author distribution (as shipped)

- `Decent`: 69
- `longpvo`: 3
- `Damian`: 1

## Confirmed author corrections (user-supplied, accumulating)

| file | title | shipped author | correct author |
|---|---|---|---|
| `baseline_ulc.json` | Baseline • Ultra Low Contact | longpvo | longpvo (ok) |
| `baseline_lc.json` | Baseline • Low Contact • 4 Bar | longpvo | longpvo (ok) |
| `baseline_hc.json` | Baseline • High Contact • 8 Bar | longpvo | longpvo (ok) |
| `rohan-soup.json` | Soup 58 | Decent | **Rohan** |
| `icbinf.json` | I Can't Believe It's Not Filter | Decent | **Rohan** |
| `D-Flow____default.json` | D-Flow / default | Damian | Damian (ok) |
| `Damian_s_LM_Leva.json` | Damian's LM Leva | Decent | **Damian** |
| `Damian_s_LRv2.json` | Damian's LRv2 | Decent | **Damian** |
| `Damian_s_LRv3.json` | Damian's LRv3 | Decent | **Damian** |
| `Damians_Q.json` | Damian's Q | Decent | **Damian** |

_Still TBD (need user): EspressoForge (Dark/Light), Londonium, Cremina,
Extractamundo Dos, Rao Allongé, A-Flow line, Weiss advanced spring lever, etc._

## de1app cross-reference (authoritative source check)

Checked local clone `~/development/repos/de1app/de1plus/profiles/*.tcl` (88 files).

- **Attribution dead end:** every real profile has `author Decent` (the only
  non-Decent is `Test_profile_editor_demo` → Damian). de1app does **not** record
  community authorship. So longpvo / Rohan / Damian / etc. attribution is
  community knowledge, not in the source. → Policy decision needed (below).
- **Canonical titles confirmed:** `Cleaning/Forward Flush x5` (our " 2" is an
  artifact — drop it), `Rao Allongé` (no trailing 3), **`Filter3` is de1app's
  actual title** (not an artifact — leave it), `Default`, `Gentle and sweet`.
- **Milky-drinks real bug:** de1app ships *distinct* milky vs straight-espresso
  profiles — same step shape (`flow`/`pressure`/`pressure`) but different params:
  milky = **88°C / flow_profile_hold 1.2**, straight = **92°C / hold 2.0**. **Our**
  two JSONs are byte-identical (declining 84/81/78, hold n/a) → we shipped milky
  as a verbatim copy of straight espresso. The **pour is pressure-controlled in
  de1app too** — the reporter's "flow pour" memory is not supported by the
  authoritative source. Fix = restore the milky/straight distinction, not convert
  to flow. (Supersedes the earlier "fix → flow" decision.)

## P1 applied (metadata-only, profileHash stable)

Edited 13 files: stripped Visualizer suffix (advanced_spring_lever, cremina,
icbinf, rohan-soup, psph); Baseline retitles + longpvo notes (ulc/lc/hc);
`Cleaning/Forward Flush x5` (dropped " 2"); authors icbinf+rohan-soup→Rohan,
Damian's LM Leva/LRv2/LRv3/Q→Damian.

### Conflicts to resolve in P2 (updated after Visualizer + blog check)
- **ICBINF notes are CORRECT** — they match the canonical Visualizer profile
  (shot 34caff10…, linked from Rohan's blog). Not a copy-paste error. Leave them.
  - **ICBINF author is 3-way ambiguous:** canonical Visualizer `author: Decent`,
    notes credit "By Joe D.", but blog (pocketsciencecoffee = **Rohan**) is by the
    stated creator. Currently set to Rohan per user. Needs final call + decide
    whether to amend the note's "By Joe D." line.
  - Blog clue: ICBINF is Rohan's filter-on-espresso (1 mlps, 96°C, coarse,
    porcupress, optional bloom usually off, optional 3°C/min decline). Steps match.
- **Soup 58 + PSPH carry ICBINF's notes verbatim** — that's the real copy-paste
  error. Their true notes/authors unknown (no source found yet). Pending.
- **Embedded author clues applied:** advanced_spring_lever → John Weiss; cremina
  → Denis (KafaTek).

## Flagged files

- `Cleaning__Forward_Flush_x5_2.json` — **title:trailingnum** — title "Cleaning/Forward Flush x5 2", author `Decent`
- `Default1.json` — **file:trailingnum** — title "Default", author `Decent`
- `Flow_profile_for_milky_drinks.json` — **name:flow!=pressure** — title "Flow profile for milky drinks", author `Decent`
- `Flow_profile_for_straight_espresso.json` — **name:flow!=pressure** — title "Flow profile for straight espresso", author `Decent`
- `Gentle_and_sweet1.json` — **file:trailingnum** — title "Gentle and sweet", author `Decent`
- `Rao_Allongé_3.json` — **title:trailingnum** — title "Rao Allongé 3", author `Decent`
- `Tea_portafilter__Blue_Willow_black_phoenix_1.json` — **file:trailingnum** — title "Tea portafilter/Oolong 1st extraction", author `Decent`
- `Tea_portafilter__Blue_Willow_black_phoenix_2.json` — **file:trailingnum** — title "Tea portafilter/Oolong 2nd extraction", author `Decent`
- `Trendy_6_bar_low_pressure_shot.json` — **name:pressure!=flow** — title "Trendy 6 bar low pressure shot", author `Decent`
- `advanced_spring_lever.json` — **notes:visualizer** — title "Advanced spring lever", author `Decent`
- `baseline_hc.json` — **notes:visualizer,title:prefix** — title "Espresso/Baseline HC", author `longpvo`
- `baseline_lc.json` — **notes:visualizer,title:prefix** — title "Visualizer/Baseline LC", author `longpvo`
- `baseline_ulc.json` — **notes:visualizer** — title "Baseline ULC", author `longpvo`
- `cremina.json` — **notes:visualizer** — title "Cremina lever machine", author `Decent`
- `icbinf.json` — **notes:visualizer** — title "I Can't Believe It's Not Filter", author `Decent`
- `kalita_20.json` — **file:trailingnum** — title "Pour over basket/Kalita 20g in, 340ml out", author `Decent`
- `psph.json` — **notes:visualizer** — title "PSPH", author `Decent`
- `rohan-soup.json` — **notes:visualizer,title:trailingnum** — title "Soup 58", author `Decent`

## Full table

| file | title | author | bev | step pumps | sig | flags | class |
|---|---|---|---|---|---|---|---|
| 7g_basket.json | 7g basket | Decent | espresso | flow/flow/pressure/pressure | 49f94506d045 |  | |
| 80s_Espresso.json | 80's Espresso | Decent | espresso | flow/flow/pressure/pressure | 73c9c61ca0fb |  | |
| A-Flow____default-dark.json | A-Flow / default-dark | Decent | espresso | flow/pressure/pressure/pressure/flow/flow | 3153da2639f7 |  | |
| A-Flow____default-like-dflow.json | A-Flow / default-like-dflow | Decent | espresso | flow/pressure/pressure/pressure/flow/flow | c40027e18ebf |  | |
| A-Flow____default-medium.json | A-Flow / default-medium | Decent | espresso | flow/pressure/pressure/pressure/flow/flow | bc98e5facc90 |  | |
| A-Flow____default-very-dark.json | A-Flow / default-very-dark | Decent | espresso | flow/pressure/pressure/pressure/flow/flow | 89f121cac5cb |  | |
| Blooming_allonge.json | Blooming Allongé | Decent | espresso | flow/flow/flow/flow/flow/flow | 17824e2bae98 |  | |
| Blooming_espresso.json | Blooming Espresso | Decent | espresso | flow/flow/flow/flow/flow/flow | b52c13d25fd7 |  | |
| Classic_Italian_espresso.json | Classic Italian espresso | Decent | espresso | flow/flow/flow/flow/flow | d4a3e37a7fae |  | |
| Cleaning__Forward_Flush_x5_2.json | Cleaning/Forward Flush x5 2 | Decent | cleaning | pressure/pressure/pressure/pressure/pressure/pressure/pressure/pressure/pressure | 02b07ddc65a6 | title:trailingnum | |
| D-Flow____default.json | D-Flow / default | Damian | espresso | pressure/pressure/flow | 877c65ba44f2 |  | |
| Damian_s_LM_Leva.json | Damian's LM Leva | Decent | espresso | pressure/pressure/pressure/pressure/pressure/pressure | f2a608e83229 |  | |
| Damian_s_LRv2.json | Damian's LRv2 | Decent | espresso | pressure/pressure/pressure/pressure/pressure/pressure/flow | beb115f0ff81 |  | |
| Damian_s_LRv3.json | Damian's LRv3 | Decent | espresso | pressure/pressure/pressure/pressure/pressure/pressure/pressure/flow | 0a5ee3eff06c |  | |
| Damians_Q.json | Damian's Q | Decent | espresso | pressure/pressure/flow | 79dcffa32775 |  | |
| Default1.json | Default | Decent | espresso | flow/flow/pressure/pressure/pressure/pressure | 8caae45a781c | file:trailingnum | |
| EspressoForge_Dark.json | Espresso Forge Dark | Decent | espresso | flow/pressure/pressure/flow | 34d630963a6a |  | |
| EspressoForge_Light.json | Espresso Forge Light | Decent | espresso | flow/pressure/pressure/pressure/flow | 944ff430d4b0 |  | |
| Extractamundo_Dos.json | Extractamundo Dos! | Decent | espresso | pressure/pressure/flow/pressure | d08a243c56f8 |  | |
| Filter_20.json | Filter 2.0 | Decent | pourover | flow/flow/flow/flow | d76f00d620ec |  | |
| Filter_21.json | Filter 2.1 | Decent | pourover | flow/flow/flow/flow/flow/flow | d8c164e85cff |  | |
| Flow_profile_for_milky_drinks.json | Flow profile for milky drinks | Decent | espresso | flow/pressure/pressure | 594e982af215 | name:flow!=pressure | |
| Flow_profile_for_straight_espresso.json | Flow profile for straight espresso | Decent | espresso | flow/pressure/pressure | 594e982af215 | name:flow!=pressure | |
| Gentle_and_sweet1.json | Gentle and sweet | Decent | espresso | flow/flow/pressure/pressure/pressure | 9e85697a9325 | file:trailingnum | |
| I_got_your_back.json | I got your back | Decent | espresso | flow/flow/flow/flow/flow/flow | cea18bed191b |  | |
| Londonium.json | Londonium | Decent | espresso | pressure/pressure/pressure/pressure/pressure/pressure/flow | edd452fed252 |  | |
| Pour_over.json | Pour over basket/Decent pour over | Decent | pourover | flow/flow/flow/flow/flow/flow/flow | ca24ce4a441a |  | |
| Preinfuse_then_45ml_of_water.json | Preinfuse then 45ml of water | Decent | espresso | flow/flow/flow/flow/flow/flow | a909a7b500e8 |  | |
| Rao_Allongé_3.json | Rao Allongé 3 | Decent | espresso | flow | ce3f8a9dcc00 | title:trailingnum | |
| Tea_portafilter__Blue_Willow_Black_Honey_Oolong.json | Tea portafilter/Bug Bite Oolong | Decent | pourover | flow/pressure/flow/pressure/flow/pressure/flow/pressure/flow | fc2f34589438 |  | |
| Tea_portafilter__Blue_Willow_Tsuyuhikari_Sencha.json | Tea portafilter/Sencha | Decent | pourover | flow/pressure/flow/pressure/flow/pressure/flow | 3006d6ea3e19 |  | |
| Tea_portafilter__Blue_Willow_Tsuyuhikari_Sensha.json | Tea portafilter/Blue Willow: Tsuyuhikari Sensha | Decent | pourover | flow/pressure/flow/pressure/flow/pressure/flow | 3006d6ea3e19 |  | |
| Tea_portafilter__Blue_Willow_black_phoenix_1.json | Tea portafilter/Oolong 1st extraction | Decent | pourover | flow/pressure/flow/pressure/flow/pressure/flow | 0746d5f8165b | file:trailingnum | |
| Tea_portafilter__Blue_Willow_black_phoenix_2.json | Tea portafilter/Oolong 2nd extraction | Decent | pourover | flow/pressure/flow | 9075b4d153c8 | file:trailingnum | |
| Tea_portafilter__Blue_Willow_lunar_winter.json | Tea portafilter/Yunnan green | Decent | pourover | flow/pressure/flow/pressure/flow/pressure/flow | 20856995f0a5 |  | |
| Traditional_lever_machine.json | Traditional lever machine | Decent | espresso | flow/flow/flow/flow/flow/flow | b83d917bfe62 |  | |
| Trendy_6_bar_low_pressure_shot.json | Trendy 6 bar low pressure shot | Decent | espresso | flow/flow/flow/flow/flow/flow | b83d917bfe62 | name:pressure!=flow | |
| TurboBloom.json | TurboBloom | Decent | espresso | flow/flow/flow/pressure/pressure/pressure | 7e21debbb313 |  | |
| TurboTurbo.json | TurboTurbo | Decent | espresso | pressure/pressure/flow/pressure/pressure/pressure | fadfb219a8e9 |  | |
| Two_spring_lever_machine_to_9_bar.json | Two spring lever machine to 9 bar | Decent | espresso | flow/flow/flow/flow/flow/flow | b83d917bfe62 |  | |
| Weiss_advanced_spring_lever.json | Weiss advanced spring lever | Decent | espresso | flow/pressure/pressure/flow | 48117ab5bd91 |  | |
| adaptive_allonge.json | Gagné/Adaptive Allongé 94C v1.0 | Decent | espresso | flow/pressure/flow/flow/flow/flow/flow/flow/flow/flow/flow/flow/flow/flow/flow/flow/flow/flow/flow/flow | ef6e01d4b399 |  | |
| adaptive_espresso.json | Gagné/Adaptive Shot 92C v1.0 | Decent | espresso | flow/pressure/flow/flow/flow/flow/flow/flow/flow/flow/flow/flow/flow/flow/flow/flow/flow/flow/flow/flow | 70e901c1ac54 |  | |
| advanced_spring_lever.json | Advanced spring lever | Decent | espresso | flow/pressure/pressure/pressure/flow | 693e84be317c | notes:visualizer | |
| baseline_hc.json | Espresso/Baseline HC | longpvo | espresso | flow/flow/pressure | fee6104e6dd2 | notes:visualizer,title:prefix | |
| baseline_lc.json | Visualizer/Baseline LC | longpvo | espresso | flow/flow/pressure | c75a6dda1519 | notes:visualizer,title:prefix | |
| baseline_ulc.json | Baseline ULC | longpvo | espresso | flow/flow/flow | 2f2737ef807f | notes:visualizer | |
| best_practice.json | Adaptive v2 | Decent | espresso | flow/flow/pressure/pressure/pressure/flow/flow | 8f0e40f506c3 |  | |
| best_practice_light.json | Best practice (light roast) | Decent | espresso | pressure/pressure/pressure/pressure/flow | 4343fb6aa22f |  | |
| cold_brew.json | Pour over basket/Cold brew 22g in, 375ml out | Decent | pourover | flow/pressure/flow/pressure/flow/pressure/flow/flow | 4f344065ba11 |  | |
| cremina.json | Cremina lever machine | Decent | espresso | pressure/pressure/pressure/pressure/pressure | 546f75d1afd0 | notes:visualizer | |
| easy_blooming_active_pressure_decline.json | Easy blooming - active pressure decline | Decent | espresso | flow/flow/flow/pressure/pressure/pressure/pressure/pressure/pressure/pressure/pressure/pressure | ec1c52483cb0 |  | |
| filter3.json | Filter3 | Decent | pourover | flow/flow/flow/flow/flow/flow/flow | 5c4df891d984 |  | |
| icbinf.json | I Can't Believe It's Not Filter | Decent | espresso | flow/flow/flow/flow/flow/flow | 671251096965 | notes:visualizer | |
| kalita_20.json | Pour over basket/Kalita 20g in, 340ml out | Decent | pourover | flow/pressure/flow/pressure/flow/pressure/flow/flow | 9f52813d2c91 | file:trailingnum | |
| manual_flow.json | GHC/manual flow control | Decent | manual | flow/flow | 1a92d3e842d7 |  | |
| manual_pressure.json | GHC/manual pressure control | Decent | manual | pressure/pressure/pressure | 6ab0e3d2cacc |  | |
| psph.json | PSPH | Decent | espresso | flow/flow/flow | 0b4e11340675 | notes:visualizer | |
| rao_allonge.json | Rao Allongé | Decent | espresso | flow/flow | cd34bff04024 |  | |
| rohan-soup.json | Soup 58 | Decent | espresso | flow/flow/flow | 462f2bacc64d | notes:visualizer,title:trailingnum | |
| tea_in_a_basket.json | Tea/in a basket | Decent | pourover | flow/flow/flow/flow/flow/flow/flow/flow/flow/flow/flow/flow/flow/flow/flow/flow | 48344a625e3b |  | |
| tea_portafilter.json | Tea portafilter/black tea | Decent | pourover | flow/pressure/flow/pressure/flow/pressure/flow/flow | 9faca569cf07 |  | |
| tea_portafilter_chinese_green.json | Tea portafilter/Chinese green | Decent | pourover | flow/pressure/flow/pressure/flow/pressure/flow/flow | 89644945500d |  | |
| tea_portafilter_japanese_green.json | Tea portafilter/Japanese green | Decent | pourover | flow/pressure/flow/pressure/flow/pressure/flow/flow | a2b0ebfb6ad3 |  | |
| tea_portafilter_no_pressure.json | Tea portafilter/no pressure | Decent | pourover | flow/pressure/flow/flow/pressure/flow/flow/pressure/flow/flow/flow | b50c97b6bf2c |  | |
| tea_portafilter_oolong.json | Tea portafilter/oolong | Decent | pourover | flow/pressure/flow/pressure/flow/pressure/flow/flow | d740460be268 |  | |
| tea_portafilter_oolong_dark.json | Tea portafilter/oolong dark | Decent | pourover | flow/pressure/flow/pressure/flow/pressure/flow/pressure/flow | fc2f34589438 |  | |
| tea_portafilter_pressurized.json | Tea portafilter/Pressurized tea | Decent | pourover | flow/pressure/flow/pressure/flow/pressure/flow | 17a128ff2d67 |  | |
| tea_portafilter_tisane.json | Tea portafilter/tisane | Decent | pourover | flow/pressure/flow/pressure/flow/pressure/flow/flow | bde4923dba7d |  | |
| tea_portafilter_white.json | Tea portafilter/white tea | Decent | pourover | flow/pressure/flow/pressure/flow/pressure/flow/flow | 89644945500d |  | |
| v60-15g.json | Pour over basket/V60 15g in, 250g out | Decent | pourover | flow/pressure/flow/pressure/flow/pressure/flow | 61dda2c70b8a |  | |
| v60-20g.json | Pour over basket/V60 20g in, 340g out | Decent | pourover | flow/pressure/flow/pressure/flow/pressure/flow/flow | 8accb82d678e |  | |
| v60-22g.json | Pour over basket/V60 22g in, 375g out | Decent | pourover | flow/pressure/flow/pressure/flow/pressure/flow/flow | 526feb75c5dc |  | |
