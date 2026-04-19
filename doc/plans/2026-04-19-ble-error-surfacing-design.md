# BLE Error Surfacing — Design

**Date:** 2026-04-19
**Status:** approved (design)
**Branch:** fix/ble-contd (continuation of fix/de1-disconnect-logging lineage)

## Problem

BLE connect failures, mid-session disconnects, and adapter-level
problems (Bluetooth off, permission revoked, scan failed) are swallowed
silently. Today the user sees no feedback when, e.g., a scale connect
times out with `FlutterBluePlusException | fbp-code: 1` — the app just
sits at "scanning done, not connected" and the only recovery path is
restarting Streamline-Bridge. This was directly reproduced on m50mini
at 07:49 on 2026-04-19.

On top of surfacing, a related bug caused `_scaleConnected = true` to
stick on `ConnectionManager` after a failed connect, making every
subsequent retry skip the scale phase. That is already fixed on this
branch (commit `3930ddd`, `ScaleController.connectToScale` now throws).

## Goal

Make every BLE-side failure visible to the user, whether they are on a
native Flutter screen (`HomeView`, `DeviceDiscoveryView`) or a WebUI
skin consuming the existing REST / WebSocket surface. Give skins a
structured payload they can look up, localize, and render however
their UX demands.

## Non-goals

- Auto-reconnect changes. Out of scope for this design — addressed
  separately if/when we decide to add healing loops.
- Operation-level failures on already-connected devices (profile
  upload, characteristic write timeouts). Not included in this pass
  (class D from the scope discussion was explicitly dropped).
- Localization. App emits English `message` / `suggestion`; skins
  that want i18n key off `kind` and use their own tables.
- Dismiss / ack protocol. Errors self-clear via the rules in
  section "Clearing rules". Ack can be added later without breaking
  the shape.

## Scope (error classes covered)

1. **Connect failures** — scale or DE1 connect timeout, GATT 133
   retries exhausted, service-not-found after connect.
2. **Mid-session disconnects** — radio-initiated drops
   (e.g., `LINK_SUPERVISION_TIMEOUT`) and remote-initiated drops.
   App-initiated deliberate teardowns (sleep flow) are **not**
   surfaced as errors.
3. **Adapter-level** — Bluetooth adapter off, BLE permission denied,
   scan failed to start.

## Taxonomy (initial set of `kind` values)

| `kind`                      | When                                                            | Sticky? |
|-----------------------------|-----------------------------------------------------------------|---------|
| `scaleConnectFailed`        | scale connect timeout / GATT 133 retries exhausted / etc.       | no      |
| `machineConnectFailed`      | DE1 connect fails                                               | no      |
| `scaleDisconnected`         | mid-session drop (not app-initiated)                            | no      |
| `machineDisconnected`       | mid-session drop (not app-initiated)                            | no      |
| `adapterOff`                | Bluetooth adapter powered off                                   | yes     |
| `bluetoothPermissionDenied` | BLE runtime permission refused                                  | yes     |
| `scanFailed`                | `scanForDevices()` failed to start (non-permission causes)      | yes     |

`kind` is a free string on the wire (not a locked enum). Adding new
kinds later is a server-only change.

## Data model

Replace the existing `ConnectionStatus.error: String?` with a
structured object:

```dart
class ConnectionError {
  final String kind;                   // see taxonomy
  final String severity;               // "warning" | "error"
  final DateTime timestamp;
  final String? deviceId;
  final String? deviceName;
  final String message;                // English default supplied by app
  final String? suggestion;            // English default supplied by app
  final Map<String, dynamic>? details; // freeform diagnostic payload
}
```

`ConnectionErrorKind` constants class provides use-site ergonomics for
server code. Wire schema keeps `kind` as a plain string.

## Emission plumbing

Single aggregation point on `ConnectionManager`:

```dart
void _emit(ConnectionError e);
void _clearError();
```

`_emit` updates `currentStatus.error` and publishes on the existing
`_statusSubject`. `_clearError` sets it back to `null`. All sources
route through these two methods.

### Sources

- **Connect failures** — `connectScale` and `connectMachine` catch
  blocks construct a `ConnectionError` from the thrown exception,
  preserving `FlutterBluePlusException.code` in `details.fbp_code`,
  and call `_emit`. `ScaleController.connectToScale` already throws
  on failed-state (commit `3930ddd`); `De1Controller.connectToDe1`
  audited to confirm it also surfaces the failure. (If not, add a
  throw there.)
