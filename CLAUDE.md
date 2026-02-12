# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ReaPrime (REA/R1) is a Flutter-based gateway application for Decent Espresso machines. It connects to DE1 espresso machines and scales via Bluetooth/USB, exposing REST and WebSocket APIs for client applications. The app supports shot control, machine state management, profile uploads, and a JavaScript plugin system for extensibility.

**Primary Platform:** Android (DE1 tablet), with support for macOS, Linux, Windows, and iOS.

## Development Commands

### Running the App

```bash
# Standard run (includes version injection from git commit)
./flutter_with_commit.sh run

# Run with simulated devices
flutter run --dart-define=simulate=1

# Run tests
flutter test

# Run specific test
flutter test test/unit_test.dart
```

### Building

```bash
# Build for Linux ARM64 (using Docker/Colima)
make build-arm

# Build for Linux x86_64 (using Docker/Colima)
make build-amd

# Build both architectures
make dual-build

# Start Colima with ARM64 profile
make colima-arm

# Start Colima with x86_64 profile
make colima-amd
```

### Linting & Analysis

```bash
# Run Flutter analyzer
flutter analyze

# Format code
flutter format lib/ test/
```

### Dependencies

```bash
# Get dependencies
flutter pub get

# Upgrade dependencies
flutter pub upgrade
```

## Architecture

### Core Design Principles

- **Transport abstraction:** All connection types (BLE, Serial, etc.) are abstracted through interfaces. Device implementations depend on injected transport interfaces, not concrete implementations.
- **Constructor dependency injection:** Controllers and services receive dependencies through constructors.
- **Single Responsibility Principle:** Each component has a clear, focused purpose.

### Key Architectural Layers

**1. Device Layer (`lib/src/models/device/`)**
- **Abstract interfaces:** `Device`, `Machine`, `Scale`, `Sensor`
- **Transport abstractions:** `DataTransport`, `BleTransport`, `SerialPort`
- **Concrete implementations:**
  - DE1 machines: `de1/de1.dart`, `serial_de1/serial_de1.dart`, `de1/unified_de1/unified_de1.dart`
  - Scales: `felicita/arc.dart`, `decent_scale/scale.dart`, `bookoo/miniscale.dart`
  - Sensors: `sensor/sensor_basket.dart`, `sensor/debug_port.dart`
  - Mock devices: `mock_de1/`, `mock_scale/` for testing without hardware

**2. Controllers (`lib/src/controllers/`)**

Controllers manage business logic and orchestrate between devices and services:
- **`DeviceController`:** Manages device discovery across multiple `DeviceDiscoveryService` implementations (BLE, Serial, Simulated)
- **`De1Controller`:** Controls DE1 machine operations (state, settings, profiles)
- **`ScaleController`:** Manages scale connections and weight data
- **`SensorController`:** Handles sensor data streams
- **`ShotController`:** Orchestrates shot execution, stopping at target weight
- **`WorkflowController`:** Manages multi-step espresso workflows
- **`ProfileController`:** Manages profile library with content-based hash IDs for automatic deduplication
- **`PersistenceController`:** Handles saving/loading shots and workflows

**3. Services (`lib/src/services/`)**

- **Discovery Services:**
  - `BluePlusDiscoveryService` (Android/iOS/macOS/Linux)
  - `UniversalBleDiscoveryService` (Windows)
  - `SerialService` (desktop platforms) with platform-specific implementations
  - `SimulatedDeviceService` (for development without hardware)

- **Storage Services:**
  - `FileStorageService`: File-based persistence
  - `HiveStoreService`: Key-value store using Hive
  - `KvStoreService`: Abstract KV interface
  - `ProfileStorageService`: Abstract interface for profile storage
  - `HiveProfileStorageService`: Hive-based profile storage implementation

- **Web Server (`webserver_service.dart`):**
  - REST API on port 8080
  - WebSocket endpoints for real-time data
  - API documentation server on port 4001
  - Handler-based routing: `de1handler.dart`, `scale_handler.dart`, `devices_handler.dart`, `shots_handler.dart`, `workflow_handler.dart`, `sensors_handler.dart`, `plugins_handler.dart`, `kv_store_handler.dart`, `settings_handler.dart`, `profile_handler.dart`

**4. Plugin System (`lib/src/plugins/`)**

REA features a JavaScript plugin system with sandboxed execution:
- **`PluginLoaderService`:** Manages plugin lifecycle (install, load, unload)
- **`PluginManager`:** Routes events between Flutter and JS runtime
- **`PluginManifest`:** Defines plugin metadata, permissions, settings, API endpoints
- **`PluginRuntime`:** Executes JavaScript via `flutter_js` bridge

Plugins can:
- React to machine state updates
- Make HTTP requests (via `fetch`)
- Store persistent data
- Emit custom events exposed as WebSocket endpoints

See `Plugins.md` for plugin development guide.

