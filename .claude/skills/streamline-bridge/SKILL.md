---
name: streamline-bridge
description: Use when touching the Flutter app, its REST/WebSocket API, profiles, shots, or simulated devices, or whenever exercising a code change against a running Streamline Bridge instance. Covers the dev loop (sb-dev start/reload/stop), REST calls via curl, WebSocket streams via websocat, and smoke-test verification.
---

# Streamline Bridge

Streamline Bridge is a Flutter gateway app for Decent Espresso machines. It exposes a REST API on port 8080 and WebSocket channels under `/ws/v1/*`.

## Authoritative sources

- REST spec: `assets/api/rest_v1.yml`
- WebSocket (AsyncAPI) spec: `assets/api/websocket_v1.yml`
- Dev loop script: `scripts/sb-dev.sh`

Full skill content lives in `doc/skills/streamline-bridge/`. Read the sub-file matching your task.

## Routing

| Task | File |
|---|---|
| Start/stop/reload the app | `doc/skills/streamline-bridge/lifecycle.md` |
| Call REST endpoints / add endpoints | `doc/skills/streamline-bridge/rest.md` |
| Read/write WebSocket streams | `doc/skills/streamline-bridge/websocket.md` |
| Work with MockDe1/MockScale | `doc/skills/streamline-bridge/simulated-devices.md` |
| Smoke-test a code change | `doc/skills/streamline-bridge/verification.md` |

## Rule of thumb

If you're about to guess an endpoint path, payload shape, or WebSocket channel — stop and read the relevant spec first. If you're about to run `flutter run` by hand, use `scripts/sb-dev.sh start` instead.
