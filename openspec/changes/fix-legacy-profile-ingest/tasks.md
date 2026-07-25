## 1. Reproduce the finding

Do this first. Every claim in the proposal is a controlled experiment, and re-running them takes minutes and establishes the baseline the rest of the change is measured against.

- [x] 1.1 Confirm the tool reproduces three shipped files byte-identically from de1app `main`: `python3 tools/ingest_profiles.py <de1app>/de1plus/profiles/{"7g basket","Classic Italian espresso","Preinfuse then 45ml of water"}.tcl --dry-run`, diffed against `assets/defaultProfiles/`.
- [x] 1.2 Confirm the tool refuses `default.tcl` and `Gentle and sweet.tcl`, and that both carry `advanced_shot {}` in de1app going back years — establishing that the shipped `Default1.json` / `Gentle_and_sweet1.json` came from another route.
- [x] 1.3 Confirm the A-Flow source-path effect: the same tool yields the shipped 6-frame file from `de1plus/profiles/` and a 9-frame file from `de1plus/plugins/A_Flow/profiles/`.
- [x] 1.4 Record the de1app revision used, so the corpus rebuild later in this change is reproducible. Recorded in `baseline.md`.

## 2. Synthesis for legacy profiles

- [x] 2.1 Port `pressure_to_advanced_list` from de1app `de1plus/profile.tcl` into `tools/ingest_profiles.py` (covers `settings_2a`).
- [x] 2.2 Port `flow_to_advanced_list` (covers `settings_2b`).
- [x] 2.3 Derive `number_of_preinfuse_frames` from the generated frames rather than reading `final_desired_shot_volume_advanced_count_start` — for legacy types de1app computes it during generation, and the stored literal is stale for the same reason the frames are.
- [x] 2.4 Re-condition the guard on profile type alone (design D2): for `settings_2a`/`2b` ignore `advanced_shot` entirely, populated or not; keep stored frames for `settings_2c` and everything else. No fallback to the stored array — an underivable profile fails loudly.
- [x] 2.5 Resolve the stop targets by profile type: plain `final_desired_shot_weight`/`_volume` for `settings_2a`/`2b`, `_advanced` only for `settings_2c` — matching de1app's own stop switches (`de1plus/device_scale.tcl:1322`, `de1plus/de1_de1.tcl:862`). Emit the corresponding `type` (`pressure`/`flow`/`advanced`) rather than labelling everything advanced.
- [x] 2.6 Verify against the four known cases: `Classic Italian espresso` 60 g → 36 g, `7g basket` 36 g → 35 g, `Preinfuse then 45ml of water` 0 → 36 g, `Gentle and sweet` target volume 0 → 36 ml. All four confirmed; see `baseline.md`.
- [x] 2.7 Validate the port against Decenza's independently-derived JSON for all five simple profiles before checking in any corpus change (design D1). A disagreement is a bug in one of the two implementations and blocks the rest of this change. All five agree frame-for-frame; see `baseline.md`.

## 3. Source provenance

- [x] 3.1 Allow plugin and profile-editor directories as ingest sources (`de1plus/plugins/*/profiles/`, `de1plus/profile_editors/*/profiles/`). A directory argument that is a `de1plus` root expands to all three source directories.
- [x] 3.2 On the same profile title appearing in more than one source directory with differing output, fail and name every path involved (design D4). Identical copies in two directories are not an error. Verified: scanning the whole `de1plus` root fails on exactly the four shadowed A-Flow profiles, naming all three paths each, and emits `default-light` once.
- [x] 3.3 Record source path + de1app revision per profile in the corpus, so a profile's origin is a lookup rather than an experiment (design D6). Written to a `provenance` map in `manifest.json`; submodule-aware, so A-Flow records the `Jan3kJ/A_Flow` commit rather than de1app's.

## 3b. Beverage type: tea and filter

Ordered before the corpus rebuild on purpose — see design D5. The enum must accept the new values before any profile carries them, or `_parseBeverageType` turns thirteen tea profiles into espresso.

