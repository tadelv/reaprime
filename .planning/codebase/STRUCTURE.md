# Codebase Structure

**Analysis Date:** 2026-02-15

## Directory Layout

```
reaprime/
├── lib/                          # Dart source code
│   ├── main.dart                 # Application entry point
│   ├── build_info.dart           # Git commit/version info
│   └── src/                      # Main application source
│       ├── app.dart              # MyApp widget, navigation config
│       ├── controllers/          # Business logic orchestration
│       ├── models/               # Data models and device abstractions
│       ├── services/             # Infrastructure services
│       ├── plugins/              # JavaScript plugin system
│       ├── webui_support/        # WebUI skin support
│       ├── settings/             # Settings UI and persistence
│       ├── home_feature/         # Main UI with status tiles and controls
│       ├── history_feature/      # Shot history view
│       ├── realtime_shot_feature/ # Live shot visualization
│       ├── realtime_steam_feature/ # Steam operation visualization
│       ├── sample_feature/       # Device discovery debug view
│       ├── landing_feature/      # Initial load/permission screens
│       ├── skin_feature/         # WebUI skin viewer
│       ├── feedback_feature/     # User feedback submission
│       ├── permissions_feature/  # Runtime permission requests
│       ├── localization/         # i18n strings
│       └── util/                 # Utility functions
├── test/                         # Unit, integration, widget tests
├── android/                      # Android platform code
├── ios/                          # iOS platform code
├── macos/                        # macOS platform code
├── linux/                        # Linux platform code
├── windows/                      # Windows platform code
├── assets/                       # Bundled resources
│   ├── api/                      # OpenAPI specs
│   ├── plugins/                  # Bundled plugins
│   ├── defaultProfiles/          # Default espresso profiles
│   └── images/                   # App icons and logos
├── doc/                          # External documentation
│   ├── Plugins.md                # Plugin development guide
│   ├── Profiles.md               # Profile API documentation
│   ├── Skins.md                  # WebUI skin development guide
│   └── DeviceManagement.md       # Device discovery and connection
├── pubspec.yaml                  # Flutter dependencies
├── analysis_options.yaml         # Linter configuration
├── CLAUDE.md                     # Claude Code guidelines
├── .planning/                    # GSD planning documents
│   └── codebase/                 # Codebase analysis outputs
├── Makefile                      # Build automation (Linux ARM/x86_64)
├── Dockerfile                    # Linux container build
└── firebase.json                 # Firebase configuration
```

## Directory Purposes

**`lib/src/controllers/`:**
- Purpose: Application business logic and state orchestration
- Contains: Controller classes managing device operations and state
- Key files:
  - `device_controller.dart`: Aggregates devices from multiple discovery services
  - `de1_controller.dart`: Manages DE1 machine state, settings, auxiliary operations
  - `scale_controller.dart`: Connects to scales, broadcasts weight data
  - `shot_controller.dart`: Orchestrates shot execution with weight monitoring
  - `workflow_controller.dart`: Manages multi-step shot workflows
  - `profile_controller.dart`: Manages profile library with content-based deduplication
  - `persistence_controller.dart`: Persists shots and workflows to storage
  - `sensor_controller.dart`: Manages connected sensor devices
  - `battery_controller.dart`: Monitors device battery levels
  - `feedback_controller.dart`: Handles user feedback submission

**`lib/src/models/device/`:**
- Purpose: Device abstractions and implementations
- Contains: Abstract interfaces and concrete device implementations
- Structure:
  - Root level: `device.dart` (base Device interface), `machine.dart`, `scale.dart`, `sensor.dart`, interfaces for DE1 protocol
  - `impl/`: Concrete device implementations per manufacturer/model
    - `de1/`: DE1 machine implementations (BLE and Serial versions)
      - `unified_de1/`: Auto-selecting BLE/Serial based on availability
      - `de1.profile.dart`: Profile upload logic (device-specific)
    - `felicita/`: Felicita scales (Arc, etc.)
    - `acaia/`: Acaia scales (Pearl, Pyxis, etc.)
    - `decent_scale/`: Decent Scale implementation
    - `eureka/`: Eureka Precisa scale
    - `bookoo/`: Bookoo Miniscale
    - `difluid/`: Difluid scale
    - `skale/`: Skale 2 scale
    - `smartchef/`: SmartChef scale
    - `varia/`: Varia AKU scale
    - `atomheart/`: Atomheart scale
    - `hiroia/`: Hiroia scale
    - `blackcoffee/`: Black Coffee scale
    - `bengle/`: Bengle interface
    - `sensor/`: Basket sensors, debug port sensors, mock implementations
    - `mock_de1/`, `mock_scale/`: Simulated devices for testing without hardware
  - `transport/`: Protocol abstraction
    - `data_transport.dart`: Base transport interface
    - `ble_transport.dart`: BLE-specific read/write/subscribe interface
    - `serial_port.dart`: Serial-specific command/stream interface

