# Streamline Bridge MCP Server — Design

## Overview

A standalone TypeScript MCP (Model Context Protocol) server that bridges Claude Code (or other MCP clients) to a running Streamline Bridge instance. Primary purpose: **developer tooling** — enabling AI-assisted integration testing, skin development, and plugin development against a simulated Streamline Bridge instance.

## Architecture

```
┌──────────────┐   stdio/SSE    ┌──────────────────┐  REST/WS   ┌────────────────────┐
│  Claude Code  │ ◄────────────► │  MCP Server (TS)  │ ◄────────► │  Streamline Bridge  │
│  (MCP client) │                │  packages/        │            │  (Flutter app,      │
│               │                │   mcp-server/     │            │   simulate=1)       │
└──────────────┘                └──────────────────┘            └────────────────────┘
                                  │                                │
                                  │ spawns & manages               │ localhost:8080
                                  └────────────────────────────────┘
```

**Approach:** Hybrid — thin proxy tools for comprehensive REST API coverage, plus smart utility tools for app lifecycle management and WebSocket streaming.

## Project Structure

```
packages/mcp-server/
├── package.json
├── tsconfig.json
├── src/
│   ├── index.ts              # Entry point, stdio + SSE transport setup
│   ├── server.ts             # MCP server definition, tool/resource registration
│   ├── bridge/
│   │   ├── rest-client.ts    # HTTP client wrapping Streamline Bridge REST API
│   │   └── ws-client.ts      # WebSocket client for real-time streams
│   ├── lifecycle/
│   │   └── app-manager.ts    # Start/stop/health-check/hot-reload the Flutter app
│   ├── tools/
│   │   ├── machine.ts        # Machine state, settings, calibration
│   │   ├── profiles.ts       # Profile CRUD, versioning, import/export
│   │   ├── shots.ts          # Shot history query, update, delete
│   │   ├── devices.ts        # Scan, connect, disconnect, list
│   │   ├── scale.ts          # Tare, timer control
│   │   ├── workflow.ts       # Get/update workflow
│   │   ├── settings.ts       # App settings
│   │   ├── plugins.ts        # Plugin listing, settings, endpoints
│   │   ├── sensors.ts        # Sensor listing, commands
│   │   ├── lifecycle.ts      # App lifecycle tools
│   │   └── streaming.ts      # WebSocket subscribe/read/unsubscribe
│   └── resources/
│       ├── static-docs.ts    # API specs, developer docs from repo
│       └── live-state.ts     # Dynamic resources from running instance
└── README.md
```

**Dependencies:** `@modelcontextprotocol/sdk`, `express` (SSE transport), `ws` (WebSocket client).

## Tools

### Proxy Tools (thin 1:1 wrappers around REST endpoints)

#### Machine (`tools/machine.ts`)
| Tool | REST Endpoint | Description |
|------|---------------|-------------|
| `machine_get_state` | `GET /api/v1/machine/state` | Current machine state snapshot |
| `machine_set_state` | `PUT /api/v1/machine/state/<state>` | Request state change (idle, espresso, steam, hotWater, flush, etc.) |
| `machine_get_info` | `GET /api/v1/machine/info` | Hardware/firmware/serial info |
| `machine_get_settings` | `GET /api/v1/machine/settings` | Machine settings |
| `machine_update_settings` | `POST /api/v1/machine/settings` | Update machine settings |
| `machine_load_profile` | `POST /api/v1/machine/profile` | Load profile to machine |
| `machine_update_shot_settings` | `POST /api/v1/machine/shotSettings` | Update shot settings |

