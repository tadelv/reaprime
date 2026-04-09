# A11Y Settings & History Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add comprehensive screen reader (TalkBack) accessibility to the Settings and History views, matching the quality of the existing dashboard a11y work.

**Architecture:** Apply existing patterns — `Semantics(explicitChildNodes: true)` on sections, `MergeSemantics` on label+control pairs, `Semantics(button: true)` with `ExcludeSemantics` on interactive elements. No new widgets or abstractions needed.

**Tech Stack:** Flutter Semantics API, existing shadcn_ui widgets

**Subagent structure:** 2 agents per view (4 total). Settings: helper widgets + sections. History: list view + detail view.

---

### Task 1: Settings — Annotate helper widgets (`_SettingsSection`, `_SettingRow`, `_InfoRow`)

**Files:**
- Modify: `lib/src/settings/settings_view.dart:1179-1301`

**Step 1: Add `Semantics(explicitChildNodes: true)` to `_SettingsSection`**

Wrap the `ShadCard` return in `_SettingsSection.build()` (line 1196) with:
```dart
return Semantics(
  explicitChildNodes: true,
  label: title,
  child: ShadCard(
    // ... existing code
  ),
);
```

Also wrap the info `IconButton` (line 1214) with `Semantics(button: true, label: 'Learn more about $title')` and `ExcludeSemantics` on the child icon.

**Step 2: Add `MergeSemantics` to `_SettingRow`**

Wrap the `Padding` return in `_SettingRow.build()` (line 1249) with `MergeSemantics`:
```dart
return MergeSemantics(
  child: Padding(
    // ... existing code
  ),
);
```

This merges the label text and the control widget so TalkBack announces them together (e.g., "Theme, Dark Theme").

**Step 3: Add `MergeSemantics` to `_InfoRow`**

Same pattern for `_InfoRow.build()` (line 1277):
```dart
return MergeSemantics(
  child: Padding(
    // ... existing code
  ),
);
```

**Step 4: Run `flutter analyze`**

Run: `flutter analyze lib/src/settings/settings_view.dart`
Expected: No new warnings

**Step 5: Commit**

```
git add lib/src/settings/settings_view.dart
git commit -m "fix(a11y): add semantics to settings helper widgets"
```

---

### Task 2: Settings — Annotate section builders

**Files:**
- Modify: `lib/src/settings/settings_view.dart:134-710`

**Step 1: Annotate Battery section (lines 201-256)**

This section doesn't use `_SettingsSection`, it's a raw `ShadCard`. Wrap it:
```dart
return Semantics(
  explicitChildNodes: true,
  label: 'Battery & Charging',
  child: ShadCard(
    // ... existing
  ),
);
```

Wrap the "Configure" `ShadButton.outline` (line 241) with:
```dart
Semantics(
  button: true,
  label: 'Configure battery and charging settings',
  child: ExcludeSemantics(
    child: ShadButton.outline(
      // ... existing
    ),
  ),
),
```

**Step 2: Annotate Presence section (lines 271-335)**

Same pattern — raw `ShadCard`, wrap with `Semantics(explicitChildNodes: true, label: 'Presence & Sleep')`.

Wrap "Configure" button with `Semantics(button: true, label: 'Configure presence and sleep settings, currently $subtitle')`.

**Step 3: Annotate Device Management section (lines 337-433)**

Wrap with `Semantics(explicitChildNodes: true, label: 'Device Management')`.

Wrap "Configure" button (line 385) with `Semantics(button: true, label: 'Configure device management, machine: ${machineName ?? "Not set"}, scale: ${scaleName ?? "Not set"}')`.

Wrap each `ShadSwitch` for simulated devices (line 414) with `MergeSemantics`.

**Step 4: Annotate Data Management section (lines 435-491)**

Wrap with `Semantics(explicitChildNodes: true, label: 'Data Management')`.

Wrap "Configure" button (line 471) with `Semantics(button: true, label: 'Configure data management')`.

**Step 5: Annotate WebUI section (lines 537-583)**

`_SettingsSection` wrapper already gets semantics from Task 1. Additional:

- Wrap the skin selector dropdown with `Semantics(label: 'Selected skin')` — the `MergeSemantics` from `_SettingRow` will merge label + dropdown.
- Wrap "Start WebUI Server" button (line 550) with `Semantics(button: true, label: 'Start WebUI server')`.
- Wrap "Open UI in browser" button (line 559) with `Semantics(button: true, label: 'Open web interface in browser')`.
- Wrap "Stop WebUI Server" button (line 565) with `Semantics(button: true, label: 'Stop WebUI server')`.
- Wrap "Check for Skin Updates" button (line 577) with `Semantics(button: true, label: 'Check for skin updates')`.

**Step 6: Annotate Advanced section (lines 585-672)**

`_SettingsSection` wrapper handles section semantics. Additional:

- The `ShadSwitch` for automatic updates (line 606) — wrap with `MergeSemantics`.
- Update available banner (line 622-648) — wrap with `Semantics(label: 'Update available: ${widget.updateCheckService?.availableUpdate?.version}')`.
- Wrap "Plugins" button (line 654) with `Semantics(button: true, label: 'Open plugins settings')`.
- Wrap "Check for updates" button (line 658) with `Semantics(button: true, label: 'Check for app updates')`.
- Wrap "Exit" button (line 665) with `Semantics(button: true, label: 'Exit Streamline-Bridge application')`.

**Step 7: Annotate About section (lines 674-710)**

`_SettingsSection` wrapper handles section semantics. Additional:

- Wrap "View GPL v3 License" button (line 702) with `Semantics(button: true, label: 'View GPL version 3 license')`.

**Step 8: Run `flutter analyze`**

Run: `flutter analyze lib/src/settings/settings_view.dart`
Expected: No new warnings

**Step 9: Commit**

```
git add lib/src/settings/settings_view.dart
git commit -m "fix(a11y): add semantics to all settings sections"
```

---

### Task 3: History — Annotate list view (left column)

**Files:**
- Modify: `lib/src/history_feature/history_feature.dart:105-364`

**Step 1: Annotate search bar (line 125)**

Add a `Semantics` label to the `SearchBar`:
```dart
Semantics(
  label: 'Search shot history',
  child: SearchBar(
    controller: _searchController,
    hintText: "Search by coffee, roaster, profile, grinder, or notes...",
  ),
),
```

**Step 2: Annotate result count (line 129-138)**

Wrap the result count text with `Semantics(liveRegion: true)` so TalkBack announces search result changes:
```dart
Semantics(
  liveRegion: true,
  child: Padding(
    padding: const EdgeInsets.only(top: 4.0, left: 8.0),
    child: Text(
      "Found ${_shots.length} shot${_shots.length == 1 ? '' : 's'}",
      // ... existing style
    ),
  ),
),
```

**Step 3: Annotate list items (lines 153-357)**

Wrap each list item's `Padding` (line 153) with `Semantics` and `ExcludeSemantics`:

```dart
return Semantics(
  button: true,
  selected: isSelected,
  label: _shotListItemLabel(record, durationSeconds),
  child: ExcludeSemantics(
    child: Padding(
      // ... existing TapRegion code
    ),
  ),
);
```

Add helper method to build the label:
```dart
String _shotListItemLabel(ShotRecord record, int durationSeconds) {
  final parts = <String>[record.shotTime()];
  if (record.workflow.context?.coffeeName != null) {
    parts.add(record.workflow.context!.coffeeName!);
  }
  if (record.workflow.context?.coffeeRoaster != null) {
    parts.add('by ${record.workflow.context!.coffeeRoaster!}');
  }
  parts.add(record.workflow.profile.title);
  if (record.workflow.context?.targetDoseWeight != null) {
    parts.add('${record.workflow.context!.targetDoseWeight!}g in');
  }
  if (record.workflow.context?.targetYield != null) {
    parts.add('${record.workflow.context!.targetYield!}g out');
  }
  parts.add('${durationSeconds}s');
  return parts.join(', ');
}
```

**Step 4: Run `flutter analyze`**

Run: `flutter analyze lib/src/history_feature/history_feature.dart`
Expected: No new warnings

**Step 5: Commit**

```
git add lib/src/history_feature/history_feature.dart
git commit -m "fix(a11y): add semantics to history list view"
```

---

### Task 4: History — Annotate detail view (right column)

