# Restyle Debug Views & Rename to debug_feature

## Scope

Restyle the 3 debug/dev views in `lib/src/sample_feature/` from Material Design to
shadcn_ui (the project's design system), and rename the directory to `debug_feature`.

## Current state

| File | Material widgets used | Already shadcn |
|------|-----------------------|----------------|
| `sample_item_list_view.dart` (~130 lines) | `Scaffold`, `AppBar`, `ListTile`, `IconButton` | `ShadButton`, lucide icons mixed in |
| `sample_item_details_view.dart` (~310 lines) | `Scaffold`, `AppBar`, `OutlinedButton`, `LinearProgressIndicator`, `Theme.of(...).textTheme.titleMedium` | `ShadButton`, `ShadDialog`, `ShadInput` |
| `scale_debug_view.dart` (~140 lines) | `Scaffold`, `AppBar`, `FilledButton` (×7), `Theme.of(...).textTheme.titleMedium` | `ShadButton` (one instance) |

None of the files have tests beyond `sample_item_details_view_test.dart` (exists but may be minimal).

## Files that import `sample_feature`

| File | Import |
|------|--------|
| `lib/src/app.dart` | `sample_item_list_view.dart`, `sample_item_details_view.dart`, `scale_debug_view.dart` |
| `lib/src/settings/advanced_page.dart` | `sample_item_list_view.dart` |
| `test/sample_feature/sample_item_details_view_test.dart` | `sample_item_details_view.dart` |

## Tasks

### Task 1: Rename `sample_feature` → `debug_feature`

- `git mv lib/src/sample_feature lib/src/debug_feature`
- `git mv test/sample_feature test/debug_feature`
- Update imports in `lib/src/app.dart`, `lib/src/settings/advanced_page.dart`, `test/debug_feature/sample_item_details_view_test.dart`
- Update internal imports within the 3 view files
- Run `flutter test` + `flutter analyze` — should be a no-op rename, 0 failures expected

### Task 2: Restyle `debug_item_list_view.dart`

Replace Material → shadcn:
- `Scaffold` → `ShadApp` layout or inline (this is a pushed route, already inside a `ShadApp`)
- `AppBar` → shadcn app-bar equivalent or a `ShadAppBar`
- `ListTile` → `ShadCard` or `ShadListTile` pattern
- `IconButton` → `ShadButton.ghost`

### Task 3: Restyle `debug_item_details_view.dart`

Replace Material → shadcn:
- `AppBar` → shadcn equivalent
- `OutlinedButton` (Wake/Sleep) → `ShadButton.outline`
- `LinearProgressIndicator` → `ShadProgress`
- `Theme.of(context).textTheme.titleMedium` → shadcn typography (`Text` with `style: ShadTheme.of(context).textTheme.h4` or similar)
- Section headers (`"Shot snapshot:"`, `"Shot settings:"`, etc.) → use `ShadTextTheme` or `Text` with bold style

### Task 4: Restyle `scale_debug_view.dart`

Replace Material → shadcn:
- `AppBar` → shadcn equivalent
- `FilledButton` (×7) → `ShadButton` (primary variant), or `ShadButton.outline` for secondary actions
- `Theme.of(context).textTheme.titleMedium` → shadcn typography
- The lone inline `ShadButton` with missing trailing comma — fix formatting

### Task 5: Final verification

- `flutter analyze lib/ test/` — no issues
- `flutter test` — all existing tests pass
- Manual: run in simulate mode, navigate to `/debug` from Settings → Advanced page

## Guardrails

- `flutter test test/debug_feature/` — existing debug detail test still passes
- `flutter test` — full suite green
- No behavioral changes — identical functionality, only visual restyling