- **Mid-session disconnects** — the existing `_listenForDisconnects`
  subscribes to `de1Controller.de1` and `scaleController.connectionState`.
  On a connected → disconnected transition, check the
  `_expectingDisconnectFor` set: if the `deviceId` is present, consume
  and suppress; otherwise emit `scaleDisconnected` or
  `machineDisconnected`.
- **Adapter off / on** — new subscription to
  `deviceScanner.adapterStateStream` (already exposed by
  `BleDiscoveryService`). On `off` → `_emit(kind: adapterOff)`. On
  `on` → if `currentError.kind == adapterOff` clear; else leave
  alone.
- **Permission / scan failures** — wrap the scan-start path in
  `_connectImpl` with a try/catch that classifies by exception type
  into `bluetoothPermissionDenied` or `scanFailed`.

### Deliberate-disconnect tracking

```dart
final Set<String> _expectingDisconnectFor = {};

void _markExpectingDisconnect(String deviceId) {
  _expectingDisconnectFor.add(deviceId);
  Timer(const Duration(seconds: 10),
      () => _expectingDisconnectFor.remove(deviceId));
}
```

Cleanup paths:

1. **Normal:** disconnect subscriber removes the entry when it matches.
2. **TTL:** 10-second safety timer removes stale entries if the
   expected disconnect event never arrives.
3. **Dispose:** `ConnectionManager.dispose()` clears the set.

Call sites: `De1StateManager` scale-power-off path (sleep flow), any
`ConnectionManager.disconnect*` paths, and the auto-sleep flow.
Specific sites enumerated in the implementation plan.

## Clearing rules

Per design discussion (A+B+C from Q5):

- **Transient kinds** (all kinds not in the sticky set) auto-clear on
  any `ConnectionPhase` transition into `scanning`,
  `connectingMachine`, `connectingScale`, or `ready`.
- **Sticky kinds** (`adapterOff`, `bluetoothPermissionDenied`,
  `scanFailed`) survive phase transitions. They clear only when the
  specific condition recovers:
  - `adapterOff` — adapter state becomes `on`.
  - `bluetoothPermissionDenied` — next successful scan start.
  - `scanFailed` — next successful scan start.
- Emitting any new error unconditionally overwrites the previous
  value regardless of stickiness. Latest event wins.

## Wire format & API surface

No new endpoints. Structured error rides on existing surfaces.

### WebSocket — `ws/v1/devices`

`DevicesStateAggregator.buildSnapshot()`
(`lib/src/services/webserver/devices_handler.dart:147`) already emits
`connectionStatus.error`. The field becomes a JSON object with the
shape of `ConnectionError`, or `null`:

```json
{
  "connectionStatus": {
    "phase": "idle",
    "foundMachines": [...],
    "foundScales": [...],
    "pendingAmbiguity": null,
    "error": {
      "kind": "scaleConnectFailed",
      "severity": "error",
      "timestamp": "2026-04-19T07:49:29.025Z",
      "deviceId": "50:78:7D:1F:AE:E1",
      "deviceName": "Decent Scale",
      "message": "Scale connect timed out after 15s.",
      "suggestion": "Try toggling Bluetooth, then retry the scan.",
      "details": { "fbp_code": 1 }
    }
  }
}
```

### REST — `/api/v1/devices`

Same aggregator — serves the same JSON shape automatically.

### Breaking change

Yes. Old `"error": "some string"` becomes `"error": { ... }`. We are
pre-1.0 and the previous field was barely populated; no deprecation
window, hard swap. Release notes must call this out.

## Skin contract (documented in `doc/Skins.md`)

On every `connectionStatus` update:

- `error == null` — hide banner, drop any active error UI.
- `error != null`:
  - Compare `error.timestamp` to last-seen to decide whether to fire
    a toast / notification (new event only).
  - Render a persistent banner / status indicator for as long as
    `error` is non-null. UX is skin's choice (banner, card, modal).
  - Preferred path: look up copy by `error.kind` in the skin's own
    i18n table.
  - Fallback: render `error.message` + `error.suggestion` verbatim
    when `kind` is unknown.
  - Include `error.deviceName` when available.

