# Smart Charging: default off + import from de1app

Tracks: [tadelv/reaprime#145](https://github.com/tadelv/reaprime/issues/145)

## Problem

tobbenb installed 0.5.11 on a Teclast tablet with a battery mod (no physical battery — relies on USB-powered operation). On first launch Bridge imported de1app settings, then after ~2 minutes the smart-charging logic cut USB power and the tablet shut down. There was no way to find and disable the setting fast enough.

Two issues on the Bridge side:

1. **Default is wrong for the battery-mod population.** `settings_service.dart:299` returns `ChargingMode.balanced` when no value is stored. For tablets without a battery, *any* mode other than `disabled` can brick the tablet when it hits the hysteresis low-water mark.
2. **de1app's `smart_battery_charging` is not imported.** Users who already configured smart charging correctly in de1app (disabled, or longevity/high-availability) have to redo it in Bridge. A tablet that was happily running with de1app's `smart_battery_charging 0` lands in Bridge with `balanced` and starts cycling.

A third item — making the smart-charging settings visible in the Streamline.js skin — is out of scope (lives in `allofmeng/streamline_project`).

## Scope

In-scope (this PR, Bridge only):

1. Flip the default in `SettingsService.chargingMode()` from `balanced` to `disabled`.
2. Parse `smart_battery_charging` out of `settings.tdb` and apply it during onboarding import, with the mapping below.

Out of scope:

- Streamline.js skin exposure of smart charging settings.
- Changes to the smart charging logic itself (`charging_logic.dart`).
- Changes to the Battery & Charging settings UI.
- Migration of existing installs already storing `balanced` — those users already went through onboarding and (presumably) their tablets survived, so we don't want to change their behavior out from under them. Only the default-for-new-installs changes.

## Mapping

| de1app `smart_battery_charging` | Bridge `ChargingMode` |
|---|---|
| `0` | `disabled` |
| `1` | `longevity` |
| `2` | `highAvailability` |
| missing / unrecognized | *no change* (don't touch the stored value) |

No de1app analog for Bridge's `balanced` mode. We lose nothing — de1app simply never produced a setting that would map there.

Rationale for leaving unrecognized values alone: the user may have already configured Bridge; the import pipeline in general prefers "overlay de1app values where present" rather than "reset to defaults."

## Files

### Modify

- **`lib/src/settings/settings_service.dart`** — line 299, change `ChargingMode.balanced.name` → `ChargingMode.disabled.name`, and the fallback on line 301 → `ChargingMode.disabled`.
- **`lib/src/import/parsers/settings_tdb_parser.dart`**
  - Add nullable `ChargingMode? chargingMode` field to `SettingsTdbResult` (and constructor, `isEmpty` check).
  - In `SettingsTdbParser.parse()`, read `data['smart_battery_charging']`, map via a private helper, return the result.
- **`lib/src/import/de1app_importer.dart`** — in Phase 5 (settings import, ~line 348) call `settingsController!.setChargingMode(settings.chargingMode!)` when non-null.

### Tests — modify

- **`test/import/settings_tdb_parser_test.dart`**
  - `smart_battery_charging 0` → `ChargingMode.disabled`
  - `smart_battery_charging 1` → `ChargingMode.longevity`
  - `smart_battery_charging 2` → `ChargingMode.highAvailability`
  - `smart_battery_charging 99` → `null` (unknown, don't touch)
  - missing key → `null`
  - `isEmpty` still `true` when only `smart_battery_charging` is absent and all other fields are null
- **`test/import/de1app_importer_test.dart`** — extend an existing settings-import test to assert the mapped value was applied via `SettingsController`.
- **New test** in `test/settings/settings_service_test.dart` (or whichever existing file covers defaults) asserting the fresh-install default is `ChargingMode.disabled`. If no such file exists, add one — small scope, targeted.

## Non-goals / explicitly not changing

- **`de1_skin_settings.tcl` in de1app** — not ours.
- **tobbenb's "clicking the row only opens fan setting" bug** — per triage, that's a Streamline.js skin issue (the current user's skin), not Bridge. Out of scope for this PR.
- **Migration for existing Bridge installs** — if someone already has `chargingMode = balanced` stored, we leave it. Default-flip only affects users with no stored value.

## Test plan

1. `flutter test test/import/settings_tdb_parser_test.dart`
2. `flutter test test/import/de1app_importer_test.dart`
3. `flutter test test/settings/` (or full settings suite)
4. `flutter test` (full suite before PR)
5. `flutter analyze` — no new warnings
6. Manual / MCP: start fresh-install simulated app (`app_start` with wiped prefs), check `settings_get` → `chargingMode: disabled`. Not strictly required given unit coverage, but a nice confidence pass.

## Rollout / risk

Low risk. Two surgical changes:

- Default flip: only affects users on first onboarding of a Bridge build that ships this change. Existing users with stored `chargingMode` are untouched.
- Import: additive — new code path only runs when `settings.tdb` has `smart_battery_charging` and the import pipeline decides to apply settings (same guard as all other imported fields).

The de1app Samsung auto-reset-to-0 quirk is not relevant: by the time we're reading `settings.tdb`, de1app has already written whatever value it ended up with. We parse what's on disk.

## Open questions

None blocking. One judgement call logged in the mapping table: `balanced` has no de1app analog; we accept that and do nothing if de1app's value doesn't map cleanly.
