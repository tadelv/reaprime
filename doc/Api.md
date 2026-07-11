# API Reference

Decent.app exposes REST and WebSocket APIs on port 8080. Full OpenAPI specs are in [`assets/api/rest_v1.yml`](../assets/api/rest_v1.yml) and [`assets/api/websocket_v1.yml`](../assets/api/websocket_v1.yml). Interactive docs are available at port 4001 when the app is running.

For skin development, see [`doc/Skins.md`](Skins.md). For plugin development, see [`doc/Plugins.md`](Plugins.md).

---

## Conditional GETs (ETag / If-None-Match)

The following list endpoints set a strong `ETag` on every `200 OK` response and honour `If-None-Match` with `304 Not Modified` (empty body) when the client's tag matches:

- `GET /api/v1/beans`
- `GET /api/v1/beans/{beanId}/batches`
- `GET /api/v1/grinders`
- `GET /api/v1/profiles`
- `GET /api/v1/shots` (per query-param combination — filters and pagination are part of the tag)

Usage:

```bash
# First request — note the ETag
curl -is http://localhost:8080/api/v1/beans

# Re-request with If-None-Match — 304 if nothing changed
curl -is -H 'If-None-Match: "abc123…"' http://localhost:8080/api/v1/beans
```

Tags are SHA-256 derived from the encoded response body. Single-resource GETs and mutation routes do **not** emit ETags.

For browser clients on a different origin, `ETag` is exposed via `Access-Control-Expose-Headers`.

---

## REST API

### Machine

| Method | Path | Description | Handler |
|--------|------|-------------|---------|
| GET | `/api/v1/machine/info` | Machine model, firmware, features | `de1handler.dart` |
| GET | `/api/v1/machine/state` | Current machine state + substate | |
| PUT | `/api/v1/machine/state/{newState}` | Request state change (`idle`, `sleep`, `espresso`, …) | |
| GET | `/api/v1/machine/settings` | DE1 machine settings (temps, flows) | |
| POST | `/api/v1/machine/settings` | Update machine settings | |
| POST | `/api/v1/machine/shotSettings` | Update shot settings (steam temp, hot water, target volume, group temp) | |
| GET | `/api/v1/machine/settings/advanced` | Advanced heater/phase settings | |
| POST | `/api/v1/machine/settings/advanced` | Update advanced settings (heater phase flows/timeouts, idle temp, `heaterVoltage`, `refillKitSetting`) | |
| DELETE | `/api/v1/machine/settings/reset` | Reset machine settings to defaults (fan, heater idle/phase flows + ph2 timeout, refill kit auto, flow multiplier 1.0, steam purge 0) | |
| GET | `/api/v1/machine/calibration` | Flow estimation calibration | |
| POST | `/api/v1/machine/calibration` | Update calibration | |
| POST | `/api/v1/machine/profile` | Upload profile to machine | |
| POST | `/api/v1/machine/firmware` | Upload firmware image to machine (raw binary body) | |
| — | USB charger | Controlled via `POST /api/v1/machine/settings` with `{"usb": "enable"}` or `{"usb": "disable"}` | |
| POST | `/api/v1/machine/waterLevels` | Update water level threshold | |
| GET | `/api/v1/machine/capabilities` | List capability identifiers (`cupWarmer`, `integratedScale`, `ledStrip`, `stopAtWeight`, `scaleCalibration`) supported by the connected machine | |
| POST | `/api/v1/machine/scale/calibrate` | Two-point integrated-scale cal: `{"command":"zero"}` (empty), then `{"command":"left","grams":500}` and `{"command":"right","grams":500}` (same mass, LEFT then RIGHT half), or `{"command":"abort"}`. Non-blocking; returns the calibration result — Bengle only, 404 elsewhere | |
| GET | `/api/v1/machine/cupWarmer` | Read cup-warmer setpoint °C + live mat temperature (`currentTemperature`, `null` = no valid reading / older FW — render a placeholder, never fake data) — Bengle only, 404 elsewhere | |
| PUT | `/api/v1/machine/cupWarmer` | Set cup-warmer setpoint °C (range 0.0–80.0; `> 0` = on, `0.0` = off; the FW enable register is app-managed — cleared on machine reboot, re-asserted on reconnect) — Bengle only | |
| GET | `/api/v1/machine/ledStrip` | Read full LED strip config (3 zones × 2 modes, 16-bit RGB) from the app cache, hydrated from the machine's stored palette on connect (all-off fallback until a PUT or `/reset` only if that read fails) — Bengle only | |
| PUT | `/api/v1/machine/ledStrip` | Write full LED strip config to the FW palette registers (persisted + live-applied by FW on write; `frontSwitch` has no register — FW mirrors the front strip) — Bengle only | |
| POST | `/api/v1/machine/ledStrip/commit` | Re-assert the cached LED config to the FW (palette writes already persist; kept for API symmetry) — Bengle only | |
| POST | `/api/v1/machine/ledStrip/reset` | Re-read the FW palette registers into the cache, return refreshed state — Bengle only | |
| POST | `/api/v1/machine/ledStrip/preview` | Show `{"front","back"}` (12-char hex) on the strips now, without changing the stored palette — Bengle only | |
| POST | `/api/v1/machine/ledStrip/preview/clear` | Restore the strips to the cached awake palette after a preview — Bengle only | |

