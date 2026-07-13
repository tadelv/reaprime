# AI Repo Map

Use this before broader docs when you need fast orientation. Read only the subsystem files that match the task, then widen to `AGENTS.md` if the local code is not enough.

## Subsystems

- Build, run, test, platform config: `doc/AI_BUILD_NOTES.md`, `Makefile`, `flutter_with_commit.sh`, `pubspec.yaml`, `.github/workflows/`.
- BLE transport, scanning, connection orchestration: `doc/AI_BLE_NOTES.md`, `lib/src/services/ble/`, `lib/src/controllers/connection/`, `lib/src/models/device/impl/`.
- DE1 machine state, protocol, shot sequencing: `lib/src/models/device/impl/de1/`, `lib/src/controllers/de1_controller.dart`, `lib/src/controllers/de1_state_manager.dart`, `lib/src/controllers/shot_sequencer.dart`.
- REST and WebSocket API: `doc/AI_API_NOTES.md`, `doc/Api.md`, `assets/api/rest_v1.yml`, `assets/api/websocket_v1.yml`, `lib/src/services/webserver/`.
- Profiles, workflows, beans, grinders: `doc/Profiles.md`, `lib/src/controllers/profile_controller.dart`, `lib/src/controllers/workflow_controller.dart`, `lib/src/services/webserver/beans_handler.dart`.
- Persistent storage: `doc/AI_STORAGE_NOTES.md`, `lib/src/services/storage_service.dart`, `lib/src/database/`, `lib/src/daos/`, `lib/src/mappers/`.
- Plugins and JS runtime: `doc/Plugins.md`, `lib/src/plugins/`, `packages/dye2-plugin/`, `assets/plugins/`.
- WebUI skins: `doc/Skins.md`, `lib/src/webui_support/`, `lib/src/services/webserver/webui/`.
- Scale devices (HDS, Bengle, Skale2, Acaia): `lib/src/models/device/impl/scale/`, `lib/src/controllers/scale_controller.dart`.
- Device discovery and connection: `doc/DeviceManagement.md`, `lib/src/controllers/connection/`, `lib/src/services/device_discovery/`.
- Crashlytics and telemetry: `doc/AI_DEBUG_NOTES.md`, `lib/src/services/crashlytics_error_filter.dart`, `lib/src/services/telemetry/`.
- Testing: `doc/AI_TESTING_NOTES.md`, `test/helpers/`.
- Onboarding and UI: `lib/src/onboarding_feature/`, `lib/src/launcher/`, `lib/src/settings/`.
- Release process: `doc/RELEASE.md`, `.github/workflows/release.yml`.
- Dev-loop skill: `.agents/skills/decent-app/SKILL.md`, `scripts/sb-dev.sh`.
- Archived design decisions: `doc/plans/archive/`.

## Start Here

- Any change: `doc/AI_TESTING_NOTES.md` for test patterns.
- BLE transport bugs, connection lifecycle, GATT errors: `doc/AI_BLE_NOTES.md`, then `lib/src/services/ble/`, `lib/src/controllers/connection/`.
- Adding or changing REST/WS endpoints: `doc/AI_API_NOTES.md`, `assets/api/rest_v1.yml` or `assets/api/websocket_v1.yml` (read spec first), then `lib/src/services/webserver/`. Update spec in same commit.
- DE1 machine behavior, shot state, profile execution: `lib/src/controllers/de1_state_manager.dart`, then `lib/src/controllers/de1_controller.dart`, `lib/src/controllers/shot_sequencer.dart`.
- Profile or workflow serialization: `doc/Profiles.md`, then `lib/src/models/data/` (domain models), `lib/src/daos/` (Drift DAOs).
- Database migration or schema change: `doc/AI_STORAGE_NOTES.md`, then `lib/src/database/app_database.dart`, `lib/src/daos/`, `lib/src/mappers/`.
- Plugin API or permission changes: `doc/Plugins.md`, then `lib/src/plugins/plugin_manager.dart`, `lib/src/plugins/plugin_host.dart`.
- Skin serving or WebUI changes: `doc/Skins.md`, then `lib/src/webui_support/`, `lib/src/services/webserver/webui/`.
- Device discovery or connection management: `doc/DeviceManagement.md`, then `lib/src/controllers/connection/connection_manager.dart`.
- Build or platform changes: `doc/AI_BUILD_NOTES.md`, then `Makefile`, `pubspec.yaml`.
- Crashlytics triage: `doc/AI_DEBUG_NOTES.md`, then `lib/src/services/crashlytics_error_filter.dart`.
- Onboarding or settings UI: `lib/src/onboarding_feature/`, `lib/src/settings/`, `lib/src/launcher/`.
- Release process: `doc/RELEASE.md`, then `.github/workflows/release.yml`.
- Historical design rationale: `doc/plans/archive/` — search for the feature name.

