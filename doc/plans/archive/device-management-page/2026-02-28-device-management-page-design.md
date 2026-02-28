# Device Management Page — Design

## Goal

Extract the device management section from the main settings page into a standalone page. The new page lets users pick preferred (auto-connect) devices from the list of currently known devices, split by machines and scales.

## Current State

- `_buildDeviceManagementSection()` in `settings_view.dart` shows device IDs and clear buttons inline.
- Preferred device IDs are stored via `SettingsController` → `SettingsService` (SharedPreferences).
- `DeviceController` tracks discovered devices via `deviceStream` (BehaviorSubject).
- `DeviceController` is not currently passed to `SettingsView`.

## Design

### New File: `lib/src/settings/device_management_page.dart`

A standalone page following the Battery/Presence page pattern.

**Constructor dependencies:**
- `SettingsController` — read/write preferred device IDs
- `DeviceController` — access `deviceStream` for the list of known devices

**Layout:**
- `Scaffold` with AppBar titled "Device Management"
- `StreamBuilder<List<Device>>` on `deviceController.deviceStream`
- Two sections, each using `_SettingsSection`-style cards:

**1. Preferred Machine**
- Lists all devices where `device.type == DeviceType.machine`
- Each row shows device name and last 8 chars of device ID
- Radio-button selection: tap to set as preferred, tap again (or "None") to clear
- Currently preferred device is pre-selected based on `settingsController.preferredMachineId`

**2. Preferred Scale**
- Same pattern for `DeviceType.scale`

**Empty state:** If no devices of a type are known, show "No machines/scales currently known" with a brief explanation that devices appear after connecting.

**On selection change:**
- Call `settingsController.setPreferredMachineId(id)` or `setPreferredScaleId(id)`
- Show a brief notice: "Changes take effect on next app start"

### Modified: `settings_view.dart`

`_buildDeviceManagementSection()` becomes a summary:

- Title: "Device Management" with icon
- Shows: "Preferred machine: {name}" or "Preferred machine: Not set"
- Shows: "Preferred scale: {name}" or "Preferred scale: Not set"
- Device names resolved from `DeviceController.devices` by matching ID; falls back to showing truncated ID if device not currently discovered
- "Configure" button navigates to `DeviceManagementPage`
- Simulated Devices toggle remains in this section

### Modified: `settings_view.dart` constructor + `app.dart`

- Add `DeviceController` parameter to `SettingsView`
- Pass `widget.deviceController` from `app.dart` when constructing `SettingsView`

### No Changes To

- `SettingsService` / `SettingsController` — reuse existing `preferredMachineId`/`preferredScaleId`
- `DeviceController` — no new methods needed
- Device models — no changes

## UX Details

- Radio selection per section (one preferred machine, one preferred scale)
- "None" option at top of each list to clear the preference
- On selection: save immediately, show snackbar "Preference saved. Takes effect on next app start."
- Device rows show: device name (bold) + device ID suffix (subtle)
