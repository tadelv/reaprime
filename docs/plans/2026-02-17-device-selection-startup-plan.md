# Device Selection Startup Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix the spinner-reset bug on the permissions screen when manually selecting a device, and add a fast-connect path that scans directly for the preferred device on startup.

**Architecture:** Two independent changes. (1) Lift connection state from `DeviceSelectionWidget` into its parent `_DeviceDiscoveryState` so device stream rebuilds don't wipe UI state. (2) Add `scanForSpecificDevice(String deviceId)` to the `DeviceDiscoveryService` interface and implement it in each service, then wire a new `directConnecting` UI state in `_DeviceDiscoveryState` that uses it.

**Tech Stack:** Flutter/Dart, `flutter_blue_plus` (BLE on Android/iOS/macOS/Linux), `universal_ble` (Windows BLE), `libserialport` (desktop USB), `usb_serial` (Android USB), RxDart `BehaviorSubject`.

---

## Task 1: Make `DeviceSelectionWidget` a pure display widget

This fixes the spinner-reset bug. The widget currently owns connection state internally, which gets wiped when its parent rebuilds. We move all connection logic to the parent.

**Files:**
- Modify: `lib/src/home_feature/widgets/device_selection_widget.dart`

**Step 1: Read the current widget**

Open `lib/src/home_feature/widgets/device_selection_widget.dart` and understand the current props and state.

Key things to note:
- `onDeviceSelected(De1Interface)` is called *after* `connectToDe1()` resolves inside the widget
- `_connectingDeviceId` and `_errorMessage` are internal state
- `autoConnectingDeviceId` is already a prop (passed from parent for auto-connect)

**Step 2: Update the widget**

Replace the widget so that:
- `onDeviceSelected` → renamed to `onDeviceTapped` (callback fires immediately on tap, before connection)
- Remove `De1Controller de1Controller` prop — widget no longer calls `connectToDe1()`
- Remove internal `_connectingDeviceId` and `_errorMessage` state
- Add props: `String? connectingDeviceId` and `String? errorMessage` (replaces both internal state and `autoConnectingDeviceId`)
- The tap handler simply calls `onDeviceTapped(de1)` if nothing is currently connecting
- `isConnecting` check uses `connectingDeviceId == de1.deviceId`
- `isAnyConnecting` check uses `connectingDeviceId != null`

New constructor signature:
```dart
const DeviceSelectionWidget({
  super.key,
  required this.deviceController,
  required this.onDeviceTapped,          // renamed, fires on tap (no await)
  this.settingsController,
  this.showHeader = false,
  this.headerText,
  this.connectingDeviceId,               // replaces autoConnectingDeviceId
  this.errorMessage,                     // replaces internal _errorMessage
});
```

New tap handler (inside `itemBuilder`):
```dart
onTap: isAnyConnecting
    ? null
    : () => widget.onDeviceTapped(de1),
```

Remove the entire `try/catch` block that called `widget.de1Controller.connectToDe1(de1)`.

Remove `_errorMessage` display from `build()` — the parent passes `errorMessage` as a prop and this widget just renders it.

**Step 3: Run the analyzer**

```bash
flutter analyze lib/src/home_feature/widgets/device_selection_widget.dart
```

Expected: no errors. Fix any type mismatches.

**Step 4: Fix call sites that pass `de1Controller` or use `onDeviceSelected`**

Search for all usages:
```bash
grep -rn "DeviceSelectionWidget\|onDeviceSelected\|autoConnectingDeviceId" lib/
```

There are two call sites:
- `lib/src/permissions_feature/permissions_view.dart` — update in Task 2
- `lib/src/home_feature/tiles/settings_tile.dart` — update now

In `settings_tile.dart`, the widget is used inside a `showShadDialog`. Update it:
- Remove `de1Controller` prop
- Rename `onDeviceSelected` → `onDeviceTapped`
- The dialog already calls `widget.controller.connectToDe1(de1)` nowhere — the dialog pattern here just calls `Navigator.of(context).pop()` after selection. Update so the dialog owns the connection: call `widget.controller.connectToDe1(de1)` in `onDeviceTapped`, then pop on success. Use local `StatefulBuilder` or move to a small `StatefulWidget` to hold connecting state in the dialog.

**Step 5: Run analyzer again**

```bash
flutter analyze lib/
```

Expected: no errors (other than pre-existing warnings unrelated to this change).

