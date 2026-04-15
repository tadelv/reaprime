# MCP Server Refactor for Multi-Client Compatibility

## Overview
Refactor the local 'streamline-bridge' MCP server (`packages/mcp-server/`) to be usable by any MCP-compatible AI assistant (not just Claude Code), focusing on configuration and documentation for existing MCP clients like Cursor, Windsurf, and Continue.dev.

**Current state:** The server already supports HTTP/SSE transport via `--http` flag, works with standard MCP protocol, but has Claude‑centric configuration (`.mcp.json`), minimal CLI, no ready‑to‑use configs for other clients, assumes local Flutter project, and is not published as npm package.

**Target state:** A well‑documented, easily installable MCP server that any MCP client can connect to, with clear configuration examples, a usable CLI, and optional packaging for distribution.

## Goals
1. **Multi‑client compatibility** – Work with Cursor, Windsurf, Continue.dev, Claude Code, and any MCP‑compatible client.
2. **Easy configuration** – Provide example config files for each major client, plus a global config file for user‑specific paths.
3. **Improved CLI** – Add proper argument parsing, help text, and subcommands for starting the server in different modes (stdio, SSE, HTTP).
4. **Decouple from local project** – Allow the server to connect to a remote Streamline Bridge instance, not just a locally running Flutter app.
5. **Comprehensive documentation** – Clear setup guides for each client, including troubleshooting and common workflows.
6. **Packaging readiness** – Structure the project so it can be published to npm (optional) and installed globally or as a project dependency.

## Non‑goals
- Rewriting the existing tool implementations (they already work).
- Changing the MCP protocol or transport layer (HTTP/SSE is already standard).
- Supporting every possible MCP client (focus on the most popular: Cursor, Windsurf, Continue.dev, Claude Code).
- Removing Claude Code support (maintain full backward compatibility).

## Phase 1: Core Decoupling & CLI (Week 1)
**Objective:** Separate configuration from the local project, add a proper CLI, and establish a global config file.

### Tasks
1. **Add CLI argument parsing** (`src/cli.ts`)
   - Use `commander.js` for structured subcommands (`serve`, `config`, `info`)
   - Subcommands:
     - `serve` – start the MCP server (default: stdio, options: `--http`, `--port`)
     - `config` – show/edit global configuration
     - `info` – display server version and detected paths
   - Environment variable support: `STREAMLINE_HOST`, `STREAMLINE_PORT`, `STREAMLINE_PROJECT_ROOT`, `STREAMLINE_FLUTTER_CMD`
   - Command‑line flags override environment variables.

2. **Global configuration file** (`~/.streamline-mcp/config.json`)
   - JSON file with default values for the above environment variables.
   - CLI `config` subcommand to view/edit.
   - Fallback chain: CLI flag → env var → config file → default.

3. **Configuration module** (`src/config.ts`)
   - Loads config file, merges with env vars, provides typed interface.
   - Validates required paths (e.g., project root exists, Flutter binary found).
   - Exports `getConfig()` function used by server and tools.

4. **Update entry point** (`src/index.ts`)
   - Replace manual `--http` flag parsing with CLI.
   - Integrate config loading.
   - Keep backward compatibility: if `--http` is passed without commander, treat as legacy mode.

5. **Update package.json**
   - Add `commander` dependency.
   - Add `bin` entry pointing to compiled CLI (or a wrapper that calls `tsx` in development).
   - Update scripts: `dev` uses CLI, `start` uses built version.

6. **Documentation**
   - Update `README.md` in `packages/mcp-server/` with new CLI usage.
   - Add example for global config.

### Files to create/modify
- `packages/mcp-server/src/cli.ts` (new)
- `packages/mcp-server/src/config.ts` (new)
- `packages/mcp-server/src/index.ts` (modify)
- `packages/mcp-server/package.json` (modify)
- `packages/mcp-server/README.md` (modify)
- User config: `~/.streamline-mcp/config.json` (created on first run if missing)

### Acceptance criteria
- Server can be started with `npx tsx src/cli.ts serve` (stdio) or `npx tsx src/cli.ts serve --http --port 3100` (SSE).
- Global config file is read/written via `npx tsx src/cli.ts config`.
- Environment variables still work and can override config.
- Existing `.mcp.json` for Claude Code continues to work (uses stdio transport).
- All existing tools and resources function identically.

## Phase 2: Packaging & Documentation (Week 2)
**Objective:** Create client‑specific configuration examples, improve documentation, and prepare for npm packaging.

