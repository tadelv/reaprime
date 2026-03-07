# Connection Management Refactor — Problem Statement & Requirements

## Problem

Device connection logic is scattered across 4+ locations with duplicated, inconsistent, and race-prone behavior:

### Where connection logic lives today

| Location | What it does | Problems |
|----------|-------------|----------|
| `DeviceDiscoveryView` (UI) | Preferred device scan, auto-connect, fallback to full scan, connection serialization (DE1 then scale), navigation | Business logic in UI; race between `_startDirectConnect` and `_discoverySubscription`; not reachable from API |
| `ScaleController` | Auto-connect to preferred/first scale when it appears in device stream | Has `_isConnecting` guard but is independently triggered — can race with discovery view's explicit `connectToScale` |
| `De1Controller` | `connectToDe1()` — connects to a given DE1, no auto-connect | No preferred device awareness; caller must find and pass the device |
| `De1StateManager` | Triggers scale scan after DE1 connects and shot ends | Yet another place that triggers scans with `autoConnect: true` |
| `SettingsTile` (UI) | Scan + connect from home screen, with dialog for multiple devices | Duplicates scan→discover→connect logic from discovery view |
| `DevicesHandler` (API) | `scan`, `connect`, `disconnect` commands via REST/WebSocket | No preferred device awareness — `{"command": "scan"}` won't auto-connect to preferred devices |

### Specific bugs / gaps

1. **API scan doesn't reconnect preferred devices.** Sending `{"command": "scan"}` over the devices WebSocket triggers `DeviceController.scanForDevices(autoConnect: connect)` but `autoConnect` is a simple boolean on `DeviceController` — `ScaleController` checks it, but `De1Controller` has no auto-connect at all. A skin or API client cannot trigger "reconnect to my preferred machine."

2. **UI-only preferred device logic.** The preferred machine ID is only acted on in `DeviceDiscoveryView.initState()`. If the view is not mounted (e.g., already past the discovery screen), the preferred device logic is dead.

3. **Race conditions.** Multiple async paths react to the same device stream updates, causing duplicate `connectToDe1` / `connectToScale` calls. We've added workarounds (`_autoConnectDeviceId` nulling, `_isConnecting` flag) but the root cause is distributed ownership.

4. **Connection serialization is fragile.** DE1-before-scale ordering is only enforced in `DeviceDiscoveryView._handleContinue()` and `_startDirectConnect()`. Other paths (API, settings tile, auto-connect) don't serialize and can overwhelm the BLE stack.

5. **Duplicate scan+connect logic.** `SettingsTile._searchAndConnect()` reimplements scan→wait→connect with a hardcoded delay instead of reacting to device stream events.

## Requirements

### Must have

- **Single owner for connection policy.** One controller decides when and how to connect to devices. No connection logic in UI widgets.
- **Preferred device auto-connect.** When a scan discovers the preferred machine or scale, connect automatically — regardless of whether triggered from UI, API, or internal logic.
- **Connection serialization.** DE1 connects first, then scale. Enforced in one place, used by all paths.
- **API parity.** `{"command": "scan"}` should reconnect to preferred devices. API clients get the same behavior as the UI.
- **Concurrent connection guard.** Only one connection attempt per device type at a time, enforced centrally.
- **Connection status stream.** Controllers/UI can observe connection progress (scanning, connecting machine, connecting scale, ready, failed).

### Nice to have

- **Reconnection on disconnect.** If a device drops, optionally trigger a scan to reconnect (with backoff).
- **Scan deduplication.** Multiple callers requesting a scan should share the same scan operation, not start competing scans.

### Out of scope (for now)

- Changing the BLE transport layer
- Multi-machine support (connecting to 2+ DE1s simultaneously)
- Changing how `DeviceController` / `DeviceDiscoveryService` discover devices

## Current architecture reference

```
DeviceDiscoveryView (UI)
  ├── reads preferredMachineId / preferredScaleId from SettingsController
  ├── calls DeviceController.scanForSpecificDevices()
  ├── listens to DeviceController.deviceStream
  ├── calls De1Controller.connectToDe1()
  ├── calls ScaleController.connectToScale()
  └── navigates on success

ScaleController
  ├── listens to DeviceController.deviceStream
  ├── auto-connects when scale appears (if shouldAutoConnect && !_isConnecting)
  └── connectToScale() — manages connection lifecycle

De1Controller
  ├── connectToDe1() — manages connection lifecycle
  └── NO auto-connect, NO preferred device awareness

DevicesHandler (API)
  ├── scan → DeviceController.scanForDevices(autoConnect: bool)
  ├── connect → De1Controller.connectToDe1() / ScaleController.connectToScale()
  └── NO preferred device awareness

De1StateManager
  └── triggers scale scan after shot ends (autoConnect: true)

SettingsTile (UI)
  └── reimplements scan → wait → connect with hardcoded delay
```

## Key files

- `lib/src/device_discovery_feature/device_discovery_view.dart` — UI with embedded connection logic
- `lib/src/controllers/scale_controller.dart` — scale auto-connect
- `lib/src/controllers/de1_controller.dart` — DE1 connection (no auto-connect)
- `lib/src/controllers/device_controller.dart` — device discovery, scan management
- `lib/src/controllers/de1_state_manager.dart` — triggers scale scan
- `lib/src/services/webserver/devices_handler.dart` — API scan/connect/disconnect
- `lib/src/home_feature/tiles/settings_tile.dart` — duplicate scan+connect in UI
- `lib/src/settings/settings_controller.dart` — stores preferredMachineId / preferredScaleId