### Scale

| Method | Path | Description | Handler |
|--------|------|-------------|---------|
| PUT | `/api/v1/scale/tare` | Tare the connected scale | `scale_handler.dart` |
| PUT | `/api/v1/scale/timer/start` | Start scale timer | |
| PUT | `/api/v1/scale/timer/stop` | Stop scale timer | |
| PUT | `/api/v1/scale/timer/reset` | Reset scale timer | |

### Devices

| Method | Path | Description | Handler |
|--------|------|-------------|---------|
| GET | `/api/v1/devices` | List devices (present + remembered) | `devices_handler.dart` |
| GET | `/api/v1/devices/scan` | Start a device scan (`?quick=`, `?connect=`) | |
| PUT | `/api/v1/devices/connect` | Connect to device by ID | |
| PUT | `/api/v1/devices/disconnect` | Disconnect device | |
| PUT | `/api/v1/devices/forget` | Forget a remembered device | |
| GET | `/api/v1/devices/wifi` | List manually-added WiFi scale endpoints | `wifi_scale_handler.dart` |
| POST | `/api/v1/devices/wifi` | Add a WiFi scale by IP/hostname (`{host}`) | |
| DELETE | `/api/v1/devices/wifi` | Remove a manual WiFi endpoint (`{host}` body or `?host=`) | |

Each device entry carries an **`available`** boolean. `true` = currently present
in discovery; `false` = a **remembered** device that isn't present (reported with
`state: "disconnected"`). Devices the user connects to are remembered and persist
across restarts, shown as unavailable when offline, until forgotten via
`PUT /api/v1/devices/forget` (deviceId in the JSON body or `?deviceId=` query).
The same `available` field is on each device in the `ws/v1/devices` snapshot.

**Manual WiFi scale endpoints.** Auto-discovered (DNS-SD) WiFi scales appear in
`GET /api/v1/devices` like any other device and need no extra calls. The
`/api/v1/devices/wifi` routes are only for *manually* entering a scale by IP or
hostname (e.g. on networks where mDNS is blocked). All three return
`{ "endpoints": [<host>, ...] }`. An added endpoint surfaces in the device list
as a "Half Decent Scale (WiFi)" entry and validates through the normal
recognition gate — a bad/unreachable address shows as a scale that never
reaches `connected`.

### Shots

| Method | Path | Description | Handler |
|--------|------|-------------|---------|
| GET | `/api/v1/shots` | Paginated list with filtering | `shots_handler.dart` |
| GET | `/api/v1/shots/ids` | All shot IDs | |
| GET | `/api/v1/shots/latest` | Most recent shot | |
| GET | `/api/v1/shots/:id` | Get shot by ID (with measurements) | |
| PUT | `/api/v1/shots/:id` | Update shot annotations | |
| DELETE | `/api/v1/shots/:id` | Delete shot | |

