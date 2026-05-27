# Default Profiles Curation (#242)

Fix wrong/stale names, leftover "Downloaded from Visualizer" notes, duplicates,
content-vs-description mismatches, and author attribution across the bundled
default profiles in `assets/defaultProfiles/`. Add a one-time migration so users
who already imported the stale versions get the corrected ones.

GitHub issue: tadelv/reaprime#242 (reporter NilsBruch; owner tadelv confirms the
profiles were pulled from Visualizer + de1app copy-exports and need a curation +
attribution pass).

## Problem classes

1. **Leftover provenance text in notes** — 8 profiles contain "Downloaded from
   Visualizer"/Visualizer boilerplate: `advanced_spring_lever`, `baseline_hc`,
   `baseline_lc`, `baseline_ulc`, `cremina`, `icbinf`, `rohan-soup`, `psph`.
2. **Title artifacts** —
   - `Visualizer/Baseline LC` (baseline_lc) — stray `Visualizer/` category prefix.
   - `Espresso/Baseline HC` (baseline_hc) — stray `Espresso/` prefix.
   - `Cleaning/Forward Flush x5 2` — trailing " 2" (de1app copy/version artifact).
   - `Filter3` — inconsistent vs `Filter 2.0`/`Filter 2.1`.
   - Suspected digit-suffix duplicates: `Rao Allongé 3` vs `Rao Allongé`,
     `Default` (Default1.json), `Gentle and sweet` (Gentle_and_sweet1.json).
   - NB: `\/` inside titles is JSON-escaped `/` — renders fine, **not** a bug.
3. **Duplicate profile** — `Tea_portafilter__Blue_Willow_Tsuyuhikari_Sencha.json`
   and `..._Tsuyuhikari_Sensha.json` have **identical steps** + near-identical
   notes, different titles (Sencha/Sensha typo). One is a stray copy; both are in
   the manifest.
4. **Content ≠ description** — `Flow profile for milky drinks`: steps are
   `preinfusion=flow`, `rise and hold=pressure`, `decline=pressure` — the pour is
   pressure-controlled despite the "Flow profile" name/description. Confirmed
   stale/wrong import. Likely not the only one; every profile needs a pass.

## Codebase mechanics (researched)

### Where / how defaults load
- `assets/defaultProfiles/*.json` (74 files) + `manifest.json` (the load list).
- Display name = `title` field (`lib/src/models/data/profile.dart:49`).
- Seeding: `ProfileController.initialize()` → `_loadDefaultProfilesIfNeeded()`
  (`lib/src/controllers/profile_controller.dart:23–100`), called from
  `lib/main.dart:276–279`. **Runs every launch**, not just first install.
- Per-profile guard (`profile_controller.dart:63–79`): looks up `_storage.get(record.id)`
  where `id == profileHash`. If found and already `isDefault && visible` → skip.
  If found but not-default/hidden → re-assert default+visible. If not found → store.
- Default profiles tagged `isDefault: true` + `metadata: {source: bundled, filename}`
  (`profile_controller.dart:58–59`). Same `ProfileRecords` table as user profiles;
  `isDefault` is the only distinguisher. Defaults can't be deleted, only hidden
  (`profile_controller.dart:254–258`).

### The hash model (this drives migration design)
`lib/src/models/data/profile_hash.dart`:
- `profileHash` = **execution fields only** (version, beverage_type, steps,
  tank_temperature, target_weight, target_volume, target_volume_count_start).
  This is the storage primary key (`ProfileRecord.id`).
- `metadataHash` = title + author + notes.
- `compoundHash` = both.

**Consequences:**
- **Metadata-only fix** (notes/title/author) → `profileHash` **unchanged** → the
  seeding guard finds the existing record and **skips it**, so the corrected
  metadata is *never picked up* by the normal path. Needs an explicit refresh.
- **Content fix** (e.g. milky drinks steps) → `profileHash` **changes** → seeding
  inserts a **new** profile; the old stale one stays `isDefault`+visible →
  duplicate. The old hash must be retired (hidden/removed).

### Existing migration hook
- Drift `AppDatabase`, `schemaVersion = 3`, `MigrationStrategy.onUpgrade`
  (`lib/src/services/database/database.dart:38–86`). No profile/data migration yet.
- No `profilesSeedVersion` gate in `SettingsService`.

## Authoritative sources for correct content

Per `CLAUDE.md`, de1app's **TCL** profile format is *not* authoritative here.
Canonical content comes from:
- **Visualizer** published JSON (where most were pulled from).
- **Author-supplied canonical text** when available.

