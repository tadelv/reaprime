# Restyle Debug Views & Rename to debug_feature

## Scope

Restyle the 3 debug/dev views in `lib/src/sample_feature/` from Material Design to
shadcn_ui (the project's design system), and rename the directory to `debug_feature`.

## Current state

| File | Material widgets used | Already shadcn |
|------|-----------------------|----------------|
| `debug_item_list_view.dart` (~130→~280 lines) | `Scaffold`, `AppBar`, `ListTile`, `IconButton` | `ShadButton`, lucide icons mixed in |
| `debug_item_details_view.dart` (~310→~430 lines) | `Scaffold`, `AppBar`, `OutlinedButton`, `LinearProgressIndicator`, `Theme.of(...).textTheme.titleMedium` | `ShadButton`, `ShadDialog`, `ShadInput` |
| `scale_debug_view.dart` (~140→~170 lines) | `Scaffold`, `AppBar`, `FilledButton` (×7), `Theme.of(...).textTheme.titleMedium` | `ShadButton` (one instance) |

None of the files have tests beyond `sample_item_details_view_test.dart` (exists but may be minimal).

## Files that import `sample_feature`

| File | Import |
|------|--------|
| `lib/src/app.dart` | `debug_item_list_view.dart`, `debug_item_details_view.dart`, `scale_debug_view.dart` |
| `lib/src/settings/advanced_page.dart` | `debug_item_list_view.dart` |
| `test/debug_feature/debug_item_details_view_test.dart` | `debug_item_details_view.dart` |

## Tasks

### Task 1: Rename `sample_feature` → `debug_feature`

- `git mv lib/src/sample_feature lib/src/debug_feature`
- `git mv test/sample_feature test/debug_feature`
- Update imports in `lib/src/app.dart`, `lib/src/settings/advanced_page.dart`, `test/debug_feature/debug_item_details_view_test.dart`
- Update internal imports within the 3 view files
- Rename `SampleItemListView` class → `DebugItemListView`
- Rename files: `sample_item_list_view.dart` → `debug_item_list_view.dart`, `sample_item_details_view.dart` → `debug_item_details_view.dart`
- Run `flutter test` + `flutter analyze`

### Task 2: Restyle `debug_item_list_view.dart`

**Direction**: Ambitious — improve UX while keeping a dense list layout.

Replace Material → shadcn with UX enhancements:

- **Custom header row**: No `Scaffold`/`AppBar`. A `Row` with title text and a scan button. When idle: radar icon. When scanning: spinner icon + "Scanning..." text.
- **Scanning indicator**: `ShadProgress` bar at top while scanning, driven by `DeviceController.scanningStream`.
- **Empty state**: When 0 devices and not scanning — centered "No devices discovered — tap Scan to search" message.
- **Device grouping**: Section headers for Machines, Scales, Sensors. Only show non-empty groups.
- **Dense list items**: Custom `Row`-based item (no `ListTile`) with connection-state icon, device name/id, and `[Inspect]` `[Connect]` actions.
- **Sensors**: Display in list but no Connect button (sensors don't have a connect flow).
- **Device count**: Show count in header ("Debug · 3 devices").

### Task 3: Restyle `debug_item_details_view.dart`

**Direction**: Ambitious — responsive layout, card-based sections, state dropdown.

Replace Material → shadcn with UX enhancements:

- **Responsive layout**: Horizontal `Flex` on wide screens (tablet), stacked vertically on narrow (phone). Use `LayoutBuilder`.
- **Section cards**: Each data section (shot snapshot, shot settings, water levels, machine info) wrapped in `ShadCard` with titled header replacing bare `Theme.of(context).textTheme.titleMedium`.
- **Machine state control**: Replace `OutlinedButton` (Wake/Sleep) with a `ShadSelect<MachineState>` dropdown of `MachineState.values`, calling `requestState()` on change. Also show current state as text.
- **`LinearProgressIndicator`** → `ShadProgress`.
- **Typography**: Replace `Theme.of(context).textTheme.titleMedium` with shadcn text styles.
- **Firmware update**: Keep existing flow (already uses `ShadDialog`), just restyle the trigger button.
- **Serial comms**: Leave as-is for now.

### Task 4: Restyle `scale_debug_view.dart`

**Direction**: Ambitious — weight hero, button hierarchy, custom header.

Replace Material → shadcn with UX enhancements:

- **Custom header**: Replace `Scaffold`/`AppBar` with a header row showing scale name + device ID.
- **Weight hero**: Large centered `Text` for current weight (e.g. "247.3g"). Prominent display since it's the primary debug data point.
- **Button hierarchy**: 
  - **Primary actions** (top): Tare (`ShadButton`) + Disconnect (`ShadButton.destructive`)
  - **Display controls** (row): Wake (`ShadButton.outline`) · Sleep (`ShadButton.outline`)
  - **Timer controls** (row): Start (`ShadButton.outline`) · Stop (`ShadButton.outline`) · Reset (`ShadButton.outline`)
- **Info row**: Battery level (plain text) + update latency (plain text) below weight.
- **Typography**: Replace `Theme.of(context).textTheme.titleMedium` with shadcn text styles.
- **States**: Show "Connecting…" while waiting; show weight data when active; show "Waiting for data…" otherwise.

### Task 5: Final verification

- `flutter analyze lib/ test/` — no issues
- `flutter test` — all existing tests pass
- Manual: run in simulate mode, navigate to `/debug` from Settings → Advanced page

## Guardrails

- `flutter test test/debug_feature/` — existing debug detail test still passes
- `flutter test` — full suite green
- No behavioral changes — identical functionality, only visual restyling