### Steams

Recorded milk-steaming sessions. Each record is opened when the machine
enters `steam` and finalized when it leaves. `SteamSnapshot.milkTemperature`
is populated from the first registered milk sensor; no probe ships in
production today, so the field is `null` on every frame until one is
attached. `SteamSettings.stopAtTemperature` (in `/api/v1/workflow`, range
0–85 °C on Bengle) is written to the Bengle's `TargetMilkTemp` register:
the machine stops steam autonomously once a milk probe is physically
attached and the reading crosses the target; on other machines or
third-party probes the app requests `idle` instead.

| Method | Path | Description | Handler |
|--------|------|-------------|---------|
| GET | `/api/v1/steams` | List all steam records (no measurements) | `steams_handler.dart` |
| GET | `/api/v1/steams/ids` | All steam record IDs | |
| GET | `/api/v1/steams/latest` | Most recent steam record (no measurements) | |
| GET | `/api/v1/steams/:id` | Get steam record by ID (with measurements) | |
| PUT | `/api/v1/steams/:id` | Update steam record annotations | |
| DELETE | `/api/v1/steams/:id` | Delete steam record | |

### Profiles

| Method | Path | Description | Handler |
|--------|------|-------------|---------|
| GET | `/api/v1/profiles` | List all profiles | `profile_handler.dart` |
| GET | `/api/v1/profiles/defaults` | List bundled default profiles (filename + metadata) | |
| GET | `/api/v1/profiles/:id` | Get profile by content-hash ID | |
| POST | `/api/v1/profiles` | Create new profile | |
| PUT | `/api/v1/profiles/:id` | Update profile (in-place; hash change replaces the record) | |
| DELETE | `/api/v1/profiles/:id` | Soft-delete profile (defaults hidden, user profiles soft-deleted) | |
| PUT | `/api/v1/profiles/:id/visibility` | Change profile visibility | |
| GET | `/api/v1/profiles/:id/lineage` | Get profile version history | |
| DELETE | `/api/v1/profiles/:id/purge` | Permanently delete (user profiles only) | |
| GET | `/api/v1/profiles/export` | Export all profiles as JSON | |
| POST | `/api/v1/profiles/import` | Import profiles from JSON | |
| POST | `/api/v1/profiles/restore/:filename` | Restore a bundled default by manifest filename | |

### Workflow

| Method | Path | Description | Handler |
|--------|------|-------------|---------|
| GET | `/api/v1/workflow` | Get current workflow (profile + context) | `workflow_handler.dart` |
| PUT | `/api/v1/workflow` | Update workflow (deep merge) | |

### Beans

| Method | Path | Description | Handler |
|--------|------|-------------|---------|
| GET | `/api/v1/beans` | List all beans | `beans_handler.dart` |
| POST | `/api/v1/beans` | Create bean | |
| GET | `/api/v1/beans/:id` | Get bean | |
| PUT | `/api/v1/beans/:id` | Update bean | |
| DELETE | `/api/v1/beans/:id` | Delete bean | |
| GET | `/api/v1/beans/:id/batches` | List batches for a bean | |
| POST | `/api/v1/beans/:id/batches` | Create batch | |
| GET | `/api/v1/bean-batches/:id` | Get batch | |
| PUT | `/api/v1/bean-batches/:id` | Update batch | |
| DELETE | `/api/v1/bean-batches/:id` | Delete batch | |

### Grinders

| Method | Path | Description | Handler |
|--------|------|-------------|---------|
| GET | `/api/v1/grinders` | List all grinders | `grinders_handler.dart` |
| POST | `/api/v1/grinders` | Create grinder | |
| GET | `/api/v1/grinders/:id` | Get grinder | |
| PUT | `/api/v1/grinders/:id` | Update grinder | |
| DELETE | `/api/v1/grinders/:id` | Delete grinder | |

### Settings

| Method | Path | Description | Handler |
|--------|------|-------------|---------|
| GET | `/api/v1/settings` | All app settings (gateway, theme, charging, devices, etc.) | `settings_handler.dart` |
| POST | `/api/v1/settings` | Update settings (partial, key-by-key) | |

