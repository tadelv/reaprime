## Context

Today the device list (`GET /api/v1/devices`, the devices WebSocket) is built from `DeviceController.devices` — the live union of all discovery services. When a device disappears from discovery it's simply gone. `DevicesStateAggregator` (`devices_handler.dart`) serializes each device as `{name, id, state, type}`. Preferred devices are persisted as single ids (`preferredScaleId`/`preferredMachineId`) via `SettingsService` (shared_preferences). Connections are observable: `De1Controller.de1` emits a `De1Interface` on machine connect; `ScaleController.connectionState` flips to `connected` and `ScaleController.lastConnectedDeviceId` holds the scale id.

The user wants devices they've used to persist as **unavailable** entries when offline (all transports), removable via **forget** (API + GUI).

## Goals / Non-Goals

**Goals:**
- Persist `{id, name, type}` for devices the user connects to or prefers, across restarts.
- Show remembered-but-absent devices in the device API as `available: false`; present ones as `available: true`.
- A forget action (REST + GUI) that drops a device from the registry.
- Cross-transport (BLE/USB/WiFi) by construction.
- Keep `DeviceController` and the discovery services unchanged — they stay live-only.

**Non-Goals:**
- Connecting *to* an unavailable device directly (it has no live transport). Reconnect happens the normal way once it reappears in discovery.
- Remembering every discovered device (only connected — avoids clutter).
- Remembering sensors (scope is the user-connectable machine + scale, matching the preferred-device model). Extensible later.
- Fixing the macOS USB unstable-id issue (documented limitation; tracked separately).

## Decisions

### Decision: A dedicated `RememberedDevicesController`, not changes to `DeviceController`
**Choice:** Introduce `RememberedDevicesController` that owns the registry, observes connections, persists, and exposes `remembered` (the registry) + `forget(id)`. `DeviceController` stays live-only.
**Why:** "Remembered/unavailable" is a presentation+persistence concern layered above live discovery. `DeviceController` deals in live `Device` objects with transports; a remembered-absent device is metadata only. Mixing metadata placeholders into `DeviceController.devices` would pollute connect/scan logic. Single-responsibility: the new controller remembers; the API layer merges.
**Alternative:** Make `DeviceController` emit remembered placeholders — rejected (invasive, muddies the live-device invariants).

### Decision: Compute `available` at the API layer (DevicesStateAggregator / devices_handler)
**Choice:** The device-list serialization merges `DeviceController.devices` (present → `available: true`) with the remembered registry entries that aren't present (→ `available: false`).
**Why:** Keeps the registry pure data and the live stream pure live. The merge is a read-time join in the one place that builds the API snapshot, so REST and WebSocket share it.
**Mechanics:** present ids = `DeviceController.devices.map(id)`. For each remembered entry whose id ∉ present, emit `{id, name, type, state: "disconnected", available: false}`. For each present device, emit its real `{id, name, type, state}` + `available: true`.

### Decision: Observe connections via existing controller streams
**Choice:** `RememberedDevicesController` subscribes to `De1Controller.de1` (machine connect → remember `{id, name, machine}`) and `ScaleController.connectionState` (on `connected` → remember the connected scale via `ScaleController.connectedScale()` `{id, name, scale}`). Preferred ids already persisted are also folded into the registry on load.
**Why:** Reuses the cleanest existing "device connected" signals without threading new callbacks through `ConnectionManager`. No change to the comms layer.
**Alternative:** Hook `DisconnectSupervisor.onScaleConnected/onMachineConnected` — those fire but don't carry the device metadata; we'd still have to read it from the controllers. Observing the controllers directly is simpler.

### Decision: Persist as a JSON list in the settings layer
**Choice:** Add a `rememberedDevices` key to `SettingsService` storing a JSON array of `{id, name, type}`; load into `RememberedDevicesController` at init, save on every change. Mirrors the `preferredScaleId` persistence pattern (shared_preferences).
**Why:** Small, structured, consistent with existing settings persistence. No new storage dependency. (Drift is available if the registry ever needs querying, but a JSON list is right-sized here.)

### Decision: Forget = `PUT /api/v1/devices/forget` (deviceId in body/query)
**Choice:** A new route in `DevicesHandler` reads `deviceId` from the JSON body (or a `?deviceId=` query fallback) and calls `RememberedDevicesController.forget(id)`. The next device snapshot omits the (absent) device.
**Why:** Fits the existing `/api/v1/devices/...` handler grouping and the verb style there (`connect`/`disconnect` are `PUT`). The id is **not** in the path because serial ids are paths (`/dev/cu.*`) and WiFi ids contain `:` — neither is URL-path-safe.

## Data flow

```
  connect machine ── De1Controller.de1 ──────────────┐
  connect scale ──── ScaleController.connected +     ┤→ RememberedDevicesController
                     connectedScale() ───────────────┘     remember {id,name,type}
                                                       persist (settings JSON)
                                                            │ registry
   DeviceController.devices (live) ──────────┐             ▼
                                              ├──► DevicesStateAggregator / devices_handler
   RememberedDevicesController.remembered ────┘     merge → available:true (present)
                                                            available:false (remembered-absent)
                                                       ▼
                                         GET /api/v1/devices  +  ws/v1/devices snapshot
                                         PUT /api/v1/devices/forget {deviceId} → registry.remove
                                                       ▼
                                                 skin: greyed "unavailable" + Forget button
```

## Risks / Trade-offs

- **deviceId stability** → matching is by `deviceId`. This is stable per transport: BLE MAC, WiFi `wifi:<host>`, and serial (real USB stable id, or — where the OS exposes no vid/pid, e.g. macOS CH34x — the port *path*, which is stable per physical port; this is the serial path-as-id fix, not the churny libserialport handle). Residual: moving a USB device to a different physical port yields a new id and a new remembered entry. Minor and arguably correct; the user can Forget the stale one.
- **Registry growth** → only connected devices are remembered, and Forget prunes. Bounded in practice (a user has a handful of machines/scales). No auto-expiry (keeps it predictable); revisit if it becomes noisy.
- **Skin must handle `available`** → an un-updated skin would render an unavailable device as if available. Mitigation: the field is additive; the skin change (grey + Forget) ships alongside. Until then, unavailable devices appear as normal disconnected entries — degraded but not broken.
- **Connecting to an unavailable entry** → it has no transport. The UI should drive a rescan/reconnect when tapped, not attempt a direct connect. Documented in the API/skin behavior.
- **Sensors excluded** → matches preferred-device scope; if users want remembered sensors later it's an additive extension.
