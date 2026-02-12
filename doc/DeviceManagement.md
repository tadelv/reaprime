# Device Management in REA

This document explains how devices (DE1 machines, scales, sensors) are discovered, connected, and managed throughout the REA application lifecycle.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Discovery Services](#discovery-services)
3. [Device Controller](#device-controller)
4. [Device-Specific Controllers](#device-specific-controllers)
5. [Connection Flow](#connection-flow)
6. [State Management](#state-management)
7. [Auto-Connection Logic](#auto-connection-logic)
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

### Device Mapping Configuration

Discovery services use UUID-to-factory mappings to create appropriate device instances:

```dart
// In main.dart
BluePlusDiscoveryService(
  mappings: {
    De1.advertisingUUID.toUpperCase(): (t) => MachineParser.machineFrom(transport: t),
    FelicitaArc.serviceUUID.toUpperCase(): (t) async => FelicitaArc(transport: t),
    DecentScale.serviceUUID.toUpperCase(): (t) async => DecentScale(transport: t),
    BookooScale.serviceUUID.toUpperCase(): (t) async => BookooScale(transport: t),
  },
)
```

**Key Points:**
- UUIDs are normalized to uppercase
- Factory functions receive a transport instance
- Async factories support complex initialization
- MachineParser handles DE1 model detection (DE1, DE1+, DE1PRO, DE1XL)

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

2. **Auto-Connect Control:**
   - Maintains `shouldAutoConnect` flag
   - Temporarily disables during manual scans
   - Restores after 200ms delay

3. **Device Lifecycle:**
   - Tracks connected devices
   - Removes disconnected devices on scan
   - Prevents duplicate device entries

### Key Methods

```dart
// Initialize all services and start initial scan
Future<void> initialize() async {
  for (var service in _services) {
    await service.initialize();
    _serviceSubscriptions.add(
      service.devices.listen((devices) => _serviceUpdate(service, devices))
    );
  }
  await scanForDevices(autoConnect: true);
}

// Trigger scan across all services
Future<void> scanForDevices({required bool autoConnect}) async {
  // Remove disconnected devices
  _devices.forEach((_, devices) async {
    for (var device in devices.where((d) => d.connectionState == disconnected)) {
      devices.remove(device);
    }
  });
  
  // Temporarily set autoConnect flag
  final tmpAutoConnect = _autoConnect;
  _autoConnect = autoConnect;
  
  // Scan all services in parallel
  await Future.wait(_services.map((s) => s.scanForDevices()));
  
  // Restore autoConnect after 200ms
  await Future.delayed(Duration(milliseconds: 200), () {
    _autoConnect = tmpAutoConnect;
  });
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

## Device-Specific Controllers

Device-specific controllers manage the lifecycle and state of individual device types.

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
- Manages scale connection (auto or manual)
- Processes weight and flow data
- Calculates smoothed weight flow
- Exposes weight snapshots

**Auto-Connect Logic:**
```dart
ScaleController({required DeviceController controller})
  : _deviceController = controller {
  _deviceController.deviceStream.listen((devices) async {
    var scales = devices.whereType<Scale>().toList();
    if (_scale == null &&
        scales.firstOrNull != null &&
        _deviceController.shouldAutoConnect) {
      final scale = scales.first;
      await connectToScale(scale);
    }
  });
}
```

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
- `connectionState`: Scale connection status
- `weightSnapshot`: Processed weight data with flow calculation

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
3. Create DeviceController(services)
   ↓
4. Create De1Controller, ScaleController, SensorController
   ↓
5. runApp(MyApp(...))
   ↓
6. PermissionsView displayed
   ↓
7. User grants permissions
   ↓
8. deviceController.initialize()
   ↓
9. Each service.initialize() called
   ↓
10. scanForDevices(autoConnect: true)
    ↓
11. Services scan and emit devices
    ↓
12. ScaleController receives scales → auto-connects to first
    ↓
13. SensorController receives sensors → auto-connects to first
    ↓
14. DeviceDiscoveryView shows DE1 list
    ↓
15. User selects DE1 from list
    ↓
16. De1Controller.connectToDe1(selected)
    ↓
17. Navigate to HomeScreen
```

### Manual Scan Flow

```
1. User taps "Scan" button (e.g., in status tile)
   ↓
2. deviceController.scanForDevices(autoConnect: true)
   ↓
3. DeviceController temporarily sets _autoConnect = true
   ↓
4. All services scan in parallel
   ↓
5. New devices discovered and emitted
   ↓
6. ScaleController/SensorController auto-connect if shouldAutoConnect
   ↓
7. After 200ms, _autoConnect restored to previous value
```

### Machine Wake → Scale Reconnect Flow

```
1. Machine state: sleeping → idle
   ↓
2. De1StateManager._handleScalePowerManagement() detects transition
   ↓
3. Check if scale connected → NO
   ↓
4. Check if scalePowerMode == disconnect → YES
   ↓
5. Call _triggerScaleScan()
   ↓
6. deviceController.scanForDevices(autoConnect: true)
   ↓
7. Wait up to 30s for ScaleController.connectionState == connected
   ↓
8. Scale found → ScaleController auto-connects
   ↓
9. User can start making espresso immediately
```

---

## State Management

### Device Connection States

**Enum:** `ConnectionState` (defined in `lib/src/models/device/device.dart`)

```dart
enum ConnectionState {
  disconnected,
  connecting,
  connected,
  disconnecting,
}
```

### State Transitions

**Devices:**
```
disconnected → connecting → connected → disconnecting → disconnected
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

## Auto-Connection Logic

### When Auto-Connect Happens

1. **Initial Scan (PermissionsView):**
   - `DeviceController.initialize()` calls `scanForDevices(autoConnect: true)`
   - ScaleController and SensorController auto-connect to first found device
   - DE1 connection is manual (user selects from list)

2. **Manual Scan (Status Tile):**
   - User taps "Scan" → `scanForDevices(autoConnect: true)`
   - Same auto-connect behavior as initial scan

3. **Machine Wake (Sleep → Idle):**
   - If scale disconnected and `scalePowerMode == disconnect`
   - De1StateManager triggers scan with auto-connect
   - Only applies to scales (not DE1)

### Why DE1 Connection is Manual

**Design Decision:** DE1 connection requires user confirmation for several reasons:

1. **Multiple Machines:** Users may have multiple DE1 machines (cafe setup, multiple devices)
2. **Safety:** Accidental connection could be dangerous (wrong machine configuration)
3. **UX Clarity:** User should explicitly know which machine they're controlling
4. **Workflow Upload:** First connection uploads workflow/profile → should be intentional

**Implementation:**
- DeviceDiscoveryView (in PermissionsView) shows list of found DE1 machines
- User taps to select → `De1Controller.connectToDe1(selected)`
- 10-second timeout: if only 1 DE1 found, auto-connects
- If no DE1 found after timeout, navigate to HomeScreen anyway

### Scale Auto-Connect Behavior

**Why Scales Auto-Connect:**

1. **Single Scale Assumption:** Most users have one scale
2. **Non-Critical:** Scale connection doesn't affect machine safety
3. **Convenience:** Users expect scale to "just work"
4. **State Persistence:** Future enhancement will remember last connected scale

**Current Limitations:**
- Always connects to first found scale
- No preference/priority system
- No last-connected memory (planned for future)

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
  final DeviceController _deviceController;
  TemperatureSensor? _sensor;
  
  TemperatureController({required DeviceController controller})
    : _deviceController = controller {
    _deviceController.deviceStream.listen((devices) async {
      var sensors = devices.whereType<TemperatureSensor>().toList();
      if (_sensor == null &&
          sensors.firstOrNull != null &&
          _deviceController.shouldAutoConnect) {
        await connectToSensor(sensors.first);
      }
    });
  }
  
  // ... connection management
}
```

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
  BehaviorSubject.seeded(ConnectionState.disconnected);

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
- **Android:** `/storage/emulated/0/Download/REA1/log.txt`
- **Other platforms:** `<app_documents>/log.txt`

### Inspect Device Stream

Add temporary logging in DeviceController:

```dart
_deviceStream.listen((devices) {
  _log.info('Current devices: ${devices.map((d) => d.name).join(", ")}');
});
```

### Check Auto-Connect Flag

Log `shouldAutoConnect` during scans:

```dart
Future<void> scanForDevices({required bool autoConnect}) async {
  _log.info('Starting scan with autoConnect=$autoConnect');
  _log.info('shouldAutoConnect before: $_autoConnect');
  // ... scan logic
  _log.info('shouldAutoConnect after: $_autoConnect');
}
```

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
flutter run --dart-define=simulate=1
```

Or toggle in Settings UI → Simulated Devices

---

## Common Issues

### Scale Doesn't Auto-Connect

**Symptoms:** Scale found during scan but doesn't connect

**Possible Causes:**
1. `shouldAutoConnect` is false during scan
2. Another scale already connected
3. Scale UUID not in mappings
4. BLE permissions not granted

**Debug Steps:**
```dart
// In ScaleController constructor
_deviceController.deviceStream.listen((devices) async {
  var scales = devices.whereType<Scale>().toList();
  _log.info('Found ${scales.length} scales');
  _log.info('Current scale: $_scale');
  _log.info('shouldAutoConnect: ${_deviceController.shouldAutoConnect}');
  // ...
});
```

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

**Cause:** Manual modification of De1Controller to auto-connect

**Fix:** Ensure De1Controller only connects on explicit `connectToDe1()` call

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

1. **Device Preferences:**
   - Remember last connected scale/sensor
   - Prioritize reconnection to preferred devices
   - Store device nicknames

2. **Smart Reconnection:**
   - Auto-reconnect to last used devices on app startup
   - Exponential backoff for failed reconnections
   - Connection quality monitoring

3. **Multi-Device Support:**
   - Connect to multiple scales simultaneously
   - Aggregate sensor data from multiple sources
   - Switch between devices without disconnection

4. **Connection Indicators:**
   - Real-time connection status in UI
   - Battery level indicators
   - Signal strength monitoring

5. **Device Fingerprinting:**
   - Unique device identification beyond UUID
   - Detect duplicate devices (same scale via BLE + Serial)
   - Prevent double-connection issues

---

## Related Files

### Core Device Management
- `lib/src/controllers/device_controller.dart` - Central coordinator
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
- `lib/src/models/device/impl/de1/` - DE1 BLE machines
- `lib/src/models/device/impl/serial_de1/` - DE1 Serial machines
- `lib/src/models/device/impl/unified_de1/` - Unified DE1 interface
- `lib/src/models/device/impl/decent_scale/` - Decent Scale (BLE + Serial)
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
- **Auto-Connect:** Automatic connection to first found device of a type
- **shouldAutoConnect:** Flag controlling whether auto-connect logic is active
- **Device Stream:** RxDart BehaviorSubject broadcasting list of discovered devices
- **State Manager:** Orchestrator for machine state changes and related behaviors
- **UUID:** Universally Unique Identifier, used to identify BLE services/devices
- **Service Mapping:** Dictionary mapping UUIDs to device factory functions

