# Replace MCP server with a Streamline Bridge skill — design

Date: 2026-04-14
Branch: `refactor/mcp-skill-replacement`
Status: Approved, ready for implementation planning

## Problem

The `packages/mcp-server/` package is ~2100 lines of TypeScript whose primary job is wrapping the REST endpoints already described in `assets/api/rest_v1.yml` (93 operations) and the WebSocket channels in `assets/api/websocket_v1.yml`. Modern LLM agents can read OpenAPI/AsyncAPI specs directly and make HTTP/WebSocket calls without a protocol layer in between.

Keeping the MCP server means:
- Two surfaces to maintain (specs + MCP tool wrappers).
- A build step, npm deps, and version drift for what is mostly pass-through code.
- Non-Claude agents (Cursor, Codex, Copilot) can't use the MCP server at all.

## Goal

Replace the MCP server with a project skill that points agents at the authoritative OpenAPI/AsyncAPI specs and gives them the shell recipes they need to exercise the running app. Delete the MCP package entirely. Result: one source of truth (the specs), one dev-loop helper script, one skill that works across any agent that can read markdown.

## Non-goals

- Changing any REST or WebSocket endpoint.
- Changing the Flutter app's behavior.
- Publishing the skill to a marketplace; shipping via the repo is enough.

## Approaches considered

**A. Full replacement — skill only, no MCP.** Delete the entire MCP package. Document everything including lifecycle and streaming via shell recipes.
- Pro: single source of truth, no build step, portable across agents.
- Con: app lifecycle (spawn, hot reload, log tailing) needs a helper script because each Claude Code Bash tool call runs in a fresh shell.

**B. Hybrid — skill for REST, slim MCP for lifecycle + streaming.** Skill handles REST surface and spec discovery. MCP retains `AppManager` and WebSocket subscription tools.
- Pro: lifecycle and streaming stay smooth for Claude.
- Con: two systems to maintain; non-Claude agents still can't use the stateful bits.

**C. Documentation only — keep MCP, add skill as a teaching layer.** Skill tells agents "here are the specs, here are the MCP tools when you need them".
- Pro: lowest risk.
- Con: smallest benefit; the rot stays.

**Chosen: A (full replacement).** With a `scripts/sb-dev.sh` helper for lifecycle and `websocat` recipes for streaming, the philosophy stays consistent: agents understand the procedure, the skill documents it, the specs stay authoritative. The helper script is the irreducible kernel of state that any replacement needs; it is ~150 lines of Bash instead of ~2100 lines of TypeScript.

## Architecture

### File layout

```
scripts/
└── sb-dev.sh                         # lifecycle helper (~150 lines)

.claude/skills/streamline-bridge/
└── SKILL.md                          # Claude Code entry point (~40 lines)

doc/skills/streamline-bridge/
├── README.md                         # tool-agnostic entry point
├── lifecycle.md                      # sb-dev reference + recipes
├── rest.md                           # OpenAPI pointer + curl patterns
├── websocket.md                      # AsyncAPI pointer + websocat patterns
├── simulated-devices.md              # MockDe1/MockScale guide
└── verification.md                   # smoke-test recipes

AGENTS.md                             # add "Working with Streamline Bridge" section
CLAUDE.md                             # update to point at sb-dev + skill instead of MCP
```

### Single source of truth, two discovery paths

- Content lives in `doc/skills/streamline-bridge/`. Plain markdown, readable by any agent.
- `.claude/skills/streamline-bridge/SKILL.md` is a thin Claude Code shim with frontmatter triggers and a routing table that points at `doc/skills/streamline-bridge/README.md`.
- `AGENTS.md` adds a "Working with Streamline Bridge" section that points at the same `doc/skills/` location.
- Non-Claude agents discover via `AGENTS.md`. Claude Code discovers via the skill frontmatter. Both read the same files.

### `scripts/sb-dev.sh`

