# Design: Device Selection Bug Fix + Preferred Device Fast Connect

**Date:** 2026-02-17  
**Branch:** fix/device-selection-on-startup

---

## Problem Statement

Two issues with the device connection startup flow:

1. **Visual bug:** When a user manually taps a device on the permissions/discovery screen, the connecting spinner disappears before navigation completes. The user can then tap again and it navigates correctly on the second tap.

2. **UX gap:** If a user has a saved `preferredMachineId`, the app still runs a full broadcast BLE scan and waits for the device to appear naturally — rather than scanning for it directly.

---

## Bug Fix: Spinner Resets on Device Stream Rebuild

### Root Cause

`_DeviceDiscoveryState` (in `permissions_view.dart`) subscribes to `deviceController.deviceStream`. When `connectToDe1()` is called, initiating the BLE connection causes the device stream to emit a new event, which triggers `setState()` on `_DeviceDiscoveryState`. This reconstructs `DeviceSelectionWidget` from scratch, wiping its internal `_connectingDeviceId` state. The spinner disappears, but `connectToDe1()` hasn't resolved yet, so navigation hasn't happened either.

### Fix: Lift Connection State to Parent

Move all connection state out of `DeviceSelectionWidget` and into `_DeviceDiscoveryState`, which already partially owns this state via `_autoConnectingDeviceId`.

**Changes to `_DeviceDiscoveryState`:**
- Add `_manualConnectingDeviceId` and `_connectionError` fields
- Handle the `onDeviceTapped` callback by calling `de1controller.connectToDe1()` directly in the parent, then calling `_navigateAfterConnection()`
- Pass `_manualConnectingDeviceId` down to `DeviceSelectionWidget` via the existing `autoConnectingDeviceId` prop (or a unified `connectingDeviceId` prop)

**Changes to `DeviceSelectionWidget`:**
- Rename `onDeviceSelected` → `onDeviceTapped` to reflect its new meaning: "user tapped this device, parent handles connection"
- Remove the `connectToDe1()` call from the tap handler — the widget no longer initiates connections
- Remove internal `_connectingDeviceId` and `_errorMessage` state — receive these entirely via props
- Becomes a pure display widget: renders device list, shows connecting state from props, calls back on tap

Since the parent owns all connection state, device stream rebuilds will no longer reset anything visible.

---

## Feature: Preferred Device Fast Connect

### Goal

If `preferredMachineId` is set, show "Connecting to your machine..." and scan specifically for that device. Navigate directly on success. Fall back to the full scan UI on failure.

### New Interface Method

`DeviceDiscoveryService` gets a new method:

```dart
Future<void> scanForSpecificDevice(String deviceId) async {
  // Default: no-op. Services that can't handle targeted scans do nothing.
}
```

Each implementation validates the `deviceId` against its own ID format and either performs a targeted scan or does nothing:

- **`BluePlusDiscoveryService`**: validates that `deviceId` is a BLE MAC/UUID format. If valid, calls `FlutterBluePlus.startScan(withRemoteIds: [DeviceIdentifier(deviceId)], withServices: [...])` — a targeted scan that returns only the specific device. Stops as soon as the device is found or after a short timeout (8s non-Linux, 20s Linux).
- **`UniversalBleDiscoveryService` / `LinuxBleDiscoveryService`**: validate BLE ID format, implement targeted scan using their respective BLE APIs if supported, otherwise fall back to `scanForDevices()`.
- **`SerialServiceDesktop`**: validates that `deviceId` exists in `SerialPort.availablePorts`. If valid, calls `_detectDevice(deviceId)` directly — no port enumeration needed.
- **`SerialServiceAndroid`**: validates that `deviceId` parses as an integer (USB device ID). If valid, finds the matching `UsbDevice` and calls `_detectDevice()` directly.
- **`SimulatedDeviceService`**: no-op (simulated devices are always "found" on normal scan).

### New `DeviceController` Method

```dart
Future<bool> scanForSpecificDevice(String deviceId)
```

- Calls `scanForSpecificDevice(deviceId)` on all services in parallel
- Listens to `deviceStream` and resolves `true` the moment a device with matching `deviceId` appears
- Resolves `false` after a timeout (8s non-Linux, 25s Linux) if the device never appears
- Returns the result so the caller can decide whether to fall back

### New UI State

Add `directConnecting` to the `DiscoveryState` enum:

```dart
enum DiscoveryState { directConnecting, searching, foundMany, foundNone }
```

**`_DeviceDiscoveryState.initState()` flow:**

1. If `preferredMachineId` is set:
   - Set state to `directConnecting` → shows "Connecting to your machine..." with a spinner
   - Call `deviceController.scanForSpecificDevice(preferredMachineId)`
   - On success: device appears in stream → `connectToDe1()` → `_navigateAfterConnection()`
   - On timeout (returns `false`): transition to `searching`, kick off normal `scanForDevices()`, proceed with standard discovery flow
2. If no `preferredMachineId`: start in `searching` as today

**New `_directConnectingView()` widget:** Simple centered column with a progress indicator and "Connecting to your machine..." text, plus a "Scan for all devices" escape hatch that cancels the direct connect and falls back to the normal scan.

---

## Files Changed

| File | Change |
|------|--------|
| `lib/src/models/device/device.dart` | Add `scanForSpecificDevice(String deviceId)` to `DeviceDiscoveryService` with default no-op |
| `lib/src/controllers/device_controller.dart` | Add `scanForSpecificDevice(String deviceId)` method |
| `lib/src/services/blue_plus_discovery_service.dart` | Implement `scanForSpecificDevice` with `withRemoteIds` targeted scan |
| `lib/src/services/universal_ble_discovery_service.dart` | Implement `scanForSpecificDevice` (targeted or fallback) |
| `lib/src/services/ble/linux_ble_discovery_service.dart` | Implement `scanForSpecificDevice` (targeted or fallback) |
| `lib/src/services/serial/serial_service_desktop.dart` | Implement `scanForSpecificDevice` with direct port detection |
| `lib/src/services/serial/serial_service_android.dart` | Implement `scanForSpecificDevice` with direct USB device detection |
| `lib/src/permissions_feature/permissions_view.dart` | Add `directConnecting` state, `_directConnectingView()`, update `initState()`; lift manual connection state from child |
| `lib/src/home_feature/widgets/device_selection_widget.dart` | Make pure display widget: `onDeviceTapped` callback, remove internal connection logic, receive connecting state via props |

---

## Non-Goals

- No changes to how `preferredMachineId` is stored (remains a plain string)
- No new data model for device transport type
- Serial services for direct connect on USB simply validate the ID format and skip BLE; BLE services skip serial IDs
