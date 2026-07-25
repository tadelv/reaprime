# AI Storage Notes

Read this when changing database schema, migrations, persistent settings, SharedPreferences keys, or profile storage. Skip it for changes that only use runtime state.

## Source Of Truth

- Database: `lib/src/database/app_database.dart` (Drift/SQLite via `@Database` annotation).
- DAOs: `lib/src/daos/` (data access objects).
- Mappers: `lib/src/mappers/` (domain ↔ Drift row mapping).
- Profile storage: `lib/src/services/profile_storage_service.dart` → `DriftProfileStorageService` → `ProfileDao` → `ProfileRecords` table.
- Settings: `lib/src/services/settings_service.dart` → `SharedPreferencesSettingsService`.
- Storage service: `lib/src/services/storage_service.dart`.

## Hard Rules

- Schema version is tracked in the Drift `@Database` annotation. Bump it on every migration.
- New tables need a migration entry in the `onUpgrade` callback.
- Domain models and Drift-generated code share class names (`ShotRecord`, `Workflow`, `ProfileRecord`). Use prefixed imports: `import '...shot_record.dart' as domain;` or `hide Workflow` on the database import.
- Profiles go through `ProfileStorageService` interface, not direct DAO access.

## Storage Ownership

| Store | Owner | Purpose |
|-------|-------|---------|
| Drift DB | `AppDatabase` | Shots, workflows, beans, grinders, profiles, settings |
| `SharedPreferences` | `SharedPreferencesSettingsService` | App settings (telemetry consent, feature flags, preferences) |
| Secure store | `DecentAccountService` | Account credentials (email, password, JWT tokens) |
| File system | `StorageService` | Data export, log files, skin assets |

Keep these stores independent. A settings reset must not clear account credentials unless explicitly requested.

## Database Schema

Persistence uses Drift (SQLite) via `AppDatabase`. DAOs in `lib/src/daos/`, mappers in `lib/src/mappers/`.

**Key tables:** `shots`, `steams`, `workflows`, `profiles`, `beans`, `bean_batches`, `grinders`, `settings`.

**Schema migration:** The `@Database` annotation's `version` field is the schema version. Migrations run in `onUpgrade` callback. Each version bump needs a corresponding migration step.

## Profile Storage

Content-based hash IDs for deduplication. `ProfileController` manages the profile library:
- Hash computed from profile content (`Profile.fromJson` → `computeHash`).
- Deduplication: two profiles with identical content get the same hash ID.
- `ProfileStorageService` interface with `DriftProfileStorageService` implementation.

## Bundled Default Profiles And The de1app Ingest Tool

`assets/defaultProfiles/` is built by `tools/ingest_profiles.py` from a de1app checkout.
`manifest.json` lists the files and carries a `provenance` map recording, per profile,
the source path, repository and commit it was harvested from. Anything the tool cannot
attribute is recorded as `"source": "unknown"` rather than left absent.

**Legacy frames are derived, never copied.** de1app's `save_profile` writes the
`advanced_shot` array out of the *global* `::settings`, so a `settings_2a`/`2b` file
ships whatever frames were loaded when it was last saved. de1app never reads them back
for those types — `sync_from_legacy` regenerates from the scalars at load time. The
tool therefore ignores the stored array entirely for `settings_2a`/`2b`, whether it is
empty or populated, and ports de1app's `pressure_to_advanced_list` /
`flow_to_advanced_list` (`de1plus/profile.tcl:11` and `:206`) instead. An underivable
profile raises rather than falling back to the stored array — a fallback would silently
restore exactly the behaviour that shipped `Default` with 75 °C and 54 °C frames.

**Stop targets are resolved by profile type.** de1app carries two spellings.
`final_desired_shot_weight` / `_volume` are authoritative for `settings_2a`/`2b`; the
`_advanced` spellings only for `settings_2c`. This is de1app's own runtime switch, in
`de1plus/device_scale.tcl` (weight) and `de1plus/de1_de1.tcl` (volume), both
`settings_2c { ...advanced } default { ...plain }`. Reading `_advanced` unconditionally
made `Classic Italian espresso` stop at 60 g where de1app stops at 36 g.

**Two de1app quirks are reproduced deliberately, not fixed:**
- `flow_to_advanced_list` gates the decline frame on `espresso_hold_time`, not
  `espresso_decline_time`. A flow profile with hold 0 and decline 20 gets no decline
  frame. Matching de1app matters more than the frame being sensible.
- The generators emit no `flow` key on pressure-pumped frames, so de1app's `ifexists`
  serialises `""` there. The tool writes `"0.0"`, which the app parses identically.

**A-Flow is harvested from `de1plus/plugins/A_Flow/profiles/`, not `de1plus/profiles/`.**
de1app ships stale 6-frame copies of four A-Flow profiles in the base directory that
permanently shadow the plugin's 9-frame versions (de1app issue #350). Passing a
`de1plus` root to the tool scans base, `plugins/*/profiles` and
`profile_editors/*/profiles`, and a profile appearing in more than one with *differing*
output is a hard error naming every path — never resolved by precedence, because the
A_Flow author has proposed resolving #350 the opposite way.

**The corpus rebuild is scoped, not wholesale.** A full re-ingest rewrites 40 files;
13 of those differences are number formatting and author attributions applied during
the `default-profiles-curation` pass (`Damian's *`, `Cremina`). Re-ingest an explicit
list.

## SharedPreferences Keys

Settings persist via `SharedPreferencesSettingsService`. Key prefixes are flat strings. Feature flags use the `FeatureFlag` enum + `SettingsService.featureFlag/setFeatureFlag` + `SettingsController.isFeatureFlagEnabled/setFeatureFlag`.

**First feature flag foundation (PR #371):** "Smart Step Advance" — the pattern for all future feature flags. Flag enum, settings service get/set, controller wrapper, UI toggle in Advanced Settings.

## Workflow Dual Representation

`Workflow.fromJson()` backfills `WorkflowContext` from legacy fields (`grinderData`, `coffeeData`, `doseData`). UI reads from `context`; API clients can write to either. Always keep both in sync when modifying serialization.

## Migration Checklist

- [ ] Bump schema version in `@Database` annotation.
- [ ] Add migration step in `onUpgrade` callback.
- [ ] Test migration from previous schema version.
- [ ] Test fresh install (no migration needed).
- [ ] Verify DAO and mapper support for new fields/tables.
- [ ] Update domain models if schema changes affect the public API.

## Focused Tests

```sh
flutter test test/daos/
flutter test test/database/
flutter test test/services/storage_service_test.dart
```

## Keeping Notes Fresh

Add migration gotchas, storage ownership changes, and data integrity rules. Prune when schema versions are retired.