**`lib/src/models/data/`:**
- Purpose: Application data models
- Contains:
  - `profile.dart`: Espresso profile model (v2 JSON format)
  - `profile_record.dart`: Profile with metadata envelope
  - `profile_hash.dart`: Content-based hashing (SHA-256)
  - `workflow.dart`: Multi-step workflow definition
  - `shot_record.dart`: Persisted shot data
  - `shot_snapshot.dart`: Real-time shot telemetry
  - `json_utils.dart`, `utils.dart`: Helper functions

**`lib/src/services/`:**
- Purpose: Infrastructure services (discovery, storage, web server, communication)
- Contains:
  - **Device Discovery:**
    - `blue_plus_discovery_service.dart`: BLE discovery (Android/iOS/macOS/Linux via flutter_blue_plus)
    - `universal_ble_discovery_service.dart`: Windows BLE discovery (via universal_ble)
    - `serial_service.dart`, `services/serial/`: Serial port discovery and communication (desktop platforms)
    - `simulated_device_service.dart`: Mock devices for development
  - **Storage:**
    - `storage/file_storage_service.dart`: File-based persistence
    - `storage/hive_store_service.dart`: Key-value store via Hive
    - `storage/hive_profile_storage.dart`: Profile persistence via Hive
    - `storage/profile_storage_service.dart`: Profile storage interface
    - `storage/kv_store_service.dart`: KV store abstraction
  - **Web Server & API:**
    - `webserver_service.dart`: Shelf-based REST/WebSocket server, handler initialization
    - `webserver/de1handler.dart`: DE1 machine API endpoints
    - `webserver/scale_handler.dart`: Scale API endpoints
    - `webserver/devices_handler.dart`: Device discovery and connection endpoints
    - `webserver/profile_handler.dart`: Profile management endpoints
    - `webserver/workflow_handler.dart`: Workflow execution endpoints
    - `webserver/shots_handler.dart`: Shot history endpoints
    - `webserver/sensors_handler.dart`: Sensor data endpoints
    - `webserver/plugins_handler.dart`: Plugin management and events
    - `webserver/settings_handler.dart`: Settings API
    - `webserver/webui_handler.dart`: WebUI skin management
    - `webserver/feedback_handler.dart`: User feedback submission
    - `webserver/kv_store_handler.dart`: Generic key-value store API
  - **Other:**
    - `foreground_service.dart`: Android foreground service for background connectivity
    - `feedback_service.dart`: GitHub issue creation for user feedback
    - `update_check_service.dart`: APK/app version checking
    - `webview_compatibility_checker.dart`: WebView feature detection
    - `apk_installer.dart`, `android_updater.dart`: Android-specific updates

**`lib/src/plugins/`:**
- Purpose: JavaScript plugin system for extensibility
- Contains:
  - `plugin_loader_service.dart`: Plugin discovery, loading, auto-load management
  - `plugin_manager.dart`: Event routing between Flutter and JS plugins
  - `plugin_manifest.dart`: Plugin metadata schema (permissions, settings, API endpoints)
  - `plugin_runtime.dart`: JavaScript execution wrapper
  - `plugin_types.dart`: Type definitions for plugin communication

**`lib/src/webui_support/`:**
- Purpose: WebUI skin support (serve custom web interfaces)
- Contains:
  - `webui_service.dart`: Skin installation and management
  - `webui_storage.dart`: Bundled skin definitions and remote sources

**`lib/src/home_feature/`:**
- Purpose: Main UI displaying machine status and controls
- Contains:
  - `home_feature.dart`: Main home view composition
  - `tiles/`: Status display tiles
    - `status_tile.dart`: DE1 state, temperatures, water levels (with lifecycle-aware streaming)
    - `settings_tile.dart`: Power controls, auxiliary functions (clean/descale), device scanning
    - `profile_tile.dart`: Profile selection UI
  - `forms/`: User input forms
    - `espresso_form.dart`: Shot start/stop controls
    - `hot_water_form.dart`: Hot water dispensing
    - `steam_form.dart`: Steam wand operation
    - `rinse_form.dart`: Group head rinsing
  - `widgets/`: Reusable components

**`lib/src/history_feature/`:**
- Purpose: Shot history browsing
- Contains: Views for listing and filtering past shots