**Step 6: Commit**

```bash
git add lib/src/home_feature/widgets/device_selection_widget.dart lib/src/home_feature/tiles/settings_tile.dart
git commit -m "refactor: make DeviceSelectionWidget a pure display widget"
```

---

## Task 2: Lift connection state into `_DeviceDiscoveryState`

Now update the parent to own all connection state, fixing the bug.

**Files:**
- Modify: `lib/src/permissions_feature/permissions_view.dart`

**Step 1: Add connection state fields to `_DeviceDiscoveryState`**

In `_DeviceDiscoveryState`, replace `_autoConnectingDeviceId` with a unified field:

```dart
String? _connectingDeviceId;   // replaces _autoConnectingDeviceId
String? _connectionError;
```

**Step 2: Add `_handleDeviceTapped` method**

```dart
Future<void> _handleDeviceTapped(De1Interface de1) async {
  if (_connectingDeviceId != null) return; // guard against double-tap
  setState(() {
    _connectingDeviceId = de1.deviceId;
    _connectionError = null;
  });
  try {
    await widget.de1controller.connectToDe1(de1);
    if (mounted) {
      await _navigateAfterConnection();
    }
  } catch (e) {
    if (mounted) {
      setState(() {
        _connectingDeviceId = null;
        _connectionError = 'Failed to connect: $e';
      });
    }
    widget.logger.severe('Manual connect failed: $e');
  }
}
```

**Step 3: Update auto-connect logic in `initState()`**

The existing auto-connect sets `_autoConnectingDeviceId` — replace with `_connectingDeviceId`:

```dart
setState(() {
  _connectingDeviceId = preferredMachine.deviceId;
});

widget.de1controller
    .connectToDe1(preferredMachine)
    .then((_) async {
      if (mounted) await _navigateAfterConnection();
    })
    .catchError((error) {
      if (mounted) {
        setState(() {
          _connectingDeviceId = null;
        });
      }
      widget.logger.severe('Auto-connect failed: $error');
    });
```

**Step 4: Update `DeviceSelectionWidget` usage in `_resultsView`**

```dart
DeviceSelectionWidget(
  deviceController: widget.deviceController,
  settingsController: widget.settingsController,
  showHeader: true,
  headerText: "Select a machine from the list",
  connectingDeviceId: _connectingDeviceId,   // unified prop
  errorMessage: _connectionError,
  onDeviceTapped: _handleDeviceTapped,       // parent handles connection
),
```

**Step 5: Run analyzer**

```bash
flutter analyze lib/src/permissions_feature/permissions_view.dart
```

Expected: no errors.

**Step 6: Manual test**

Run the app with simulated devices:
```bash
flutter run --dart-define=simulate=1
```

Tap a device on the discovery screen. Verify:
- Spinner appears and stays visible until navigation completes
- Navigation happens automatically (no second tap needed)
- If connection fails, error message appears and spinner clears

**Step 7: Commit**

```bash
git add lib/src/permissions_feature/permissions_view.dart
git commit -m "fix: lift connection state to parent to fix spinner reset bug"
```

---

## Task 3: Add `scanForSpecificDevice` to the interface and `DeviceController`

**Files:**
- Modify: `lib/src/models/device/device.dart`
- Modify: `lib/src/controllers/device_controller.dart`

**Step 1: Add to `DeviceDiscoveryService` interface**

In `lib/src/models/device/device.dart`, add a default no-op implementation:

```dart
abstract class DeviceDiscoveryService {
  Stream<List<Device>> get devices;

  Future<void> initialize() async {
    throw "Not implemented yet";
  }

  Future<void> scanForDevices() async {
    throw "Not implemented yet";
  }

  /// Scan for a specific device by ID.
  ///
  /// Implementations should validate whether [deviceId] belongs to their
  /// transport (BLE MAC format for BLE services, port path for serial, etc.)
  /// and no-op if it does not. This avoids BLE services scanning for USB IDs
  /// and vice versa.
  Future<void> scanForSpecificDevice(String deviceId) async {
    // Default: no-op. Override in services that support targeted scanning.
  }
}
```

**Step 2: Add `scanForSpecificDevice` to `DeviceController`**

In `lib/src/controllers/device_controller.dart`, add:

