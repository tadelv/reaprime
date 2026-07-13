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

**Key note:** Decent uses its own JSON profile format — the TCL-based profile format in `de1app` is not authoritative for profiles here.

**MMR (Memory-Mapped Register) reads:** Used for DE1 debug log buffer, firmware settings, and advanced state. MMR read timeout observed on M50Mini under `flutter run` debug mode (~270ms in release). Not reproducible in release builds — dev-loop annoyance only.

## Workflow Dual Representation

Workflow JSON has both `context` (new: `WorkflowContext` with `grinderModel`, `coffeeName`, etc.) and legacy fields (`grinderData`, `coffeeData`, `doseData`). `Workflow.fromJson()` backfills context from legacy fields. UI reads from `context`; API clients can write to either. Always keep both in sync when modifying serialization.

## Profile Upload Gotcha

**Issue #389:** Profile push to DE1 writes to workflow but the DE1 doesn't execute the new profile until next restart. Not a serialization bug — a DE1 firmware behavior quirk.

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

## Keeping Notes Fresh

Add protocol compatibility rules, API versioning decisions, and endpoint design rationale. Prune when specs are updated.
