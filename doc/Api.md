# API Reference

Streamline-Bridge exposes REST and WebSocket APIs on port 8080. Full OpenAPI specs are in [`assets/api/rest_v1.yml`](../assets/api/rest_v1.yml) and [`assets/api/websocket_v1.yml`](../assets/api/websocket_v1.yml). Interactive docs are available at port 4001 when the app is running.

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
| POST | `/api/v1/machine/state` | Request state change (idle, sleep, etc.) | |
| GET | `/api/v1/machine/settings` | DE1 machine settings (temps, flows) | |
| POST | `/api/v1/machine/settings` | Update machine settings | |
| GET | `/api/v1/machine/settings/advanced` | Advanced heater/phase settings | |
| POST | `/api/v1/machine/settings/advanced` | Update advanced settings | |
| GET | `/api/v1/machine/calibration` | Flow estimation calibration | |
| POST | `/api/v1/machine/calibration` | Update calibration | |
| POST | `/api/v1/machine/profile` | Upload profile to machine | |
| POST | `/api/v1/machine/usb-charger` | Toggle USB charger | |
| POST | `/api/v1/machine/water-threshold` | Update water level threshold | |

### Scale

| Method | Path | Description | Handler |
|--------|------|-------------|---------|
| POST | `/api/v1/scale/tare` | Tare the connected scale | `scale_handler.dart` |
| POST | `/api/v1/scale/timer/start` | Start scale timer | |
| POST | `/api/v1/scale/timer/stop` | Stop scale timer | |
| POST | `/api/v1/scale/timer/reset` | Reset scale timer | |

### Devices

| Method | Path | Description | Handler |
|--------|------|-------------|---------|
| GET | `/api/v1/devices` | List discovered devices | `devices_handler.dart` |
| POST | `/api/v1/devices/scan` | Start BLE scan | |
| POST | `/api/v1/devices/connect` | Connect to device by ID | |
| POST | `/api/v1/devices/disconnect` | Disconnect device | |

### Shots

| Method | Path | Description | Handler |
|--------|------|-------------|---------|
| GET | `/api/v1/shots` | Paginated list with filtering | `shots_handler.dart` |
| GET | `/api/v1/shots/ids` | All shot IDs | |
| GET | `/api/v1/shots/latest` | Most recent shot | |
| GET | `/api/v1/shots/:id` | Get shot by ID (with measurements) | |
| PUT | `/api/v1/shots/:id` | Update shot annotations | |
| DELETE | `/api/v1/shots/:id` | Delete shot | |

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

Settings fields include: `gatewayMode`, `themeMode`, `logLevel`, `weightFlowMultiplier`, `volumeFlowMultiplier`, `scalePowerMode`, `preferredMachineId`, `preferredScaleId`, `defaultSkinId`, `automaticUpdateCheck`, `chargingMode`, `nightModeEnabled`, `nightModeSleepTime`, `nightModeMorningTime`, `lowBatteryBrightnessLimit`, `simulatedDevices`.

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
| POST | `/api/v1/display/wakelock/request` | Request wakelock override | |
| POST | `/api/v1/display/wakelock/release` | Release wakelock override | |

### Presence & Sleep

| Method | Path | Description | Handler |
|--------|------|-------------|---------|
| POST | `/api/v1/presence/heartbeat` | Signal user presence (keep-alive) | `presence_handler.dart` |
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
| POST | `/api/v1/sensors/:id/command` | Execute sensor command | |

### Key-Value Store

| Method | Path | Description | Handler |
|--------|------|-------------|---------|
| GET | `/api/v1/kv/:namespace` | List keys in namespace | `kv_store_handler.dart` |
| GET | `/api/v1/kv/:namespace/:key` | Get value | |
| PUT | `/api/v1/kv/:namespace/:key` | Set value | |
| DELETE | `/api/v1/kv/:namespace/:key` | Delete key | |

### Data Management

| Method | Path | Description | Handler |
|--------|------|-------------|---------|
| GET | `/api/v1/data/export` | Export full backup as ZIP | `data_export_handler.dart` |
| POST | `/api/v1/data/import` | Import from ZIP (raw bytes, `Content-Type: application/zip`) | |
| POST | `/api/v1/data/sync` | Sync with another Bridge instance | `data_sync_handler.dart` |

Sync accepts: `target` (URL), `mode` (pull/push/two_way), `onConflict` (skip/overwrite), `sections` (array: profiles, shots, workflow, settings, store, beans, grinders).

### Other

| Method | Path | Description | Handler |
|--------|------|-------------|---------|
| GET | `/api/v1/info` | Build metadata (version, commit, branch) | `info_handler.dart` |
| POST | `/api/v1/feedback` | Submit feedback (creates GitHub issue) | `feedback_handler.dart` |
| GET | `/api/v1/logs` | Recent log entries | `logs_handler.dart` |
| GET | `/api/v1/webview-logs` | WebView console log forwarding | `webview_logs_handler.dart` |

### Debug (simulate mode only)

Only registered when the app is launched with `--dart-define=simulate=1`. Returns 404 on production builds.

| Method | Endpoint | Description | Handler |
|--------|----------|-------------|---------|
| POST | `/api/v1/debug/scale/stall` | Pause mock scale weight emission (stays "connected") | `debug_handler.dart` |
| POST | `/api/v1/debug/scale/resume` | Resume weight emission after stall | `debug_handler.dart` |
| POST | `/api/v1/debug/scale/disconnect` | Simulate scale disconnect (emits disconnected state, stops data) | `debug_handler.dart` |

All endpoints return 400 if no scale is connected or the connected scale is not a `MockScale`.

---

## WebSocket API

All WebSocket endpoints are on port 8080 at `/ws/v1/...`. See [`assets/api/websocket_v1.yml`](../assets/api/websocket_v1.yml) for full schemas.

| Path | Description | Data |
|------|-------------|------|
| `/ws/v1/machine/snapshot` | Machine state stream (~10Hz) | Temps, pressures, flow, state |
| `/ws/v1/scale/snapshot` | Scale weight/flow stream. Stays open across scale disconnects; emits `{"status":"connected"\|"disconnected"}` frames on state change. | Weight, flow, battery |
| `/ws/v1/machine/shot-settings` | Shot settings changes | Target temp, volume, weight |
| `/ws/v1/machine/water-levels` | Water level changes | Current/limit levels |
| `/ws/v1/machine/raw` | Raw BLE characteristic data | Hex-encoded bytes |
| `/ws/v1/devices` | Device discovery + `ConnectionManager` status (phase, found devices, ambiguity, errors). Also accepts `scan`/`connect`/`disconnect` commands. | Device list, `connectionStatus` |
| `/ws/v1/sensors/:id/snapshot` | Sensor data stream | Sensor-specific |
| `/ws/v1/plugins/:id/:endpoint` | Plugin WebSocket proxy | Plugin-specific |
| `/ws/v1/logs` | App log stream | Timestamped log entries |
| `/ws/v1/display` | Display state changes | Brightness, wakelock |

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