Settings fields include: `gatewayMode`, `themeMode`, `logLevel`, `weightFlowMultiplier`, `volumeFlowMultiplier`, `hotWaterFlowMultiplier`, `scalePowerMode`, `blockOnNoScale`, `stopHotWaterAtWeight`, `preferredMachineId`, `preferredScaleId`, `defaultSkinId`, `automaticUpdateCheck`, `chargingMode`, `nightModeEnabled`, `nightModeSleepTime`, `nightModeMorningTime`, `lowBatteryBrightnessLimit`, `simulatedDevices`.

`stopHotWaterAtWeight` (boolean, default `true`): when on and a scale is connected, hot-water dispensing tares the scale and stops at the configured hot-water `volume` target treated as grams (mirrors the espresso stop-at-weight). The machine's own volume/time stop remains a backstop, and the value is ignored in `full` gateway mode (a skin owns the machine). `hotWaterFlowMultiplier` (number, default `0.3`) is the seconds-of-lookahead applied to scale weight flow for that stop — separate from `weightFlowMultiplier` because hot water dispenses with a different pump/flow profile than espresso. See [DeviceManagement.md](DeviceManagement.md#hot-water-stop-at-weight).

### WebUI & Skins

| Method | Path | Description | Handler |
|--------|------|-------------|---------|
| GET | `/api/v1/webui/skins` | List installed skins | `webui_handler.dart` |
| GET | `/api/v1/webui/skins/:id` | Get skin details | |
| GET | `/api/v1/webui/skins/default` | Get default skin | |
| PUT | `/api/v1/webui/skins/default` | Set default skin (`{skinId}`) | |
| POST | `/api/v1/webui/skins/install/github-release` | Install from GitHub release | |
| POST | `/api/v1/webui/skins/install/github-branch` | Install from GitHub branch | |
| POST | `/api/v1/webui/skins/install/url` | Install from ZIP URL | |
| DELETE | `/api/v1/webui/skins/:id` | Remove installed skin | |
| POST | `/api/v1/webui/skins/update` | Check all skins for updates from remote sources | |
| GET | `/api/v1/webui/server/status` | Server status (`{serving, path, port, ip}`) | |
| POST | `/api/v1/webui/server/start` | Start serving default skin on port 3000 | |
| POST | `/api/v1/webui/server/stop` | Stop serving | |
| GET | `/api/v1/webui/skin-assets/:id/:filepath` | Fetch a file from another installed skin (cross-skin asset sharing) | |

### Plugins

| Method | Path | Description | Handler |
|--------|------|-------------|---------|
| GET | `/api/v1/plugins` | List all plugins (with `loaded`, `autoLoad` fields) | `plugins_handler.dart` |
| GET | `/api/v1/plugins/:id/settings` | Get plugin settings | |
| POST | `/api/v1/plugins/:id/settings` | Update plugin settings | |
| POST | `/api/v1/plugins/:id/enable` | Load plugin + enable auto-load | |
| POST | `/api/v1/plugins/:id/disable` | Unload plugin + disable auto-load | |
| DELETE | `/api/v1/plugins/:id` | Remove plugin (unload + delete files) | |
| POST | `/api/v1/plugins/install` | Install from URL (not yet implemented — returns 501) | |
| GET/WS | `/api/v1/plugins/:id/:endpoint` | Plugin HTTP/WebSocket proxy | |

### Display

| Method | Path | Description | Handler |
|--------|------|-------------|---------|
| GET | `/api/v1/display` | Display state (brightness, wakelock) | `display_handler.dart` |
| POST | `/api/v1/display/brightness` | Set brightness | |
| POST | `/api/v1/display/wakelock` | Request wakelock override | |
| DELETE | `/api/v1/display/wakelock` | Release wakelock override | |

### Presence & Sleep