### Tasks
1. **Client configuration examples**
   - Create `examples/` directory with:
     - `cursor.mcp.json` – Cursor configuration (SSE transport)
     - `windsurf.mcp.json` – Windsurf configuration (SSE transport)
     - `continue.json` – Continue.dev configuration (SSE transport)
     - `claude-code.mcp.json` – Claude Code configuration (stdio transport, updated with new CLI command)
   - Each example includes comments explaining how to adapt for remote vs local Bridge.

2. **Documentation overhaul**
   - `doc/MCP-Server.md` (or expand existing `packages/mcp-server/README.md`):
     - Quick start for each client.
     - Explanation of transport choices (stdio vs SSE).
     - How to connect to a remote Bridge instance.
     - Troubleshooting common issues (port conflicts, Flutter not found).
   - Add cross‑references from main project `README.md`.

3. **npm packaging readiness**
   - Update `package.json` with proper metadata, keywords, license.
   - Add `prepublishOnly` script to run `tsc`.
   - Test local installation with `npm link`.

4. **Testing**
   - Add integration tests for CLI argument parsing.
   - Test config file loading precedence.

### Files to create/modify
- `packages/mcp-server/examples/` (new directory)
- `packages/mcp-server/examples/*.json` (new files)
- `packages/mcp-server/README.md` (major update)
- `doc/MCP-Server.md` (new, or integrate into existing docs)
- `packages/mcp-server/package.json` (metadata, scripts)

### Acceptance criteria
- Users can copy‑paste example configs into their client configuration.
- Documentation clearly explains setup for Cursor, Windsurf, Continue.dev, and Claude Code.
- Package can be built and installed locally without errors.

## Phase 3: Advanced Features & Testing (Week 3)
**Objective:** Add WebSocket transport option, Docker support, and comprehensive test coverage.

### Tasks
1. **WebSocket transport**
   - Add `--ws` flag to CLI for native WebSocket transport (alternative to SSE).
   - Implement using `@modelcontextprotocol/sdk` WebSocket server.
   - Update examples for clients that prefer WebSocket over SSE.

2. **Docker support**
   - Create `Dockerfile` for running the MCP server in a container.
   - Document how to use with a remote Bridge instance.

3. **Enhanced logging & diagnostics**
   - Add `--verbose` flag for debug output.
   - Log transport events, tool calls, and errors.

4. **Test coverage**
   - Unit tests for `config.ts` and `cli.ts`.
   - Integration tests that start the server and verify tool registration.
   - MCP protocol compliance tests.

5. **Final polish**
   - Version bump to `0.2.0`.
   - Update changelog.
   - Verify backward compatibility with all existing workflows.

### Files to create/modify
- `packages/mcp-server/src/transports/` (optional, for WebSocket)
- `packages/mcp-server/Dockerfile` (new)
- `packages/mcp-server/test/` (expand test suite)
- `CHANGELOG.md` (new or update)

### Acceptance criteria
- Server supports WebSocket transport alongside SSE and stdio.
- Docker image builds and runs.
- Test coverage >80% for new code.
- All existing MCP tools still work across all transports.

## Testing Strategy
- **Unit tests:** Vitest for `config.ts`, `cli.ts`, and utility functions.
- **Integration tests:** Start server in SSE mode, connect test client, call a simple tool (e.g., `info`).
- **MCP verification:** Use the existing MCP tools to test against a running Bridge instance (simulate mode).
- **Backward compatibility:** Ensure Claude Code `.mcp.json` still works with the updated CLI command.

## Risks & Mitigations
- **Risk:** Breaking existing Claude Code workflows.
  - Mitigation: Keep legacy `--http` flag support, test with actual Claude Code connection.
- **Risk:** Configuration precedence confusion.
  - Mitigation: Clear documentation, `config` subcommand to show effective settings.
- **Risk:** Increased complexity for users.
  - Mitigation: Provide simple copy‑paste examples for each client, step‑by‑step guides.

## Success Metrics
1. Server can be configured for Cursor, Windsurf, Continue.dev, and Claude Code with ≤5 minutes of setup.
2. All existing MCP tools remain functional.
3. Documentation answers common questions without requiring deep MCP protocol knowledge.
4. CLI is intuitive (`--help` provides clear guidance).

---

*Plan created on 2026‑03‑22. Branch: `feature/mcp-server-refactor`.*