**Files:**
- Modify: `lib/src/history_feature/history_feature.dart:366-883`

**Step 1: Annotate action buttons (lines 417-453)**

Wrap each button with `Semantics(button: true)` + `ExcludeSemantics`:

```dart
Semantics(
  button: true,
  label: 'Edit shot notes',
  child: ExcludeSemantics(
    child: ShadButton.outline(/* existing */),
  ),
),
Semantics(
  button: true,
  label: 'Repeat this shot with same workflow settings',
  child: ExcludeSemantics(
    child: ShadButton(/* existing */),
  ),
),
Semantics(
  button: true,
  label: 'Delete this shot',
  child: ExcludeSemantics(
    child: ShadButton.destructive(/* existing */),
  ),
),
```

**Step 2: Annotate stat cards (lines 459-490)**

Wrap each `_StatCard` with `MergeSemantics`. Modify `_StatCard.build()` (line 820):
```dart
@override
Widget build(BuildContext context) {
  return MergeSemantics(
    child: Semantics(
      label: '$label: $value',
      child: ExcludeSemantics(
        child: ShadCard(
          // ... existing code
        ),
      ),
    ),
  );
}
```

**Step 3: Annotate detail sections (Coffee, Equipment, Notes, Additional Info)**

Add `Semantics(header: true)` to each section title Row (lines 499-509, 546-556, 589-599, 619-629).

Wrap each section title `Text` with:
```dart
Semantics(
  header: true,
  child: Text(
    "Coffee Details",
    // ... existing style
  ),
),
```

Wrap section `ShadCard` containers with `Semantics(explicitChildNodes: true, label: 'section name')`.

**Step 4: Annotate `_DetailRow`**

Modify `_DetailRow.build()` (line 858) to wrap with `MergeSemantics`:
```dart
@override
Widget build(BuildContext context) {
  return MergeSemantics(
    child: Padding(
      // ... existing code
    ),
  );
}
```

**Step 5: Annotate chart section (lines 679-696)**

Wrap the "Shot Profile" heading text (line 682) with `Semantics(header: true)`.

Wrap the `ShotChart` SizedBox (line 689) with a descriptive `Semantics` and exclude the chart:
```dart
Semantics(
  label: _chartSummaryLabel(record),
  child: ExcludeSemantics(
    child: SizedBox(
      height: 500,
      child: ShotChart(/* existing */),
    ),
  ),
),
```

Add helper method:
```dart
String _chartSummaryLabel(ShotRecord record) {
  final duration = record.measurements.isNotEmpty
      ? record.measurements.last.machine.timestamp.difference(record.timestamp)
      : Duration.zero;
  final parts = <String>['Shot profile chart'];
  parts.add('duration ${duration.inSeconds} seconds');
  if (record.measurements.isNotEmpty) {
    final maxPressure = record.measurements
        .map((m) => m.machine.groupPressure)
        .reduce((a, b) => a > b ? a : b);
    parts.add('peak pressure ${maxPressure.toStringAsFixed(1)} bar');
    final maxFlow = record.measurements
        .map((m) => m.machine.groupFlow)
        .reduce((a, b) => a > b ? a : b);
    parts.add('peak flow ${maxFlow.toStringAsFixed(1)} millilitres per second');
  }
  return parts.join(', ');
}
```

**Step 6: Annotate "No shot selected" placeholder (line 372)**

```dart
Center(child: Semantics(
  label: 'No shot selected. Select a shot from the list on the left.',
  child: ExcludeSemantics(child: Text("No shot selected")),
)),
```

**Step 7: Run `flutter analyze`**

Run: `flutter analyze lib/src/history_feature/history_feature.dart`
Expected: No new warnings

**Step 8: Run full test suite**

Run: `flutter test`
Expected: All tests pass

**Step 9: Commit**

```
git add lib/src/history_feature/history_feature.dart
git commit -m "fix(a11y): add semantics to history detail view"
```

---

### Task 5: Final verification

**Step 1: Run `flutter analyze` on full project**

Run: `flutter analyze`
Expected: No new warnings related to our changes

**Step 2: Run `flutter test`**

Run: `flutter test`
Expected: All tests pass

**Step 3: Commit any remaining fixes**

If analyze or tests revealed issues, fix and commit.
