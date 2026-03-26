# Device Management in REA

This document explains how devices (DE1 machines, scales, sensors) are discovered, connected, and managed throughout the REA application lifecycle.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Discovery Services](#discovery-services)
3. [Device Controller](#device-controller)
4. [Connection Manager](#connection-manager)
5. [Device-Specific Controllers](#device-specific-controllers)
6. [Connection Flow](#connection-flow)
7. [State Management](#state-management)
8. [Adding New Devices](#adding-new-devices)

---

## Architecture Overview

REA uses a layered architecture for device management:

```
┌─────────────────────────────────────────────────────────┐
│                    Application Layer                     │
│        (UI, API Handlers, De1StateManager)              │
└─────────────────┬───────────────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────────────┐
│              Connection Manager                          │
│   Orchestrates scan → connect policy (preferred devices)│
└─────────────────┬───────────────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────────────┐
│              Controller Layer                            │
│   De1Controller  │  ScaleController  │  SensorController│
└─────────────────┬───────────────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────────────┐
│              Device Controller                           │
│   Coordinates discovery services and device stream      │
└─────────────────┬───────────────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────────────┐
│           Discovery Services Layer                       │
│  BluePlus  │  UniversalBle  │  Serial  │  Simulated    │
└─────────────────┬───────────────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────────────┐
│              Transport Layer                             │
│        BLE Transport  │  Serial Transport               │
└─────────────────┬───────────────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────────────┐
│               Device Layer                               │
│        De1  │  Scales  │  Sensors  │  Mock Devices     │
└─────────────────────────────────────────────────────────┘
```

**Key Principles:**
- **Transport Abstraction:** Devices depend on injected transport interfaces, not concrete implementations
- **Constructor Dependency Injection:** All dependencies passed through constructors
- **Single Responsibility:** Each layer has a clear, focused purpose
- **Reactive Streams:** RxDart BehaviorSubjects for state broadcasting

---

## Discovery Services

Discovery services are responsible for scanning and creating device instances. Each service handles a specific transport type.

### Available Services

#### 1. BluePlusDiscoveryService
- **Platform:** Android, iOS, macOS, Linux
- **Package:** `flutter_blue_plus`
- **File:** `lib/src/services/blue_plus_discovery_service.dart`
- **Discovery:** Scans for BLE advertisements, matches service UUIDs to device factories

#### 2. UniversalBleDiscoveryService
- **Platform:** Windows
- **Package:** `universal_ble`
- **File:** `lib/src/services/universal_ble_discovery_service.dart`
- **Discovery:** Windows-compatible BLE scanning

#### 3. SerialService
- **Platform:** Desktop (macOS, Linux, Windows), Android (USB OTG)
- **Files:**
  - `lib/src/services/serial/serial_service_desktop.dart` (desktop)
  - `lib/src/services/serial/serial_service_android.dart` (Android)
  - `lib/src/services/serial/serial_service.dart` (factory)
- **Discovery:** Enumerates serial ports, probes for device identification

#### 4. SimulatedDeviceService
- **Platform:** All
- **File:** `lib/src/services/simulated_device_service.dart`
- **Purpose:** Testing without physical hardware
- **Activation:** Set `simulate=1` compile-time variable or enable in settings

### Device Matching

Discovery services use name-based matching via `DeviceMatcher` to create appropriate device instances from BLE advertisement names:

**File:** `lib/src/services/device_matcher.dart`

**Key Points:**
- Unfiltered BLE scans — no service UUID filtering
- `DeviceMatcher.match()` takes a transport and advertised name, returns a `Device?`
- Name rules map advertisement names to device factories
- Service verification happens during `onConnect()` using `BleServiceIdentifier`

### Service Lifecycle

1. **Initialization:** `service.initialize()`
   - Set up platform-specific scanning
   - Initialize internal state
   - Start listening to platform events

2. **Scanning:** `service.scanForDevices()`
   - Start platform-specific scan
   - Match discovered devices to mappings
   - Create device instances via factories
   - Emit devices via stream

3. **Device Stream:** `service.devices`
   - Broadcast stream of discovered devices
   - Updates when new devices found or existing devices disconnect

---

## Device Controller

**File:** `lib/src/controllers/device_controller.dart`

The DeviceController is the central coordinator for all device discovery services.

### Responsibilities

1. **Service Coordination:**
   - Manages multiple discovery services
   - Subscribes to each service's device stream
   - Merges devices from all services into unified stream

2. **Device Lifecycle:**
   - Tracks discovered devices
   - Removes disconnected devices on scan (allows re-discovery with fresh transport)
   - Prevents duplicate device entries

3. **Scan Management:**
   - Exposes `scanningStream` for scan lifecycle tracking
   - Coordinates parallel scans across all discovery services
   - Suppresses disconnect/reconnect detection during active scans — intermediate device list changes are transient noise. Genuine disconnects outside of scans are still detected.

**Note:** DeviceController does **not** handle connection policy. All connection decisions (which device to connect, when to connect) are handled by `ConnectionManager`.

### Key Methods

```dart
// Initialize all services
Future<void> initialize() async {
  for (var service in _services) {
    await service.initialize();
    _serviceSubscriptions.add(
      service.devices.listen((devices) => _serviceUpdate(service, devices))
    );
  }
}

// Trigger scan across all services
Future<void> scanForDevices() async {
  _scanningStream.add(true);
  // Scan all services in parallel
  await Future.wait(_services.map((s) => s.scanForDevices()));
  _scanningStream.add(false);
}
```

### Device Stream

The unified device stream combines all devices from all services:

```dart
Stream<List<Device>> get deviceStream => _deviceStream.asBroadcastStream();

List<Device> get devices => 
  _devices.values.fold(List<Device>.empty(growable: true), (res, el) {
    res.addAll(el);
    return res;
  }).toList();
```

---

## Connection Manager

**File:** `lib/src/controllers/connection_manager.dart`

The ConnectionManager is the centralized orchestrator for all device connection decisions. It replaces the previously scattered auto-connect logic that was spread across DeviceController, ScaleController, and De1StateManager.

### Connection Status

ConnectionManager exposes a `ConnectionStatus` stream with the following phases:

```
idle → scanning → connectingMachine → connectingScale → ready
```

- **`idle`:** No connection activity
- **`scanning`:** BLE/USB scan in progress
- **`connectingMachine`:** Connecting to a DE1 machine
- **`connectingScale`:** Connecting to a scale
- **`ready`:** All requested devices connected

The status also tracks:
- `foundMachines` / `foundScales` — devices discovered during the last scan
- `pendingAmbiguity` — `machinePicker` or `scalePicker` when the UI needs to show a device selection dialog
- `error` — error message from the last connection attempt

### Connection Policy

When `connect()` is called:

1. **Scan** for all devices via `DeviceController.scanForDevices()`
2. **Early connect** — if preferred device IDs are set in settings, connect as soon as they appear during scan (don't wait for scan to finish)
3. **Machine phase** — apply preferred machine policy:
   - Preferred set + found → auto-connect
   - Preferred set + not found, but others available → show picker (`machinePicker`)
   - No preferred, 1 machine → auto-connect
   - No preferred, multiple → show picker (`machinePicker`)
4. **Scale phase** — apply preferred scale policy (same logic as machine)

### Key Methods

- `connect()` — Full scan + connect flow (machine + scale)
- `scanAndConnectScale()` — Scale-only reconnect (skips machine phase)
- `connectMachine(De1Interface)` — Connect to a specific machine
- `connectScale(Scale)` — Connect to a specific scale
- `disconnectMachine()` / `disconnectScale()` — Explicit disconnects

### Disconnect Handling

ConnectionManager listens for disconnects automatically:
- Watches `de1Controller.de1` stream — `null` means machine disconnected
- Watches `scaleController.connectionState` — resets `_scaleConnected` flag on disconnect
- Resets phase to `idle` when machine disconnects

### Preferred Device Settings

Device preferences are stored via `SettingsController`:
- `preferredMachineId` — auto-set on successful machine connection
- `preferredScaleId` — auto-set on successful scale connection
- Configurable in Settings → Device Management

---

## Device-Specific Controllers

Device-specific controllers manage the lifecycle and state of individual device types. They handle the low-level connection mechanics; the ConnectionManager handles the policy of *when* and *which* device to connect.

### De1Controller

**File:** `lib/src/controllers/de1_controller.dart`

**Responsibilities:**
- Manages DE1 connection (manual, user-selected)
- Exposes machine state streams
- Handles steam/hot water/flush settings
- Manages shot settings and profile uploads

**Connection Flow:**
```dart
Future<void> connectToDe1(De1Interface de1Interface) async {
  _onDisconnect(); // Clean up any existing connection
  _de1 = de1Interface;
  await de1Interface.onConnect();
  _de1Controller.add(_de1);
  
  // Subscribe to machine streams
  _subscriptions.add(_de1.ready.listen(_initializeData));
  _subscriptions.add(_de1.connectionState.listen(_processConnection));
}
```

**Key Streams:**
- `de1`: Current connected DE1 (or null)
- `steamData`: Steam settings
- `hotWaterData`: Hot water settings
- `rinseData`: Flush/rinse settings

### ScaleController

**File:** `lib/src/controllers/scale_controller.dart`

**Responsibilities:**
- Manages scale connection lifecycle (called by ConnectionManager)
- Processes weight and flow data
- Calculates smoothed weight flow
- Exposes weight snapshots and connection state

**Note:** ScaleController does **not** auto-connect. Connection decisions are made by `ConnectionManager`. ScaleController only handles the mechanics of connecting to a specific scale.

**Connection Flow:**
```dart
Future<void> connectToScale(Scale scale) async {
  _onDisconnect();
  _scaleConnection = scale.connectionState.listen(_processConnection);
  _scaleSnapshot = scale.currentSnapshot.listen(_processSnapshot);
  await scale.onConnect();
  _scale = scale;
}
```

**Key Streams:**
- `connectionState`: Scale connection status (`BehaviorSubject<ConnectionState>`)
- `weightSnapshot`: Processed weight data with flow calculation
- `currentConnectionState`: Synchronous getter for current state

### SensorController

**File:** `lib/src/controllers/sensor_controller.dart`

**Responsibilities:**
- Manages sensor connections (basket sensors, debug port)
- Auto-connects to first found sensor
- Exposes sensor data streams

**Pattern:** Mirrors ScaleController auto-connect logic

---

## Connection Flow

### Initial App Startup

```
1. main.dart
   ↓
2. Create discovery services with device mappings
   ↓
3. Create DeviceController(services), De1Controller, ScaleController
   ↓
4. Create ConnectionManager(deviceController, de1Controller, scaleController, settingsController)
   ↓
5. runApp(MyApp(...))
   ↓
6. PermissionsView → DeviceDiscoveryView displayed
   ↓
7. User grants permissions → deviceController.initialize()
   ↓
8. DeviceDiscoveryView calls connectionManager.connect()
   ↓
9. ConnectionManager: scan → early-connect preferred devices → apply policy
   ↓
10. Status stream: idle → scanning → connectingMachine → connectingScale → ready
    ↓
11. DeviceDiscoveryView navigates to HomeScreen on `ready`
```

If multiple machines or scales are found without a preferred device set, ConnectionManager emits `pendingAmbiguity: machinePicker` or `scalePicker`, and the UI shows a picker dialog.

### Scale Reconnect from HomeScreen

```
1. User taps "Scale" text in StatusTile (when no scale connected)
   ↓
2. connectionManager.scanAndConnectScale()
   ↓
3. BLE scan runs, preferred scale policy applied
   ↓
4. If multiple scales found → scalePicker dialog shown
```

### Machine Wake → Scale Reconnect Flow

```
1. Machine state: sleeping → idle
   ↓
2. De1StateManager._handleScalePowerManagement() detects transition
   ↓
3. Check if scale connected → NO, scalePowerMode == disconnect → YES
   ↓
4. Call connectionManager.scanAndConnectScale()
   ↓
5. Scan runs, preferred scale connected automatically
```

---

## State Management

### Device Connection States

**Enum:** `ConnectionState` (defined in `lib/src/models/device/device.dart`)

```dart
enum ConnectionState {
  discovered,
  connecting,
  connected,
  disconnecting,
  disconnected,
}
```

**Lifecycle:** `discovered → connecting → connected → disconnecting → disconnected`

- `discovered` — device created by discovery service, never connected
- `connecting` — connection in progress
- `connected` — connection established
- `disconnecting` — disconnection in progress
- `disconnected` — was connected, connection lost or explicitly closed

### State Transitions

**Devices:**
```
discovered → connecting → connected → disconnecting → disconnected
```

**Controllers:**
- Subscribe to device `connectionState` stream
- Update internal state on transitions
- Clean up resources on disconnect

### De1StateManager Integration

**File:** `lib/src/controllers/de1_state_manager.dart`

The De1StateManager is the central orchestrator for machine state changes and related behaviors:

**Responsibilities:**
1. Listen to machine state transitions
2. Manage scale power based on state transitions
3. Handle gateway mode logic (full/tracking/disabled)
4. Trigger device scans when needed
5. Manage shot tracking in tracking mode
6. Navigate to realtime features in disabled mode

**Dependencies:**
```dart
De1StateManager({
  required De1Controller de1Controller,
  required DeviceController deviceController,
  required ScaleController scaleController,
  required WorkflowController workflowController,
  required PersistenceController persistenceController,
  required SettingsController settingsController,
  required GlobalKey<NavigatorState> navigatorKey,
})
```

**Key Methods:**
- `_handleSnapshot(MachineSnapshot)`: Processes all machine state updates
- `_handleScalePowerManagement(MachineState)`: Manages scale sleep/wake/scan
- `_triggerScaleScan()`: Initiates device scan with 30s timeout

---

## Connection Policy

All connection decisions are centralized in `ConnectionManager`. Individual controllers (De1Controller, ScaleController) only handle the mechanics of connecting/disconnecting.

### Preferred Device Policy

ConnectionManager uses `SettingsController` to read preferred device IDs:

1. **Preferred device set + found during scan** → auto-connect immediately (early connect during scan)
2. **Preferred device set + not found, but others available** → show picker dialog
3. **No preferred device, 1 found** → auto-connect silently
4. **No preferred device, multiple found** → show picker dialog
5. **No devices found** → stay idle

Preferred device IDs are auto-saved on successful connection and can be managed in Settings → Device Management.

### Machine vs Scale Connection

- **Machine** connects first, then scale phase runs
- **Scale failures are non-blocking** — if scale connection fails, machine stays connected and phase stays `ready`
- **Scale-only reconnect** — `scanAndConnectScale()` skips the machine phase entirely (used by De1StateManager for wake-from-sleep and by StatusTile for manual reconnect)

---

## Adding New Devices

### Step-by-Step Guide

#### 1. Define Device Interface

Create an interface in `lib/src/models/device/`:

```dart
// Example: New temperature sensor
abstract class TemperatureSensor implements Device {
  Stream<double> get temperature;
  Future<void> setTargetTemperature(double temp);
}
```

#### 2. Implement Concrete Device

Create implementation in `lib/src/models/device/impl/`:

```dart
class AcaiaTemperatureSensor implements TemperatureSensor {
  final BLETransport _transport;
  
  static const String serviceUUID = "ACAIA-TEMP-SERVICE-UUID";
  
  AcaiaTemperatureSensor({required BLETransport transport})
    : _transport = transport;
  
  @override
  Future<void> onConnect() async {
    // Subscribe to BLE characteristics
  }
  
  @override
  Future<void> disconnect() async {
    // Clean up subscriptions
  }
  
  // ... implement temperature methods
}
```

#### 3. Add Device Mapping

Update `main.dart`:

```dart
services.add(
  BluePlusDiscoveryService(
    mappings: {
      // ... existing mappings
      AcaiaTemperatureSensor.serviceUUID.toUpperCase(): (t) async {
        return AcaiaTemperatureSensor(transport: t);
      },
    },
  ),
);
```

#### 4. Create Controller (Optional)

If device requires specialized logic, create controller:

```dart
class TemperatureController {
  TemperatureSensor? _sensor;

  /// Called by ConnectionManager when a sensor should be connected.
  Future<void> connectToSensor(TemperatureSensor sensor) async {
    _sensor = sensor;
    await sensor.onConnect();
    // ... subscribe to streams
  }

  void dispose() {
    // ... cancel subscriptions
  }
}
```

**Note:** Connection decisions (when to connect, which device) should be handled by `ConnectionManager`, not by the device-specific controller.

#### 5. Add API Handler (Optional)

Create handler in `lib/src/services/webserver/`:

```dart
class TemperatureHandler {
  final TemperatureController _controller;
  
  void addRoutes(ShelfPlus app) {
    app.get('/api/v1/temperature', () async {
      final temp = await _controller.getCurrentTemperature();
      return {'temperature': temp};
    });
  }
}
```

#### 6. Update OpenAPI Documentation

Add endpoints to `assets/api/rest_v1.yml` and `websocket_v1.yml`.

---

## Best Practices

### Transport Abstraction

Always depend on interfaces, not concrete implementations:

```dart
// ✅ Good
class MyDevice implements Device {
  final BLETransport _transport;
  
  MyDevice({required BLETransport transport}) : _transport = transport;
}

// ❌ Bad
class MyDevice implements Device {
  final BluePlusTransport _transport; // Coupled to specific implementation
  
  MyDevice({required BluePlusTransport transport}) : _transport = transport;
}
```

### Stream Cleanup

Always cancel subscriptions in `dispose()` methods:

```dart
class MyController {
  StreamSubscription<Device>? _deviceSubscription;
  
  MyController() {
    _deviceSubscription = deviceStream.listen(...);
  }
  
  void dispose() {
    _deviceSubscription?.cancel();
    _deviceSubscription = null;
  }
}
```

### Error Handling

Use `catchError` for non-critical operations:

```dart
// Scale power management - don't crash if scale disconnected
scale.sleepDisplay().catchError((e) {
  _logger.warning('Failed to sleep scale display: $e');
});
```

Use `try-catch` for critical operations:

```dart
// Device connection - need to handle error gracefully
try {
  await device.onConnect();
} catch (e) {
  _logger.severe('Failed to connect to device', e);
  // Show user error message
}
```

### State Broadcasting

Use `BehaviorSubject` for stateful streams:

```dart
final BehaviorSubject<ConnectionState> _connectionController =
  BehaviorSubject.seeded(ConnectionState.discovered);

Stream<ConnectionState> get connectionState => _connectionController.stream;
```

### Initialization Order

Controllers must be created before state managers:

```dart
// main.dart
final deviceController = DeviceController(services);
final de1Controller = De1Controller(controller: deviceController);
final scaleController = ScaleController(controller: deviceController);

// app.dart
final stateManager = De1StateManager(
  deviceController: deviceController,
  de1Controller: de1Controller,
  scaleController: scaleController,
  // ...
);
```

---

## Debugging Tips

### Enable Detailed Logging

Set log level in settings UI or SharedPreferences:

```dart
// Settings → Log Level → FINEST
Logger.root.level = Level.FINEST;
```

Logs are written to:
- **All platforms:** `<app_documents>/log.txt`

### Inspect Device Stream

Add temporary logging in DeviceController:

```dart
_deviceStream.listen((devices) {
  _log.info('Current devices: ${devices.map((d) => d.name).join(", ")}');
});
```

### Check ConnectionManager Status

Monitor connection phases via WebSocket or logs:

```dart
// Subscribe to ConnectionManager status
connectionManager.status.listen((status) {
  _log.info('Phase: ${status.phase}, ambiguity: ${status.pendingAmbiguity}');
});
```

Or via the `/ws/v1/devices` WebSocket — the `connectionStatus` field shows the current phase, found devices, and any pending ambiguity.

### Monitor State Transitions

Add logging in De1StateManager:

```dart
void _handleSnapshot(MachineSnapshot snapshot) {
  _logger.info('State transition: $_previousMachineState → ${snapshot.state.state}');
  // ... state handling
}
```

### Simulated Devices

Use simulated devices for testing without hardware:

```bash
flutter run --dart-define=simulate=1              # Simulate all devices
flutter run --dart-define=simulate=machine         # Simulate machine only
flutter run --dart-define=simulate=machine,scale   # Simulate machine and scale
```

Supported types: `machine`, `scale`, `sensor` (comma-separated).

Or toggle in Settings UI → Simulated Devices

---

## Common Issues

### Scale Doesn't Connect

**Symptoms:** Scale found during scan but doesn't connect

**Possible Causes:**
1. Preferred scale ID is set but doesn't match any found scale
2. Another scale already connected (`_scaleConnected` flag)
3. Scale UUID not matched by `DeviceMatcher`
4. BLE permissions not granted
5. Stale device objects in `BluePlusDiscoveryService._devices` list (should be purged on each scan)

**Debug Steps:**
- Check ConnectionManager logs: `ConnectionManager` logger at `fine` level
- Check `preferredScaleId` in settings: GET `/api/v1/settings`
- Check WebSocket `/ws/v1/devices` for `connectionStatus.pendingAmbiguity`

### Multiple Scans Interfere

**Symptoms:** Devices disappear/reappear during scan

**Cause:** Multiple overlapping scans (BLE stack limitation)

**Solution:** Use `_isScanning` flag pattern:

```dart
bool _isScanning = false;

Future<void> scan() async {
  if (_isScanning) {
    _log.info('Scan already in progress');
    return;
  }
  _isScanning = true;
  try {
    await actualScan();
  } finally {
    _isScanning = false;
  }
}
```

### DE1 Auto-Connects (Unexpected)

**Symptoms:** DE1 connects without user selection

**Cause:** ConnectionManager auto-connects when only 1 machine is found, or when a preferred machine ID is set in settings

**Fix:** Clear the preferred machine ID in Settings → Device Management, or check `ConnectionManager` logs for the connection policy decision

### Serial Devices Not Found

**Symptoms:** Serial scales/machines not discovered

**Platform-Specific Issues:**
- **Desktop:** Check `libserialport` package is included
- **Android:** Enable USB debugging, check USB permissions
- **macOS:** Grant serial port access in System Preferences

**Debug:**
```dart
// In SerialService.scanForDevices()
final ports = SerialPort.availablePorts;
_log.info('Found serial ports: $ports');
```

---

## Future Roadmap

### Planned Enhancements

1. **Smart Reconnection:**
   - Exponential backoff for failed reconnections
   - Connection quality monitoring

2. **Multi-Device Support:**
   - Connect to multiple scales simultaneously
   - Aggregate sensor data from multiple sources
   - Switch between devices without disconnection

3. **Connection Indicators:**
   - Signal strength monitoring
   - Connection quality metrics

4. **Device Fingerprinting:**
   - Unique device identification beyond UUID
   - Detect duplicate devices (same scale via BLE + Serial)
   - Prevent double-connection issues

---

## Related Files

### Core Device Management
- `lib/src/controllers/connection_manager.dart` - Centralized connection orchestration
- `lib/src/controllers/device_controller.dart` - Discovery coordination
- `lib/src/controllers/de1_controller.dart` - DE1 machine management
- `lib/src/controllers/scale_controller.dart` - Scale management
- `lib/src/controllers/sensor_controller.dart` - Sensor management
- `lib/src/controllers/de1_state_manager.dart` - State orchestration

### Discovery Services
- `lib/src/services/blue_plus_discovery_service.dart` - BLE (Android/iOS/macOS/Linux)
- `lib/src/services/universal_ble_discovery_service.dart` - BLE (Windows)
- `lib/src/services/serial/serial_service.dart` - Serial device factory
- `lib/src/services/serial/serial_service_desktop.dart` - Desktop serial
- `lib/src/services/serial/serial_service_android.dart` - Android USB OTG
- `lib/src/services/simulated_device_service.dart` - Testing mocks

### Device Implementations
- `lib/src/models/device/impl/de1/` - DE1 machines (BLE + Serial, unified interface in `unified_de1/`)
- `lib/src/models/device/impl/decent_scale/` - Decent Scale (BLE + Serial)
- `lib/src/models/device/impl/acaia/` - Acaia scales (unified: IPS protocol for older ACAIA/PROCH, Pyxis protocol for Lunar/Pearl/Pyxis, auto-detected at connect time)
- `lib/src/models/device/impl/felicita/` - Felicita Arc scale
- `lib/src/models/device/impl/bookoo/` - Bookoo Miniscale
- `lib/src/models/device/impl/mock_de1/` - Mock DE1 for testing
- `lib/src/models/device/impl/mock_scale/` - Mock scale for testing

### UI Components
- `lib/src/permissions_feature/permissions_view.dart` - Initial scan and DE1 selection
- `lib/src/home_feature/tiles/status_tile.dart` - Connection status display
- `lib/src/sample_feature/sample_item_list_view.dart` - Device list debugging

---

## Glossary

- **BLE:** Bluetooth Low Energy, wireless protocol for IoT devices
- **Transport:** Abstraction layer for device communication (BLE, Serial, etc.)
- **Discovery Service:** Component that scans for and creates device instances
- **Device Controller:** Central coordinator for all discovery services
- **Device-Specific Controller:** Manages lifecycle of a specific device type (DE1, Scale, Sensor)
- **ConnectionManager:** Centralized orchestrator for device connection policy
- **ConnectionStatus:** State object with phase, found devices, and ambiguity info
- **Device Stream:** RxDart BehaviorSubject broadcasting list of discovered devices
- **State Manager:** Orchestrator for machine state changes and related behaviors
- **UUID:** Universally Unique Identifier, used to identify BLE services/devices
- **Service Mapping:** Dictionary mapping UUIDs to device factory functions