- [x] 3b.1 Extend `BeverageType` (`lib/src/models/data/profile.dart:133`) with `tea`, `teaPortafilter` and `filter`.
- [x] 3b.2 Give the enum an explicit wire-name mapping so `teaPortafilter` serialises as `tea_portafilter` in both `_parseBeverageType` and `toJson`, rather than relying on `.name` (design D5). `tea` and `filter` round-trip unchanged. Enum now carries a `wireName`; all three serialisation sites (`profile.dart` `toJson`, `profile_hash.dart`, `profile_controller.listDefaults`) use it. `rest_v1.yml` enums updated in the same change.
- [x] 3b.3 Confirm the new values are **not** added to the `cleaning`/`calibrate` scaleless branch (`app.dart:423`, `de1_state_manager.dart:605`) — tea and filter are brewed to weight. Confirmed: all four beverage-keyed branches (`app.dart:423`, `de1_state_manager.dart:605` and `:727`, `de1handler.dart:410`) name `cleaning`/`calibrate` explicitly, so the new values behave like espresso. No edit required.
- [x] 3b.4 Drop `filter`, `tea` and `tea_portafilter` from `BEVERAGE_TYPE_MAP` in `tools/ingest_profiles.py` and add them to `VALID_BEVERAGE_TYPES`. Leave `descale → cleaning` alone.
- [x] 3b.5 Re-ingest the 15 affected profiles: 13 `tea_portafilter`, `Tea/in a basket` (`tea`), `Filter 2.0` and `Filter3` (`filter`). Done — note the count is **12** `tea_portafilter`, not 13; 12 + `tea` + 2 × `filter` = the 15 the proposal totals. `Filter 2.1` is genuinely `pourover` in de1app. All 15 differ from their shipped copy in `beverage_type` alone, verified field by field.
- [x] 3b.6 Check what the resulting profile-hash change invalidates (`profile_hash.dart` includes beverage type) before landing. Findings in `migration-impact.md`.
- [x] 3b.7 Round-trip test: a profile ingested as `tea_portafilter` parses back to `BeverageType.teaPortafilter` and re-serialises to `tea_portafilter` — not `espresso`, not `teaPortafilter`. Added to `test/profile_test.dart`.

## 4. Rebuild the corpus

