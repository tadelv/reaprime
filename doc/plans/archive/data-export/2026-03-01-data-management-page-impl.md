# Data Management Settings Page Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a dedicated Data Management settings sub-page consolidating export, import, telemetry, and feedback controls.

**Architecture:** New `DataManagementPage` widget following the established sub-page pattern (`PresenceSettingsPage` as template). Move existing export/import/feedback logic from `settings_view.dart` into the new page. Add full backup export/import via the local REST API (`localhost:8080`). Move telemetry toggle from Advanced section.

**Tech Stack:** Flutter, ShadCN UI (`ShadCard`, `ShadButton`, `ShadSwitch`, `ShadDialog`), `dart:io` HttpClient, `file_picker`, `archive`

---

### Task 1: Create DataManagementPage with export section

**Files:**
- Create: `lib/src/settings/data_management_page.dart`

**What to build:**

Create `DataManagementPage` as a `StatefulWidget` following the `PresenceSettingsPage` pattern:
- Constructor takes `SettingsController`, `PersistenceController`
- `Scaffold` + `AppBar(title: "Data Management")`
- `ListenableBuilder(listenable: controller)` wrapping the body
- `SafeArea(top: false)` + `SingleChildScrollView` + `Column(spacing: 16)`

**Section 1: "Export & Backup"** (`ShadCard`):
- "Export Full Backup" button — calls `GET http://localhost:8080/api/v1/data/export` using `dart:io` `HttpClient`, saves response bytes via `FilePicker.platform.saveFile(fileName: "streamline_bridge_export_<timestamp>.zip")`. Show progress dialog during download, success/error snackbar after.
- "Export Logs" button — move `_exportLogs()` logic from `settings_view.dart:668-699`
- "Export Shots" button — move `_exportShots()` logic from `settings_view.dart:701-742`

**Section 2: "Import & Restore"** (`ShadCard`):
- "Import Full Backup" button — opens a `ShadDialog` with conflict strategy choice (Skip existing / Overwrite), then `FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['zip'])`, reads bytes, POSTs to `http://localhost:8080/api/v1/data/import?onConflict=skip|overwrite` with body bytes. Show progress dialog, then result summary dialog showing imported/skipped/error counts per section.

**Section 3: "Privacy & Feedback"** (`ShadCard`):
- `ShadSwitch` for "Anonymous crash reporting" — same as current Advanced section (`settings_view.dart:485-495`)
- "Send Feedback" button — same `showFeedbackDialog()` call as current (`settings_view.dart:418-426`)

**Imports needed:**
```dart
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:archive/archive_io.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reaprime/src/controllers/persistence_controller.dart';
import 'package:reaprime/src/feedback_feature/feedback_view.dart';
import 'package:reaprime/src/settings/settings_controller.dart';
import 'package:reaprime/src/util/shot_exporter.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
```

**Reference files:**
- Template: `lib/src/settings/presence_settings_page.dart` (page structure)
- Export logic to move: `lib/src/settings/settings_view.dart:668-742` (`_exportLogs`, `_exportShots`)
- Feedback call: `lib/src/settings/settings_view.dart:418-426`
- Telemetry toggle: `lib/src/settings/settings_view.dart:485-495`
- Progress dialog pattern: `lib/src/settings/settings_view.dart:1021-1038` (`_showProgressDialog`)

**Step 1:** Create the file with all three sections and all action methods.

**Step 2:** Run `flutter analyze lib/src/settings/data_management_page.dart` — expect no issues.

**Step 3:** Commit: `feat: add DataManagementPage with export, import, telemetry, and feedback`

---

### Task 2: Wire into settings_view.dart

**Files:**
- Modify: `lib/src/settings/settings_view.dart`

**What to change:**

1. **Replace `_buildDataManagementSection()`** (lines 396-432) with a summary card + "Configure" button following the `_buildPresenceSection()` pattern (lines 252-315):
   - Icon: `Icons.storage_outlined`
   - Title: "Data Management"
   - Description: "Export, import, and backup your data"
   - Subtitle: "Backup, restore, and privacy settings"
   - `ShadButton.outline` "Configure" → `Navigator.of(context).push(MaterialPageRoute(builder: (_) => DataManagementPage(...)))`

2. **Remove telemetry toggle from `_buildAdvancedSection()`** (lines 485-496 — the `ShadSwitch` and following `Divider`).

3. **Remove moved methods:** `_exportLogs()` (668-699), `_exportShots()` (701-742), `_showImportDialog()` (990-1019), `_showProgressDialog()` (1021-1038), `_importFromFile()` (1040-1101), `_importFromFolder()` (1103-1164).

4. **Clean up unused imports** that were only needed for the removed methods: `archive/archive_io.dart`, `path_provider`, `shot_exporter.dart`, `shot_importer.dart`, `feedback_view.dart`. Add import for `data_management_page.dart`.

5. **Remove `PersistenceController` from constructor** if it's no longer used in `settings_view.dart` after moving the export/import methods. Check if anything else uses it first.

**Step 1:** Make all changes.

**Step 2:** Run `flutter analyze` — expect no issues.

**Step 3:** Run `flutter test` — expect all existing tests still pass (237 pass, 4 pre-existing failures).

**Step 4:** Commit: `refactor: move data management controls to dedicated sub-page`

---

### Task 3: Final verification

**Step 1:** Run `flutter analyze` — no issues.

**Step 2:** Run `flutter test` — same pass/fail counts as before.

**Step 3:** Run `flutter run --dart-define=simulate=1` so user can visually verify the settings page navigation, export/import buttons, and telemetry toggle.
