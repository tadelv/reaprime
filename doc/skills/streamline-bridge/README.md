# Streamline Bridge — agent skill

This skill covers driving a running Streamline Bridge Flutter app in simulate mode from the shell: REST via `curl`, WebSocket via `websocat`, and lifecycle (start, stop, reload, logs) via `scripts/sb-dev.sh`. It's written for any agent that can read markdown and execute shell commands — Claude Code, Cursor, Codex, Windsurf, humans — and deliberately avoids agent-specific mechanisms like MCP tools or slash commands.

## Routing

| Task | File |
|---|---|
| Start/stop/reload the app | `lifecycle.md` |
| Call REST endpoints, add endpoints | `rest.md` |
| Read/write WebSocket streams | `websocket.md` |
| Work with MockDe1 / MockScale | `simulated-devices.md` |
| Smoke-test a code change | `verification.md` |
| End-to-end regression recipes | `scenarios/` |

## Authoritative sources

**Always read the spec before making API calls.** Never guess paths or shapes — the specs are the ground truth and stay in sync with the code.

- `assets/api/rest_v1.yml` — OpenAPI 3.0 spec. Canonical REST endpoint reference.
- `assets/api/websocket_v1.yml` — AsyncAPI 3.0 spec. Canonical WebSocket channels and message shapes.
- `scripts/sb-dev.sh` — lifecycle helper. The entry point for driving a running dev instance.
- `CLAUDE.md` and `AGENTS.md` at the repo root — project-wide conventions, architecture, and workflow rules.

## Prerequisites

Hard dependencies on `PATH`:

- `bash`
- `curl`
- `jq`
- `websocat` (or `wscat` fallback — see `websocket.md`)
- `flutter`
- `mkfifo` (POSIX — macOS and Linux only; Windows contributors run `flutter run` directly, see `lifecycle.md`)

## Quick start

```bash
scripts/sb-dev.sh start --connect-machine MockDe1
curl -sf http://localhost:8080/api/v1/devices | jq .
scripts/sb-dev.sh stop
```

From here, pick the file in the routing table that matches your task.
