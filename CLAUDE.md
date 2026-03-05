# CLAUDE.md

## Project Overview

Streamline-Bridge (formerly REA/ReaPrime/R1) is a Flutter gateway app for Decent Espresso machines. Connects to DE1 machines and scales via BLE/USB, exposing REST (port 8080) and WebSocket APIs. Includes a JavaScript plugin system. Primary platform: Android (DE1 tablet), also macOS, Linux, Windows, iOS. Note: the rename is in progress — code, repo, and file references may still use the old names.

**Reference implementation:** The original Decent Espresso app at `github.com/decentespresso/de1app` is the authoritative source for DE1 protocol behavior, BLE characteristics, and machine state logic. Consult it when implementation details are unclear. Note: Streamline-Bridge uses its own JSON profile format — the TCL-based profile format in de1app is not authoritative for profiles here.

## Commands

```bash
# Run
./flutter_with_commit.sh run              # Standard (injects git commit version)
flutter run --dart-define=simulate=1      # Simulated devices (no hardware needed)

# Test & Lint
flutter test                              # All tests
flutter test test/unit_test.dart          # Specific test file
flutter analyze                           # Static analysis
flutter format lib/ test/                 # Format code

# Build (Linux via Docker/Colima)
make build-arm                            # ARM64
make build-amd                            # x86_64
make dual-build                           # Both architectures
```

## Branching & Workflow

### Branching Strategy

**Before any planning or implementation, always ask the user first:**
1. **Branch strategy:** New branch, worktree, or current branch?
2. **Completion strategy:** PR, local merge to main, or leave as-is?

**Check out the chosen branch/worktree before writing anything** — plans, code, or docs should all be written on the feature branch, not on `main`.

**Do not assume.** `main` has branch protection requiring PRs. Pushing directly bypasses protections.

**Worktree gotcha:** `EnterWorktree` branches track `origin/main` — pushing will push directly to `main`. To create a proper PR from a worktree:
```bash
git push -u origin HEAD:feature/my-branch-name
gh pr create --base main
```

### Planning Phase

**For non-trivial features or fixes, start with planning (on the feature branch):**

1. Use `EnterPlanMode` to explore the codebase and design the approach.
2. Write a plan in `doc/plans/` covering: steps, files to change, architecture considerations, testing.
3. Present to user for review. Iterate until approved. Only then implement.

**Skip planning only for:** simple typo fixes, single-line changes, or tasks with very specific instructions.

### Verification Loop

**Before starting work, ask the user** which verification approach to use:
- **Tests + analyze only** — automated checks only. Best for refactors, internal logic, well-tested code paths.
- **Tests + run app** — run with `simulate=1` so user can visually verify. Best for GUI features, UX changes.
- **Tests + MCP smoke test** — use the local MCP tools (`streamline-bridge` server) to start the app in simulate mode and exercise changed endpoints/state directly. Preferred for API, workflow, and data changes since MCP tools provide richer verification than raw `curl`.
- **Tests + custom check** — user specifies what to verify (e.g., real hardware test, WebSocket stream check).

**Ask the user** whether new/updated tests are needed for the change. If yes, write tests before or alongside the implementation — not as an afterthought.

After every meaningful code change:
1. Run relevant tests + `flutter analyze`. Fix immediately if anything fails.
2. Run full `flutter test` before committing and before claiming done.
3. Perform the user's chosen verification approach before reporting completion. Evidence before assertions.

Plans go in `doc/plans/`. Don't commit unless asked. When finishing a branch, ask user to archive to `doc/plans/archive/`. After implementation, ask whether to update related docs.

## Architecture

### Design Principles

- **Transport abstraction:** Device implementations depend on injected transport interfaces (`DataTransport`, `BleTransport`, `SerialPort`), not concrete implementations.
- **Constructor dependency injection:** No service locators. Dependencies passed through constructors.
- **Single Responsibility:** Each controller/service has one focused purpose.

### Layer Overview

| Layer | Path | Purpose |
|-------|------|---------|
| Devices | `lib/src/models/device/` | Abstract interfaces (`Device`, `Machine`, `Scale`, `Sensor`) + implementations in `impl/` |
| Controllers | `lib/src/controllers/` | Business logic orchestration between devices and services |
| Services | `lib/src/services/` | Discovery, storage, settings, web server |
| Plugins | `lib/src/plugins/` | JS plugin lifecycle, manifest, sandboxed runtime |
| Bundled Plugins | `packages/dye2-plugin/` | DYE2 (Describe Your Espresso) — TypeScript/Vite plugin for bean & grinder management. Reference implementation for bundled plugins. |
| UI Features | `lib/src/` | `home_feature/`, `history_feature/`, `realtime_shot_feature/`, `settings/`, etc. |
| WebUI Skins | `lib/src/webui_support/` | Web-based UI skin management and serving |

