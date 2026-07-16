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