Recommended kind → action mapping (skins free to override):

| kind                        | action                                       |
|-----------------------------|----------------------------------------------|
| `scaleConnectFailed`        | "Retry" → trigger scan with connect          |
| `machineConnectFailed`      | "Retry" → trigger scan with connect          |
| `scaleDisconnected`         | "Reconnect" → trigger scan with connect      |
| `machineDisconnected`       | "Reconnect" → trigger scan with connect      |
| `adapterOff`                | instruction text: "Turn Bluetooth on."       |
| `bluetoothPermissionDenied` | instruction text: grant permission in settings |
| `scanFailed`                | "Retry scan" → trigger scan                  |

Skin dismiss is not supported in MVP — errors self-clear per the
rules above. `ackError` command can be added later without breaking
the shape.

## Native Flutter UI

New widget `ConnectionErrorBanner` — `StreamBuilder<ConnectionStatus>`
rendering a `ShadAlert` when `status.error != null`. Severity maps
to alert variant. Primary action is "Retry" / "Reconnect" for
transient kinds.

Mounted in:

- `DeviceDiscoveryView` — replaces any ad-hoc error text currently
  shown.
- `HomeView` — top-of-screen banner, dismissed only via the automatic
  clearing rules.

Not mounted when a WebUI skin is active in fullscreen: skins own
their own UX, native banner would double-draw.

Onboarding's troubleshooting wizard (`troubleshooting_wizard.dart`)
keying off error kinds is **out of scope** for this design.

## Testing

**Unit — `test/controllers/connection_manager_test.dart` (extend):**

- `ConnectionError.toJson` / `fromJson` roundtrip.
- `_emit` sets the field, publishes, stamps timestamp.
- Sticky-kind handling: `adapterOff` survives a phase transition to
  `scanning`; transient kinds don't.
- Environmental recovery: adapter `on` clears `adapterOff`; adapter
  `on` does **not** clear an unrelated transient error.
- `_expectingDisconnectFor`: expected disconnect suppresses error;
  subsequent unexpected disconnect for same device emits; TTL clears
  stale entries after 10s (use fake async).
- Error emission on `connectScale` throw path — `kind ==
  scaleConnectFailed`, `fbp_code` preserved in `details`.
- Error emission on `connectMachine` throw path — same for
  `machineConnectFailed`.
- Mid-session disconnect subscriber — unexpected drop emits
  `scaleDisconnected` / `machineDisconnected`; deliberate teardown
  does not.

**Unit — `test/controllers/scale_controller_test.dart`:**

- Existing throw-on-failure behavior still holds post-refactor.

**Unit — `test/services/webserver/devices_handler_test.dart`
(extend):**

- `DevicesStateAggregator` snapshot contains the structured `error`
  object when set; `null` when cleared.

**Widget — `test/device_discovery_view_test.dart` (extend):**

- `ConnectionErrorBanner` renders when `status.error != null`,
  hides when `null`, and the Retry button dispatches a scan command.

**E2E — new
`.agents/skills/streamline-bridge/scenarios/ble-error-surfacing.md`:**

- Toggle Android BT off → `ws/v1/devices` emits `kind: adapterOff`.
- Toggle BT on → error clears.
- Start a scan with no DE1/scale in range → scan completes, no error
  emitted (not a failure).
- Force a connect timeout (power off scale during connect) →
  `kind: scaleConnectFailed` appears, then clears on next scan start.
- Trigger sleep flow (machine → sleeping) → no `scaleDisconnected`
  emitted.

## Docs to update

- `doc/Api.md` — document the new `connectionStatus.error` shape
  under the devices endpoint.
- `doc/Skins.md` — add the skin contract section (see above) and
  the kind → action mapping.
- `assets/api/websocket_v1.yml` — update `DevicesState` schema with
  the new `ConnectionError` shape.
- `assets/api/rest_v1.yml` — update the `/api/v1/devices` response
  schema to match.
- `doc/DeviceManagement.md` — brief note on error surfacing and the
  `_expectingDisconnectFor` tracking.

## Open questions / follow-ups (explicitly deferred)

- Operation-level errors on already-connected devices (class D).
- Auto-reconnect loops with backoff.
- Skin `ackError` command.
- Kind-aware troubleshooting wizard integration.
- i18n of `message` / `suggestion` in the app.