### Key Controllers

- **`DeviceController`:** Coordinates multiple `DeviceDiscoveryService` implementations → unified device stream
- **`De1Controller`:** Machine operations (state, settings, profiles)
- **`ShotController`:** Orchestrates shot execution, stops at target weight. Timer lifecycle: reset on first tare (preparingForShot), start on second tare (preinfusion/pouring), stop when shot ends.
- **`ProfileController`:** Profile library with content-based hash IDs for deduplication
- **`WorkflowController`:** Multi-step espresso workflows

### Storage

Persistence uses Drift (SQLite) via `AppDatabase` in `lib/src/services/database/`. DAOs in `daos/` subfolder, mappers in `mappers/`. Storage service interfaces in `lib/src/services/storage/`, all backed by Drift implementations: `StorageService` (shots, workflow), `ProfileStorageService` (profiles), `BeanStorageService` (beans + batches), `GrinderStorageService` (grinders).

**Ambiguous imports:** Domain models and Drift-generated code share class names (`ShotRecord`, `Workflow`, `ProfileRecord`). Use prefixed imports: `import '...shot_record.dart' as domain;` or `hide Workflow` on the database import.

### Web Server

Handler-based routing in `lib/src/services/webserver/`. Each handler has `addRoutes()`, registered in `webserver_service.dart` `_init()`. Newer handlers are standalone imports; legacy ones use `part of`. API docs on port 4001, specs in `assets/api/`.

### REST API Overview

| Resource | Base Path | Handler |
|----------|-----------|---------|
| Machine | `/api/v1/machine/` | `webserver_service.dart` (part of) |
| Shots | `/api/v1/shots` | `shots_handler.dart` — paginated list with filtering (see `assets/api/rest_v1.yml`) |
| Profiles | `/api/v1/profiles` | `profiles_handler.dart` |
| Workflow | `/api/v1/workflow` | `workflow_handler.dart` — GET/PUT with deep merge |
| Beans | `/api/v1/beans` | `beans_handler.dart` — CRUD + `/api/v1/beans/<id>/batches` for batches, `/api/v1/bean-batches/<id>` for individual batch ops |
| Grinders | `/api/v1/grinders` | `grinders_handler.dart` — CRUD |
| Devices | `/api/v1/devices` | `webserver_service.dart` (part of) |
| Data Export | `/api/v1/data/export`, `/import` | `data_export_handler.dart` — ZIP-based full data export/import |
| Feedback | `/api/v1/feedback` | `feedback_handler.dart` — POST creates GitHub issue with optional logs/screenshots as Gist. Requires `GITHUB_FEEDBACK_TOKEN` at build time. |

### MCP Server

The MCP server in `packages/mcp-server/` bridges Claude to the Flutter app's REST/WebSocket APIs. Tool files in `src/tools/`, registered in `src/server.ts`. Lifecycle management (start/stop/reload) in `src/lifecycle/app-manager.ts`.

**When using MCP hot reload:** Always try `app_hot_reload` first (preserves state). Only use `app_hot_restart` if reload fails. Both have 30-second timeouts.

**Adding MCP tools:** Create a tool file in `src/tools/`, export a `register*Tools(server, rest)` function, import and call it in `server.ts`. Follow existing patterns (Zod schemas, REST client delegation, JSON responses).

**Using MCP for verification:** When the app is running (or can be started via `app_start`), prefer MCP tools over raw `curl` for smoke-testing changes. Use `app_start` with `connectDevice: "MockDe1"` and/or `connectScale: "MockScale"` for simulated testing. MCP tools can read machine state, exercise REST endpoints, subscribe to WebSocket streams, and manage workflows — all from within the conversation.

### Data Flow (key paths)

1. **Discovery:** `DeviceController` → multiple `DeviceDiscoveryService` instances → unified device stream
2. **Machine State:** Transport messages → DE1 parses → `De1Controller` broadcasts → WebSocket + Plugins
3. **API Requests:** HTTP → Shelf router → Handler → Controller → Device
4. **UI Scan:** Scan button → `DeviceController.scanForDevices()` → auto-connect (1 device) or selection dialog (multiple) or error (none)