```dart
/// Scan all services for a specific device by ID.
///
/// Returns true if the device appears in [deviceStream] within the timeout,
/// false otherwise. Callers should fall back to [scanForDevices] on false.
Future<bool> scanForSpecificDevice(String deviceId) async {
  final timeout = Duration(seconds: Platform.isLinux ? 25 : 8);

  // Start targeted scan on all services in parallel (each service
  // self-validates whether the ID belongs to its transport)
  for (final service in _services) {
    service.scanForSpecificDevice(deviceId).catchError((e) {
      _log.warning("Service $service scanForSpecificDevice failed: $e");
    });
  }

  // Wait until the device appears in the stream or we time out
  try {
    await _deviceStream
        .expand((devices) => devices)
        .where((device) => device.deviceId == deviceId)
        .first
        .timeout(timeout);
    return true;
  } on TimeoutException {
    return false;
  }
}
```

Add `import 'dart:async';` if not already present (for `TimeoutException`). Also needs `import 'dart:io';` for `Platform`.

**Step 3: Run analyzer**

```bash
flutter analyze lib/src/models/device/device.dart lib/src/controllers/device_controller.dart
```

Expected: no errors.

**Step 4: Commit**

```bash
git add lib/src/models/device/device.dart lib/src/controllers/device_controller.dart
git commit -m "feat: add scanForSpecificDevice to DeviceDiscoveryService interface and DeviceController"
```

---

## Task 4: Implement `scanForSpecificDevice` in `BluePlusDiscoveryService`

This is the primary BLE service used on Android, iOS, macOS, and non-Linux desktop.

**Files:**
- Modify: `lib/src/services/blue_plus_discovery_service.dart`

**Step 1: Add a BLE ID validator helper**

BLE device IDs from `flutter_blue_plus` are MAC addresses (`AA:BB:CC:DD:EE:FF`) on Android/Linux, or UUIDs on iOS/macOS. A simple check: contains `:` (MAC) or is 36 chars with `-` (UUID).

```dart
bool _isBleDeviceId(String deviceId) {
  // MAC address format: AA:BB:CC:DD:EE:FF
  final macPattern = RegExp(r'^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$');
  // UUID format: 8-4-4-4-12 hex chars
  final uuidPattern = RegExp(
    r'^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$',
  );
  return macPattern.hasMatch(deviceId) || uuidPattern.hasMatch(deviceId);
}
```

**Step 2: Implement `scanForSpecificDevice`**

```dart
@override
Future<void> scanForSpecificDevice(String deviceId) async {
  if (!_isBleDeviceId(deviceId)) {
    _log.fine('scanForSpecificDevice: "$deviceId" is not a BLE ID, skipping');
    return;
  }

  _log.info('Starting targeted BLE scan for device $deviceId');

  var subscription = FlutterBluePlus.onScanResults.listen((results) {
    if (results.isEmpty) return;
    final r = results.last;
    final foundId = r.device.remoteId.str;

    if (_devices.firstWhereOrNull((d) => d.deviceId == foundId) != null) return;
    if (_devicesBeingCreated.contains(foundId)) return;

    final s = r.advertisementData.serviceUuids.firstWhereOrNull(
      (adv) => deviceMappings.keys.map((e) => Guid(e)).toList().contains(adv),
    );
    if (s == null) return;

    final deviceFactory = deviceMappings[s.str];
    if (deviceFactory == null) return;

    _devicesBeingCreated.add(foundId);
    _createDevice(foundId, deviceFactory);
  }, onError: (e) => _log.warning('Targeted scan error: $e'));

  FlutterBluePlus.cancelWhenScanComplete(subscription);

  await FlutterBluePlus.adapterState
      .where((val) => val == BluetoothAdapterState.on)
      .first;

  await FlutterBluePlus.startScan(
    withRemoteIds: [DeviceIdentifier(deviceId)],
    withServices: deviceMappings.keys.map((e) => Guid(e)).toList(),
    oneByOne: true,
  );

  // Stop after timeout (device found earlier stops via cancelWhenScanComplete)
  final timeout = Platform.isLinux
      ? const Duration(seconds: 20)
      : const Duration(seconds: 8);
  await Future.delayed(timeout, () async {
    await FlutterBluePlus.stopScan();
  });

  _deviceStreamController.add(_devices.toList());
}
```

**Step 3: Run analyzer**

```bash
flutter analyze lib/src/services/blue_plus_discovery_service.dart
```

Expected: no errors.