**`lib/src/realtime_shot_feature/`:**
- Purpose: Live visualization of shot progress
- Contains: Charts showing pressure, flow, weight over time during active shot

**`lib/src/realtime_steam_feature/`:**
- Purpose: Steam operation visualization
- Contains: Real-time display during steam/hot water operations

**`lib/src/settings/`:**
- Purpose: Application settings and configuration
- Contains:
  - `settings_controller.dart`: In-memory settings with persistence
  - `settings_service.dart`: SharedPreferences-based storage
  - `settings_view.dart`: Settings UI (gateway mode, scale behavior, default skin)
  - `gateway_mode.dart`: Full vs. restricted operation mode
  - `scale_power_mode.dart`: Scale sleep behavior configuration
  - `plugins_settings_view.dart`: Plugin management UI

**`lib/src/sample_feature/`:**
- Purpose: Device discovery and debug views
- Contains:
  - `sample_item_list_view.dart`: List available devices with connection status
  - `scale_debug_view.dart`: Scale weight and battery display

**`lib/src/util/`:**
- Purpose: Shared utility functions
- Contains: Helpers for common operations (animations, state management, math)

**`test/`:**
- Purpose: Automated tests
- Contains:
  - `unit_test.dart`: Unit tests for controllers and services
  - `profile_test.dart`: Comprehensive profile hashing and management tests (21 tests)
  - `widget_test.dart`: Flutter widget tests

**`assets/`:**
- Purpose: Bundled static resources
- Contains:
  - `api/`: OpenAPI specification files for REST/WebSocket endpoints
  - `plugins/`: Bundled plugins auto-copied to app documents on startup
  - `defaultProfiles/`: Default espresso profiles (auto-loaded)
  - `images/`: App icons and logos

**`doc/`:**
- Purpose: External developer documentation
- Contains:
  - `Plugins.md`: JavaScript plugin development guide
  - `Profiles.md`: Profile API and content-based hashing
  - `Skins.md`: WebUI skin development and deployment
  - `DeviceManagement.md`: Device discovery and connection patterns
  - `RELEASE.md`: Release process and versioning

## Key File Locations

**Entry Points:**
- `lib/main.dart`: Application startup, dependency initialization
- `lib/src/app.dart`: MyApp widget, routing configuration, controller injection

**Configuration:**
- `pubspec.yaml`: Flutter dependencies (flutter_blue_plus, shelf, hive, etc.)
- `analysis_options.yaml`: Linter rules
- `lib/build_info.dart`: Git commit/version information (generated by `flutter_with_commit.sh`)
- `.env.dev`: Environment variables for local development (not committed)

**Core Logic:**
- `lib/src/controllers/device_controller.dart`: Device discovery orchestration
- `lib/src/controllers/de1_controller.dart`: DE1 machine state management
- `lib/src/controllers/scale_controller.dart`: Scale integration
- `lib/src/controllers/shot_controller.dart`: Shot execution control
- `lib/src/models/device/machine.dart`: Machine abstraction
- `lib/src/models/device/scale.dart`: Scale abstraction

**API:**
- `lib/src/services/webserver_service.dart`: HTTP/WebSocket server
- `lib/src/services/webserver/de1handler.dart`: Machine API routes
- `lib/src/services/webserver/profile_handler.dart`: Profile API routes

**Testing:**
- `test/profile_test.dart`: Profile hash mechanics (21 comprehensive tests)
- `test/unit_test.dart`: General unit tests

## Naming Conventions

**Files:**
- Dart files use `snake_case`: `device_controller.dart`, `blue_plus_discovery_service.dart`
- Feature directories use descriptive names: `home_feature`, `realtime_shot_feature`
- Device implementation directories named after manufacturer: `felicita`, `acaia`, `decent_scale`
- Interfaces typically named without "Impl" suffix; implementations may have suffixes: `DecentScale` class in `decent_scale.dart`

**Directories:**
- Controllers: `controllers/` (flat, one file per controller)
- Device implementations: `models/device/impl/{manufacturer}/{model}.dart` or `models/device/impl/{type}/{name}.dart`
- Features: `{feature_name}_feature/` with subfolders for domain separation (tiles, forms, widgets)
- Services: `services/` with subfolders by function (`storage/`, `serial/`, `ble/`, `webserver/`)
- Tests: `test/` with names matching tested module: `profile_test.dart` for profile functionality