| Method | Path | Description | Handler |
|--------|------|-------------|---------|
| POST | `/api/v1/machine/heartbeat` | Signal user presence (keep-alive) | `presence_handler.dart` |
| GET | `/api/v1/presence/settings` | Get presence/sleep settings | |
| POST | `/api/v1/presence/settings` | Update presence/sleep settings | |
| GET | `/api/v1/presence/schedules` | List wake schedules | |
| POST | `/api/v1/presence/schedules` | Create wake schedule | |
| PUT | `/api/v1/presence/schedules/:id` | Update wake schedule | |
| DELETE | `/api/v1/presence/schedules/:id` | Delete wake schedule | |

### Sensors

| Method | Path | Description | Handler |
|--------|------|-------------|---------|
| GET | `/api/v1/sensors` | List connected sensors | `sensors_handler.dart` |
| GET | `/api/v1/sensors/:id` | Get sensor manifest | |
| POST | `/api/v1/sensors/:id/execute` | Execute sensor command | |

### Key-Value Store

| Method | Path | Description | Handler |
|--------|------|-------------|---------|
| GET | `/api/v1/store/:namespace` | List keys in namespace (or `?full=1` for the whole namespace) | `kv_store_handler.dart` |
| GET | `/api/v1/store/:namespace/:key` | Get value | |
| POST | `/api/v1/store/:namespace/:key` | Set value | |
| DELETE | `/api/v1/store/:namespace/:key` | Delete key | |

`GET /api/v1/store/:namespace?full=1` returns the entire namespace as a `{key: value}` map in one request instead of one GET per key. It sends an `ETag`, so a repeat request with `If-None-Match` returns `304 Not Modified` when nothing changed — cheap to poll. Without the flag the endpoint returns just the array of keys.

### Data Management

| Method | Path | Description | Handler |
|--------|------|-------------|---------|
| GET | `/api/v1/data/export` | Export full backup as ZIP | `data_export_handler.dart` |
| POST | `/api/v1/data/import` | Import from ZIP (raw bytes, `Content-Type: application/zip`) | |
| POST | `/api/v1/data/sync` | Sync with another Bridge instance | `data_sync_handler.dart` |

Sync accepts: `target` (URL), `mode` (pull/push/two_way), `onConflict` (skip/overwrite), `sections` (array: profiles, shots, workflow, settings, store, beans, grinders).

### Account

| Method | Path | Description | Handler |
|--------|------|-------------|---------|
| GET | `/api/v1/account/decent` | Decent account link status: `{loggedIn}` | `account_handler.dart` |
| GET | `/api/v1/account/proxy/<path>` | Auth-enriching proxy to `decentespresso.com/<path>` | `account_proxy_handler.dart` |
| POST | `/api/v1/account/proxy/<path>` | Auth-enriching write proxy (relays body) | `account_proxy_handler.dart` |
| PUT | `/api/v1/account/proxy/<path>` | Auth-enriching write proxy (relays body) | `account_proxy_handler.dart` |

Linking/unlinking a Decent account is **native-only** — there are no network login/logout routes. The webserver is unauthenticated with `Access-Control-Allow-Origin: *`, so exposing credential operations would let any LAN client or browser origin store attacker credentials or unlink the account. The status response omits the linked email (PII).

The **proxy** lets clients *use* the account without ever seeing the credentials: it attaches the linked account's Basic auth server-side, forwards to `decentespresso.com`, and relays the upstream status + body verbatim. It requires `Authorization: Bearer <token>` and is enforced only on this path. `GET` requires `account:proxy` (including the skin token injected into served skin pages); `POST`/`PUT` require the stronger `account:proxy:write` scope, so the read-only skin token cannot write. Forwarding is restricted to the `support/api/` prefix. The OpenAPI spec documents the generated-client-safe `/support/api/{endpoint}` form; use this raw catch-all route when a Decent backend path contains additional slashes. Responses: 401 (missing/invalid token or no linked account), 403 (token unscoped or path not allowed). Write-scoped tokens are minted from the account page's API-token UI by enabling "Allow write access".

### Other

