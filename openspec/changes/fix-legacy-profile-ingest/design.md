## Context

The corpus in `assets/defaultProfiles/` was assembled from two sources — Visualizer uploads and de1app copy-exports — and `tools/ingest_profiles.py` is the tool for the second. Nine profiles are wrong, from three causes established by running the tool against de1app `main` and diffing its output against the shipped files.

That control matters, so it is worth stating what it proved rather than only what it suggested:

- `7g basket`, `Classic Italian espresso`, `Preinfuse then 45ml of water` — the tool reproduces the shipped file **byte-identically**, including the stale frames. These came through the tool and the tool would produce them again today.
- `A-Flow / default-dark` — the tool reproduces the shipped 6-frame file byte-identically **when pointed at `de1plus/profiles/`**, and produces a 9-frame file when pointed at `de1plus/plugins/A_Flow/profiles/`. The tool is correct; the source path was wrong.
- `Default`, `Gentle and sweet` — the tool **refuses** both today, because de1app has shipped `advanced_shot {}` for them since at least 2020. Their shipped frames could not have come from this tool. They arrived through the Visualizer/copy-export route the curation notes describe.

The last of those is the reason this design does not stop at "fix the guard". A guard fix repairs three profiles; it leaves two untouched and would leave the tool still unable to ingest them.

## Goals / Non-Goals

**Goals:**
- Make `settings_2a`/`2b` frames derived rather than copied, so the class cannot recur.
- Make the five simple profiles ingestible from de1app for the first time.
- Harvest A-Flow from the plugin directory and add the missing fifth profile.
- Make a wrong source directory a loud failure rather than a silent selection.
- Leave the corpus with recorded provenance, so the next question of this kind is answerable without re-running the experiment above.

**Non-Goals:**
- Any change to the app's runtime import path. `de1app_importer.dart` scans `profiles_v2` JSON and `tcl_parser.dart` never touches `advanced_shot`; this defect does not reach it.
- Fixing de1app. #350 is filed; this change makes the project correct regardless of how it resolves.
- Preserving the displaced Weiss variant. `Advanced spring lever` is restored to de1app's profile; retitling and keeping the variant is additive and can be done separately without conflicting with that.
- A general Tcl interpreter. Only two generator functions are needed.

## Decisions

### D1 — Port the synthesis; do not import corrected JSON from elsewhere

Decenza can supply correct JSON for all nine files immediately, and that is the cheaper path. It is the wrong one: it fixes today's corpus and leaves the tool unable to ingest a legacy profile tomorrow, so the next harvest reintroduces the class. Porting `pressure_to_advanced_list` / `flow_to_advanced_list` from de1app's `de1plus/profile.tcl` is bounded work — two functions over the profile's scalars — and it is what the tool's own error message already says is missing.

Decenza's output is used as a **cross-check**, not as a source: two independent implementations of the same de1app generator agreeing is meaningfully stronger than either alone, and it costs nothing since the files exist.

*Alternative rejected:* shelling out to a Tcl interpreter against de1app's real `profile.tcl`. It removes the reimplementation risk entirely, but makes the corpus build depend on a working Tcl install and a de1app checkout at a known revision. Worth reconsidering if the port proves fiddly.

### D2 — Key the guard on type, and make derivation total

The current guard fires on `not steps and settings_type in ("settings_2a","settings_2b")`. The `not steps` clause is the defect: it makes the check fire only in the case where copying would have been harmless anyway, and never in the case where it is destructive.

After this change, the type alone decides:

| type | frames |
|---|---|
| `settings_2a`, `settings_2b` | derived from scalars; `advanced_shot` ignored entirely |
| `settings_2c` and everything else | stored `advanced_shot` used as-is |

Ignoring the array *entirely* for legacy types — rather than preferring derivation and falling back to the stored copy — is deliberate. A fallback would reintroduce exactly the current behaviour for any profile the derivation does not yet handle, and it would do so silently. Failing loudly on an underivable profile is the property worth having.

### D3 — A-Flow is a source-path fix, not a tool fix

Re-running the existing tool against `de1plus/plugins/A_Flow/profiles/` produces the correct 9-frame output today. So the A-Flow work is: change which directory is harvested, add `default-light` to the corpus and the manifest, and prevent recurrence with D4.

Note both `de1plus/plugins/A_Flow` and `de1plus/profile_editors/A_Flow` are submodules of the same upstream repo (`Jan3kJ/A_Flow`) at the same commit, so either serves; the plugin path is the one de1app's own seeding logic uses.

### D4 — Disagreeing sources fail; they are not resolved by precedence

A precedence rule ("plugin wins") would fix today's symptom and is what Decenza currently does. It is fragile here for a specific reason: the A_Flow author has proposed resolving #350 the *opposite* way — deleting the defaults from the plugin and maintaining them in `de1plus/profiles/` instead. Under that resolution a "plugin wins" rule silently selects a deleted-then-stale file, or nothing.

