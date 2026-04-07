# Accessibility: Onboarding & Landing Views — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add screen reader accessibility (Semantics widgets, labels, focus ordering, live regions) to the onboarding flow, import views, and landing/skin selection — addressing native Flutter views from [#93](https://github.com/tadelv/reaprime/issues/93).

**Architecture:** Each view gets `Semantics` annotations following a consistent pattern: decorative icons excluded, meaningful icons labeled, progress indicators wrapped, icon+text rows merged, status text marked as live regions, and main content areas grouped for focus traversal.

**Tech Stack:** Flutter `Semantics`, `MergeSemantics`, `ExcludeSemantics`, `FocusTraversalGroup`. Testing via `SemanticsController` in widget tests + Xcode Accessibility Inspector on macOS.

---

### Task 1: Welcome Step — Semantics

**Files:**
- Modify: `lib/src/onboarding_feature/steps/welcome_step.dart:24-65`

**Step 1: Add semantic structure to welcome step**

The welcome step is text-only with one button — minimal changes needed. Wrap the main Column in a `Semantics` widget with a page-level label, and add `FocusTraversalGroup` for logical tab order.

```dart
// welcome_step.dart:27 — wrap Scaffold body
return Scaffold(
  body: Semantics(
    label: 'Welcome to Streamline Bridge',
    explicitChildNodes: true,
    child: Center(
      // ... existing code
    ),
  ),
);
```

**Step 2: Run `flutter analyze`**

Run: `flutter analyze`
Expected: No new warnings

**Step 3: Commit**

```bash
git add lib/src/onboarding_feature/steps/welcome_step.dart
git commit -m "feat(a11y): add semantics to welcome step"
```

---

### Task 2: Permissions & Initialization Steps — Semantics

**Files:**
- Modify: `lib/src/onboarding_feature/steps/permissions_step.dart:122-150`
- Modify: `lib/src/onboarding_feature/steps/initialization_step.dart:122-149`

Both steps have identical structure: a `ShadProgress` + status `Text`. Apply the same pattern to both.

**Step 1: Wrap progress indicator and mark status text as live region**

For permissions_step.dart (line 134-143):
```dart
return Column(
  spacing: 16,
  children: [
    Semantics(
      label: 'Requesting permissions',
      child: SizedBox(width: 200, child: ShadProgress()),
    ),
    Semantics(
      liveRegion: true,
      child: Text(
        'Requesting permissions...',
        style: Theme.of(context).textTheme.titleMedium,
      ),
    ),
  ],
);
```

Same pattern for initialization_step.dart (line 133-142) with label `'Starting Streamline'` and text `'Streamline is starting...'`.

Also wrap the error text (`snapshot.hasError` branch) with a live region semantics.

**Step 2: Run `flutter analyze`**

Run: `flutter analyze`
Expected: No new warnings

**Step 3: Commit**

```bash
git add lib/src/onboarding_feature/steps/permissions_step.dart lib/src/onboarding_feature/steps/initialization_step.dart
git commit -m "feat(a11y): add semantics to permissions and initialization steps"
```

---

### Task 3: Scan Step — Scanning & Connecting Views

**Files:**
- Modify: `lib/src/onboarding_feature/steps/scan_step.dart:269-339`

**Step 1: Add semantics to _scanningView**

- Wrap `ShadProgress()` at line 281 in `Semantics(label: 'Scanning for devices')`.
- Mark the status text as a live region (it changes between coffee messages, "X devices found", "Still scanning...").
- The `AnimatedOpacity` + `IgnorePointer` combo at line 304 already hides the button — add `ExcludeSemantics` when `!_showTakingTooLong` so screen readers don't read a hidden button.

```dart
// line 304-319
ExcludeSemantics(
  excluding: !_showTakingTooLong,
  child: AnimatedOpacity(
    opacity: _showTakingTooLong ? 1.0 : 0.0,
    duration: const Duration(milliseconds: 400),
    child: IgnorePointer(
      ignoring: !_showTakingTooLong,
      // ... existing button
    ),
  ),
),
```

**Step 2: Add semantics to _connectingView**

- Wrap `ShadProgress()` at line 334 in `Semantics(label: 'Connecting')`.
- Mark the label text as a live region.

**Step 3: Run `flutter analyze`**

Run: `flutter analyze`
Expected: No new warnings

**Step 4: Commit**

```bash
git add lib/src/onboarding_feature/steps/scan_step.dart
git commit -m "feat(a11y): add semantics to scan step scanning/connecting views"
```

---

### Task 4: Scan Step — Error & Device Picker Views

**Files:**
- Modify: `lib/src/onboarding_feature/steps/scan_step.dart:341-565`

**Step 1: Add semantics to error views**

For `_errorView` (line 474-503):
- Mark the alert icon at line 481 as decorative: `Icon(LucideIcons.triangleAlert, size: 48, color: ..., semanticLabel: null)` — the heading "Connection Error" conveys the meaning.
- Add `ExcludeSemantics` around the icon, rely on heading text.
- Wrap the icon+text row in the retry button with `MergeSemantics`.

