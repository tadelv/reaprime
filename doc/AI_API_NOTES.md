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

### Backup Import and Sync Invariants

- A successful backup import requires at least one recognized selected payload; metadata alone is not payload.
- `200` means all processed import sections completed without errors. Any section error, including a returned `SectionImportResult.errors` list, means `207`.
- Section errors remain isolated so other recognized sections may import. Imports are not transactional and successful sections are not rolled back.
- `DataImportOutcome` (or its equivalent) is the source of import completeness classification; clients must not infer it by reparsing the section response map.
- Data sync preserves complete, partial, and fatal phase states. A remote import `207` is a partial push, not a target failure.
- UI clients must not collapse `207` into complete success.
- Backup export is atomic: a requested section export failure returns an error and never a partial ZIP. Native callers validate HTTP `200` and `application/zip` before opening a save picker.
- Remote sync clients accept legacy flat section maps and structured `sections` responses, but fail closed for missing sections, malformed semantic fields, contradictory declarations, or a hybrid representation.
- In every sync mode, omitted sections mean all locally registered sections; explicit empty, unknown, or malformed section lists are rejected before network activity.

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

**Skin token bridge:** HTML served on port 3000 receives the account-proxy token only when the request host is loopback or an IP currently assigned to a local network interface. The live interface list is authoritative to avoid retaining stale DHCP addresses in the allowlist and to support Ethernet or multiple adapters. The WiFi IP cached for display is accepted only when interface enumeration fails. Hostnames remain rejected to preserve the DNS-rebinding boundary.

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

- **Initial attachment is deterministic.** When `connectedDe1OrNull` returns a machine, it is subscribed immediately before subscribing to the controller stream. When no machine exists, the socket starts detached and waits for the first non-null `De1Controller.de1` event. Telemetry sockets emit nothing until attachment, while raw commands still return the documented detached-command error.

- **Commands during disconnect produce an error frame.** `/ws/v1/machine/raw` commands sent while no machine is attached get a `{"error": "No machine connected"}` response rather than being silently dropped. The socket stays open. Raw commands are never queued for later delivery — a delayed raw read/write could be stale or unsafe.

- **Controller stream has explicit `onDone`/`onError`.** On controller shutdown the payload subscription is cleaned up and the socket is closed, rather than leaking subscriptions.

### Clients Affected

All four machine sockets: `/ws/v1/machine/snapshot`, `/ws/v1/machine/shotSettings`, `/ws/v1/machine/waterLevels`, `/ws/v1/machine/raw`.

## Tare Lockout During Shot (issue #499)

`PUT /api/v1/scale/tare` rejects with `400` (`type: "block_tare_during_shot"`) when the `blockTareDuringShot` setting is on and `De1Controller.currentShotState.state` is not `idle`/`finished`. The gate lives in `ScaleHandler`, not `ScaleController.tare()` — `ShotSequencer`/`HotWaterSequencer` call the controller method directly for legitimate in-app tares (arm-before-pour, stop-at-weight), and gating the controller method would break the shot itself.

**Full gateway mode is explicitly exempt**, checked via `settingsController.gatewayMode == GatewayMode.full` alongside the shot-state check — not left implicit. In `full` mode the skin owns the shot and `De1StateManager` normally never starts its own `ShotSequencer` for it, so `currentShotState` would usually stay idle anyway; but the launcher/home-screen path in `De1StateManager._handleEspressoState` starts an app-owned `ShotSequencer` "regardless of mode" whenever the app's own home screen is foregrounded, even under `full` gateway mode. Relying on ShotSequencer-absence alone would make the lockout accidentally engage in that edge case, which is out of scope for the setting's intent (it exists to protect app-tracked shots, not skin-owned ones) — hence the explicit gateway-mode check rather than an inferred one.

## Keeping Notes Fresh

Add protocol compatibility rules, API versioning decisions, and endpoint design rationale. Prune when specs are updated.

## Data Sync Invariants

- Sync phase success is derived from requested section semantics, not transport status alone.
- Existing direct `pull.<section>` and `push.<section>` paths are compatibility surfaces; semantic phase data is additive under `phases`.
- Pull, push, and two-way may omit sections; omission means all locally registered sections. Explicit empty lists are invalid in every mode. Missing requested archive or import sections prevent completion.
- Legacy HTTP `200` import bodies with embedded errors are partial or failed according to section progress.
- Two-way push requires a complete pull unless `continueOnPullFailure: true` is explicitly requested.
- Skipped push is represented as a `skipped` phase, and partial section processing is not transactional.

## Workflow PUT Queue

`PUT /api/v1/workflow` operations are serialized through one queue owned by
`WorkflowHandler`. One HTTP request is exactly one queue entry. Separate requests
must not be coalesced without a future explicit client or session contract. The
handler reads the workflow base when a queue entry reaches execution, then applies
only that request's deep merge. Machine side effects from separate workflow PUTs
must never overlap, and a failure must not poison the queue tail.

The final base commits controller workflow state before the existing direct machine
writes. A machine-write failure returns `500`, but this path does not roll back
already-completed machine writes or controller state. `WorkflowDeviceSync` remains
the owner of asynchronous profile upload after controller changes.
>>>>>>> 9ce4c366 (fix(api): serialize workflow PUT requests)
