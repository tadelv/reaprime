# Accessibility: Settings & History Views — Design

## Problem

GH #93 tracks screen reader accessibility for Bridge.app. Onboarding, scan, import, landing, and dashboard views are done. Settings and shot history remain — both have zero Semantics widgets. This blocks closing #93.

## Approach

Apply the same patterns established in dashboard a11y work (commit 5387fed):
- `Semantics(explicitChildNodes: true)` on container sections
- `MergeSemantics` on label+control / label+value pairs
- `Semantics(button: true, label: '...')` + `ExcludeSemantics` on interactive elements
- `Semantics(header: true)` on section headings
- Contextual labels including live state values

## Settings View (`lib/src/settings/settings_view.dart`)

### Sections
Wrap each `_SettingsSection` / `ShadCard` with `Semantics(explicitChildNodes: true, label: 'Section name')`.

### Label+control pairs
Wrap each `_SettingRow` with `MergeSemantics` so label and control announce as one (e.g., "Theme, Dark").

### Navigation buttons
`ShadButton.outline` items navigating to sub-pages get `Semantics(button: true, label: 'Configure [feature] settings')` with `ExcludeSemantics` on children.

### Dropdowns
Wrap `DropdownButton` with `Semantics` including current value (e.g., "Gateway mode, Full").

### Switches
ShadSwitch has `label`/`sublabel`. Wrap with `MergeSemantics` to unify announcement.

### Icon-only buttons
Add `Semantics(button: true, label: '...')`.

## History View (`lib/src/history_feature/history_feature.dart`)

### List items
Wrap each shot card in `Semantics(button: true, label: 'Shot on [date], [coffee], [dose]g in, [yield]g out, [duration]')` with `ExcludeSemantics` on children.

### Search bar
Add semantic label describing purpose.

### Result count
Announce as status when search changes.

### Detail view sections
Section headers: `Semantics(header: true)`. Section containers: `Semantics(explicitChildNodes: true, label: '...')`.

### Stat cards
`MergeSemantics` on each `_StatCard` (label+value).

### Detail rows
`MergeSemantics` on each `_DetailRow` (label+value).

### Action buttons
`Semantics(button: true, label: 'Edit shot notes')`, `'Repeat this shot'`, `'Delete this shot'`.

### Chart
Wrap `ShotChart` in `Semantics(label: 'Shot chart summary: [duration], peak pressure, peak flow, final weight')`. Exclude chart internals from semantics — fl_chart tooltips aren't SR-accessible.

### Decorative icons
Wrap in `ExcludeSemantics`.

## Out of scope

- Streamline.js skin `role="button"` fix (separate workstream)
- Dialog a11y (TalkBack node merging — tracked separately)
- Scan step status announcements (tracked separately)
- Chart data table alternative (not needed for Approach B)

## Testing

Deploy to device, verify with TalkBack that all interactive elements are discoverable, labeled, and activatable via double-tap.