For `_adapterErrorView` (line 505-539):
- Same pattern: exclude bluetooth icon, rely on "Bluetooth Unavailable" heading.
- `MergeSemantics` on retry button's icon+text row.

**Step 2: Add semantics to _devicePickerView**

For the `_devicePickerView` (line 341-472):
- The `CircularProgressIndicator` at line 452-453 needs `Semantics(label: 'Connecting')`.
- Icon in ReScan button (line 436) — already paired with "ReScan" text in a `Row`, wrap the Row in `MergeSemantics` so it reads as one item.
- Same for connecting button icon+text row.

**Step 3: Add semantics to bottom sheet**

For `_showTakingTooLongSheet` (line 573-631):
- `ListTile` already provides semantic structure (title is read). The leading icons are decorative (title text conveys meaning). No change needed — Flutter's `ListTile` handles this well.

**Step 4: Add semantics to _noDevicesFoundView**

- Handled by `ScanResultsSummary` widget (Task 5).

**Step 5: Run `flutter analyze`**

Run: `flutter analyze`
Expected: No new warnings

**Step 6: Commit**

```bash
git add lib/src/onboarding_feature/steps/scan_step.dart
git commit -m "feat(a11y): add semantics to scan step error and picker views"
```

---

### Task 5: Scan Results Summary & Device Selection Widget

**Files:**
- Modify: `lib/src/onboarding_feature/widgets/scan_results_summary.dart:24-169`
- Modify: `lib/src/home_feature/widgets/device_selection_widget.dart:80-250`

**Step 1: ScanResultsSummary semantics**

- The large icon at line 39-43 is decorative (heading text below describes the state). Add `ExcludeSemantics`:
```dart
ExcludeSemantics(
  child: Icon(
    icon,
    size: 64,
    color: theme.colorScheme.primary.withValues(alpha: 0.7),
  ),
),
```

- Button icon+text rows (lines 65-72, 78-88, 91-102) — wrap each `Row` inside the button `child` with `MergeSemantics` so screen readers read "Scan Again", "Troubleshoot", "Export Logs" as single items. Actually, since the text already says the action, the icon is decorative within the button context. `MergeSemantics` on the Row is sufficient.

**Step 2: DeviceSelectionWidget semantics**

- Error info icon at lines 194-196 and 229-231: decorative (error text follows). Add `ExcludeSemantics` around the icon, or add `semanticLabel: null` (already no label, but explicitly exclude).
- The `Checkbox` at line 149 needs a semantic label. Wrap the Row (lines 144-168) in `MergeSemantics` so checkbox + "Auto-connect" text reads as one: "Auto-connect, checkbox, checked/unchecked".

```dart
// line 144-168 — wrap the auto-connect row
MergeSemantics(
  child: Row(
    children: [
      SizedBox(
        width: 24,
        height: 24,
        child: Checkbox(
          value: isPreferred,
          semanticLabel: 'Auto-connect ${device.name}',
          onChanged: (value) { ... },
        ),
      ),
      SizedBox(width: 4),
      // ExcludeSemantics on "Auto-connect" text since checkbox label covers it
      ExcludeSemantics(
        child: Text('Auto-connect', ...),
      ),
    ],
  ),
),
```

Wait — `Checkbox` doesn't have a `semanticLabel` parameter directly. Instead, use `MergeSemantics` to combine with the text, which is the Flutter-recommended approach.

**Step 3: Run `flutter analyze`**

Run: `flutter analyze`
Expected: No new warnings

**Step 4: Commit**

```bash
git add lib/src/onboarding_feature/widgets/scan_results_summary.dart lib/src/home_feature/widgets/device_selection_widget.dart
git commit -m "feat(a11y): add semantics to scan results summary and device selection"
```

---

### Task 6: Import Views — Source Picker, Progress, Summary, Result

**Files:**
- Modify: `lib/src/import/widgets/import_source_picker.dart:99-160`
- Modify: `lib/src/import/widgets/import_progress_view.dart:19-66`
- Modify: `lib/src/import/widgets/import_summary_view.dart:86-103`
- Modify: `lib/src/import/widgets/import_result_view.dart:31-325`

**Step 1: ImportSourcePicker — _SourceCard semantics**

The `_SourceCard` widget (line 99-160) uses `InkWell` + icon + title + subtitle + chevron. Wrap the whole `InkWell` content in `MergeSemantics` so screen reader reads it as a single tappable item. Add `Semantics(button: true)` to signal it's interactive. Exclude the chevron icon:

```dart
// _SourceCard build, line 118
child: Semantics(
  button: true,
  child: InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: MergeSemantics(
      child: Padding(
        // ... existing Row
        // Add ExcludeSemantics around chevron:
        ExcludeSemantics(
          child: Icon(LucideIcons.chevronRight, size: 16, ...),
        ),
        // Add ExcludeSemantics around container icon (title text conveys meaning):
        ExcludeSemantics(
          child: Container(... Icon(icon, ...) ...),
        ),
      ),
    ),
  ),
),
```

**Step 2: ImportProgressView semantics**

