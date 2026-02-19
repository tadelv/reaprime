# Preferred Device Selection — Design Document

**Issue:** #11
**Date:** 2026-02-19
**Status:** Draft

## Goal

Store preferred DE1 and Scale device IDs in application preferences so the app automatically connects to preferred devices on startup after scanning. Extend the existing preferred-machine functionality (which is fully implemented) to also support preferred scales.

## Requirements

1. **Settings persistence** for `preferredScaleId` (mirroring existing `preferredMachineId`)
2. **Two-column device selection screen**: machines column + scales column, same list item widget for both
3. **Machine selection required** to proceed; scale selection is optional
4. **Parallel auto-connect on startup**: scan for both preferred devices simultaneously; machine connection gates navigation, scale connects independently
5. **Skip selection screen** entirely when preferred device auto-connect succeeds (current machine behavior)
6. **REST API** exposes `preferredScaleId` alongside `preferredMachineId`
7. **Settings plugin** updated with scale preference input field
8. **Settings view** updated to display and clear preferred scale

## Current State

### What exists (machines)
- `SettingsController.preferredMachineId` with SharedPreferences persistence
- `SettingsService.preferredMachineId()` / `setPreferredMachineId()`
- `DeviceSelectionWidget` with "Auto-connect to this machine" checkbox
- `DeviceDiscoveryView` with targeted scan → fallback to full scan
- `SettingsHandler` GET/POST for `preferredMachineId`
- `settings_view.dart` shows preferred machine ID with "Clear" button
- `settings.reaplugin` shows editable text input for machine ID

### What's missing (scales)
- No `preferredScaleId` in settings layer
- No scale selection UI in device discovery screen
- `ScaleController` blindly connects to `scales.first`
- No API endpoint for preferred scale
- No settings view or plugin UI for scale preference

## Design

### Layer 1: Settings Persistence

Add to `SettingsKeys` enum:
- `preferredScaleId`

Add to `SettingsService`:
- `Future<String?> preferredScaleId()`
- `Future<void> setPreferredScaleId(String? scaleId)`

Add to `SettingsController`:
- `String? _preferredScaleId` field
- `String? get preferredScaleId` getter
- `Future<void> setPreferredScaleId(String? scaleId)` setter
- Load in `loadSettings()`

### Layer 2: Generalize DeviceSelectionWidget

Refactor `DeviceSelectionWidget` to be device-type-agnostic:
- Accept `DeviceType` parameter to filter devices from the stream
- Accept generic `onDeviceTapped(Device)` callback
- Accept `String? preferredDeviceId` and `Function(String?)? onPreferredChanged` for the checkbox
- Same card visual: name, truncated ID, connecting indicator, "Auto-connect" checkbox
- Remove hardcoded `De1Interface` cast — work with `Device` interface

### Layer 3: Two-Column Discovery UI

Refactor `_resultsView` in `_DeviceDiscoveryState`:
- **Layout:** `Row` with two `Expanded` children — machines column (left) and scales column (right)
- **Machine column:** required — shows discovered machines with selection + auto-connect checkbox
- **Scale column:** optional — shows discovered scales with selection + auto-connect checkbox. Shows "No scales found" if empty
- **Connect button:** at the bottom, enabled once a machine is tapped. Optionally also connects selected scale
- **State tracking:** track `_selectedMachine` and `_selectedScale` separately; machine is the gate for the connect button

Sizing: widen the current `SizedBox(height: 500, width: 300)` to accommodate two columns (e.g., `width: 600` or use `ConstrainedBox`).

### Layer 4: Startup Auto-Connect

In `_DeviceDiscoveryState.initState`:
- Check both `preferredMachineId` and `preferredScaleId`
- If `preferredMachineId` is set: targeted scan for machine (existing behavior)
- If `preferredScaleId` is set: pass it to `ScaleController` so it can prefer that scale during auto-connect
- Both scans happen in parallel via the existing `DeviceController`

Modify `ScaleController`:
- Accept `preferredScaleId` (via constructor or setter from settings)
- In the device stream listener: if `preferredScaleId` is set, connect only to the scale with that ID (not `scales.first`)
- If preferred scale not found after scan completes, don't connect any scale (user can connect manually later or from settings tile)

Navigation: machine auto-connect success → navigate immediately (skip selection screen). Scale connects in the background.

### Layer 5: REST API

Update `SettingsHandler`:
- `GET /api/v1/settings`: include `preferredScaleId` in response
- `POST /api/v1/settings`: accept `preferredScaleId` (string or null)

### Layer 6: Settings Plugin & Settings View

**settings.reaplugin/plugin.js:**
- Add "Auto-Connect Scale ID" input field in the HTML UI, mirroring the existing "Auto-Connect Device ID" field
- Uses existing generic `updateReaSetting('preferredScaleId', value)` — no new JS logic needed

**settings_view.dart:**
- In `_buildDeviceManagementSection()`, add a "Preferred Scale" subsection below the existing "Auto-Connect Device" section
- When set: show scale ID + destructive "Clear Auto-Connect Scale" button
- When unset: show "No auto-connect scale set" in italic with help text
- Update `_showPreferredDeviceInfo()` dialog to also mention scale auto-connect

## Key Files to Modify

| File | Changes |
|------|---------|
| `lib/src/settings/settings_service.dart` | Add `preferredScaleId` methods + key |
| `lib/src/settings/settings_controller.dart` | Add `preferredScaleId` field/getter/setter |
| `lib/src/home_feature/widgets/device_selection_widget.dart` | Generalize to support any DeviceType |
| `lib/src/permissions_feature/permissions_view.dart` | Two-column layout, parallel auto-connect |
| `lib/src/controllers/scale_controller.dart` | Prefer `preferredScaleId` over `scales.first` |
| `lib/src/services/webserver/settings_handler.dart` | Add `preferredScaleId` to GET/POST |
| `lib/src/settings/settings_view.dart` | Add preferred scale display/clear UI |
| `assets/plugins/settings.reaplugin/plugin.js` | Add scale ID input field |

## Out of Scope

- Preferred sensor selection (sensors are not user-facing in the same way)
- Multiple preferred scales (only one preferred scale ID)
- Scale-specific targeted BLE scan (scales piggyback on the existing full scan; the preference filtering happens in `ScaleController`)