State lives under `/tmp/streamline-bridge-$USER/`:

```
flutter.pid     — flutter process id
holder.pid      — `tail -f /dev/null > fifo` keeps the stdin fifo open for write
stdin           — named pipe; flutter reads from it
flutter.log     — combined stdout+stderr
```

Commands:

```
sb-dev start [--platform macos] [--connect-machine MockDe1] [--connect-scale MockScale] [--dart-define k=v]
sb-dev stop
sb-dev reload            # hot reload:  sends "r", waits for /reloaded/i in new log lines
sb-dev hot-restart       # hot restart: sends "R", waits for /restarted/i
sb-dev status            # pid, http reachability, device list via curl
sb-dev logs [-n 50] [--filter text]
```

Behavior distilled from `packages/mcp-server/src/lifecycle/app-manager.ts`:

- `start` creates the fifo, launches a persistent `tail -f /dev/null > fifo &` holder so flutter's reader never hits EOF, spawns `./flutter_with_commit.sh run … < fifo > flutter.log 2>&1 &`, polls `/api/v1/devices` until it returns 200, then optionally auto-connects via `/api/v1/devices/scan?connect=true`.
- Auto-connect uses `--dart-define=preferredMachineId=…` / `preferredScaleId=…` — the same fast-path the Flutter UI honors today to skip device selection.
- `reload` records the current line count, writes `r` to the fifo, then tails new lines until it sees `/reloaded/i`.
- `stop` writes `q`, waits 5s, SIGKILL if still alive, kills the holder, removes the fifo and pid files.
- Windows is not supported by `sb-dev.sh` (POSIX-only: `mkfifo`, bash process substitution). Windows devs run `flutter run` in a real terminal.

### Skill content summary

**`SKILL.md`** — frontmatter trigger on "flutter run", "streamline bridge", "rest_v1", "websocket_v1", "mcp-server", "simulated device", "api endpoint", "sb-dev". One paragraph of orientation. Routing table to sub-files.

**`README.md`** — same orientation + routing table, without frontmatter. Tool-agnostic.

**`lifecycle.md`** — sb-dev command reference, quick recipes for common cases, hot reload vs cold restart guidance, Windows caveat.

**`rest.md`** — base URL, authoritative spec pointer (`assets/api/rest_v1.yml`), curl examples for each verb, gotchas not in the spec (e.g. `/machine/state` returns 500 before a DE1 connects, use `/devices` for liveness).

**`websocket.md`** — authoritative spec pointer (`assets/api/websocket_v1.yml`), `websocat` install note, one-shot snapshot pattern (`timeout 3 websocat …`), background subscription pattern (`websocat … > /tmp/sb-stream.log &`), jq extraction examples.

**`simulated-devices.md`** — why simulate exists, `MockDe1`/`MockScale` names, auto-connect fast-path, typical TDD scenarios.

**`verification.md`** — when to verify via running app, smoke-test recipe, explicit recipes for "add endpoint" and "change WebSocket message shape" that require updating the spec in the same commit. Reinforces: stale spec → stale agent knowledge.

## Deletions

| Path | Lines | Reason |
|---|---|---|
| `packages/mcp-server/src/tools/*.ts` (16 files) | ~1100 | REST pass-throughs → skill + curl |
| `packages/mcp-server/src/bridge/rest-client.ts` + tests | ~200 | no consumers |
| `packages/mcp-server/src/bridge/ws-client.ts` + tests | ~150 | replaced by websocat |
| `packages/mcp-server/src/lifecycle/app-manager.ts` + tests | ~400 | replaced by sb-dev.sh |
| `packages/mcp-server/src/resources/*.ts` | ~50 | direct file paths + curl |
| `packages/mcp-server/src/{server,index}.ts` | ~210 | entry points |
| `packages/mcp-server/package.json`, `tsconfig.json`, `vitest.config.ts`, `node_modules/`, `dist/` | — | package infra |