### Baseline line — author `longpvo` (user-supplied canonical notes)
The `Baseline *` profiles are authored by **longpvo** (already correct in the
files). Canonical titles + notes to apply:

- **Baseline • Ultra Low Contact** (`baseline_ulc`): no pressure ceiling, bloom
  exit 0.5s, max flow, 20g:50g–60g (1:2.5–3). "let pressure and flow guide your
  grind / you can delete step #2 for no bloom".
- **Baseline • Low Contact • 4 Bar** (`baseline_lc`, retitle from
  `Visualizer/Baseline LC`): 2–4 bar, bloom exit 1.5 bar drop or 2s max, 6 mlps
  max, 20g:45g–50g (1:2.25–2.5). "extract LIGHT… if there isn't enough
  resistance, it will yeet".
- **Baseline • Medium Contact • 6 Bar** — *not currently shipped* (we have ULC/LC/HC
  only). longpvo: 4–6 bar, bloom exit 2 bar drop or 4s max, 4 mlps max,
  20g:40g–45g (1:2–2.25), "almost identical to ExDos". **Open question: add it?**
- **Baseline • High Contact • 8 Bar** (`baseline_hc`, retitle from
  `Espresso/Baseline HC`): 6–8 bar, bloom exit 3 bar drop or 6s max, 2.5 mlps max,
  20g:35g–40g (1:1.75–2). "extract LOUD"; HC-specific resistance/time-out tips.

Shared guidance to fold into the Baseline notes (temperature targets by roast,
dialing-in tips, Machine > Calibrate page 2 settings of Heater test time-out 30s /
flow 8 mlps) — captured verbatim from user message; apply consistently across the
Baseline set. Full text lives in the conversation/issue thread.

## Curation method

Per-profile audit, one row per file. For each of the 74:
1. Record current `title`, `author`, `notes`, step pump-types, beverage_type.
2. Compare against canonical source (Visualizer / author text).
3. Decide: **keep as-is**, **metadata-fix** (title/author/notes only), **content-fix**
   (steps/targets), **dedup/remove**, or **needs user decision**.
4. Track old `profileHash` (and new one if content changes) for the migration map.

Produce an audit table (in this doc or a sibling CSV) before editing files. Edits
are deterministic JSON changes. Ambiguous content calls (is this profile "wrong"
or just a variant?) go to the user — Vid has the domain knowledge.

Known decisions queued:
- Drop one of Sencha/Sensha tea dup (identical steps). Keep the correctly-spelled
  "Sencha", remove "Sensha"; update `manifest.json`.
- Strip Visualizer boilerplate from the 8 notes.
- Retitle `Visualizer/Baseline LC`, `Espresso/Baseline HC`,
  `Cleaning/Forward Flush x5 2`, reconcile `Filter3`.
- Investigate `Rao Allongé 3` / `Default1` / `Gentle_and_sweet1` for true dups.
- Fix milky-drinks content (or rename if pressure-control is actually intended).

## Migration design (schemaVersion 4)

Two mechanisms, both idempotent:

