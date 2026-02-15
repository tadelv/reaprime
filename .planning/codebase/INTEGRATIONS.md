# External Integrations

**Analysis Date:** 2026-02-15

## APIs & External Services

**GitHub API:**
- Service: Issue tracking and Gist uploads for feedback
- SDK/Client: `http` package (manual HTTP calls)
- Auth: `GITHUB_FEEDBACK_TOKEN` environment variable (compile-time)
- Endpoints:
  - `POST https://api.github.com/repos/{owner}/{repo}/issues` - Create feedback issues
  - `POST https://api.github.com/gists` - Upload logs/screenshots as Gists
- Implementation: `lib/src/services/feedback_service.dart`
- Handler: `lib/src/services/webserver/feedback_handler.dart`
- Default repo: `tadelv/reaprime` (configurable)
- API docs: REST endpoint `POST /api/v1/feedback` for submitting feedback

**GitHub Releases API:**
- Service: WebUI skin version management and downloads
- SDK/Client: `http` package
- Auth: None (public repositories)
- Endpoints:
  - `GET https://api.github.com/repos/{owner}/{repo}/releases` - Fetch latest releases
  - `GET https://api.github.com/repos/{owner}/{repo}/branches` - Fetch branch info
  - Binary downloads from release assets
- Implementation: `lib/src/webui_support/webui_storage.dart`
- Used by: `POST /api/v1/webui/skins/install/github-release` and `github-branch` endpoints

## Data Storage

**Databases:**
- Type/Provider: Hive CE (local, embedded key-value database)
  - Connection: File-based (no external connection)
  - Client: `hive_ce` / `hive_ce_flutter` packages
  - Namespaced boxes for different data types:
    - `default` - General settings and cache
    - Named boxes for profiles, shots, workflows, plugins
  - Implementation: `lib/src/services/storage/hive_store_service.dart`
  - Profile storage: `lib/src/services/storage/hive_profile_storage.dart`

**File Storage:**
- Local filesystem only
- Paths:
  - Android: `/storage/emulated/0/Download/REA1/` (logs), app documents directory
  - macOS/Linux/Windows: App documents directory (via `path_provider`)
- Used for: Logs, plugin data, WebUI skins, default profiles
- Implementation: `lib/src/services/storage/file_storage_service.dart`

**Caching:**
- In-memory: RxDart `BehaviorSubject` streams for controllers
- Persistent: Hive CE for long-term storage
- No external caching service (Redis, Memcached)

## Authentication & Identity

**Auth Provider:**
- Custom (no external provider)
- Implementation: None - gateway assumes authenticated local network or embedded use
- Security: Runs on `0.0.0.0:8080` (all interfaces) - assumes trusted network

## Monitoring & Observability

**Error Tracking:**
- Firebase Crashlytics (Android, iOS, macOS, Windows)
  - Project ID: `rea-1-556fd`
  - Configuration: `lib/firebase_options.dart`
  - Implementation: Automatic exception reporting, initialized in `lib/main.dart`
  - Not available on Linux (no Firebase support)

**Performance Monitoring:**
- Firebase Performance (Android, iOS, macOS, Windows)
  - SDK: `firebase_performance` v0.11.1+3

**Analytics:**
- Firebase Analytics (Android, iOS, macOS, Windows)
  - SDK: `firebase_analytics` v12.1.0
  - Events: Custom events can be logged via Firebase SDK
  - Not available on Linux

**Logs:**
- Approach: Rotating file appenders to disk + console output
- Framework: `package:logging` with `logging_appenders`
- Paths: `~/Download/REA1/log.txt` (Android), app documents directory (other platforms)
- Configuration: `Logger.root` configured in `lib/main.dart` with `ColorFormatter` for console, `DefaultLogRecordFormatter` for files

## CI/CD & Deployment

**Hosting:**
- Self-hosted / Gateway deployment
- Embedded in Flutter application (Shelf HTTP server)
- No external hosting platform required

**CI Pipeline:**
- GitHub Actions (`.github/` directory present)
- No external CI service detected beyond GitHub

## Environment Configuration

**Required env vars:**
- `GITHUB_FEEDBACK_TOKEN` - GitHub personal access token for creating feedback issues (optional, feedback disabled if missing)
- `simulate=1` - Dart compile-time variable for device simulation without hardware

**Secrets location:**
- Build-time: Environment variables passed to Flutter build process
- Runtime: `.env.dev` (development only, not version controlled)
- Firebase credentials: Generated via FlutterFire CLI, embedded in app configs:
  - Android: `android/app/google-services.json`
  - iOS: `ios/Runner/GoogleService-Info.plist`
  - macOS: `macos/Runner/GoogleService-Info.plist`
  - Windows: Embedded in `lib/firebase_options.dart`

## Webhooks & Callbacks

**Incoming:**
- None detected - gateway only makes outbound requests

**Outgoing:**
- Plugin event webhooks: Custom WebSocket endpoints for plugin-emitted events (e.g., `/ws/v1/plugins/{pluginId}/{eventName}`)
- No external webhook integrations

## Device Communication Protocols

**Bluetooth Low Energy (BLE):**
- Protocols: Custom binary protocols per device
- Implementations:
  - `lib/src/services/blue_plus_discovery_service.dart` - BluePlus (Android, iOS, macOS)
  - `lib/src/services/universal_ble_discovery_service.dart` - UniversalBLE (Windows)
  - `lib/src/services/ble/linux_ble_discovery_service.dart` - Linux D-Bus Bluetooth
- Supported scales (BLE):
  - Acaia, Acaia Pyxis
  - Atom Heart
  - Black Coffee
  - Bookoo MiniScale
  - Felicita Arc
  - Hiroia
  - Skale 2
  - SmartChef
  - Difluid
  - Eureka
  - Varia Aku

**Serial Communication:**
- Protocol: RS-232/USB serial for DE1 machines and some devices
- Implementation: `lib/src/services/serial/serial_service.dart`
- Library: `flutter_libserialport` (git master)
- Platform-specific:
  - Linux: Direct libserialport FFI binding
  - macOS/Windows: Platform channels + native libraries

**Transport Abstraction:**
- Abstract interfaces: `lib/src/models/device/transport/data_transport.dart`, `ble_transport.dart`, `serial_port.dart`
- All device implementations use injected transport dependencies

## Third-Party Devices Supported

**Espresso Machines:**
- Decent Espresso DE1 (BLE and Serial)
- Implementations: `lib/src/models/device/impl/de1/`, `lib/src/models/device/impl/serial_de1/`, `lib/src/models/device/impl/de1/unified_de1/`

**Scales:**
- Multiple third-party scales via BLE (see Device Communication section)
- Implementations in `lib/src/models/device/impl/{device_name}/`

**Sensors:**
- Sensor basket for water measurement
- Debug port sensor for diagnostics
- Implementations: `lib/src/models/device/impl/sensor/`

---

*Integration audit: 2026-02-15*