**5. UI Features (`lib/src/`)**

- `home_feature/`: Main UI with machine status tiles and control forms
  - `StatusTile`: Displays DE1 state, temperatures, water levels, scale info with lifecycle-aware streams
  - `SettingsTile`: Power controls, auxiliary functions (clean/descale), and device scanning
  - `ProfileTile`: Profile selection and management
- `history_feature/`: Shot history viewing
- `realtime_shot_feature/`: Live shot visualization
- `settings/`: App configuration, gateway mode settings
- `sample_feature/`: Device discovery and debug view (`SampleItemListView`)

### Data Flow

1. **Device Discovery:** `DeviceController` coordinates multiple `DeviceDiscoveryService` instances → emits unified device stream
2. **Connection:** User/API requests connection → Controller calls `device.onConnect()` → Device sets up transport subscriptions
3. **Machine State:** DE1 sends BLE/Serial messages → `DataTransport` parses → DE1 implementation updates state → `De1Controller` broadcasts changes → WebSocket clients + Plugins receive updates
4. **Shot Control:** `ShotController` subscribes to scale weight + machine state → stops shot when target weight reached
5. **API Requests:** HTTP client → Shelf router → Handler (e.g., `De1Handler`) → Controller → Device
6. **Plugin Events:** Machine state change → `PluginManager` sends `stateUpdate` event → JS runtime → Plugin emits custom event → WebSocket broadcasts to API clients
7. **UI Scan Flow:** User clicks Scan button (when DE1 disconnected) → `SettingsTile._handleScan()` → `DeviceController.scanForDevices()` → If 1 DE1: auto-connect → If multiple: show `_DeviceSelectionDialog` → If none: show error dialog

### Important Conventions

- **RxDart Streams:** Controllers use `BehaviorSubject` for state broadcasting
- **Async Initialization:** Services/controllers have `initialize()` methods called from `main.dart`
- **Foreground Service:** On Android, app can run as foreground service to maintain BLE connection in background (`ForegroundTaskService`)
- **Logging:** Uses `package:logging` with `Logger.root` configured in `main.dart`. Logs written to `~/Download/REA1/log.txt` on Android and app documents directory on other platforms.
- **StreamBuilder Best Practices:** 
  - Always check both `hasData` AND `data != null` for nullable streams (e.g., `De1Interface?`)
  - Use explicit type parameters: `StreamBuilder<De1Interface?>` to avoid type inference issues
  - For lifecycle-aware widgets, implement `WidgetsBindingObserver` and conditionally set stream to `null` when app is backgrounded to prevent unnecessary rebuilds

## Documentation

Comprehensive documentation is located in the `doc/` directory:

- **`doc/Skins.md`** - Complete WebUI skin development guide (API reference, development workflow, deployment)
- **`doc/Plugins.md`** - Plugin development guide (JavaScript API, manifest structure, event system)
- **`doc/Profiles.md`** - Profile API documentation (content-based hashing, version tracking, management)
- **`doc/DeviceManagement.md`** - Device discovery and connection management
- **`doc/RELEASE.md`** - Release process and versioning guidelines

## Plugin Development

Plugins are `.reaplugin` directories containing `manifest.json` and `plugin.js`. Key points:

- Bundled plugins in `assets/plugins/` are auto-copied to app documents directory on startup
- Plugins can be installed by copying directories into the app's plugins folder
- Manifest defines permissions (`log`, `api`, `emit`, `pluginStorage`), settings schema, and API endpoint definitions
- JavaScript runtime provides: `host.log()`, `host.emit()`, `host.storage()`, `fetch()`, `btoa()`
- Events: `stateUpdate` (machine telemetry), `storageRead`, `storageWrite`, `shutdown`
- Plugin-emitted events are routed to WebSocket endpoints: `/ws/v1/plugins/{pluginId}/{eventName}`

See `doc/Plugins.md` for comprehensive plugin development guide.

## Testing

- Unit tests: `test/unit_test.dart`
- Profile tests: `test/profile_test.dart` (21 comprehensive tests including hash mechanics)
- Widget tests: `test/widget_test.dart`
- Simulated devices enable testing without physical hardware:
  - Set `simulate=1` compile-time variable
  - Or toggle in settings UI

## Common Workflows

### Adding a New Device Type

1. Create interface in `lib/src/models/device/` (extend `Device`, `Machine`, or `Scale`)
2. Implement concrete device in `lib/src/models/device/impl/{device_name}/`
3. Add device UUID mapping in `main.dart` discovery service configuration
4. Create controller if device requires specialized logic
5. Add API handler in `lib/src/services/webserver/`

### Adding a New API Endpoint

1. Create or modify handler in `lib/src/services/webserver/`
2. Add route in handler's `addRoutes()` method
3. Register handler in `_init()` in `webserver_service.dart`
4. Document endpoint in `assets/api/rest_v1.yml` or `websocket_v1.yml`

