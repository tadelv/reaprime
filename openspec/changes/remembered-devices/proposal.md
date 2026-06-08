## Why

When a device the user relies on becomes unavailable — a scale moves out of BLE range, a USB cable is unplugged, a machine is powered off — it simply **vanishes** from the device list. The user loses sight of a device they've used and have to wait for it to be rediscovered, with no indication it's a known device that's merely offline. A device they've connected to before should stay visible, clearly marked **unavailable**, so they know it exists and can reconnect when it returns — and can deliberately **forget** it when they no longer want it.

This is cross-cutting: it applies to every transport (BLE machine + scale, USB serial, WiFi scale), so it belongs above the individual discovery services.

## What Changes

- **Remember devices** the user has connected to (or set as preferred), persisted across app restarts. The registry holds lightweight metadata: `{id, name, type}`.
- **Show remembered devices as `unavailable`** in the device list/API when they are not currently present, instead of dropping them. When the device reappears in discovery, it flips back to available.
- Add an **`available` flag** to each entry in the device API (REST + WebSocket): `true` for a currently-present device, `false` for a remembered device that isn't present.
- Add a **forget** action — `PUT /api/v1/devices/{id}/forget` (REST) plus a button in the GUI skin — to remove a device from the remembered registry.
- Scope: only **connected/preferred** devices are remembered (not every device ever scanned), avoiding clutter from nearby devices the user doesn't own.
- **BREAKING:** none. `available` is an added field (absent-field-tolerant clients are unaffected). Existing device entries keep all current fields.

## Capabilities

### New Capabilities
- `remembered-devices`: Persisting devices the user connects to (or prefers), surfacing remembered-but-absent devices in the device list/API as `unavailable`, computing the available/unavailable flag against live discovery, and forgetting a remembered device via the API and GUI. Covers the persistent registry, the connection-observation that adds to it, the availability computation, and the forget action.

### Modified Capabilities
<!-- None as OpenSpec specs (no existing specs dir). The device REST/WS contract is
     extended additively (an `available` field + a forget endpoint), documented in
     assets/api/*.yml and doc/Api.md. -->

## Impact

- **New code:**
  - `RememberedDevicesController` (`lib/src/controllers/`) — owns the registry, observes machine/scale connections (via `De1Controller.de1` and `ScaleController.connectionState` / `lastConnectedDeviceId`), adds `{id, name, type}` on connect, exposes the registry + a `forget(id)` method, persists via the settings layer.
  - `RememberedDevice` value type `{id, name, type}` (metadata only — not a live `Device`).
- **Persistence:** extend `SettingsService` / `SettingsController` with a `rememberedDevices` key (JSON list), mirroring the `preferredScaleId` pattern.
- **API layer:**
  - `DevicesStateAggregator` / `devices_handler.dart` — merge live devices with remembered-absent ones, add `available: bool` per entry.
  - New `PUT /api/v1/devices/{id}/forget` route in `DevicesHandler`.
  - Update `assets/api/rest_v1.yml` + `assets/api/websocket_v1.yml` (`DeviceInfo` gains `available`; add the forget endpoint) and `doc/Api.md`.
- **Wiring:** construct `RememberedDevicesController` in `main.dart`, give it `De1Controller`/`ScaleController`/settings, pass it to the webserver.
- **Skin (streamline.js, separate repo):** render `available: false` entries greyed/"unavailable" with a Forget button calling the new endpoint.
- **Unchanged:** `DeviceController` (stays live-only — the remembered/availability concept lives in the new controller + the API layer), the discovery services, the `Device` interface, transports.
- **Identity assumption:** matching is by `deviceId`, which is stable for every transport — BLE (MAC), WiFi (`wifi:<host>`), and serial (USB stable id, or the port path as a stable fallback where the OS exposes no vid/pid, e.g. macOS CH34x — see the serial path-as-id fix). The only edge case is moving a USB device to a *different* physical port, which yields a new path-based id and so a new remembered entry — arguably correct, and trivially Forgotten.
