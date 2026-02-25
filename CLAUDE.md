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

1. **Enter plan mode:** Use `EnterPlanMode` to explore the codebase and design the implementation approach.
2. **Write the plan:** Create a plan file in `doc/plans/` with:
   - Implementation steps
   - Files to modify/create
   - Architectural considerations
   - Testing approach
3. **Plan annotation:** Present the plan to the user. The user will review and provide feedback, clarifications, or requested changes as annotations to the plan.
4. **Iterate if needed:** Update the plan based on user feedback until approved.
5. **Only after plan approval:** Proceed to implementation.

**Skip planning only for:**
- Simple typo fixes
- Single-line changes
- Tasks with very specific, detailed instructions from the user

### Verification Loop

**Before starting work, ask the user** which verification approach to use:
- **Tests + analyze only** — automated checks only. Best for refactors, internal logic, well-tested code paths.
- **Tests + run app** — run with `simulate=1` so user can visually verify. Best for GUI features, UX changes.
- **Tests + API smoke test** — run app, then `curl` changed endpoints to verify responses. Best for API work.
- **Tests + custom check** — user specifies what to verify (e.g., real hardware test, WebSocket stream check).

**Ask the user** whether new/updated tests are needed for the change. If yes, write tests before or alongside the implementation — not as an afterthought.

During development, after every meaningful code change:

1. **Targeted check:** Run the specific test file(s) related to the change + `flutter analyze`.
   ```bash
   flutter test test/relevant_test.dart
   flutter analyze
   ```
2. **Fix before continuing.** If tests fail or analyzer reports issues, fix them immediately — do not accumulate broken state.
3. **Full suite at milestones:** Run `flutter test` (all tests) before committing, after completing a plan step, and before claiming work is done.
4. **Final verification:** Perform the user's chosen verification approach before reporting completion. Never skip. Evidence before assertions.

### Plans

- Write implementation plans as `.md` files in `doc/plans/`.
- **Do not commit** plan files unless the user requests it or asks to save progress.
- After a plan is fully implemented, ask the user whether to update relevant
  documentation with the outcome.
- **When creating a PR or finishing a branch**, ask the user to archive the plan:
  move it to `doc/plans/archive/` and commit it as part of the branch.
  This keeps the plan alongside the implementation for future reference.

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
| UI Features | `lib/src/` | `home_feature/`, `history_feature/`, `realtime_shot_feature/`, `settings/`, etc. |
| WebUI Skins | `lib/src/webui_support/` | Web-based UI skin management and serving |

### Key Controllers

- **`DeviceController`:** Coordinates multiple `DeviceDiscoveryService` implementations → unified device stream
- **`De1Controller`:** Machine operations (state, settings, profiles)
- **`ShotController`:** Orchestrates shot execution, stops at target weight. Timer lifecycle: reset on first tare (preparingForShot), start on second tare (preinfusion/pouring), stop when shot ends.
- **`ProfileController`:** Profile library with content-based hash IDs for deduplication
- **`WorkflowController`:** Multi-step espresso workflows

### Web Server

Handler-based routing in `lib/src/services/webserver/`. Each handler file is a `part of` `webserver_service.dart` (shares its imports — `Response`, `jsonError`, `sws`, etc.). Each handler has an `addRoutes()` method, registered in `_init()`. API docs served on port 4001. API specs in `assets/api/`.

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
4. Document in `assets/api/rest_v1.yml` or `websocket_v1.yml`

## Documentation

Detailed docs in `doc/`:
- **`doc/Skins.md`** — WebUI skin development (API reference, deployment, examples)
- **`doc/Plugins.md`** — Plugin development (JS API, manifest, events, permissions)
- **`doc/Profiles.md`** — Profile API (content-based hashing, version tracking, endpoints)
- **`doc/DeviceManagement.md`** — Device discovery and connection management
- **`doc/RELEASE.md`** — Release process and versioning

