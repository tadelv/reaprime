# Architecture

**Analysis Date:** 2026-02-15

## Pattern Overview

**Overall:** Multi-layered transport-abstracted architecture with dependency injection

**Key Characteristics:**
- Transport abstraction enables multiple device connection types (BLE, Serial, USB) without coupling device logic to specific protocols
- Controller-based orchestration between device layer and services
- RxDart streams for reactive state management and broadcasting
- REST/WebSocket API layer via Shelf with handler-based routing
- Plugin system with sandboxed JavaScript execution for extensibility

## Layers

**Transport Layer:**
- Purpose: Abstract communication protocols (BLE, Serial, USB) behind common interfaces
- Location: `lib/src/models/device/transport/`
- Contains: `DataTransport` (base interface), `BLETransport`, `SerialTransport` implementations
- Depends on: Platform-specific BLE/Serial libraries (flutter_blue_plus, flutter_libserialport)
- Used by: Device implementations to send/receive bytes without protocol coupling

**Device Layer:**
- Purpose: Represent physical machines, scales, and sensors with protocol-agnostic abstractions
- Location: `lib/src/models/device/`
- Contains: Abstract classes (`Device`, `Machine`, `Scale`, `Sensor`) and concrete implementations in `impl/` subdirectories
- Depends on: Transport layer (injected via constructors)
- Used by: Controllers for device operations; DeviceDiscoveryService for device enumeration
- Pattern: Constructor dependency injection - devices receive transport instances, not BLE-specific dependencies

**Discovery Layer:**
- Purpose: Enumerate available devices across multiple connection types
- Location: Service implementations in `lib/src/services/`
- Contains: `BluePlusDiscoveryService` (Android/iOS/macOS/Linux), `UniversalBleDiscoveryService` (Windows), `SerialService`, `SimulatedDeviceService`
- Depends on: Device implementations, transport layer
- Used by: `DeviceController` to maintain unified device list
- Pattern: Multiple discovery services registered in `main.dart` with device UUID-to-constructor mappings for auto-instantiation

**Controller Layer:**
- Purpose: Orchestrate device operations and manage application state
- Location: `lib/src/controllers/`
- Contains: `DeviceController`, `De1Controller`, `ScaleController`, `ShotController`, `WorkflowController`, `ProfileController`, `PersistenceController`, `SensorController`
- Depends on: Device layer, discovery services, storage services
- Used by: UI layer, WebSocket handlers, plugin system
- Pattern: Controllers use `BehaviorSubject` for state broadcasting; subscribe to device streams and aggregate/transform data

**Storage Layer:**
- Purpose: Persist application data (shots, profiles, settings, plugin state)
- Location: `lib/src/services/storage/`
- Contains: `FileStorageService`, `HiveStoreService`, `HiveProfileStorageService`, `KvStoreService`
- Depends on: Hive (key-value store), Flutter path_provider
- Used by: Controllers (ProfileController, PersistenceController) for CRUD operations

**Plugin Layer:**
- Purpose: Extend functionality via sandboxed JavaScript execution
- Location: `lib/src/plugins/`
- Contains: `PluginLoaderService`, `PluginManager`, `PluginRuntime`, `PluginManifest`
- Depends on: flutter_js (JavaScript runtime), storage services
- Used by: Main app initialization, WebSocket handlers for plugin event routing
- Pattern: Plugins receive `host` object with limited APIs (log, emit, storage); events from machine state trigger plugin updates

**Web Server Layer:**
- Purpose: Expose REST/WebSocket APIs for client applications
- Location: `lib/src/services/webserver_service.dart`, handlers in `lib/src/services/webserver/`
- Contains: Shelf-based server with handlers for machines, scales, profiles, workflows, plugins, settings
- Depends on: Controllers (for state access), WebSocket channels, Shelf routing
- Used by: External clients, WebUI skins
- Pattern: Handler-based routing - each handler (`De1Handler`, `ScaleHandler`, etc.) manages its own routes via `addRoutes()`

