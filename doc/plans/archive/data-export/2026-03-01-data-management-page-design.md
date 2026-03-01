# Data Management Settings Page Design

## Overview

A dedicated settings sub-page for all data-related operations: export, import, backup, telemetry consent, and feedback. Follows the established sub-page pattern used by `BatteryChargingSettingsPage`, `PresenceSettingsPage`, and `DeviceManagementPage`.

## Motivation

The full data export/import feature (added on this branch) has no UI access point. Additionally, the existing data-related buttons (export logs, export shots, import shots, send feedback) and the telemetry toggle are scattered across two sections in settings_view.dart. Consolidating them into a dedicated page improves discoverability and organization.

## Page Layout

### Section 1: Export & Backup (`ShadCard`)

- **Export Full Backup** — Calls `GET /api/v1/data/export` on the local web server, saves the ZIP via FilePicker. Primary backup action.
- **Export Logs** — Existing logic from `_exportLogs()`: reads log file, saves via FilePicker.
- **Export Shots** — Existing logic from `_exportShots()`: exports shot JSON wrapped in a zip archive via FilePicker.

### Section 2: Import & Restore (`ShadCard`)

- **Import Full Backup** — File picker for ZIP files, then a dialog letting user choose conflict strategy (skip existing / overwrite). Calls `POST /api/v1/data/import?onConflict=...`. Displays the import result summary afterward.

The separate "Import shots" button is removed — the full import handles shots along with everything else.

### Section 3: Privacy & Feedback (`ShadCard`)

- **Anonymous crash reporting** — `ShadSwitch` toggle, moved from the Advanced section. Same sublabel text.
- **Send Feedback** — Existing `showFeedbackDialog()` call.

## Changes to settings_view.dart

- `_buildDataManagementSection()` → Simplified to a summary card with subtitle + "Configure" button navigating to `DataManagementPage` via `MaterialPageRoute`.
- Telemetry toggle removed from `_buildAdvancedSection()`.
- Export/import helper methods (`_exportLogs()`, `_exportShots()`, `_showImportDialog()`) removed — logic moves to the new page.

## New File

`lib/src/settings/data_management_page.dart`

## Dependencies

Constructor receives:
- `SettingsController` — telemetry toggle
- `PersistenceController` — shot export
- `WebUIService` — web server host/port for data export/import API calls

## Pattern Conformance

Follows the established sub-page pattern:
- `StatefulWidget` with `Scaffold` + `AppBar(title: "Data Management")`
- `ListenableBuilder(listenable: settingsController)` wrapping the body
- `SafeArea(top: false)` + `SingleChildScrollView` + `Column(spacing: 16)`
- Each section as a `ShadCard`