### Working with Profiles

REA includes a complete Profiles API for managing espresso profiles:

**Core Concepts:**
- Profiles are v2 JSON format (same as de1app's `profiles_v2`)
- **Content-based hash IDs**: Profiles use SHA-256 hashes of execution fields as IDs (format: `profile:<20_hex_chars>`)
- **Three-hash system**: Profile hash (ID), metadata hash, compound hash for change detection
- **Automatic deduplication**: Identical profiles share the same ID across all devices
- **Version tracking**: Parent-child relationships via `parentId` for profile evolution

**Key Files:**
- Profile data model: `lib/src/models/data/profile.dart`
- Profile record envelope: `lib/src/models/data/profile_record.dart`
- Hash calculation: `lib/src/models/data/profile_hash.dart`
- Controller: `lib/src/controllers/profile_controller.dart`
- Storage interface: `lib/src/services/storage/profile_storage_service.dart`
- Hive implementation: `lib/src/services/storage/hive_profile_storage.dart`
- REST API handler: `lib/src/services/webserver/profile_handler.dart`
- Machine profile handling: `lib/src/models/device/impl/de1/de1.profile.dart`

**API Endpoints:**
- `GET /api/v1/profiles` - List all profiles (with filtering)
- `POST /api/v1/profiles` - Create new profile
- `GET /api/v1/profiles/{id}` - Get specific profile
- `PUT /api/v1/profiles/{id}` - Update profile
- `DELETE /api/v1/profiles/{id}` - Soft delete profile
- `PUT /api/v1/profiles/{id}/visibility` - Change visibility
- `GET /api/v1/profiles/{id}/lineage` - Get version history
- `DELETE /api/v1/profiles/{id}/purge` - Permanently delete
- `POST /api/v1/profiles/import` - Batch import
- `GET /api/v1/profiles/export` - Export all profiles
- `POST /api/v1/profiles/restore/{filename}` - Restore default profile

**Usage:**
- Upload profile to machine: `POST /api/v1/machine/profile`
- Update via workflow: `PUT /api/v1/workflow` (recommended)
- Default profiles in: `assets/defaultProfiles/` (auto-loaded on startup)

See `doc/Profiles.md` for comprehensive documentation.

### Working with WebUI Skins

REA supports custom web-based user interfaces (skins) that connect to the gateway API:

**Core Concepts:**
- Skins are static web apps (HTML/CSS/JS) served by Streamline-Bridge
- Support for modern frameworks: Next.js, React, Vue, Svelte, etc.
- GitHub Release integration for version management
- REST API for installation without recompiling app

**Key Files:**
- WebUI storage: `lib/src/webui_support/webui_storage.dart`
- WebUI service: `lib/src/webui_support/webui_service.dart`
- REST API handler: `lib/src/services/webserver/webui_handler.dart`

**API Endpoints:**
- `GET /api/v1/webui/skins` - List all installed skins
- `GET /api/v1/webui/skins/{id}` - Get specific skin
- `GET /api/v1/webui/skins/default` - Get default skin (preference-based)
- `PUT /api/v1/webui/skins/default` - Set default skin preference
- `POST /api/v1/webui/skins/install/github-release` - Install from GitHub release
- `POST /api/v1/webui/skins/install/github-branch` - Install from GitHub branch
- `POST /api/v1/webui/skins/install/url` - Install from URL
- `DELETE /api/v1/webui/skins/{id}` - Remove skin

**Default Skin Behavior:**
- User preference stored in `SettingsController.defaultSkinId`
- Defaults to `'streamline-project'` if no preference set
- Automatically saved when user selects skin in Settings view
- Fallback order: preference → streamline-project → first bundled → first available
- Persists across app restarts via SharedPreferences

**Remote Bundled Skins:**
Edit `lib/src/webui_support/webui_storage.dart` to add hardcoded skins that auto-download on startup:
```dart
static const List<Map<String, dynamic>> _remoteWebUISources = [
  {
    'type': 'github_branch',
    'repo': 'allofmeng/streamline_project',
    'branch': 'main',
  },
];
```

See `doc/Skins.md` for complete development guide and `doc/SKIN_DEPLOYMENT_GUIDE.md` for deployment instructions.

## Memory & Performance Considerations

- **Stream subscriptions:** Always cancel subscriptions in `dispose()` methods
- **BLE characteristic reads:** Throttle rapid reads to avoid overwhelming Bluetooth stack
- **Large data:** Shot records with many data points—consider pagination for history endpoints
- **Plugin JS runtime:** Each plugin runs in isolated JS context; limit plugin count on resource-constrained devices

## Code Style from avante.md

- Prioritize readable, maintainable code
- Follow Dart/Flutter best practices
- Pay attention to memory leaks (especially stream subscriptions)
- Use constructor dependency injection
- Single Responsibility Principle for all components