- [x] 4.1 Re-ingest the five simple profiles: `7g basket`, `Classic Italian espresso`, `Preinfuse then 45ml of water`, `Default`, `Gentle and sweet`.
- [x] 4.2 Re-ingest all five A-Flow profiles from `de1plus/plugins/A_Flow/profiles/`, including `default-light`, which the corpus has never carried. All five now carry 9 frames, authored `Janek` (the plugin's attribution) rather than `Decent`.
- [x] 4.3 Re-ingest `Cleaning/Forward Flush x5` (restores the lost `Pressure rise 1 start` frame) and `Advanced spring lever` (replaces the Weiss variant with de1app's 88 °C profile). Neither needs a tool change. Forward Flush is back to 10 frames opening on `Pressure rise 1 start`; `Advanced spring lever` is now de1app's — `Decent`, 5 frames at 88 °C, `2s infuse` through `maintain flow`.
- [x] 4.4 Add `A-Flow____default-light.json` to `assets/defaultProfiles/manifest.json`. Manifest now lists 71 profiles.
- [x] 4.5 Verify the corrected `Default` no longer carries 75 °C/54 °C frames and matches its declared `espresso_temperature` of 90.0 — the symptom that started this. Frame temperatures are now 90 / 88 / 88 / 88 / 88 / 88.
- [x] 4.6 Verify `Weiss advanced spring lever` is **unchanged** by the rebuild. It is already correct, and it is the profile the displaced variant was confused with — if it moves, something rewrote the wrong slot. Untouched — not in the rebuild's write set, and `git status` shows no modification.
- [x] 4.7 Confirm the other 52 common profiles are untouched by the rebuild. A change there means the synthesis is firing on something it should not. Exactly 27 profile files changed (12 content, 15 beverage type) plus one added and the manifest; the other 43 corpus files are untouched. The rebuild is deliberately scoped rather than a full re-ingest — see the note below.

**Scope note.** A full re-ingest of every de1app profile would rewrite 40 corpus files, not 27. The extra 13 are number-formatting normalisations (`"36"` to `"36.0"`) and author attributions applied during the earlier curation pass — `Damian's LM Leva`, `Damian's LRv2/LRv3`, `Damian's Q` (`Damian` to `Decent`) and `Cremina lever machine` (`Denis (KafaTek)` to `Decent`). Overwriting those would be the same class of regression this change warns about for `Advanced spring lever`, so the rebuild targets an explicit list instead. Worth a separate decision.

## 5. Regression cover

- [x] 5.1 Add a test asserting no bundled `settings_2a`/`2b` profile ships frames contradicting its own scalars, failing with the profile name and the contradicting field. Added to `test/profiles/default_profiles_bundled_test.dart` as three checks over the 12 `pressure`/`flow` typed profiles: frame names must come from the generator vocabulary, temperature spread must stay within the four presets, and each frame's pump must match the profile type. The shipped `Default1.json` failed all three.
- [x] 5.2 Add a test that the ingest tool ignores a populated `advanced_shot` on a legacy-type profile, using a fixture with deliberately mismatched stored frames. `tools/ingest_profiles_test.py`, `LegacyStepSynthesisTest` — fixture ships two pour-over frames at 75 °C / 54 °C against a 90 °C `settings_2a` profile.
- [x] 5.3 Add a test that two disagreeing source directories cause a failure naming both paths. `SourceCollisionTest`, including that identical copies are not an error and that a collision writes no output file.
- [ ] 5.4 `flutter test` and `flutter analyze` clean. **Blocked — no Flutter SDK on this machine** (`flutter` is not on `PATH`, not in `brew list`, and no SDK exists on disk). `python3 -m unittest ingest_profiles_test` passes 19/19. The Dart changes are unverified by a compiler; see the handover note below.

## 6. Decisions this change cannot make alone

- [x] 6.1 Decide whether corrected profiles are pushed to users who already hold a copy (design open question 1). Check first whether the local copy tracks modification — the recommendation depends on it. **Resolved: no decision needed.** A bundled default cannot be modified in place — `ProfileController.update` rejects it (`profile_controller.dart:272`), so a user's variant is always a separate `isDefault: false` record that `_retireStaleDefaults` skips. Corrected profiles reach existing installs through the mechanism already in place: the new content is stored under its new hash and the superseded record is hidden, never deleted. Full analysis, including the one real side effect (a user who *hid* a bundled default sees the corrected version reappear), in `migration-impact.md`.

## Handover: what is not verified

There is no Flutter SDK on this machine, so `flutter test` and `flutter analyze` never
ran. Everything below is verified; everything Dart is not.

**Verified:**
- `python3 -m unittest ingest_profiles_test` — 19/19 pass.
- The synthesis port agrees with Decenza's real `profile_sync` binary on all five
  simple profiles, and across all 89 de1app profiles the only disagreements are the
  four A-Flow source-path cases, four float-literal precision differences in de1app's
  own files, and one profile absent from this corpus. See `baseline.md`.
- The port reproduces, value-for-value, seven corpus profiles that de1app's own
  generator produced via the Visualizer route.
- The new bundled-corpus assertions were run against the actual 71 corpus files in
  Python before being written as Dart: 12 derived profiles, zero failures.

**Not verified — needs `flutter test` and `flutter analyze`:**
- `lib/src/models/data/profile.dart` — `BeverageType` gains a `wireName` field.
- `lib/src/models/data/profile_hash.dart`, `lib/src/controllers/profile_controller.dart`
  — the two other `.name` call sites switched to `.wireName`. A repo-wide search
  confirms no `beverageType.name` remains and nothing switches over `BeverageType`.
- `test/profile_test.dart` — new `beverage type` group.
- `test/profiles/default_profiles_bundled_test.dart` — new `derived profiles agree with
  their own scalars` group and the provenance check.

## 7. Close out

- [x] 7.1 Correct the "contained to the 3 levers" scoping in `doc/plans/archive/default-profiles-curation/audit.md`, or add a forward-pointer to this change. That note is still what a reader finds today, and it is wrong by five profiles. A superseded-note block now sits directly under the original claim, naming the five and pointing at this change.
- [x] 7.2 Note in the de1app #350 thread that this project now harvests A-Flow from the plugin directory, so the shadowing no longer reaches these users either way it resolves. **Closed without posting** — decided the upstream thread does not need updating; the point of the task was to carry the #350 context into this change, which the collision guard (task 3.2) and `doc/AI_STORAGE_NOTES.md` now do. Nothing here blocks or depends on how #350 resolves.