- Download icon at line 30-34: decorative (heading says "Importing Your Data..."). Wrap with `ExcludeSemantics`.
- `ShadProgress` at line 42: wrap with `Semantics(label: 'Import progress, ${progress.current} of ${progress.total}')`.
- Progress text at line 44-48: mark as `Semantics(liveRegion: true)` — this changes during import.
- Count texts (shots/profiles processed) at lines 50-59: mark as live regions.

**Step 3: ImportSummaryView — _CountRow semantics**

The `_CountRow` (line 86-103) has icon + label. Icon is decorative (label text like "42 shots" is sufficient). Wrap with `MergeSemantics` so it reads as one item, or simply `ExcludeSemantics` the icon:

```dart
// _CountRow build method
return MergeSemantics(
  child: Row(
    children: [
      ExcludeSemantics(
        child: Icon(icon, size: 18, color: theme.colorScheme.primary),
      ),
      const SizedBox(width: 12),
      Text(label, style: theme.textTheme.p),
    ],
  ),
);
```

**Step 4: ImportResultView semantics**

- Status icon at line 49-57: decorative (heading below says "Import Complete" or "Import Complete (with issues)"). `ExcludeSemantics`.
- `_ResultRow` (line 267-299): same pattern as `_CountRow` — `MergeSemantics` + `ExcludeSemantics` on icon.
- Toggle button icon (line 138-143): the icon (chevron up/down) is paired with text "Hide/Show details". `MergeSemantics` on the Row.
- Share button icon (line 173): paired with "Share Report" text. `MergeSemantics` on the Row.

**Step 5: Run `flutter analyze`**

Run: `flutter analyze`
Expected: No new warnings

**Step 6: Commit**

```bash
git add lib/src/import/widgets/
git commit -m "feat(a11y): add semantics to import source picker, progress, summary, and result views"
```

---

### Task 7: Landing Feature — All Sub-views

**Files:**
- Modify: `lib/src/landing_feature/landing_feature.dart:168-397`

**Step 1: Error and no-skins views**

- `_buildErrorView` (line 208-226): error icon at line 212 is decorative. `ExcludeSemantics`. Mark error text as `Semantics(liveRegion: true)`.
- `_buildNoSkinsView` (line 228-251): web_asset_off icon at line 232 is decorative. `ExcludeSemantics`.

**Step 2: Loading view**

- `_buildLoadingView` (line 253-265): `CircularProgressIndicator` at line 257 needs `Semantics(label: 'Starting WebUI server')`. Mark text as live region.

**Step 3: Skin selection view**

- Web icon at line 274: decorative. `ExcludeSemantics`.
- `ListTile` leading icons at line 304-306 (star/web_asset): these communicate "bundled vs installed" — add `semanticLabel`:
```dart
leading: Icon(
  skin.isBundled ? Icons.star : Icons.web_asset,
  color: skin.isBundled ? Colors.amber : null,
  semanticLabel: skin.isBundled ? 'Bundled skin' : 'Installed skin',
),
```
- Check circle trailing icon at line 327: selection indicator. Add `semanticLabel: 'Selected'`:
```dart
trailing: isSelected
    ? const Icon(Icons.check_circle, color: Colors.green, semanticLabel: 'Selected')
    : null,
```

**Step 4: Serving view**

- Check circle icon at line 349: decorative (heading "Skin Ready!" conveys success). `ExcludeSemantics`.
- Auto-navigate countdown text at line 377: `Semantics(liveRegion: true)` — this updates every second. Actually, announcing every second would be noisy. Instead, just mark the text as a standard semantic node (no live region). The user can navigate to it to check.
- `LinearProgressIndicator` at line 382-383: wrap with `Semantics(label: 'Auto-navigating to dashboard countdown', value: '${_remainingSeconds} seconds remaining')`.

**Step 5: Run `flutter analyze`**

Run: `flutter analyze`
Expected: No new warnings

**Step 6: Commit**

```bash
git add lib/src/landing_feature/landing_feature.dart
git commit -m "feat(a11y): add semantics to landing feature views"
```

---

### Task 8: Verify with Accessibility Inspector

**Step 1: Run the app on macOS in simulate mode**

Run: `flutter run --dart-define=simulate=1 -d macos`

**Step 2: Open Xcode Accessibility Inspector**

Open Xcode → Developer Tools → Accessibility Inspector. Point it at the running app window.

**Step 3: Walk through each step**

Navigate through the onboarding flow and verify:
- Welcome: heading and button are readable
- Permissions/Init: progress indicator has label, status text updates
- Scan: scanning state reads correctly, "taking too long" button hidden from screen reader when invisible, error views exclude decorative icons
- Import: source cards read as buttons with title text, progress updates are announced, result rows read cleanly
- Landing: skin list items have bundled/installed labels, selection indicator reads "Selected", countdown doesn't spam

**Step 4: Fix any issues found**

**Step 5: Commit fixes if any**

---

### Task 9: Update Obsidian TODO with remaining items

**Step 1: Add dashboard, settings, and shot history as subtasks under #93 in Obsidian**

Update `Professional/Decent/ReaPrime/TODO.md` to mark the onboarding accessibility as done and add remaining items as subtasks.