Failing with both paths named is correct under either resolution, and costs one run of human attention on the day de1app changes.

### D5 — Beverage type keeps de1app's wire spelling, and the enum lands first

Two traps here, both cheap to avoid and both silent if missed.

**The wire spelling does not survive Dart naming conventions.** `_parseBeverageType` matches on `type.name` and `toJson` writes `beverageType.name`, so an enum case named `teaPortafilter` would serialise as `"teaPortafilter"` — a value neither de1app nor Decenza uses, trading one interop break for another. The enum needs an explicit wire-name mapping so `tea_portafilter` round-trips exactly. `tea` and `filter` happen to round-trip for free; `tea_portafilter` is the one that does not, and it is the one covering thirteen of the fifteen profiles.

**Ordering is a correctness constraint, not a preference.** `_parseBeverageType` returns `BeverageType.espresso` for anything unrecognised. Ship the corpus change first and thirteen tea profiles silently become espresso — strictly worse than the pour-over flattening they have today, and invisible because nothing errors. The enum change lands first, or the two land together.

*Behaviour is deliberately unchanged.* The only conduct keyed on beverage type is the `cleaning`/`calibrate` "scaleless" branch (`app.dart:423`, `de1_state_manager.dart:605`). Tea and filter are brewed to weight like espresso and pour-over, so they must **not** join that set. This change adds vocabulary, not behaviour.

*Alternative rejected:* keeping the flattening and treating it as a deliberate simplification. Defensible in isolation — de1app appears to use beverage type only for labels — but it costs users the ability to distinguish thirteen tea profiles from pour-overs, and `tea_portafilter` is a value de1app formally declares in `app_metadata.tcl`, not an informal one.

### D6 — Provenance is recorded in the corpus, not in a plan document

The reason `Default` took a controlled experiment to attribute is that nothing in the file said where it came from. The existing curation work put provenance in `doc/plans/archive/`, which is where it goes to be forgotten — and indeed its "contained to the 3 levers" scoping is still the note a reader would find today, five profiles after it stopped being true.

Recording source path + revision per profile (in the manifest, or a sidecar) makes the next such question a lookup.

## Risks / Trade-offs

**The synthesis port drifts from de1app's generator.** A reimplementation is one more thing that can be subtly wrong, and it would be wrong in the same direction for every profile.
→ *Mitigation:* validate against Decenza's independently-derived output for all five simple profiles before checking anything in. Any disagreement is a bug in one of the two, found before it ships rather than after.

**Nine profiles change what they brew, for users who already have them.** Someone dialled in on the current `Default` will get a different shot.
→ *Mitigation:* this needs an explicit decision, not a default. See open question 1 — the honest framing is that the current behaviour is a defect (54 °C brew water), not a profile someone chose.

**`Advanced spring lever` looked like it might be deliberately ours** — it is author-attributed to John Weiss, and overwriting a curated profile because it differs from de1app would be a regression dressed as a fix. It is not: de1app ships Weiss's profile *separately*, as `Weiss advanced spring lever`, and we already carry that one correctly. Ours is a third Visualizer variant occupying a name de1app uses for something else.
→ *Mitigation:* the check that settled it is cheap and worth repeating if this is ever questioned — compare our file against **both** de1app profiles, not just the same-titled one. Matching neither, while a correctly-matching copy of the other already exists in the corpus, is what distinguishes a collision from a choice.

**de1app #350 resolves by moving the canonical directory.** Then the harvest path in D3 becomes the stale one.
→ *Mitigation:* D4 is exactly this mitigation — the run fails and names both paths instead of quietly harvesting the wrong one.

**The comparison baseline is another app.** Decenza is not authoritative by virtue of being a second opinion.
→ *Mitigation:* the claims here do not rest on Decenza. Each rests on de1app's own file: `default.tcl` declares 90.0, the tool's own output is byte-identical to the shipped file, `advanced_shot {}` is visible in git history back to 2020. Decenza supplied the comparison that found them; de1app supplies the evidence that they are wrong.

## Migration Plan

The corpus change is a rebuild of ten files plus one manifest entry, verifiable by re-running the tool. Rollback is a revert.

The user-facing question is separate and is the real decision: `default_profiles_migration_test.dart` suggests a mechanism already exists for pushing corpus updates to existing installs. Whether to use it here is open question 1.

## Open Questions

1. **Do corrected profiles reach users who already hold a copy?** Leaving them means those users keep brewing at 54 °C; replacing them silently overwrites something a user may have adjusted. *Recommendation: replace where the local copy is unmodified, leave and notify where it is not — but this depends on whether the local copy tracks modification, which needs checking.*
2. **Should the tool ingest from a pinned de1app revision rather than a working checkout?** It would make the corpus reproducible and give D6's provenance record something exact to name.