**Step 4: Commit**

```bash
git add lib/src/services/blue_plus_discovery_service.dart
git commit -m "feat: implement scanForSpecificDevice in BluePlusDiscoveryService"
```

---

## Task 5: Implement `scanForSpecificDevice` in serial services

**Files:**
- Modify: `lib/src/services/serial/serial_service_desktop.dart`
- Modify: `lib/src/services/serial/serial_service_android.dart`

**Step 1: Desktop serial (`serial_service_desktop.dart`)**

A serial port ID on desktop is a port path string (e.g. `/dev/ttyACM0`, `/dev/ttyUSB0`, `COM3`). Validate by checking if the ID exists in `SerialPort.availablePorts`.

```dart
@override
Future<void> scanForSpecificDevice(String deviceId) async {
  final available = SerialPort.availablePorts;
  if (!available.contains(deviceId)) {
    _log.fine('scanForSpecificDevice: "$deviceId" not in available serial ports, skipping');
    return;
  }

  _log.info('Direct serial detection for port $deviceId');
  // Skip if already connected
  for (final d in _devices) {
    if (d.deviceId == deviceId) {
      final state = await d.connectionState.first;
      if (state == ConnectionState.connected) {
        _log.fine('Device $deviceId already connected');
        return;
      }
    }
  }

  try {
    final device = await _detectDevice(deviceId);
    if (device != null) {
      _devices.add(device);
      _machineSubject.add(_devices);
      _log.info('Direct connect found device on $deviceId');
    }
  } catch (e) {
    _log.warning('Direct serial detection failed for $deviceId: $e');
  }
}
```

**Step 2: Android serial (`serial_service_android.dart`)**

Android USB device IDs are integers. Validate by attempting `int.tryParse`.

```dart
@override
Future<void> scanForSpecificDevice(String deviceId) async {
  final intId = int.tryParse(deviceId);
  if (intId == null) {
    _log.fine('scanForSpecificDevice: "$deviceId" is not an Android USB device ID, skipping');
    return;
  }

  _log.info('Direct USB detection for device ID $deviceId');
  final usbDevices = await UsbSerial.listDevices();
  final target = usbDevices.firstWhereOrNull((d) => d.deviceId == intId);
  if (target == null) {
    _log.fine('USB device $deviceId not found in connected devices');
    return;
  }

  // Skip if already tracked
  if (_devices.firstWhereOrNull((d) => d.deviceId == deviceId) != null) {
    _log.fine('Device $deviceId already in device list');
    return;
  }

  try {
    final device = await _detectDevice(target);
    if (device != null) {
      _devices.add(device);
      _machineSubject.add(_devices);
      _log.info('Direct USB connect found device $deviceId');
    }
  } catch (e) {
    _log.warning('Direct USB detection failed for $deviceId: $e');
  }
}
```

**Step 3: Run analyzer**

```bash
flutter analyze lib/src/services/serial/
```

Expected: no errors.

**Step 4: Commit**

```bash
git add lib/src/services/serial/serial_service_desktop.dart lib/src/services/serial/serial_service_android.dart
git commit -m "feat: implement scanForSpecificDevice in serial discovery services"
```

---

## Task 6: Implement `scanForSpecificDevice` in `LinuxBleDiscoveryService` and `UniversalBleDiscoveryService`

**Files:**
- Modify: `lib/src/services/ble/linux_ble_discovery_service.dart`
- Modify: `lib/src/services/universal_ble_discovery_service.dart`

**Step 1: Shared BLE ID validator**

Both services need the same MAC/UUID check as `BluePlusDiscoveryService` (Task 4, Step 1). Copy the `_isBleDeviceId` helper into each service. (It's small enough that duplication is fine — don't abstract prematurely.)

**Step 2: `LinuxBleDiscoveryService`**

Linux BLE has the quirk that scanning and connecting are mutually exclusive (BlueZ). The targeted scan should use `withRemoteIds` but otherwise follow the same queue-then-connect pattern as `scanForDevices`. Add:

