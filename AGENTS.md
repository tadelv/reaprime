# AGENTS.md

This file provides guidance for AI coding agents that don't natively read `CLAUDE.md`.

## Primary Instructions

**Read `CLAUDE.md` for complete project documentation.**

## How to Use CLAUDE.md

`CLAUDE.md` is the authoritative source for this project. However, some sections contain references to Claude Code-specific features that other agents should handle as follows:

### Use as-is

These sections are tool-agnostic and apply to all agents:
- **Project Overview** — Tech stack, architecture, supported platforms
- **Commands** — Run, test, lint, build commands
- **Architecture** — Design principles, layer overview, key controllers, storage
- **Conventions & Gotchas** — RxDart patterns, BLE handling, StreamBuilder patterns
- **Testing** — Test tiers, helpers, widget test patterns
- **Common Workflows** — Adding devices, API endpoints
- **Documentation** — Links to detailed docs

### Adapt the Workflow Section

The **Development Workflow** section references `EnterPlanMode`, which is Claude Code-specific. Interpret it as:

> For planning, use the agent's equivalent planning/analysis mode. Explore the codebase to understand the problem, then write a plan in `doc/plans/` before implementing.

### Adapt the Branching Section

The **Branching Strategy** section references `EnterWorktree`, which is Claude Code-specific. Interpret it as:

> Use standard git commands (`git checkout -b`, `git worktree add`, etc.) for branching. Ask the user which strategy they prefer before creating branches.

### Skills Reference

The **Development Workflow** references a TDD skill in `.claude/skills/tdd-workflow/`. Other agents should follow these principles:

- **Test-first approach:** Write tests before implementation
- **Three test tiers:** Unit, integration, end-to-end
- **Self-review:** Review your own code before claiming done
- **Full suite:** Run `flutter test` and `flutter analyze` before committing

## Working with Streamline Bridge (all agents)

The authoritative dev-loop skill lives under the [agentskills.io](https://agentskills.io) cross-client path `.agents/skills/streamline-bridge/`. Any compliant client auto-discovers it. Non-compliant clients can read it as plain markdown.

- **Entry point:** `.agents/skills/streamline-bridge/SKILL.md`
- **Routing:** `SKILL.md` has a table pointing at sibling files for lifecycle, REST, WebSocket, simulated devices, verification, and the end-to-end scenarios under `scenarios/`.
- **Lifecycle helper:** `scripts/sb-dev.sh` (POSIX shell) manages `flutter run` in simulate mode — start, stop, hot reload, logs, status.
- **Authoritative specs:** `assets/api/rest_v1.yml` (OpenAPI 3.0) and `assets/api/websocket_v1.yml` (AsyncAPI 3.0). Always read the relevant spec before making calls — don't guess endpoint paths or payload shapes.

Claude Code also loads the skill via a thin forwarder at `.claude/skills/streamline-bridge/SKILL.md` that points at the same canonical location.

Prerequisites: `bash`, `curl`, `jq`, `websocat`, `flutter`, and POSIX `mkfifo` (macOS/Linux). Windows contributors run `flutter run` in a real terminal — see `.agents/skills/streamline-bridge/lifecycle.md` for the Windows caveat.

## File Locations

| Purpose | Path |
|---------|------|
| Project instructions | `CLAUDE.md` |
| TDD workflow | `.claude/skills/tdd-workflow/SKILL.md` |
| Plans (before commit) | `doc/plans/` |
| API reference | `doc/Api.md` |
| API specs (OpenAPI) | `assets/api/rest_v1.yml`, `assets/api/websocket_v1.yml` |
| Detailed docs | `doc/*.md` |
