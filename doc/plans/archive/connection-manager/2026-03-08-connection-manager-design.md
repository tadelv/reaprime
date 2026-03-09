# Connection Manager — Design Document

Companion to [2026-03-07-connection-management-refactor.md](2026-03-07-connection-management-refactor.md) (problem statement).

## Overview

Introduce a `ConnectionManager` that centralizes all device connection policy — preferred device matching, DE1→scale serialization, preference saving, and ambiguity resolution. All callers (UI, API, De1StateManager) go through ConnectionManager. Existing controllers (De1Controller, ScaleController) become pure executors.

## Architecture

```
Callers (DeviceDiscoveryView, SettingsTile, DevicesHandler, De1StateManager)
        │
  ConnectionManager  ← policy: preferred matching, serialization, preference saving
        │
  ┌─────┴─────┐
De1Controller  ScaleController  ← pure executors: connect/disconnect only
        │
  DeviceController  ← scan + device stream (unchanged)
```

## ConnectionManager Interface

```dart
class ConnectionManager {
  // Entry points
  Future<void> connect({BuildContext? uiContext});
  Future<void> connectMachine(De1Interface machine);
  Future<void> connectScale(Scale scale);
  Future<void> disconnectMachine();
  Future<void> disconnectScale();

  // Observable state
  Stream<ConnectionStatus> get status;

  // Dependencies (constructor-injected)
  // DeviceController, De1Controller, ScaleController, SettingsController
}
```

## Connection Flow

### `connect({BuildContext? uiContext})` — Main entry point

All scan+connect requests go through this. There is no separate "scan without connecting" at the ConnectionManager level.

**Machine phase:**

1. Start full unfiltered scan via `DeviceController.scanForDevices()`.
2. Apply preferred device policy to scan results:
   - **Preferred machine ID set, found in results** → `connectMachine(preferred)`
   - **Preferred machine ID set, not found** → wait briefly, retry. Still not found:
     - `uiContext != null` → show device list to user
     - `uiContext == null` → emit `pendingAmbiguity: machinePicker`
   - **No preferred, 0 machines** → emit `noDevicesFound`
   - **No preferred, 1 machine** → `connectMachine(onlyOne)`
   - **No preferred, many machines** →
     - `uiContext != null` → show picker dialog
     - `uiContext == null` → emit `pendingAmbiguity: machinePicker`

3. On successful machine connection → save device ID as preferred.

**Scale phase (silent, non-blocking, after machine connects):**

1. Apply preferred device policy to found scales:
   - **Preferred scale, found** → `connectScale(preferred)`
   - **Preferred scale, not found** → do nothing
   - **No preferred, 0 scales** → do nothing
   - **No preferred, 1 scale** → `connectScale(onlyOne)`
   - **No preferred, many scales** →
     - `uiContext != null` → show picker
     - `uiContext == null` → skip (skin can read device list and resolve)

2. On successful scale connection → save device ID as preferred.

### `connectMachine(machine)` / `connectScale(scale)` — Direct connect

For when the caller already has a specific device (debug view, API connect command, user picks from dialog):

1. Concurrent connection guard — reject if already connecting same device type.
2. Delegate to `De1Controller.connectToDe1()` or `ScaleController.connectToScale()`.
3. On success → save as preferred via SettingsController.

## ConnectionStatus Stream

```dart
enum ConnectionPhase {
  idle,
  scanning,
  connectingMachine,
  connectingScale,
  ready,
}

enum AmbiguityReason {
  machinePicker,
  scalePicker,
}

class ConnectionStatus {
  final ConnectionPhase phase;
  final List<De1Interface> foundMachines;
  final List<Scale> foundScales;
  final AmbiguityReason? pendingAmbiguity;
  final String? error;
}
```

**How callers use it:**

- **DeviceDiscoveryView** — observes `phase` for progress, `pendingAmbiguity` to show picker dialogs. ConnectionManager can also show pickers directly when `uiContext` is provided.
- **Skins/API** — observe via WebSocket devices stream. When `pendingAmbiguity == machinePicker`, skin shows its own selection UI, then calls `connectMachine(selected)`.
- **SettingsTile** — calls `connect(uiContext: context)`, observes `phase` for spinner.
- **De1StateManager** — calls `connect()` (no uiContext) on wake-from-sleep.

## Preferred Device Policy

- No preferred device → user picks (or first-found if only one); saved on successful connection.
- Has preferred device → connect directly if found; show device list on failure.
- Any successful connection saves the device as preferred (UI, API, auto-connect — all the same).
- Users can manually manage preferences in settings UI or via API.

## Reconnection Policy

- No auto-reconnect at ConnectionManager level. DE1 transport layer handles its own reconnection.
- Callers (UI, skin, API) explicitly trigger `connect()` when they want reconnection.

## Scale Connection Policy

- Scales connect after DE1, silently and non-blocking.
- Scale failure never blocks the user.
- Multiple scales with no preference and no `uiContext` → skip. Skin/API documentation should note: when scan completes and multiple scales are found but none connected, the skin should prompt the user.

## Debug View Requirements

- Debug views must not call `device.onConnect()` in `build()`.
- Each device in the debug list gets two actions:
  - **Inspect** — calls `device.onConnect()` directly for raw stream/command access. Device is NOT registered with De1Controller/ScaleController.
  - **Connect** — calls `connectionManager.connectMachine()` or `connectionManager.connectScale()`, registering the device as the active device for shots/workflows/API.

## Impact on Existing Code

### Logic removed:

| File | Change |
|------|--------|
| DeviceDiscoveryView | Becomes thin UI: calls `connectionManager.connect(uiContext:)`, observes status stream. All preferred device logic, fallback, serialization, stream listeners removed. |
| ScaleController | Auto-connect listener removed. Pure executor: `connectToScale()` / disconnect only. |
| DeviceController | `shouldAutoConnect` flag removed. `scanForSpecificDevices()` / `scanForSpecificDevice()` removed. |
| SettingsTile | `_searchAndConnect()` replaced with `connectionManager.connect(uiContext:)`. |
| De1StateManager | Scale-scan-on-wake calls `connectionManager.connect()` instead of `scanForDevices(autoConnect: true)`. |
| DevicesHandler | scan/connect commands delegate to ConnectionManager. Exposes ConnectionStatus on WebSocket. |

### Unchanged:

| File | Why |
|------|-----|
| De1Controller | Pure executor, called by ConnectionManager. |
| DeviceController (core) | Scan + device stream unchanged. |
| SettingsController | ConnectionManager calls setPreferred* on success. |

### New:

| File | What |
|------|------|
| `lib/src/controllers/connection_manager.dart` | New ConnectionManager class. |
| Debug views | Remove onConnect from build, add Inspect/Connect buttons. |
| main.dart | Create ConnectionManager, inject dependencies. |

## Testing

### Unit tests (ConnectionManager):

- No preferred, 1 machine → auto-connects, saves preference
- No preferred, many machines, with uiContext → picker callback
- No preferred, many machines, no uiContext → pendingAmbiguity
- Preferred found → direct connect
- Preferred not found → fallback to list / ambiguity
- Scale: preferred found → silent connect after DE1
- Scale: many, no preference, no uiContext → skip
- Scale: many, no preference, with uiContext → picker
- Concurrent guard → second connect rejected while first in progress
- Preference saved on success, not on failure
- Serialization → scale only after DE1 completes

### Mocks:

- MockDeviceController — control device stream
- MockDe1Controller / MockScaleController — verify connect calls
- MockSettingsController — verify preference reads/writes

### Integration:

- Run with `simulate=1`, verify full flow via MCP tools