**UI Layer:**
- Purpose: Display machine status, accept user input, visualize shot data
- Location: `lib/src/` features (home_feature, history_feature, realtime_shot_feature, settings)
- Contains: StatefulWidgets using `StreamBuilder` to subscribe to controller state
- Depends on: Controllers, models
- Used by: Flutter Material app
- Pattern: Features organized by domain; lifecycle-aware streams to prevent rebuilds when app backgrounded

## Data Flow

**Device Discovery Flow:**
1. `main.dart` initializes discovery services (BluePlus, Serial, Simulated)
2. Services registered with `DeviceController` with UUID-to-constructor mappings
3. User initiates scan → `DeviceController.scanForDevices()` → all services scan in parallel
4. Devices found → service calls constructor with transport instance → concrete Device created
5. Service emits `List<Device>` → `DeviceController` aggregates across all services → `deviceStream` broadcasts unified list
6. UI listens to `deviceStream` and displays available devices or auto-connects if single match

**Machine State Update Flow:**
1. DE1 sends BLE/Serial message → `DataTransport` receives bytes
2. Transport parses bytes into protocol messages (e.g., `StateInfo` frame)
3. `De1Interface` concrete implementation processes message → updates internal state
4. `currentSnapshot` stream emits `MachineSnapshot` with latest telemetry
5. `De1Controller` observes via `de1.currentSnapshot` → broadcasts to `_de1Controller` BehaviorSubject
6. `WebSocket` clients subscribed to `/ws/v1/machine/frame` receive real-time updates
7. `PluginManager` routes `stateUpdate` event to loaded plugins
8. Plugins may emit custom events → routed to WebSocket `/ws/v1/plugins/{pluginId}/{eventName}`

**Shot Control Flow:**
1. User selects profile and starts shot
2. `ShotController` created with profile, DE1, scale references
3. Subscribes to combined stream: DE1 state + scale weight
4. Monitors weight vs. target and DE1 state
5. Calls `de1.requestState(MachineState.espresso)` to begin
6. On target weight + state conditions met → calls `de1.requestState()` to stop
7. Persists shot record via `PersistenceController`
8. `ShotController` broadcasts snapshots for real-time visualization

**Profile Management Flow:**
1. Profiles stored with content-based hash IDs (SHA-256 of execution fields)
2. `ProfileController` manages upload, storage, versioning via `ProfileStorageService`
3. `De1` exposes profile upload logic in device-specific `de1.profile.dart` implementations
4. REST handler `ProfileHandler` routes `/api/v1/profiles/*` endpoints to controller
5. Profiles auto-deduplicate via identical hash IDs across devices

**State Management:**

Controllers use **RxDart BehaviorSubject** pattern:
- `BehaviorSubject.seeded(initialValue)` stores current state
- `.stream` provides reactive stream for UI/handlers to subscribe
- `.add(newValue)` updates and broadcasts to all listeners
- Pattern prevents memory leaks via explicit subscription cancellation in `dispose()`

Example:
```dart
// In De1Controller
final BehaviorSubject<De1Interface?> _de1Controller = BehaviorSubject.seeded(null);
Stream<De1Interface?> get de1 => _de1Controller.stream;

// UI subscribes
StreamBuilder<De1Interface?>(
  stream: de1Controller.de1,
  builder: (context, snapshot) => /* display current de1 or loading */
)
```

## Key Abstractions

**Device:**
- Purpose: Unified interface for any connectable hardware (machines, scales, sensors)
- Examples: `De1Interface`, `Scale`, `Sensor`
- Pattern: Abstract base with `onConnect()`, `disconnect()`, `connectionState` stream; concrete implementations in `impl/` subdirectories

**Machine:**
- Purpose: Specialization of Device for espresso machines
- Examples: `UnifiedDe1` (BLE-based), machines via `MachineParser` (auto-instantiation)
- Pattern: Extends Device; provides `currentSnapshot` stream and `requestState()` for shot control

**DataTransport:**
- Purpose: Abstract protocol from device logic
- Examples: BLE transport with service/characteristic read/write/subscribe, Serial transport with command streams
- Pattern: Devices depend on transport interface injected in constructor; enables unit testing with mock transports