| Method | Path | Description | Handler |
|--------|------|-------------|---------|
| GET | `/api/v1/info` | Build metadata (version, commit, branch) + gateway LAN IP (`localIp`) | `info_handler.dart` |
| GET | `/api/v1/update` | App-update state snapshot (`phase`, `latestVersion`, `releaseNotes`, `releaseUrl`, `installable`). Pure read — no network call; force a re-check via `/ws/v1/update`. | `update_handler.dart` |
| POST | `/api/v1/feedback` | Submit feedback (creates GitHub issue) | `feedback_handler.dart` |
| GET | `/api/v1/logs` | Recent log entries, newest first. Live log + rotated files `log.txt.1..N` are always stitched chronologically; response is a size-bounded tail window (`?kb=N`, default 1024 KB, clamped to 4096 KB). `?order=asc` for original chronological order | `logs_handler.dart` |
| GET | `/api/v1/webview/logs` | WebView console log forwarding, newest first (`?order=asc` for original chronological order) | `webview_logs_handler.dart` |
| POST | `/api/v1/derek/answers/stream` | Relay to the Derek RAG assistant: forwards the JSON body verbatim to `derek.decentespresso.com/api/answers/stream` and pipes the SSE response back unbuffered. No auth (public data). Exists so browser skins avoid Derek's failing CORS preflight. | `derek_handler.dart` |

### Debug (simulate mode only)

Only registered when the app is launched with `--dart-define=simulate=1`. Returns 404 on production builds.

| Method | Endpoint | Description | Handler |
|--------|----------|-------------|---------|
| POST | `/api/v1/debug/update/force` | Force a fake "update available" so the update API/UI can be tested without a real newer release. Optional query: `version` (default `99.0.0`), `downloadUrl` (default = real latest APK, so the download/install path runs end-to-end). | `debug_handler.dart` |
| POST | `/api/v1/debug/scale/stall` | Pause mock scale weight emission (stays "connected") | `debug_handler.dart` |
| POST | `/api/v1/debug/scale/resume` | Resume weight emission after stall | `debug_handler.dart` |
| POST | `/api/v1/debug/scale/disconnect` | Simulate scale disconnect (emits disconnected state, stops data) | `debug_handler.dart` |

All endpoints return 400 if no scale is connected or the connected scale is not a `MockScale`.

---

## WebSocket API

All WebSocket endpoints are on port 8080 at `/ws/v1/...`. See [`assets/api/websocket_v1.yml`](../assets/api/websocket_v1.yml) for full schemas.

| Path | Description | Data |
|------|-------------|------|
| `/ws/v1/machine/snapshot` | Machine state stream (~10Hz) | Temps, pressures, flow, state; `weight` / `weightFlow` (gravimetric) / `milkTemperature` from the integrated scale on a Bengle, 0 otherwise |
| `/ws/v1/scale/snapshot` | Scale weight/flow stream. Stays open across scale disconnects; emits `{"status":"connected"\|"disconnected"}` frames on state change. | Weight, flow, battery |
| `/ws/v1/machine/shotSettings` | Shot settings changes | Target temp, volume, weight |
| `/ws/v1/machine/waterLevels` | Water level changes | Current/limit levels |
| `/ws/v1/machine/raw` | Raw BLE characteristic data | Hex-encoded bytes |
| `/ws/v1/machine/shotState` | Shot sequencer state + decision feed: why a step advanced, why the shot stopped. Replays the latest frame on connect; idle between shots; not gated on a connected machine. | `event` (`state`\|`decision`\|`terminal`), `shotId`, shot phase, machine context, `decision {kind, reason, details, data}` |
| `/ws/v1/devices` | Device discovery + `ConnectionManager` status (phase, found devices, ambiguity, errors). Also accepts `scan`/`connect`/`disconnect` commands. | Device list, `connectionStatus` |
| `/ws/v1/sensors/:id/snapshot` | Sensor data stream | Sensor-specific |
| `/ws/v1/plugins/:id/:endpoint` | Plugin WebSocket proxy | Plugin-specific |
| `/ws/v1/logs` | App log stream | Timestamped log entries |
| `/ws/v1/webview/logs` | WebView console log stream | WebView console messages |
| `/ws/v1/display` | Display state changes | Brightness, wakelock |
| `/ws/v1/update` | App-update state stream. Also accepts `{"command":"check"}` and `{"command":"install"}` (Android installs; other platforms reply `{"error","url"}`). | `phase`, `progress`, `latestVersion`, `installable` |