## Conventions & Gotchas

- **RxDart:** Controllers use `BehaviorSubject` for state broadcasting
- **Async init:** Services/controllers have `initialize()` methods called from `main.dart`
- **Logging:** `package:logging`, configured in `main.dart`. Logs to `~/Download/REA1/log.txt` (Android) or app documents dir (other platforms)
- **Foreground service:** Android uses `ForegroundTaskService` to maintain BLE in background
- **StreamBuilder patterns:**
  - Check both `hasData` AND `data != null` for nullable streams (e.g., `De1Interface?`)
  - Use explicit type parameters: `StreamBuilder<De1Interface?>`
  - Lifecycle-aware widgets: implement `WidgetsBindingObserver`, set stream to `null` when backgrounded
- **Stream subscriptions:** Always cancel in `dispose()` methods
- **BLE Discovery:** Device discovery uses unfiltered scans with name-based matching (`DeviceMatcher`). Service verification happens during `onConnect()` using `BleServiceIdentifier`. All BLE operations use 128-bit UUID format for maximum platform compatibility.
- **BLE reads:** Throttle rapid characteristic reads to avoid overwhelming Bluetooth stack
- **Workflow dual representation:** Workflow JSON has both `context` (new: `WorkflowContext` with `grinderModel`, `coffeeName`, etc.) and legacy fields (`grinderData`, `coffeeData`, `doseData`). `Workflow.fromJson()` backfills context from legacy fields. UI reads from `context`; API clients can write to either. Always keep both in sync when modifying serialization.

## Testing

Run with `flutter test`. Simulated devices available via `--dart-define=simulate=1` or settings UI toggle.

### Test Helpers (`test/helpers/`)

- **`MockDeviceDiscoveryService`:** Controllable discovery for widget tests. Add/remove specific devices at specific times via `addDevice()`, `removeDevice()`, `clear()`.
- **`TestScale`:** Use instead of `MockScale` — `MockScale` has `Timer.periodic` that conflicts with `pumpAndSettle()`.
- **`MockSettingsService`:** In-memory `SettingsService`. Sets `telemetryPromptShown` and `telemetryConsentDialogShown` to `true` to skip dialogs.

### Widget Test Patterns

- **Stream propagation:** Add devices to mock service *before* building widgets, then `await tester.pump()` to flush microtasks before `pumpWidget()`.
- **ShadApp wrapping:** Use `ShadApp(home: Scaffold(body: child))` — `Scaffold` provides `Material` ancestor for `ListTile`/`Checkbox`.
- **Animations:** Use `pump()` not `pumpAndSettle()` when tree has `CircularProgressIndicator` or ongoing animations.
- **DeviceDiscoveryView:** Use `tester.runAsync()` — it uses real `Future.delayed` and stream microtask propagation.

## Common Workflows

### Adding a New Device Type

1. Create interface in `lib/src/models/device/` (extend `Device`, `Machine`, or `Scale`)
2. Implement in `lib/src/models/device/impl/{device_name}/`
3. Add name matching rule in `lib/src/services/device_matcher.dart`
4. Add service verification in the device's `onConnect()` using `BleServiceIdentifier.matchesAny()`
5. Create controller if needed in `lib/src/controllers/`
6. Add API handler in `lib/src/services/webserver/`

### Adding a New API Endpoint

1. Create/modify handler in `lib/src/services/webserver/`
2. Add route in handler's `addRoutes()`
3. Register in `webserver_service.dart` `_init()`
4. Add corresponding MCP tool in `packages/mcp-server/src/tools/` and register in `server.ts`
5. Document in `assets/api/rest_v1.yml` or `websocket_v1.yml`

## Documentation

Detailed docs in `doc/`:
- **`doc/Skins.md`** — WebUI skin development (API reference, deployment, examples)
- **`doc/Plugins.md`** — Plugin development (JS API, manifest, events, permissions)
- **`doc/Profiles.md`** — Profile API (content-based hashing, version tracking, endpoints)
- **`doc/DeviceManagement.md`** — Device discovery and connection management
- **`doc/RELEASE.md`** — Release process and versioning
- **`packages/dye2-plugin/README.md`** — DYE2 bundled plugin (architecture, build, dev server, extension guide)