**DeviceDiscoveryService:**
- Purpose: Enumerate available devices of any type from one source (BLE, Serial, Simulated)
- Examples: `BluePlusDiscoveryService` scans for all DE1s and scales via UUIDs; `SimulatedDeviceService` creates mock devices for development
- Pattern: Stream-based; services register device constructors in `main.dart` UUID mappings

**Handler (Web API):**
- Purpose: Route HTTP/WebSocket requests to controller operations
- Examples: `De1Handler`, `ScaleHandler`, `ProfileHandler`
- Pattern: Each handler manages its own routes via `addRoutes()` method; handler receives controller reference for state access

## Entry Points

**Application Entry:**
- Location: `lib/main.dart`
- Triggers: App startup (Flutter entry point)
- Responsibilities:
  - Initialize logging to file and console
  - Set up Firebase crash reporting
  - Create discovery services with UUID mappings
  - Initialize Hive database
  - Create all controllers with dependencies
  - Initialize plugin system
  - Start web server (REST/WebSocket on port 8080, API docs on 4001)
  - Launch Flutter app with controllers injected

**Web Server Entry:**
- Location: `lib/src/services/webserver_service.dart` `startWebServer()` function
- Triggers: Called from `main.dart` initialization
- Responsibilities:
  - Create handler instances with controller references
  - Set up Shelf routing with CORS headers
  - Register routes from all handlers
  - Serve static files (API docs, WebUI skins)
  - Accept WebSocket connections for real-time updates

**Device Connection Entry:**
- Location: `lib/src/controllers/device_controller.dart` `scanForDevices()`
- Triggers: User manual scan or auto-connect on startup
- Responsibilities:
  - Call `scanForDevices()` on all discovery services in parallel
  - Aggregate discovered devices into unified list
  - Trigger auto-connect if single DE1 found and auto-connect enabled
  - Broadcast device list to listeners

**Shot Execution Entry:**
- Location: `lib/src/controllers/shot_controller.dart` constructor and `executeShotSequence()`
- Triggers: User starts shot from UI or workflow
- Responsibilities:
  - Subscribe to combined DE1 + scale stream
  - Monitor state/weight transitions
  - Call machine control methods at appropriate times
  - Persist shot record on completion

## Error Handling

**Strategy:** Layered try-catch with logging and graceful degradation

**Patterns:**

1. **Device Connection Failures:**
   - Device implementation catches transport errors
   - Updates `connectionState` stream to `disconnected`
   - Controller listens to state changes and cleans up subscriptions
   - UI displays "Device disconnected" state

2. **API Request Errors:**
   - Handler catches controller exceptions
   - Returns appropriate HTTP status code (400/404/500) with JSON error body
   - WebServer logs error with context

3. **Plugin Execution Errors:**
   - `PluginManager` wraps plugin calls in try-catch
   - Logs error; continues app execution
   - Plugin-specific errors don't crash main app

4. **Storage Failures:**
   - `FileStorageService`, `HiveStoreService` catch I/O errors
   - Log and throw; let caller decide retry strategy
   - Controllers may retry or fallback to in-memory state

## Cross-Cutting Concerns

**Logging:**
- Framework: `package:logging` with `Logger.root`
- Configuration: `Level.FINE` in development; file appenders to `~/Download/REA1/log.txt` (Android) and app documents (other platforms)
- Usage: Every major operation logged with context (device name, state transition, API endpoint)

**Validation:**
- Controllers validate input before device operations (e.g., ShotController checks scale connection)
- Handlers validate HTTP request payloads before passing to controllers
- Device implementations validate transport messages before state updates

**Authentication:**
- Gateway mode (settings) determines API capabilities: full mode allows shot control, restricted mode limits to monitoring
- No per-request authentication; all authenticated via single gateway instance assumption
- Future: HTTP Bearer token support in WebSocket upgrade (designed in API structure)

**Lifecycle Management:**
- Controllers and services have `initialize()` and `dispose()` methods
- `initialize()` called from `main.dart` in dependency order
- `dispose()` called on widget teardown for UI-bound controllers
- Stream subscriptions explicitly cancelled in `dispose()` to prevent memory leaks

---

*Architecture analysis: 2026-02-15*