## Coupling

When you change X, also check Y and Z.

| Changing... | Must also check... | Why |
|-------------|---------------------|-----|
| BLE transport (`universal_ble_transport.dart`) | `UnifiedDe1Transport`, `De1Controller`, `ConnectionManager`, `CharSubscriptions`, crashlytics error filter, all transport tests | All layers share the `DataTransport` interface; gone-device handling affects error filtering |
| REST/WS endpoint (handler) | API spec (`rest_v1.yml` / `websocket_v1.yml`), router (`_init()`), `doc/Api.md`, handler test | Spec must stay in sync; stale spec = stale agent knowledge |
| Database schema (`app_database.dart`) | `@Database` version bump, migration in `onUpgrade`, DAOs, mappers, domain models (import prefixes) | Schema drift breaks persistence silently |
| Profile/workflow serialization | `Workflow.fromJson()`, `ProfileDao`, `ProfileStorageService`, legacy field backfill, spec | Dual representation (`context` + legacy fields); both must stay in sync |
| `ConnectionManager` | 7 collaborators (`DisconnectExpectations`, `StatusPublisher`, `ScanReportBuilder`, `DisconnectSupervisor`, `EarlyConnectWatcher`, `ScanOrchestrator`, `PolicyResolver`) | Delegate to the right collaborator rather than growing the manager |
| `De1StateManager` | `ShotSequencer`, `SteamSequencer`, `ScaleController` (sleep/wake), `ConnectionManager` (reconnect) | Machine state transitions cascade to shot lifecycle, scale power, and reconnect logic |
| Plugin API or permissions | `PluginManager`, `PluginHost`, `dye2-plugin`, `doc/Plugins.md`, bundled plugin assets | Plugin host + bundled plugin must stay compatible |
| WebUI / skin serving | `lib/src/webui_support/`, `lib/src/services/webserver/webui/`, `doc/Skins.md` | Skin install, serving, and metadata are coupled |
| Device discovery | `DeviceMatcher`, `BleServiceIdentifier`, `ScanStateGuardian`, `ScanOrchestrator`, `doc/DeviceManagement.md` | Name matching, service verification, and scan lifecycle are interdependent |
| `BatteryController` / charging | `charging_logic.dart`, `De1Controller`, DE1 FW behavior (auto-re-enables charger) | Charger mode logic depends on DE1 FW quirks |

## Focused Tests

- All tests: `flutter test`.
- Single test file: `flutter test test/path/to/test.dart`.
- Specific test: `flutter test --name "test name"`.
- Static analysis: `flutter analyze`.
- Format check: `flutter format lib/ test/`.
- API smoke test (running app): `scripts/sb-dev.sh start` then `curl` / `websocat` per `.agents/skills/decent-app/verification.md`.
- BLE transport tests: `flutter test test/services/ble/`.
- Connection manager tests: `flutter test test/controllers/connection/`.
- Handler tests: `flutter test test/services/webserver/`.

## Avoid Reading Unless Needed

- `doc/plans/archive/` — historical design docs. Useful for understanding why a decision was made, but stale for current code.
- `test/` test files — read only the ones relevant to the change.
- `assets/` assets unrelated to API specs.
- `ios/`, `android/`, `macos/`, `linux/`, `windows/` — platform-native project files. Only touch when adding platform capabilities.
- `packages/dye2-plugin/` — bundled plugin; read only when changing plugin system or the DYE2 plugin itself.
