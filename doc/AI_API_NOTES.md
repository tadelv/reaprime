# AI API Notes

Read this when changing REST endpoints, WebSocket topics, API specs, auth proxy, or Decent binary protocol handling. Skip it for pure UI, BLE transport, or plugin changes.

## Source Of Truth

- REST spec: `assets/api/rest_v1.yml` (OpenAPI 3.0). Always read before making calls.
- WebSocket spec: `assets/api/websocket_v1.yml` (AsyncAPI 3.0).
- Full endpoint reference: `doc/Api.md`.
- Handler implementations: `lib/src/services/webserver/`.
- Router registration: `lib/src/services/webserver/webserver_service.dart` `_init()`.

## Hard Rules

- Update the spec file in the same commit as endpoint changes. The spec is authoritative — stale spec = stale agent knowledge.
- Every handler has `addRoutes()`, registered in `webserver_service.dart` `_init()`.
- Most handlers use `part of webserver_service.dart`. Standalone imports: `shots_handler`, `beans_handler`, `grinders_handler`, `workflow_handler`, `data_export_handler`, `data_sync_handler`, `info_handler`.
- API docs served on port 4001. REST on port 8080.

## REST API Conventions

- Standard response envelope: `{ data, error, status }`.
- Error responses use `jsonBadRequest()` / `jsonError()` / `jsonNotFound()` helpers.
- Content-based hash IDs for profile deduplication (`ProfileController`).
- ETag / `If-None-Match` support on cacheable resources (#203).

## WebSocket Conventions

- WebSocket topics are path-based: `/ws/v1/machine/state`, `/ws/v1/machine/shotState`, `/ws/v1/scale/snapshot`, etc.
- `ShotSequencer` emits structured `ShotDecision`s (why a step advanced, why the shot stopped).
- `SteamSequencer` manages steam session lifecycle (start on entry, finalize on exit).
- Presence tracking via `PresenceController` — client keep-alive.

## Auth Proxy

**Design (PR #296):** Rea acts as an auth-enriching reverse proxy. Clients call Rea endpoints (e.g., `GET /api/v1/account/proxy/support/api/...`), Rea attaches Basic Auth from the secure store, forwards to `decentespresso.com`, returns response body + status as-is.

**Who is calling:** Every proxied request carries client identity (skin id, plugin id, API client token). Rea logs per-request for auditability.

**Scope:**
- Phase 1 (shipped): Read-only proxy (`GET` only).
- Phase 2 (shipped PR #366): Write proxy (`POST`/`PUT`) for shot upload, profile push.

**Permissions:**
- Skins (same-origin webview): implicit access.
- Cross-origin API clients: bearer token scoped to `account:proxy`.
- Plugins: must declare `proxy.decent_api` permission.
- Consent prompt (#300): pending, client consent over active view.

## Decent Binary Protocol

**Source:** Original DE1 app at `github.com/decentespresso/de1app` is the authoritative source for DE1 protocol behavior, BLE characteristics, and machine state logic.

**Profiles:** Use Profile JSON v2 format. See `doc/Profiles.md` for the full profile API and content-based hashing.

**MMR (Memory-Mapped Register) reads:** Used for DE1 debug log buffer, firmware settings, and advanced state. Not for general profile or workflow operations.

## Workflow Dual Representation

Workflow JSON has both `context` (new: `WorkflowContext` with `grinderModel`, `coffeeName`, etc.) and legacy fields (`grinderData`, `coffeeData`, `doseData`). `Workflow.fromJson()` backfills context from legacy fields. UI reads from `context`; API clients can write to either. Always keep both in sync when modifying serialization.

## Adding An Endpoint (Checklist)

1. Create/modify handler in `lib/src/services/webserver/`.
2. Add route in handler's `addRoutes()`.
3. Register in `webserver_service.dart` `_init()`.
4. Update `assets/api/rest_v1.yml` (or `websocket_v1.yml`) in the same commit.
5. Update `doc/Api.md` if user-facing.
6. Smoke-test via `scripts/sb-dev.sh` + `curl`/`websocat`.

## Focused Tests

```sh
flutter test test/services/webserver/
```

Device smoke tests:
```sh
scripts/sb-dev.sh start
curl http://localhost:8080/api/v1/info
websocat ws://localhost:8080/ws/v1/machine/state
```

## Machine WebSocket Re-bind (PR #453)

### Problem

A machine power-cycle drops the De1 object and builds a new one under the same device id (the USB stable id is derived from the SAMD21 factory serial, so it is byte-identical across a power-cycle). Machine sockets used to bind to one De1 instance at open and never re-bind, so a client that connected before the power-cycle sat on an open-but-silent socket forever (bench bug i14).

### Solution

`De1Handler._withDe1Ws` watches `De1Controller.de1` and re-attaches the payload subscription when the controller publishes a new instance. The socket stays open during the disconnect gap and frames resume automatically.

### Design Choices

- **Instance identity (`identical()`), not deviceId, is the swap signal.** The USB stable id is byte-identical across a power-cycle, so an id comparison would see "same machine" and never re-bind. `identical()` also keeps a duplicate emission of the same De1 from double-subscribing (which would double the frame rate).

- **No `{"status": ...}` frames.** Unlike the scale socket, the machine sockets carry a single typed payload per frame and existing clients parse every frame as that type; injecting a status frame would be a breaking change to the wire contract. Link state is already published, instance-independently, on `/ws/v1/devices`.

- **Initial attachment is deterministic.** The initial machine is read from `connectedDe1OrNull` and subscribed immediately, before subscribing to the controller stream. This eliminates the window where a command could arrive while `attached` is still null waiting for the BehaviorSubject replay.

- **Commands during disconnect produce an error frame.** `/ws/v1/machine/raw` commands sent while no machine is attached get a `{"error": "No machine connected"}` response rather than being silently dropped. The socket stays open. Raw commands are never queued for later delivery — a delayed raw read/write could be stale or unsafe.

- **Controller stream has explicit `onDone`/`onError`.** On controller shutdown the payload subscription is cleaned up and the socket is closed, rather than leaking subscriptions.

### Clients Affected

All four machine sockets: `/ws/v1/machine/snapshot`, `/ws/v1/machine/shotSettings`, `/ws/v1/machine/waterLevels`, `/ws/v1/machine/raw`.

## Keeping Notes Fresh

Add protocol compatibility rules, API versioning decisions, and endpoint design rationale. Prune when specs are updated.
