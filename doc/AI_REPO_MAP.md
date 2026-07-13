# AI Repo Map

Use this before broader docs when you need fast orientation. Read only the subsystem files that match the task, then widen to `CLAUDE.md` if the local code is not enough.

## Subsystems

- Build, run, test, platform config: `Makefile`, `flutter_with_commit.sh`, `pubspec.yaml`, `analysis_options.yaml`, `.github/workflows/`.
- BLE transport, scanning, connection orchestration: `doc/AI_BLE_NOTES.md`, `lib/src/services/ble/`, `lib/src/controllers/connection/`, `lib/src/models/device/impl/`.
- DE1 machine state, protocol, shot sequencing: `lib/src/models/device/impl/de1/`, `lib/src/controllers/de1_controller.dart`, `lib/src/controllers/de1_state_manager.dart`, `lib/src/controllers/shot_sequencer.dart`, `lib/src/services/de1/`.
- REST and WebSocket API: `doc/Api.md`, `assets/api/rest_v1.yml`, `assets/api/websocket_v1.yml`, `lib/src/services/webserver/`.
- Profiles, workflows, beans, grinders: `lib/src/controllers/profile_controller.dart`, `lib/src/controllers/workflow_controller.dart`, `lib/src/services/webserver/beans_handler.dart`, `lib/src/services/webserver/grinders_handler.dart`.
- Persistent storage: `lib/src/services/storage_service.dart`, `lib/src/database/`, `lib/src/daos/`, `lib/src/mappers/`.
- Plugins and JS runtime: `lib/src/plugins/`, `packages/dye2-plugin/`, `assets/plugins/`.
- WebUI skins: `lib/src/webui_support/`, `lib/src/services/webserver/webui/`.
- Scale devices (HDS, Bengle, Skale2, Acaia): `lib/src/models/device/impl/scale/`, `lib/src/controllers/scale_controller.dart`.
- Crashlytics and telemetry: `lib/src/services/crashlytics_error_filter.dart`, `lib/src/services/telemetry/`.
- Onboarding and UI: `lib/src/onboarding_feature/`, `lib/src/launcher/`, `lib/src/settings/`.
- Dev-loop skill: `.agents/skills/decent-app/SKILL.md`, `scripts/sb-dev.sh`.

## Start Here

- BLE transport bugs, connection lifecycle, GATT errors: `doc/AI_BLE_NOTES.md`, then `lib/src/services/ble/`, `lib/src/controllers/connection/`.
- Adding or changing REST/WS endpoints: `assets/api/rest_v1.yml` or `assets/api/websocket_v1.yml` (read spec first), then `lib/src/services/webserver/`, update spec in same commit.
- DE1 machine behavior, shot state, profile execution: `lib/src/controllers/de1_state_manager.dart`, then `lib/src/controllers/de1_controller.dart`, `lib/src/controllers/shot_sequencer.dart`.
- Profile or workflow serialization: `lib/src/models/data/` (domain models), `lib/src/daos/` (Drift DAOs), `lib/src/services/webserver/{workflow,profile}_handler.dart`.
- Database migration or schema change: `lib/src/database/app_database.dart`, `lib/src/daos/`, `lib/src/mappers/`. Schema versions in the Drift `@Database` annotation.
- Plugin API or permission changes: `lib/src/plugins/plugin_manager.dart`, `lib/src/plugins/plugin_host.dart`, `packages/dye2-plugin/`.
- Skin serving or WebUI changes: `lib/src/webui_support/`, `lib/src/services/webserver/webui/`, `doc/Skins.md`.
- Build or platform changes: `Makefile`, `pubspec.yaml`, `flutter_with_commit.sh`, `doc/AI_BUILD_NOTES.md`.
- Crashlytics triage: `doc/AI_DEBUG_NOTES.md`, `lib/src/services/crashlytics_error_filter.dart`.
- Onboarding or settings UI: `lib/src/onboarding_feature/`, `lib/src/settings/`, `lib/src/launcher/`.

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
- `doc/agents/` — agent workflow policies, not code-level guidance.
- `assets/` assets unrelated to API specs.
- `ios/`, `android/`, `macos/`, `linux/`, `windows/` — platform-native project files. Only touch when adding platform capabilities.
- `packages/dye2-plugin/` — bundled plugin; read only when changing plugin system or the DYE2 plugin itself.