```dart
@override
Future<void> scanForSpecificDevice(String deviceId) async {
  if (!_isBleDeviceId(deviceId)) {
    _log.fine('scanForSpecificDevice: "$deviceId" is not a BLE ID, skipping');
    return;
  }
  if (!_adapterReady) {
    _log.warning('BLE adapter not ready, cannot do targeted scan');
    return;
  }

  _log.info('Linux targeted BLE scan for $deviceId');

  var sub = FlutterBluePlus.onScanResults.listen((results) {
    if (results.isEmpty) return;
    final r = results.last;
    final foundId = r.device.remoteId.str;
    if (_devicesBeingCreated.contains(foundId)) return;
    if (_devices.firstWhereOrNull((d) => d.deviceId == foundId) != null) return;

    final s = r.advertisementData.serviceUuids.firstWhereOrNull(
      (adv) => deviceMappings.keys.map((e) => Guid(e)).toList().contains(adv),
    );
    if (s == null) return;
    final factory = deviceMappings[s.str];
    if (factory == null) return;

    _devicesBeingCreated.add(foundId);
    _pendingDevices.add(_PendingDevice(foundId, factory));
  }, onError: (e) => _log.warning('Targeted scan error: $e'));

  FlutterBluePlus.cancelWhenScanComplete(sub);

  await FlutterBluePlus.startScan(
    withRemoteIds: [DeviceIdentifier(deviceId)],
    withServices: deviceMappings.keys.map((e) => Guid(e)).toList(),
    oneByOne: true,
  );

  // Linux: scan for up to 15s then stop and process
  await Future.delayed(const Duration(seconds: 15), () async {
    await FlutterBluePlus.stopScan();
  });

  await Future.delayed(_postScanSettleDelay);

  if (_pendingDevices.isNotEmpty) {
    for (final pending in List.of(_pendingDevices)) {
      await _createDevice(pending.deviceId, pending.factory);
    }
    _pendingDevices.clear();
  }

  _deviceStreamController.add(_devices.toList());
}
```

**Step 3: `UniversalBleDiscoveryService`**

`universal_ble` is the Windows BLE service. It doesn't expose `withRemoteIds` filtering, so fall back to `scanForDevices()` but only if the ID looks like a BLE ID:

```dart
@override
Future<void> scanForSpecificDevice(String deviceId) async {
  if (!_isBleDeviceId(deviceId)) {
    log.fine('scanForSpecificDevice: "$deviceId" is not a BLE ID, skipping');
    return;
  }
  // universal_ble does not support withRemoteIds filtering — fall back to full scan
  log.info('universal_ble: falling back to full scan for $deviceId');
  await scanForDevices();
}
```

**Step 4: Run analyzer**

```bash
flutter analyze lib/src/services/ble/
```

Expected: no errors.

**Step 5: Commit**

```bash
git add lib/src/services/ble/linux_ble_discovery_service.dart lib/src/services/universal_ble_discovery_service.dart
git commit -m "feat: implement scanForSpecificDevice in Linux and Universal BLE services"
```

---

## Task 7: Add `directConnecting` UI state and wire up fast-connect in `permissions_view.dart`

**Files:**
- Modify: `lib/src/permissions_feature/permissions_view.dart`

**Step 1: Add `directConnecting` to `DiscoveryState`**

```dart
enum DiscoveryState { directConnecting, searching, foundMany, foundNone }
```

**Step 2: Add `_directConnectingView()` widget method**

```dart
Widget _directConnectingView(BuildContext context) {
  final theme = ShadTheme.of(context);
  return Column(
    mainAxisSize: MainAxisSize.min,
    spacing: 16,
    children: [
      SizedBox(width: 200, child: ShadProgress()),
      Text(
        'Connecting to your machine...',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      TextButton(
        onPressed: _fallbackToFullScan,
        child: Text('Scan for all devices', style: theme.textTheme.muted),
      ),
    ],
  );
}
```

**Step 3: Add `_fallbackToFullScan()` method**

```dart
void _fallbackToFullScan() {
  setState(() {
    _state = DiscoveryState.searching;
  });
  widget.deviceController.scanForDevices(autoConnect: false);
}
```

**Step 4: Update `initState()` to start with direct connect if preferred device is set**

Replace the beginning of `initState()`:

```dart
@override
void initState() {
  super.initState();

  if (!widget.settingsController.telemetryConsentDialogShown) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showTelemetryConsentDialog();
    });
  }

  final preferredMachineId = widget.settingsController.preferredMachineId;

  if (preferredMachineId != null) {
    // Fast-connect path: scan specifically for the preferred device
    _state = DiscoveryState.directConnecting;
    _startDirectConnect(preferredMachineId);
  }

  // Always listen to device stream for the normal foundMany path
  _discoverySubscription = widget.deviceController.deviceStream.listen((data) {
    final discoveredDevices = data.whereType<De1Interface>().toList();
    if (discoveredDevices.isNotEmpty && _state != DiscoveryState.directConnecting) {
      setState(() {
        _state = DiscoveryState.foundMany;
      });
    }
  });

  // Timeout for the normal search path only
  if (preferredMachineId == null) {
    _startNormalScanWithTimeout();
  }
}
```

**Step 5: Add `_startDirectConnect()` method**

```dart
Future<void> _startDirectConnect(String deviceId) async {
  final found = await widget.deviceController.scanForSpecificDevice(deviceId);

  if (!mounted) return;

  if (!found) {
    widget.logger.info('Preferred device $deviceId not found, falling back to full scan');
    _fallbackToFullScan();
    _startNormalScanWithTimeout();
    return;
  }

  // Device is now in the stream — find and connect
  final device = widget.deviceController.devices
      .whereType<De1Interface>()
      .firstWhereOrNull((d) => d.deviceId == deviceId);

  if (device == null) {
    widget.logger.warning('Device appeared then vanished: $deviceId');
    _fallbackToFullScan();
    _startNormalScanWithTimeout();
    return;
  }

  setState(() {
    _connectingDeviceId = device.deviceId;
  });

  try {
    await widget.de1controller.connectToDe1(device);
    if (mounted) await _navigateAfterConnection();
  } catch (e) {
    widget.logger.severe('Direct connect failed: $e');
    if (mounted) {
      setState(() {
        _connectingDeviceId = null;
      });
      _fallbackToFullScan();
      _startNormalScanWithTimeout();
    }
  }
}
```

**Step 6: Extract `_startNormalScanWithTimeout()` method**

Move the existing post-timeout logic to a named method so it can be called from both `initState()` and the fallback path:

```dart
void _startNormalScanWithTimeout() {
  Future.delayed(_timeoutDuration, () {
    if (!mounted) return;
    final discoveredDevices =
        widget.deviceController.devices.whereType<De1Interface>().toList();
    setState(() {
      _isScanning = false;
      if (discoveredDevices.isEmpty && _state != DiscoveryState.foundMany) {
        _state = DiscoveryState.foundNone;
      }
    });
  });
}
```

**Step 7: Update `build()` to handle `directConnecting` state**

```dart
@override
Widget build(BuildContext context) {
  switch (_state) {
    case DiscoveryState.directConnecting:
      return _directConnectingView(context);
    case DiscoveryState.searching:
      return _searchingView(context);
    case DiscoveryState.foundMany:
      return SizedBox(height: 500, width: 300, child: _resultsView(context));
    case DiscoveryState.foundNone:
      return _noDevicesFoundView(context);
  }
}
```

**Step 8: Run analyzer**

```bash
flutter analyze lib/src/permissions_feature/permissions_view.dart
```

Expected: no errors. Fix any issues (e.g. missing `firstWhereOrNull` import — it's from `package:collection/collection.dart`).

**Step 9: Run full analyzer**

```bash
flutter analyze lib/
```

Expected: no new errors introduced by this change.

**Step 10: Manual test — no preferred device**

```bash
flutter run --dart-define=simulate=1
```

Verify normal flow unchanged: spinner → device list → tap → navigate.

**Step 11: Manual test — with preferred device**

Set a preferred device via the checkbox in the device list, restart the app. Verify:
- "Connecting to your machine..." screen appears immediately
- Navigates to SkinView/LandingFeature without showing device list
- "Scan for all devices" button falls back to normal scan if tapped

**Step 12: Commit**

```bash
git add lib/src/permissions_feature/permissions_view.dart
git commit -m "feat: add direct-connect startup flow for preferred device"
```

---

## Task 8: Final check

**Step 1: Full analyzer pass**

```bash
flutter analyze lib/
```

Expected: no errors.

**Step 2: Run tests**

```bash
flutter test
```

Expected: all tests pass.

**Step 3: Check for any remaining references to removed API**

```bash
grep -rn "autoConnectingDeviceId\|onDeviceSelected\b" lib/
```

Expected: no results (both were renamed/removed).

**Step 4: Commit if any cleanup needed, then done**

```bash
git log --oneline -8
```

Should show a clean sequence of commits for this feature.