#### Profiles (`tools/profiles.ts`)
| Tool | REST Endpoint | Description |
|------|---------------|-------------|
| `profiles_list` | `GET /api/v1/profiles` | List profiles (visibility/parent filters) |
| `profiles_get` | `GET /api/v1/profiles/<id>` | Get single profile by ID |
| `profiles_create` | `POST /api/v1/profiles` | Create new profile |
| `profiles_update` | `PUT /api/v1/profiles/<id>` | Update profile |
| `profiles_delete` | `DELETE /api/v1/profiles/<id>` | Delete profile |
| `profiles_get_lineage` | `GET /api/v1/profiles/<id>/lineage` | Version history |
| `profiles_import` | `POST /api/v1/profiles/import` | Bulk import |
| `profiles_export` | `GET /api/v1/profiles/export` | Export all profiles |

#### Shots (`tools/shots.ts`)
| Tool | REST Endpoint | Description |
|------|---------------|-------------|
| `shots_list` | `GET /api/v1/shots` | List shots (ordering/filtering) |
| `shots_get` | `GET /api/v1/shots/<id>` | Get specific shot |
| `shots_get_latest` | `GET /api/v1/shots/latest` | Most recent shot |
| `shots_update` | `PUT /api/v1/shots/<id>` | Update shot metadata |
| `shots_delete` | `DELETE /api/v1/shots/<id>` | Delete shot |

#### Devices (`tools/devices.ts`)
| Tool | REST Endpoint | Description |
|------|---------------|-------------|
| `devices_list` | `GET /api/v1/devices` | All connected devices |
| `devices_scan` | `GET /api/v1/devices/scan` | Trigger device scan |
| `devices_connect` | `PUT /api/v1/devices/connect` | Connect to device |
| `devices_disconnect` | `PUT /api/v1/devices/disconnect` | Disconnect from device |

#### Scale (`tools/scale.ts`)
| Tool | REST Endpoint | Description |
|------|---------------|-------------|
| `scale_tare` | `PUT /api/v1/scale/tare` | Tare the scale |
| `scale_timer_start` | `PUT /api/v1/scale/timer/start` | Start timer |
| `scale_timer_stop` | `PUT /api/v1/scale/timer/stop` | Stop timer |
| `scale_timer_reset` | `PUT /api/v1/scale/timer/reset` | Reset timer |

#### Workflow (`tools/workflow.ts`)
| Tool | REST Endpoint | Description |
|------|---------------|-------------|
| `workflow_get` | `GET /api/v1/workflow` | Get current workflow |
| `workflow_update` | `PUT /api/v1/workflow` | Update workflow (deep merge) |

#### Settings (`tools/settings.ts`)
| Tool | REST Endpoint | Description |
|------|---------------|-------------|
| `settings_get` | `GET /api/v1/settings` | Get app settings |
| `settings_update` | `POST /api/v1/settings` | Update settings |

#### Plugins (`tools/plugins.ts`)
| Tool | REST Endpoint | Description |
|------|---------------|-------------|
| `plugins_list` | `GET /api/v1/plugins` | List loaded plugins |
| `plugins_get_settings` | `GET /api/v1/plugins/<id>/settings` | Get plugin settings |
| `plugins_update_settings` | `POST /api/v1/plugins/<id>/settings` | Update plugin settings |

#### Sensors (`tools/sensors.ts`)
| Tool | REST Endpoint | Description |
|------|---------------|-------------|
| `sensors_list` | `GET /api/v1/sensors` | List connected sensors |
| `sensors_get` | `GET /api/v1/sensors/<id>` | Get sensor info |
| `sensors_execute_command` | `POST /api/v1/sensors/<id>/execute` | Execute sensor command |

### Smart Utility Tools

#### Lifecycle (`tools/lifecycle.ts`)

| Tool | Description |
|------|-------------|
| `app_start` | Launch the Flutter app in simulate mode. Spawns `flutter run --dart-define=simulate=1`, captures stdout/stderr into rolling buffer (~1000 lines), waits for HTTP server ready (polls `/api/v1/machine/state`, 60s timeout). Optional `connect_device` param to auto-connect (scans + connects). Optional `dart_defines` for additional flags. Returns PID + connection status. |
| `app_stop` | Graceful shutdown. SIGTERM → 5s wait → SIGKILL. Cleans up child process. |
| `app_restart` | Cold restart — stop + start with same parameters. |
| `app_status` | Health check — is process running? Is HTTP server reachable? Connected device info. |
| `app_logs` | Read last N lines from captured flutter run stdout/stderr. Optional `filter` string to grep for specific terms. |
| `app_hot_reload` | Send `r` to flutter process stdin. Waits for "Reloaded" confirmation in stdout. |
| `app_hot_restart` | Send `R` to flutter process stdin. Waits for "Restarted" confirmation in stdout. |

