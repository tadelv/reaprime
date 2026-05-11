# Domain Docs

This repo's domain language and architectural context live in existing files — no separate `CONTEXT.md` or `doc/adr/`.

## Before exploring, read these

- **`CLAUDE.md`** at repo root — project overview, architecture (layers, controllers, storage, web server), conventions, gotchas, common workflows
- **`AGENTS.md`** at repo root — tool-agnostic equivalent for non-Claude agents
- **`doc/Api.md`** — REST + WebSocket API reference
- **`doc/Skins.md`** — WebUI skin development
- **`doc/Plugins.md`** — JS plugin development
- **`doc/Profiles.md`** — Profile API and content-based hashing
- **`doc/DeviceManagement.md`** — Device discovery and connection management
- **`doc/RELEASE.md`** — Release process and versioning
- **`doc/plans/archive/`** — Archived design docs (the *why* behind shipped features, rejected alternatives, constraints)
- **`.agents/skills/decent-app/`** — Dev-loop skill: `sb-dev` lifecycle, REST/WebSocket recipes, simulated devices, verification scenarios

If a topic isn't covered, check the `de1app` reference implementation (per `CLAUDE.md`).

## Use the existing vocabulary

When naming domain concepts (issue titles, refactor proposals, test names), match terminology used in `CLAUDE.md` and the `doc/` files. Examples: "ConnectionManager phases" not "connection lifecycle states", "transport abstraction" not "BLE wrapper", "simulated devices" not "mock hardware mode".

## Flag conflicts

If your output contradicts existing documented architecture or conventions in `CLAUDE.md`, surface it explicitly rather than silently overriding.

## No CONTEXT.md / doc/adr/

Skills like `improve-codebase-architecture` and `grill-with-docs` should treat `CLAUDE.md` + `doc/` as the equivalents. Do not create `CONTEXT.md` or `doc/adr/` — duplication would drift.

