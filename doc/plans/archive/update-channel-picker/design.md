# Issue #82 — Update channel picker

## Decisions

- Expose Stable and Beta channels only.
- Stable accepts final GitHub releases.
- Beta accepts final releases and every GitHub prerelease.
- Default to Stable and persist the choice in SharedPreferences.
- Re-check immediately after a channel change.
- Hide the picker on iOS.
- Defer Development/Nightly until nightly releases exist.

## Acceptance criteria

- Stable users are offered only newer final releases.
- Beta users are offered the highest newer final or prerelease version.
- Semantic version precedence detects prerelease-to-prerelease and prerelease-to-final upgrades.
- The selected channel survives settings reloads and drives manual and periodic checks.
- Settings > Updates shows the selected channel and allows changing it outside iOS.
- Changing channel triggers an update check.

## Verification

1. Add failing tests at the `AndroidUpdater.checkForUpdate`, `UpdateCheckService.checkForUpdate`, and `SettingsController` interfaces.
2. Implement the smallest persistence, filtering, comparison, and picker changes.
3. Run `dart format lib test`, focused tests, `flutter analyze`, and full `flutter test`.
