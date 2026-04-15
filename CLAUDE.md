# CLAUDE.md

> **Note:** If you're using a different AI coding agent (Cursor, Copilot, Windsurf, Codex, etc.), see `AGENTS.md` for tool-agnostic guidance. `CLAUDE.md` is Claude Code-specific and includes commands like `EnterPlanMode` and references to `.claude/skills/`.

## Project Overview

Streamline-Bridge (formerly REA/ReaPrime/R1) is a Flutter gateway app for Decent Espresso machines. Connects to DE1 machines and scales via BLE/USB, exposing REST (port 8080) and WebSocket APIs. Includes a JavaScript plugin system. Primary platform: Android (DE1 tablet), also macOS, Linux, Windows, iOS. Note: the rename is in progress — code, repo, and file references may still use the old names.

**Reference implementation:** The original Decent Espresso app at `github.com/decentespresso/de1app` is the authoritative source for DE1 protocol behavior, BLE characteristics, and machine state logic. Consult it when implementation details are unclear. Note: Streamline-Bridge uses its own JSON profile format — the TCL-based profile format in de1app is not authoritative for profiles here.

## Commands

```bash
# Run
./flutter_with_commit.sh run              # Standard (injects git commit version)
flutter run --dart-define=simulate=1      # Simulated devices (no hardware needed)
flutter run --dart-define=simulate=machine  # Simulate machine only (comma-separated: machine,scale)

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

**Do not push to remote or create PRs until the user explicitly instructs you to.** Commit locally as needed, but wait for the user to say when to push.

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

### Development Workflow

**For features, bugfixes, and refactors:** Follow the TDD workflow skill (`.claude/skills/tdd-workflow/`). It covers test tier selection (unit, integration, end-to-end), outside-in test writing, inside-out implementation, self-review loops, and the end-to-end verification protocol via `scripts/sb-dev.sh`.

**For non-code changes** (docs, config, CI) where no test tiers apply, ask the user which verification approach to use:
- **Analyze only** — `flutter analyze`. Minimum for any change.
- **Run app** — run with `simulate=1` so user can visually verify. For GUI/UX changes.
- **End-to-end smoke test** — use `scripts/sb-dev.sh` + `curl` / `websocat` to exercise affected endpoints. See `.agents/skills/streamline-bridge/verification.md`. For API spec or manifest changes.
- **Custom check** — user specifies (e.g., real hardware test, WebSocket stream check).

After every meaningful code change:
1. Run relevant tests + `flutter analyze`. Fix immediately if anything fails.
2. Run full `flutter test` before committing and before claiming done.
3. Evidence before assertions — show test output, not just "tests pass."

Plans go in `doc/plans/`. Don't commit unless asked. After implementation, ask whether to update related docs.

**Before opening a PR, merging locally, or considering work done:**
1. Move all plans and implementation documents from `doc/plans/` to `doc/plans/archive/<meaningful-subfolder-name>/`. The subfolder name should reflect the feature or fix (e.g., `app-store-readiness`, `scale-auto-connect`).
2. Check if any documentation needs updating based on the changes made — e.g., `doc/Api.md` if endpoints changed/added, `doc/Skins.md` if skin behavior changed, `doc/Plugins.md` if events changed/added, `doc/Profiles.md` if profile handling changed, `doc/DeviceManagement.md` if device flows changed, etc.

Both steps are required, not optional.

## Architecture

### Design Principles

- **Transport abstraction:** Device implementations depend on injected transport interfaces (`DataTransport`, `BleTransport`, `SerialPort`), not concrete implementations. **Never import 3rd-party BLE libraries** (e.g. `flutter_blue_plus`) outside the `services/ble/` layer — wrap library-specific types (errors, events) in domain types at the transport boundary.
- **Constructor dependency injection:** No service locators. Dependencies passed through constructors.
- **Single Responsibility:** Each controller/service has one focused purpose.

### Layer Overview

| Layer | Path | Purpose |
|-------|------|---------|
| Devices | `lib/src/models/device/` | Abstract interfaces (`Device`, `Machine`, `Scale`, `Sensor`) + implementations in `impl/` |
| Controllers | `lib/src/controllers/` | Business logic orchestration between devices and services |
| Services | `lib/src/services/` | Discovery, storage, settings, web server |
| Plugins | `lib/src/plugins/` | JS plugin lifecycle, manifest, sandboxed runtime |
| Bundled Plugins | `packages/dye2-plugin/`, `assets/plugins/` | DYE2 (bean/grinder management, TypeScript/Vite), Settings (web-based settings dashboard, plain JS). |
| UI Features | `lib/src/` | `home_feature/`, `history_feature/`, `realtime_shot_feature/`, `settings/`, etc. |
| WebUI Skins | `lib/src/webui_support/` | Web-based UI skin management and serving |

### Key Controllers

- **`DeviceController`:** Coordinates multiple `DeviceDiscoveryService` implementations → unified device stream
- **`ConnectionManager`:** Centralized connection orchestrator. Scans for devices, applies preferred-device policy, handles machine→scale connection sequencing. Exposes `ConnectionStatus` stream with phases: `idle`, `scanning`, `connectingMachine`, `connectingScale`, `ready`.
- **`De1Controller`:** Machine operations (state, settings, profiles)
- **`ScaleController`:** Scale connection lifecycle, weight/flow data processing
- **`ShotController`:** Orchestrates shot execution, stops at target weight. Timer lifecycle: reset on first tare (preparingForShot), start on second tare (preinfusion/pouring), stop when shot ends.
- **`ProfileController`:** Profile library with content-based hash IDs for deduplication
- **`WorkflowController`:** Multi-step espresso workflows
- **`PersistenceController`:** Thin persistence layer — delegates to `StorageService`, emits `shotsChanged` stream for UI/handler invalidation
- **`SensorController`:** Sensor data management and broadcasting
- **`BatteryController`:** Battery level monitoring and charging state
- **`PresenceController`:** Client presence/keep-alive tracking
- **`DisplayController`:** Display/screen management
- **`FeedbackController`:** Feedback submission orchestration

### Storage

Persistence uses Drift (SQLite) via `AppDatabase` in `lib/src/services/database/`. DAOs in `daos/` subfolder, mappers in `mappers/`. Storage service interfaces in `lib/src/services/storage/`, all backed by Drift implementations: `StorageService` (shots, workflow), `ProfileStorageService` (profiles), `BeanStorageService` (beans + batches), `GrinderStorageService` (grinders).

**Ambiguous imports:** Domain models and Drift-generated code share class names (`ShotRecord`, `Workflow`, `ProfileRecord`). Use prefixed imports: `import '...shot_record.dart' as domain;` or `hide Workflow` on the database import.

### Web Server

Handler-based routing in `lib/src/services/webserver/`. Each handler has `addRoutes()`, registered in `webserver_service.dart` `_init()`. Most handlers use `part of webserver_service.dart`; standalone imports: `shots_handler`, `beans_handler`, `grinders_handler`, `workflow_handler`, `data_export_handler`, `data_sync_handler`, `info_handler`. API docs on port 4001, specs in `assets/api/`.

### REST & WebSocket API

Full endpoint reference in **[`doc/Api.md`](doc/Api.md)**. OpenAPI specs in `assets/api/rest_v1.yml` and `assets/api/websocket_v1.yml`.

### Dev-loop skill

Driving a running Flutter app (start, stop, hot reload, curl, websocat) is documented in `.agents/skills/streamline-bridge/`. Entry point: `.agents/skills/streamline-bridge/README.md`. Lifecycle is managed by `scripts/sb-dev.sh` (POSIX shell, macOS/Linux only). Prefer `sb-dev reload` (preserves state) over `sb-dev hot-restart`. For end-to-end smoke-testing a change, see `.agents/skills/streamline-bridge/verification.md` and the regression recipes under `.agents/skills/streamline-bridge/scenarios/`.

### Data Flow (key paths)

1. **Discovery:** `DeviceController` → multiple `DeviceDiscoveryService` instances → unified device stream
2. **Machine State:** Transport messages → DE1 parses → `De1Controller` broadcasts → WebSocket + Plugins
3. **API Requests:** HTTP → Shelf router → Handler → Controller → Device
4. **Connection Flow:** `ConnectionManager.connect()` → scan → apply preferred-device policy → connect machine → connect scale. Status stream drives `DeviceDiscoveryView` UI (phases: idle → scanning → connectingMachine → connectingScale → ready)

## Conventions & Gotchas

- **RxDart:** Controllers use `BehaviorSubject` for state broadcasting
- **Async init:** Services/controllers have `initialize()` methods called from `main.dart`
- **Logging:** `package:logging`, configured in `main.dart`. Logs to `~/Download/REA1/log.txt` (Android) or app documents dir (other platforms)
- **Foreground service:** Android uses `ForegroundTaskService` to maintain BLE in background. Auto-stops after a 5-minute grace period when the machine disconnects; auto-restarts on reconnect. Shows connection state in the notification.
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

### Test Tiers

| Tier | What | Mock boundary |
|------|------|---------------|
| **Unit** | Single controller, model, DAO, handler | Direct collaborators mocked |
| **Integration** | Multi-component flows (e.g., scan → connect → measure) | Only hardware/transport edge mocked |
| **End-to-end** | API surface, WebSocket streams, full-stack through running app | App in simulate mode (MockDe1, MockScale) |

All Dart tests (unit + integration) live in `test/` and run via `flutter test`. End-to-end regression recipes live under `.agents/skills/streamline-bridge/scenarios/` as markdown — run them via `scripts/sb-dev.sh` + `curl` / `websocat`. See `.claude/skills/tdd-workflow/` for the full process.

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
4. **Update `assets/api/rest_v1.yml` (or `websocket_v1.yml`) in the same commit** — the spec is authoritative, stale spec = stale agent knowledge
5. Update `doc/Api.md` if user-facing. Smoke-test via `scripts/sb-dev.sh` + `curl` — see `.agents/skills/streamline-bridge/verification.md`

## Documentation

Detailed docs in `doc/`:
- **`doc/Api.md`** — Full REST & WebSocket API reference (all endpoints, methods, payloads)
- **`doc/Skins.md`** — WebUI skin development (API reference, deployment, examples)
- **`doc/Plugins.md`** — Plugin development (JS API, manifest, events, permissions)
- **`doc/Profiles.md`** — Profile API (content-based hashing, version tracking, endpoints)
- **`doc/DeviceManagement.md`** — Device discovery and connection management
- **`doc/RELEASE.md`** — Release process and versioning
- **`.agents/skills/streamline-bridge/`** — Dev-loop skill: `sb-dev` lifecycle, REST/WebSocket recipes, simulated devices, verification scenarios
- **`packages/dye2-plugin/README.md`** — DYE2 bundled plugin (architecture, build, dev server, extension guide)