**M1 — metadata refresh for unchanged-content defaults.**
Change `_loadDefaultProfilesIfNeeded()` so that when an existing `isDefault`
record is found by `profileHash`, it also compares the bundled `metadataHash`
against the stored one and **updates title/author/notes** (recompute metadata +
compound hashes) when they differ. Safe because a user-edited default would have a
*different* `profileHash* (new record, `isDefault:false`), so the matched
`isDefault` record is always the pristine default. This makes metadata fixes
self-applying on next launch — no version gate needed.

**M2 — retire content-changed defaults.**
For profiles whose *content* (steps/targets) changed, the new JSON seeds as a new
record automatically. The stale old record must be hidden. Maintain an explicit
`retiredDefaultProfileHashes` list (old `profileHash` → reason). A Drift v4
`onUpgrade` (or a one-time settings-gated routine in `ProfileController`) hides
any stored default whose id is in that list and is still visible. Gate with a new
`profileCurationVersion` in `SettingsService` so it runs once.

Open choice: implement M2 as a Drift migration vs. a settings-gated pass in
`ProfileController.initialize()`. Lean toward the controller pass — it already
owns default seeding and has the `Profile`/hash types loaded; Drift `onUpgrade`
operates at raw-SQL level and would duplicate hash logic.

## Testing

- Unit test asserting **no bundled profile** has "Downloaded from"/Visualizer
  boilerplate in notes, and no `title` has a category prefix (`Visualizer/`,
  `Espresso/`) or a trailing `\s\d+$` artifact.
- Unit test: every filename in `manifest.json` exists and parses; no duplicate
  `profileHash` across the bundled set (catches accidental copies like Sencha/Sensha).
- Migration tests:
  - M1: seed an old-metadata default, run seeding with corrected bundled metadata,
    assert title/author/notes updated and `profileHash` stable.
  - M1 negative: a user profile with same content but different author is NOT
    overwritten.
  - M2: a retired-hash default present + visible → hidden after migration; runs
    once (version gate); user profiles untouched.
- End-to-end: `sb-dev` + `GET /api/v1/profiles` shows corrected titles; milky-drinks
  reflects fixed content. (See `.agents/skills/decent-app/verification.md`.)

## Phases

- **P0 — Audit.** ✅ Per-profile audit in `default-profiles-audit.md`; 5 dup groups
  + lever corruption found; decisions captured.
- **P1 — Mechanical fixes.** ✅ Stripped Visualizer notes (8), Baseline retitles +
  longpvo notes (ulc/lc/mc/hc), `Cleaning/Forward Flush x5`, author overrides.
- **P2 — Content + dedup.** ✅ Removed Sencha, Bug Bite Oolong, white tea (dup
  collisions); re-ported lever trio + milky/straight from Visualizer (distinct);
  added Baseline MC; authors finalized; Soup 58/PSPH notes stubbed. Manifest 73→71.
- **P3 — Migration.** ✅ Dynamic, hash-free: M1 refreshes default metadata when the
  bundled `metadataHash` changes; M2 (`_retireStaleDefaults`) hides defaults whose
  `metadata.filename` left the manifest or whose id ≠ current bundled id. Hidden,
  not deleted. Tests: `test/profiles/default_profiles_migration_test.dart` (4),
  `default_profiles_bundled_test.dart` (5). Full suite 1360 green, analyze clean.
- **P4 — Verify + docs.** Remaining: end-to-end `sb-dev` smoke (GET /profiles on a
  fresh simulate DB); check `doc/Profiles.md`; archive this plan + audit.

## Deferred (accepted, not actioned)
- Suspected dups left in place pending per-item decision: `Rao Allongé 3` vs
  `Rao Allongé`, `Default1`, `Gentle_and_sweet1` (titles already clean; filenames
  cosmetic).
- Soup 58 / PSPH correct notes — stubbed; need a real source.

## Decisions (user-confirmed)

1. **Add Baseline • Medium Contact • 6 Bar** (longpvo set has 4; we ship 3).
   Source/build the MC variant ("almost identical to ExDos") + add to manifest.
2. **Milky drinks → restore de1app's distinct params** (revised after de1app
   check; supersedes the earlier "convert to flow"). de1app keeps the pour
   *pressure*-controlled and differentiates milky vs straight by temperature +
   hold flow: milky **88°C / flow_profile_hold 1.2**, straight **92°C / 2.0**.
   Our two JSONs are byte-identical (we shipped milky = a copy of straight).
   Fix = faithful TCL→JSON conversion of de1app's milky-drinks into our Decent
   JSON v2 format (do **not** hand-invent step values; verify the converted
   profile round-trips via `sb-dev`). → content change → M2 retire list.
3. **Dedup: flag all, remove none without sign-off.** Surface every suspected dup
   (Sencha/Sensha, `Rao Allongé 3`, `Default1`, `Gentle_and_sweet1`) in the P0
   audit; user decides each individually before any removal.
4. **Attribution policy: `Decent` default + community overrides.** de1app records
   every real profile as `author Decent` (verified), so it's not an attribution
   source. Keep `Decent` as the default (matches de1app) and override only with
   user-confirmed community authors. Confirmed so far: Baseline line → `longpvo`;
   Soup 58 + ICBINF → `Rohan`; D-Flow + Damian's LM Leva/LRv2/LRv3/Q → `Damian`.
   (Visualizer-scraping for more authors was declined this pass.)
5. **Migration aggressiveness:** retire stale defaults by **hiding** (recoverable),
   never hard-delete.

## Dependencies (canonical content to obtain)

- **Flow-controlled "milky drinks"** step JSON — from Visualizer/Decent canonical.
- **Baseline • Medium Contact • 6 Bar** step JSON — from longpvo (Visualizer/Discord).
- Per-profile canonical sources for the full author audit.
  → These may need the user to supply JSON/links where not on Visualizer.