**Classes & Types:**
- PascalCase: `DeviceController`, `BluePlusDiscoveryService`, `DecentScale`
- Interfaces: no "I" prefix; use "Interface" suffix or descriptive name: `De1Interface`, `Machine`, `Scale`
- Enums: PascalCase singular: `DeviceType`, `ConnectionState`, `MachineState`
- Constants: camelCase in classes, UPPER_SNAKE_CASE for global constants

**Functions & Methods:**
- camelCase: `startWebServer()`, `scanForDevices()`, `tare()`, `onConnect()`
- Private methods: prefix with underscore: `_serviceUpdate()`, `_processSnapshot()`
- Callbacks: descriptive names: `_handleScan()`, `_processConnection()`

**Streams & Subjects:**
- Variable naming: `{noun}Stream`, `{noun}Subject` or `{noun}Controller` (BehaviorSubject)
- Examples: `deviceStream`, `currentSnapshot`, `connectionState`, `_de1Controller` (BehaviorSubject)
- Getter: `{noun}` returns Stream; subject not exposed directly: `de1` getter returns `_de1Controller.stream`

## Where to Add New Code

**New Machine Type:**
1. Create directory: `lib/src/models/device/impl/{manufacturer}/`
2. Implement concrete class extending `Machine` in `{model}.dart`
3. Implement protocol parsing (BLE characteristics or serial commands)
4. Register in `main.dart` `bleDeviceMappings` or serial service discovery
5. Create API handler if specialized endpoints needed: `lib/src/services/webserver/{device_name}_handler.dart`
6. Add tests: `test/{device_name}_test.dart`

**New Scale Type:**
1. Create directory: `lib/src/models/device/impl/{manufacturer}/`
2. Implement concrete class extending `Scale` in `{model}.dart`
3. Implement weight streaming via `BLETransport` or `SerialTransport`
4. Register in `main.dart` `bleDeviceMappings`
5. Implement `currentSnapshot` stream emitting `ScaleSnapshot`
6. Implement `tare()`, `sleepDisplay()`, `wakeDisplay()` methods

**New Feature:**
1. Create directory: `lib/src/{feature_name}_feature/`
2. Create main view: `lib/src/{feature_name}_feature/{feature_name}_feature.dart`
3. Create subdirectories as needed: `tiles/`, `forms/`, `widgets/`
4. Inject controllers via constructor from `main.dart`
5. Subscribe to controller streams using `StreamBuilder` with null checks: `if (snapshot.hasData && snapshot.data != null)`
6. Register route in `_MyAppState` router configuration

**New API Endpoint:**
1. Create or modify handler: `lib/src/services/webserver/{resource}_handler.dart`
2. Add route in handler's `addRoutes()` method
3. Register handler initialization in `webserver_service.dart` `_init()` function
4. Document endpoint in `assets/api/rest_v1.yml` or `websocket_v1.yml`
5. Return JSON response with `response.json(data)` or WebSocket message with JSON serialization

**New Storage Type:**
1. Implement interface: `lib/src/services/storage/{name}_service.dart`
2. Extend `StorageService` or `KvStoreService` interface
3. Inject in controller or service that needs it
4. Call `initialize()` from `main.dart` if required

**Utility Functions:**
1. Place in `lib/src/util/` with descriptive filename
2. Export from barrel file or import directly where used
3. Keep functions focused and testable
4. Add unit tests in `test/util_test.dart`

## Special Directories

**`lib/src/models/device/impl/mock_de1/`, `mock_scale/`:**
- Purpose: Simulated devices for development and testing without hardware
- Generated: No (hand-written)
- Committed: Yes
- Activate: Set `simulate=1` compile-time variable or toggle in Settings UI

**`build/`:**
- Purpose: Flutter build artifacts
- Generated: Yes (build process)
- Committed: No (.gitignored)

**`assets/plugins/`:**
- Purpose: Bundled plugins auto-copied to app documents on startup
- Generated: No (hand-written plugin directories)
- Committed: Yes (as plugin source files)
- Deployment: Plugins copied to `${appDocDir}/plugins/` on app initialization

**`assets/defaultProfiles/`:**
- Purpose: Default espresso profiles included in app
- Generated: No (hand-written JSON profiles)
- Committed: Yes
- Loading: Auto-loaded by `ProfileController` on startup if not already in database

**`.planning/`:**
- Purpose: GSD codebase analysis outputs
- Generated: Yes (by codebase mapper)
- Committed: Yes (for team reference)
- Contents: ARCHITECTURE.md, STRUCTURE.md, CONVENTIONS.md, TESTING.md, STACK.md, INTEGRATIONS.md, CONCERNS.md

---

*Structure analysis: 2026-02-15*