### `shotState` events

`/ws/v1/machine/shotState` streams the app's shot-sequencer decisions as a single event type
discriminated by `event`. Every frame carries the current shot phase (`state`) and machine context,
so a late joiner gets a coherent view from any single frame; `decision` is non-null only on
`decision`/`terminal` frames.

```json
{
  "event": "decision",
  "timestamp": "2026-06-17T10:32:18.903Z",
  "shotId": "a1b2c3d4-...",
  "state": "pouring",
  "machineState": "espresso",
  "machineSubstate": "pouring",
  "profileFrame": 2,
  "scaleConnected": true,
  "scaleLost": false,
  "machineHasAutonomousSAW": false,
  "decision": {
    "kind": "stop",
    "reason": "targetWeight",
    "details": "Target weight 36.0g reached (projected: 36.4). Stopping shot.",
    "data": {"targetYield": 36.0, "projectedWeight": 36.4}
  }
}
```

- `shotId` equals the persisted `ShotRecord.id`, so the stream can be correlated to the saved shot.
  The final stop reason is also persisted on the record as `stopReason`.
- `decision.reason` is an **open set** — tolerate unknown values. Known reasons: `targetWeight`,
  `targetVolume` (app-side targets), `profileSkip` (app-issued weight skip), `profileAdvance`
  (firmware-natural step exit), `apiStop` / `appStop` (stop command attributed to a REST client /
  the in-app Stop button), `machineEnded` (GHC stop or natural profile completion —
  indistinguishable), `noScale` (blocked by `blockOnNoScale`), `error` / `disconnected` (abnormal
  endings, `event: "terminal"`), `stoppingBackstop` (post-stop settling window closed by the safety
  timer; never the stop reason itself).
- Coverage: the feed reflects app-side sequencing only. In full gateway mode with the app
  backgrounded no sequencer runs (the feed stays `idle`), and on machines with autonomous
  stop-at-weight (Bengle) the final yield stop is firmware-side and reported as `machineEnded`.

### `connectionStatus.error`

When a BLE operation fails (connect timeout, mid-session disconnect, adapter off, permission denied, scan failure), the devices WebSocket emits an update with a structured `connectionStatus.error` object. `null` when no error is active.

```json
{
  "kind": "scaleConnectFailed",
  "severity": "error",
  "timestamp": "2026-04-19T07:49:29.025Z",
  "deviceId": "50:78:7D:1F:AE:E1",
  "deviceName": "Decent Scale",
  "message": "Scale Decent Scale failed to connect.",
  "suggestion": "Wake the scale and try again.",
  "details": {"fbp_code": 1}
}
```

See [`assets/api/websocket_v1.yml`](../assets/api/websocket_v1.yml) for the full `ConnectionError` schema. Full `kind` taxonomy, lifecycle rules, and the recommended skin handling pattern are in [`doc/Skins.md`](Skins.md#handling-connection-errors).

---

## Bundled Plugins

### Settings Plugin (`settings.reaplugin`)

Built-in settings dashboard accessible at `/api/v1/plugins/settings.reaplugin/ui`. Provides a web-based interface for managing all app settings, skins, plugins, data, and more.

**Query parameters:**
- `backName` — customizes the back button label. E.g., `/api/v1/plugins/settings.reaplugin/ui?backName=Extracto` shows "Back to Extracto" instead of "Back to WebUI".

**Sections:** REA Application Settings, Battery & Charging, Machine Settings, Machine Advanced Settings, Calibration, Presence & Sleep, Simulated Devices, Web Interface (skin management + server control), Data Management (export/import/sync), Plugin Management, Feedback, About.

**Self-protection:** The plugin management section prevents disabling or removing `settings.reaplugin` itself (UI guard).

### DYE2 Plugin (`dye2.reaplugin`)

Bean and grinder management. See [`packages/dye2-plugin/README.md`](../packages/dye2-plugin/README.md).
