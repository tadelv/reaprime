# Plan: Devices WebSocket Endpoint (`/ws/v1/devices`)

## Context

Issue #30 requests a WebSocket endpoint that streams device list updates from `DeviceController`, fires on individual device connection state changes, sends current state on connect, and accepts bidirectional commands (scan, connect, disconnect). The controller currently has no scanning state tracking, which needs to be added.

## Outgoing Message Format

```json
{
  "devices": [
    { "name": "DE1", "id": "AA:BB:CC:DD:EE:FF", "state": "connected", "type": "machine" }
  ],
  "scanning": false
}
```

Reuses the existing `_deviceList()` JSON format, wrapped in an envelope with controller state.

## Incoming Command Format

```json
{ "command": "scan" }
{ "command": "scan", "connect": true, "quick": true }
{ "command": "connect", "deviceId": "AA:BB:CC:DD:EE:FF" }
{ "command": "disconnect", "deviceId": "AA:BB:CC:DD:EE:FF" }
```

Error responses: `{ "error": "..." }`

## Implementation Steps

### Step 1: Add scanning state to DeviceController

**File:** `lib/src/controllers/device_controller.dart`

- Add `BehaviorSubject<bool> _scanningStream` (seeded false), expose `scanningStream` getter and `isScanning` getter
- In `scanForDevices()`: set `true` before scan, `false` in the delayed callback after scan completes
- In `scanForSpecificDevices()`: set `true` at entry, `false` on success or timeout
- Close `_scanningStream` in `dispose()`

### Step 2: Add WebSocket handler to DevicesHandler

**File:** `lib/src/services/webserver/devices_handler.dart`

- Add `Logger _log`
- Add route: `app.get('/ws/v1/devices', sws.webSocketHandler(_handleDevicesSocket))`
- `_handleDevicesSocket(WebSocketChannel, String?)`:
  - Subscribe to `_controller.deviceStream` — on each update, refresh per-device `connectionState` subscriptions and emit state
  - Subscribe to `_controller.scanningStream` — emit state on change
  - Subscribe to each device's `connectionState` stream — emit state on any device state change
  - Send initial state immediately via `_emitState()` (calls existing `_deviceList()` + `isScanning`)
  - Listen to `socket.stream` for incoming commands -> `_handleCommand()`
  - Clean up all subscriptions on `onDone`/`onError`
- `_handleCommand(Map<String, dynamic>, WebSocketChannel)`:
  - `scan` -> calls `_controller.scanForDevices()` (with `connect`/`quick` params)
  - `connect` -> reuses connect logic from existing `_handleConnect` (switch on device type)
  - `disconnect` -> calls `device.disconnect()`
  - Unknown command -> error response

### Step 3: Per-device connection state tracking

Each device exposes `Stream<ConnectionState> connectionState` that fires on transitions like `connecting` -> `connected` -> `disconnecting` -> `disconnected`. The `deviceStream` only fires when the device **list** changes (device added/removed), NOT when an individual device's connection state transitions. To capture those:

- Maintain a `Map<String, StreamSubscription<ConnectionState>>` keyed by `deviceId`
- When `deviceStream` emits a new list, diff against current subscriptions:
  - Subscribe to new devices' `connectionState` streams — each fires `_emitState()` on change
  - Cancel subscriptions for devices no longer in the list
- This ensures a WebSocket message is sent when e.g. a machine goes from `connecting` to `connected`
- All per-device subscriptions are cancelled in the socket `onDone`/`onError` cleanup

### Step 4: Update AsyncAPI spec

**File:** `assets/api/websocket_v1.yml`

- Add `Devices` channel at `ws/v1/devices`
- Add `DevicesState` (outgoing) and `DevicesCommand` (incoming) messages
- Add `DevicesState`, `DeviceInfo`, `DevicesCommand` schemas

### Step 5: Tests

**Modify:** `test/devices_handler_test.dart`
- Test `DeviceController.scanningStream` state transitions
- Test WS route registration (non-404 response)

**Create:** `test/devices_ws_test.dart`
- Integration tests: start local server, connect via `IOWebSocketChannel`
- Test initial state on connection
- Test device list update emission
- Test scan/connect/disconnect commands
- Test error responses for invalid commands

## Key Design Decisions

- **Add WS to existing DevicesHandler** (not a new file) — follows `De1Handler` pattern of mixing REST+WS, handler already has all required dependencies
- **`{ "command": "..." }` format** instead of issue's `{ "connect": "<id>" }` — unambiguous dispatch, extensible, `quick-connect` maps to `{ "command": "scan", "connect": true, "quick": true }`
- **Per-device connectionState subscriptions** — `deviceStream` only fires on list changes, not individual state transitions (connecting->connected). Without this, we'd miss requirement #2
- **Full state snapshots** (not deltas) — simpler, idempotent, clients always have complete picture
- **No debounce initially** — rapid emissions are acceptable since messages are idempotent; can add throttling later if needed

## Files Modified

| File | Change |
|------|--------|
| `lib/src/controllers/device_controller.dart` | Add scanning state BehaviorSubject |
| `lib/src/services/webserver/devices_handler.dart` | Add WS route + handler + command processing |
| `assets/api/websocket_v1.yml` | Document new channel and schemas |
| `test/devices_handler_test.dart` | Scanning state tests |
| `test/devices_ws_test.dart` | New: WebSocket integration tests |

## Verification

1. `flutter test test/devices_handler_test.dart` — scanning state + route tests
2. `flutter test test/devices_ws_test.dart` — WebSocket integration tests
3. `flutter analyze` — no new warnings
4. `flutter test` — full suite passes
5. Manual: run with `simulate=1`, connect via `wscat -c ws://localhost:8080/ws/v1/devices`, verify initial state, send commands
