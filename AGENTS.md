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

### MCP Server

The **MCP Server** section describes Claude-specific MCP tools. For other agents:

- The app exposes REST (port 8080) and WebSocket APIs
- Use `flutter run --dart-define=simulate=1` for simulated testing
- MCP scenarios in `test/mcp_scenarios/*.yaml` define end-to-end verification flows

## File Locations

| Purpose | Path |
|---------|------|
| Project instructions | `CLAUDE.md` |
| TDD workflow | `.claude/skills/tdd-workflow/SKILL.md` |
| Plans (before commit) | `doc/plans/` |
| API reference | `doc/Api.md` |
| API specs (OpenAPI) | `assets/api/rest_v1.yml`, `assets/api/websocket_v1.yml` |
| Detailed docs | `doc/*.md` |