Total deleted: ~2100 lines of TypeScript + package infrastructure.

## Additions

| Path | Size | Purpose |
|---|---|---|
| `scripts/sb-dev.sh` | ~150 lines | Lifecycle helper |
| `.claude/skills/streamline-bridge/SKILL.md` | ~40 lines | Claude Code entry |
| `doc/skills/streamline-bridge/README.md` | ~60 lines | Tool-agnostic entry |
| `doc/skills/streamline-bridge/lifecycle.md` | ~80 lines | sb-dev reference |
| `doc/skills/streamline-bridge/rest.md` | ~50 lines | OpenAPI + curl |
| `doc/skills/streamline-bridge/websocket.md` | ~60 lines | AsyncAPI + websocat |
| `doc/skills/streamline-bridge/simulated-devices.md` | ~60 lines | MockDe1/MockScale |
| `doc/skills/streamline-bridge/verification.md` | ~80 lines | Smoke-test recipes |

Total added: ~580 lines of markdown + ~150 lines of shell.

Net: ~2100 lines deleted, ~730 lines added.

## CLAUDE.md updates

1. Delete the `### MCP Server` subsection under Architecture.
2. Replace "Using MCP for verification" paragraph with a pointer to `doc/skills/streamline-bridge/verification.md`.
3. Replace "When using MCP hot reload" guidance with `sb-dev reload` / `sb-dev hot-restart` equivalents.
4. Drop the "Adding MCP tools" workflow entry.
5. Add a line under Documentation: `doc/skills/streamline-bridge/` — dev-loop skill.

## AGENTS.md updates

Add a `## Working with Streamline Bridge (all agents)` section (~15 lines) that points at `doc/skills/streamline-bridge/README.md` and reproduces the routing table.

## Migration sequence

1. Write `scripts/sb-dev.sh` and the skill content first, without deleting MCP. Prove the helper works end-to-end: start, reload, curl, websocat, stop.
2. Dry-run: do a small feature or trivial change using only the skill + `sb-dev` + `curl` + `websocat`. If the workflow feels rough, patch the docs before deleting anything.
3. Delete `packages/mcp-server/` in a single commit. Update root `pubspec.yaml` if it references the package. Update `.gitignore`.
4. Update `CLAUDE.md` and `AGENTS.md` in the same commit as the skill, so references stay consistent.
5. One PR, three commits: (a) add skill + sb-dev, (b) update CLAUDE/AGENTS, (c) delete mcp-server.

## Risks and mitigations

1. **Flutter `run` with stdin-as-pipe edge cases.** The current `AppManager` uses a plain pipe and works, so we have a known-working precedent. If it regresses on some macOS/Flutter combo during dry-run, fallback is an `expect(1)` wrapper or documenting "quit + restart instead of hot reload".
2. **Context bloat from sub-files.** Mitigated by the routing table in `SKILL.md` — agents load only the sub-file they need.
3. **Spec drift.** `verification.md` is explicit: update `rest_v1.yml` / `websocket_v1.yml` in the same commit as any API change. `CLAUDE.md` reinforces. Optional follow-up: a lint/test that flags modified handlers without a spec diff.
4. **Contributors losing the MCP `app_start` muscle memory.** `sb-dev start` mirrors the API one-for-one. The CLAUDE.md migration note documents the command swap.

## Testing the skill itself

The skill is "working" when an agent with only these files and the specs can:

1. Start the app with `MockDe1` auto-connected, confirm `/api/v1/machine/state` returns a valid snapshot.
2. Load a profile via `POST /api/v1/machine/profile`, trigger a shot, observe state changes over the WebSocket snapshot channel.
3. Edit Dart code, `sb-dev reload`, verify the change via curl.
4. Stop cleanly, check no orphaned flutter processes.

This is the dry-run step in the migration sequence. If any of these flows require ad-hoc fixes to the docs, iterate on the skill before deleting MCP.