#### Streaming (`tools/streaming.ts`)

| Tool | Description |
|------|-------------|
| `stream_subscribe` | Open a WebSocket subscription (machine snapshot, scale, sensors, devices). Returns subscription ID. Messages buffered internally. |
| `stream_read` | Poll latest N messages from a subscription buffer. |
| `stream_unsubscribe` | Close a subscription and discard buffer. |

## Resources

### Static Resources (read from repo, always available)

| URI | Source File | Description |
|-----|------------|-------------|
| `streamline://docs/api/rest` | `assets/api/rest_v1.yml` | REST API OpenAPI spec |
| `streamline://docs/api/websocket` | `assets/api/websocket_v1.yml` | WebSocket AsyncAPI spec |
| `streamline://docs/skins` | `doc/Skins.md` | Skin development guide |
| `streamline://docs/plugins` | `doc/Plugins.md` | Plugin development guide |
| `streamline://docs/profiles` | `doc/Profiles.md` | Profile API & hashing docs |
| `streamline://docs/devices` | `doc/DeviceManagement.md` | Device discovery & connection |

### Live Resources (fetched from running instance on demand)

| URI | Source | Description |
|-----|--------|-------------|
| `streamline://live/machine/state` | `GET /api/v1/machine/state` | Current machine state snapshot |
| `streamline://live/machine/info` | `GET /api/v1/machine/info` | Connected machine hardware info |
| `streamline://live/devices` | `GET /api/v1/devices` | All connected devices |
| `streamline://live/workflow` | `GET /api/v1/workflow` | Current workflow configuration |
| `streamline://live/plugins` | `GET /api/v1/plugins` | Loaded plugins and manifests |

Live resources return a helpful error message (not a failure) if the app isn't running: `"App is not running. Use the app_start tool to launch it."`

## Transport & Configuration

### stdio (primary — for Claude Code)

Configuration in project `.mcp.json`:

```json
{
  "mcpServers": {
    "streamline-bridge": {
      "command": "npx",
      "args": ["tsx", "packages/mcp-server/src/index.ts"],
      "env": {
        "STREAMLINE_HOST": "localhost",
        "STREAMLINE_PORT": "8080"
      }
    }
  }
}
```

### SSE (secondary — for other MCP clients)

```bash
npx tsx packages/mcp-server/src/index.ts --sse --sse-port 3100
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `STREAMLINE_HOST` | `localhost` | Streamline Bridge host |
| `STREAMLINE_PORT` | `8080` | Streamline Bridge REST/WS port |
| `STREAMLINE_PROJECT_ROOT` | auto-detected | Path to repo root (for static resources + app lifecycle) |
| `STREAMLINE_FLUTTER_CMD` | `flutter` | Flutter binary path |

## Key Design Decisions

1. **Standalone process over embedded** — keeps MCP concerns separate from the Flutter app; no Dart MCP SDK needed; can evolve independently.
2. **Hybrid tool approach** — thin proxy for full API coverage, smart utilities for lifecycle and streaming. Can add higher-level workflow tools later.
3. **Buffered streaming** — WebSocket connections managed internally with message buffers, exposed via subscribe/read/unsubscribe pattern. Works within MCP's request/response model.
4. **Flutter process management** — holding the `flutter run` process enables hot reload/restart via stdin, stdout/stderr capture for log inspection, and proper lifecycle control.
5. **Static + live resources** — static docs available without the app running (design-time), live state available during testing (runtime). Graceful degradation when app is offline.
