# BLE Scan Refactor Design

**Date:** 2026-02-23  
**Status:** Ready for Implementation  
**Author:** Claude (Sonnet 4.5)  
**Branch:** `fix/ble-uuids`  
**Implementation Plan:** `doc/plans/2026-02-23-ble-scan-refactor.md`

## Problem Statement

Current BLE discovery relies on service UUID filtering (`withServices` parameter) to find coffee machine peripherals. This approach is fragile across target platforms:

**Android (9-15):**
- UUID filters only match UUIDs in the **primary advertisement packet**
- Many devices put 128-bit UUIDs in the **scan response** instead → silent misses
- Scan start throttling: 5 scans per 30 seconds (since Android 7) → silently returns zero results when exceeded
- Unfiltered scans paused when screen is off (since Android 8.1)

**Linux/BlueZ:**
- UUID filtering is software-side in the daemon, not hardware
- Shared discovery sessions: another process's scan can override our filter entirely

**Result:** Users report scales (Decent Scale, Skale2) not appearing in discovery on Android 9/12. Devices never appear in logs, even at scan time.

## Context for Different Machine Implementation

### Current Branch State

**Branch:** `fix/ble-uuids`  
**Last commit:** `6c52dcc add proposal for scan rewrite`

**Recent commits (most recent first):**
- `6c52dcc` - Added `doc/plans/ble-scan-proposal.md` with unfiltered scan strategy
- `9901e05` - Fixed short-form UUID handling from Android BLE stack
- `0881eec` - Updated discovery services to use BleServiceIdentifier
- `c7eae14` through `c2e37c7` - Migrated all 16 device implementations to BleServiceIdentifier

### Completed Work (BleServiceIdentifier)

✅ **Already implemented on this branch:**

**BleServiceIdentifier Model** (`lib/src/models/device/ble_service_identifier.dart`):
- Type-safe UUID abstraction with automatic conversion
- Supports `.short()`, `.long()`, `.parse()`, and `.both()` constructors
- Automatic Bluetooth SIG base UUID expansion: `0000xxxx-0000-1000-8000-00805f9b34fb`
- Validates UUIDs at construction time
- Implements equality/hashCode for Map key usage
- Example: `BleServiceIdentifier.short('fff0')` automatically expands to `0000fff0-0000-1000-8000-00805f9b34fb`

**All Device Implementations Migrated:**
- ✅ DecentScale - `static final serviceIdentifier = BleServiceIdentifier.short('fff0')`
- ✅ Skale2Scale - `static final serviceIdentifier = BleServiceIdentifier.short('ff08')`
- ✅ FelicitaArc - Uses BleServiceIdentifier
- ✅ EurekaScale - Uses BleServiceIdentifier
- ✅ AcaiaScale, AcaiaPyxisScale - Use BleServiceIdentifier
- ✅ HiroiaScale, BlackCoffeeScale, AtomheartScale, DifluidScale - Use BleServiceIdentifier
- ✅ VariaAkuScale, SmartChefScale, BookooScale - Use BleServiceIdentifier
- ✅ UnifiedDe1, Bengle - Use BleServiceIdentifier

**Discovery Services:**
- Current implementation: Use `BleServiceIdentifier` in `deviceMappings` for UUID-based filtering
- Still use `withServices` parameter with UUID list (this is what we're removing)

**This work provides the foundation for service verification after connection.**

### What This Refactor Changes

**Removing:**
- UUID-based scan filtering (`withServices` parameter)
- `deviceMappings` dictionary in discovery services
- `MachineParser` from discovery flow (connects during scan to read model)
- Device factory lookup by service UUID

**Adding:**
- `DeviceMatcher` utility for name-based device matching
- `_isScanning` flag to prevent concurrent scans
- Service verification in each device's `onConnect()` method
- Model warning in UnifiedDe1 for Bengle hardware misidentification

**Impact:**
- Unfiltered scans find all BLE devices, filter by name in software
- Discovery adds devices to list WITHOUT connecting
- User selection triggers connection
- Connection calls `onConnect()` which verifies service UUID exists
- Fixes Android 9/12 issues where scales don't appear in scan (UUIDs in scan response, not primary packet)

## Proposed Solution: Name-Based Discovery with Service Verification

Replace UUID-based scan filtering with a **two-phase strategy**: broad scan with name-prefix matching, followed by post-connection service verification.

### Design Goals

1. **Platform resilience:** Works on Android 9-15, Linux/BlueZ, iOS, Windows, macOS
2. **No UUID filter dependency:** Avoid fragile UUID matching in scan filters
3. **Fast failure:** Quick detection of mismatched devices via service verification
4. **Clean architecture:** Simple name-based matching without unnecessary caching

### Approach

**Phase 1 - Discovery (Scan):**
- Start unfiltered BLE scan (empty `withServices` list)
- Match devices by advertised name in software using `DeviceMatcher`
- Add matched devices to discovery list (not connected)
- Platform-agnostic, works regardless of where UUID appears in advertisement

**Phase 2 - Verification (Connect):**
- User selects device → `onConnect()` called
- Device discovers services and verifies expected service UUID using `BleServiceIdentifier`
- Throw exception if service not found → connection fails, error shown to user

**Benefits:**
- Survives Android fragmentation (no dependency on advertisement packet structure)
- Avoids BlueZ filter-merge conflicts
- Makes code easier to reason about: scan finds candidates, user connection verifies them
- Clean separation: discovery finds devices, connection validates them

## Architecture

### Component 1: DeviceMatcher Utility

**Purpose:** Centralized device name matching logic with custom match strategies per device.

**Location:** `lib/src/services/device_matcher.dart`

**Interface:**
```dart
class DeviceMatcher {
  static Future<Device?> match({
    required BLETransport transport,
    required String advertisedName,
  }) async {
    final name = advertisedName;
    final nameLower = name.toLowerCase();
    
    // Exact matches
    if (name == 'Decent Scale') return DecentScale(transport: transport);
    if (name == 'Skale2') return Skale2Scale(transport: transport);
    
    // Prefix/contains matches
    if (nameLower.startsWith('felicita')) return FelicitaArc(transport: transport);
    if (nameLower.contains('acaia')) {
      if (nameLower.contains('pyxis')) return AcaiaPyxisScale(transport: transport);
      return AcaiaScale(transport: transport);
    }
    
    // Multi-name disambiguation
    if (nameLower.contains('eureka') || nameLower.contains('precisa')) {
      return EurekaScale(transport: transport);
    }
    if (nameLower.contains('solo barista') || nameLower.contains('lsj-001')) {
      return EurekaScale(transport: transport); // Same protocol
    }
    
    // DE1 family
    if (name == 'DE1' || name == 'nrf5x' || nameLower.startsWith('de1')) {
      return UnifiedDe1(transport: transport);
    }
    if (name == 'Bengle') return Bengle(transport: transport);
    
    // SmartChef, Varia, etc.
    if (nameLower.contains('smartchef')) return SmartChefScale(transport: transport);
    if (nameLower.contains('aku') || nameLower.contains('varia')) {
      return VariaAkuScale(transport: transport);
    }
    if (nameLower.contains('hiroia') || nameLower.contains('jimmy')) {
      return HiroiaScale(transport: transport);
    }
    if (nameLower.contains('difluid')) return DifluidScale(transport: transport);
    if (nameLower.startsWith('black')) return BlackCoffeeScale(transport: transport);
    if (nameLower.contains('atomheart') || nameLower.contains('eclair')) {
      return AtomheartScale(transport: transport);
    }
    if (nameLower.contains('bookoo')) return BookooScale(transport: transport);
    
    return null; // No match
  }
}
```

**Matching Strategies:**
- **Exact:** `name == 'Decent Scale'` - for devices with consistent names
- **Prefix:** `startsWith('felicita')` - for devices with model variations (e.g., "Felicita Arc")
- **Contains:** `contains('acaia')` - for flexible matching (e.g., "ACAIA LUNAR", "Acaia Pearl")
- **Multi-name:** Handle devices sharing protocols (Solo Barista → EurekaScale)

**Extension Point:**
Future platform-specific variations can be added via:
```dart
static Future<Device?> matchAndroid(...) // Android-specific quirks
static Future<Device?> matchLinux(...)   // BlueZ-specific quirks
```

### Component 2: Discovery Service Updates

**BluePlusDiscoveryService:**

**Changes:**
1. Remove `_buildScanGuids()` - no UUID filter needed
2. Remove `_findFactory()` - replaced by `DeviceMatcher.match()`
3. Add `_isScanning` flag to prevent concurrent scans
4. Update `scanForDevices()` to:
   - Scan with empty `withServices` list
   - Match by name using `DeviceMatcher`

**Scan Flow:**
```dart
Future<void> scanForDevices() async {
  if (_isScanning) {
    _log.warning('Scan already in progress, ignoring request');
    return;
  }
  
  _isScanning = true;
  
  try {
    var subscription = FlutterBluePlus.onScanResults.listen((results) {
      if (results.isEmpty) return;
      final r = results.last;
      final deviceId = r.device.remoteId.str;
      final name = r.advertisementData.advName;
      
      // Skip if already exists or being created
      if (_devices.firstWhereOrNull((d) => d.deviceId == deviceId) != null) return;
      if (_devicesBeingCreated.contains(deviceId)) return;
      
      // Match by name
      _devicesBeingCreated.add(deviceId);
      _createDeviceFromName(deviceId, name);
    });
    
    FlutterBluePlus.cancelWhenScanComplete(subscription);
    
    await FlutterBluePlus.adapterState
        .where((val) => val == BluetoothAdapterState.on)
        .first;
    
    // Unfiltered scan
    await FlutterBluePlus.startScan(oneByOne: true);
    
    // Platform-specific timeout
    final timeout = Platform.isLinux
        ? const Duration(seconds: 15)
        : const Duration(seconds: 15);
    
    await Future.delayed(timeout, () async {
      await FlutterBluePlus.stopScan();
    });
  } finally {
    _isScanning = false;
  }
}

Future<void> _createDeviceFromName(String deviceId, String name) async {
  try {
    final transport = Platform.isAndroid
        ? AndroidBluePlusTransport(remoteId: deviceId)
        : BluePlusTransport(remoteId: deviceId);
    
    final device = await DeviceMatcher.match(
      transport: transport,
      advertisedName: name,
    );
    
    if (device == null) {
      _log.fine('No device match for name "$name"');
      return;
    }
    
    // Add device to list (not connected yet - user selects device to connect)
    _devices.add(device);
    _deviceStreamController.add(_devices);
    _log.info('Device $deviceId "$name" added to discovery list');
    
    // Set up cleanup listener for when device disconnects
    StreamSubscription? sub;
    sub = device.connectionState.skip(1).listen((event) {
      if (event == ConnectionState.disconnected) {
        _log.info("Device $deviceId disconnected, removing from discovery list");
        _devices.removeWhere((d) => d.deviceId == deviceId);
        _deviceStreamController.add(_devices);
        sub?.cancel();
      }
    });
  } catch (e) {
    _log.severe("Error creating device $deviceId: $e");
  } finally {
    _devicesBeingCreated.remove(deviceId);
  }
}
```



**UniversalBleDiscoveryService:**

Similar changes:
- Remove UUID filter generation
- Use `DeviceMatcher.match()`
- Add `_isScanning` flag
- Platform-specific: Linux still uses empty `withServices` (BlueZ compatibility)

### Component 3: Service Verification in Device onConnect()

**Current behavior:**
- Devices call `_transport.discoverServices()`
- No explicit verification that expected service exists

**New behavior:**
- After `discoverServices()`, verify expected service UUID is present
- Throw exception if service not found
- Discovery service catches exception, removes device from list

**Implementation pattern (applies to all devices):**

```dart
class Skale2Scale implements Scale {
  static final serviceIdentifier = BleServiceIdentifier.short('ff08');
  
  @override
  Future<void> onConnect() async {
    if (await _transport.connectionState.first == true) return;
    
    _connectionStateController.add(ConnectionState.connecting);
    
    try {
      await _transport.connect();
      
      final services = await _transport.discoverServices();
      
      // NEW: Verify expected service exists
      if (!services.contains(serviceIdentifier.long) && 
          !services.contains(serviceIdentifier.short)) {
        throw Exception(
          'Expected service ${serviceIdentifier.long} not found. '
          'Discovered services: $services'
        );
      }
      
      // Continue with normal initialization
      await _initScale();
      _connectionStateController.add(ConnectionState.connected);
    } catch (e) {
      _log.warning('Failed to connect: $e');
      _connectionStateController.add(ConnectionState.disconnected);
      await _transport.disconnect();
      rethrow; // Let discovery service handle the error
    }
  }
}
```

**Discovery service behavior:**

Discovery services create device instances and add them to the list. They do NOT call `onConnect()`. Connection happens later when:
- User selects device from UI
- App auto-connects to previously paired device
- API endpoint triggers connection

Service verification runs during the device's `onConnect()` method, which is called by whatever code initiates the connection (not by discovery service).

### Component 4: MachineParser Removal

**Current flow:**
- `main.dart` maps DE1 advertising UUID → `MachineParser.machineFrom()`
- `MachineParser` connects, reads MMR, determines DE1 vs Bengle, disconnects

**New flow:**
- `DeviceMatcher` routes by name: `"DE1"` → `UnifiedDe1`, `"Bengle"` → `Bengle`
- No connection during discovery

**Safety check in UnifiedDe1:**

Add warning when model is read during normal operation:

```dart
// In UnifiedDe1, where model is checked from MMR
Future<int> _readModel() async {
  final model = await _readMMRInt(MMRItem.v13Model);
  
  if (model >= 128) {
    _log.warning(
      'Device model=$model indicates Bengle hardware, but initialized as UnifiedDe1. '
      'Device may have advertised incorrect name ("$name" instead of "Bengle") during discovery. '
      'Functionality may be limited.'
    );
  }
  
  return model;
}
```

**Files to modify:**
- Remove: `lib/src/models/device/impl/machine_parser.dart`
- Update: `lib/main.dart` - remove `MachineParser.machineFrom()` references
- Update: `lib/src/models/device/impl/de1/unified_de1/unified_de1.dart` - add model warning

## Data Flow

### Discovery Flow

1. **User taps scan**
2. **Discovery service** checks `_isScanning` flag
3. **Start unfiltered scan** with `FlutterBluePlus.startScan(oneByOne: true)`
4. **Scan results arrive** → extract `deviceId` and `advertisedName`
5. **Match by name** → `DeviceMatcher.match(name, transport)` returns `Device?`
6. **If match:** Add device to discovered devices list (not connected yet)
7. **If no match:** Log and skip
8. **Scan completes** (15s timeout) → set `_isScanning = false`
9. **User selects device** from UI → triggers `device.onConnect()`
10. **Service verification** happens in `onConnect()`:
    - Connect to transport
    - Discover services
    - Verify expected service UUID exists
    - If verified: device stays connected
    - If failed: throw exception, disconnect, show error to user

### Service Verification Flow

1. **User selects device** from discovery list (or app auto-connects)
2. **Device onConnect() called** by UI/controller/API
3. **Connect to transport**
4. **Discover services** → returns `List<String>` of UUIDs
5. **Check for expected service** using `BleServiceIdentifier`
6. **If found:** Continue initialization, device becomes active
7. **If not found:** Throw exception with discovered services list, disconnect, show error to user

## Testing Strategy

### Unit Tests

**DeviceMatcher:**
- Exact name matches return correct device type
- Prefix matches work (e.g., "Felicita Arc" → FelicitaArc)
- Contains matches work (e.g., "ACAIA LUNAR" → AcaiaScale)
- Multi-name disambiguation (Solo Barista → EurekaScale)
- Unknown names return null
- Case-insensitive matching

**Discovery Services:**
- `_isScanning` flag prevents concurrent scans
- Unfiltered scan starts successfully
- Name matching called for each result
- Service verification failures handled gracefully

### Integration Tests

**Real Hardware:**
- Test Decent Scale discovery on Android 9/12
- Test Skale2 discovery on Android 9/12
- Verify other scales still discovered (Felicita, Acaia, etc.)

**Edge Cases:**
- Device advertises wrong name → service verification catches mismatch
- Bengle advertises as "DE1" → warning logged, continues as UnifiedDe1
- Multiple devices with similar names (e.g., "Acaia Lunar", "Acaia Pearl")
- Screen-off scanning on Android

### Regression Testing

- Run full test suite: `flutter test`
- Verify no existing functionality broken
- Test device reconnection after disconnect
- Test multiple simultaneous scale connections

## Migration Plan

### Phase 1: DeviceMatcher Implementation
1. Create `DeviceMatcher` utility class
2. Add unit tests for all matching logic
3. Verify all current devices have name match cases

### Phase 2: Discovery Service Updates
1. Add `_isScanning` flag to discovery services
2. Remove UUID filter logic
3. Replace device factory lookup with `DeviceMatcher.match()`
4. Update both `BluePlusDiscoveryService` and `UniversalBleDiscoveryService`

### Phase 3: Service Verification
1. Add service verification to each device's `onConnect()` method
2. Add error handling tests
3. Verify exceptions propagate correctly to discovery services

### Phase 4: MachineParser Removal
1. Update `DeviceMatcher` with DE1/Bengle name routing
2. Remove `MachineParser` from `main.dart`
3. Delete `machine_parser.dart` file
4. Add model warning to `UnifiedDe1`

### Phase 5: Testing & Validation
1. Run full test suite
2. Test with real hardware (Decent Scale, Skale2 on Android 9/12)
3. Monitor logs for service verification failures
4. Test connection flow: discovery → user selection → service verification

## Risks & Mitigations

**Risk 1: Too many scan results without UUID filtering**
- *Mitigation:* Name filtering in software is fast. Modern devices handle this easily. Scan only runs for 15s.

**Risk 2: Device advertises unexpected name**
- *Mitigation:* Service verification catches mismatches. Warning logged, device not added to list.

**Risk 3: Bengle advertises as "DE1"**
- *Mitigation:* Service verification will pass (both use same service UUID). Runtime model check logs warning. Functionality preserved.

**Risk 4: Breaking existing working devices**
- *Mitigation:* Name matching is additive. All current devices have name cases. Service verification uses existing `BleServiceIdentifier` work.

## Success Criteria

1. Decent Scale and Skale2 appear in device discovery on Android 9/12
2. All existing working devices continue to connect
3. No regressions in test suite
4. Service verification catches mismatched devices during connection
5. Unfiltered scan works on all platforms (Android, Linux, iOS, Windows, macOS)

## Key Implementation Files

**Device Implementations** (all in `lib/src/models/device/impl/`):
- `decent_scale/scale.dart` - DecentScale
- `skale/skale2_scale.dart` - Skale2Scale (primary Android 9/12 issue)
- `felicita/arc.dart` - FelicitaArc
- `eureka/eureka_scale.dart` - EurekaScale (also handles Solo Barista protocol)
- `acaia/acaia_scale.dart`, `acaia/acaia_pyxis_scale.dart` - Acaia scales
- `hiroia/hiroia_scale.dart` - HiroiaScale
- `blackcoffee/blackcoffee_scale.dart` - BlackCoffeeScale
- `atomheart/atomheart_scale.dart` - AtomheartScale
- `difluid/difluid_scale.dart` - DifluidScale
- `varia/varia_aku_scale.dart` - VariaAkuScale
- `smartchef/smartchef_scale.dart` - SmartChefScale
- `bookoo/miniscale.dart` - BookooScale
- `de1/unified_de1/unified_de1.dart` - UnifiedDe1
- `bengle/bengle.dart` - Bengle

**Discovery Services:**
- `lib/src/services/blue_plus_discovery_service.dart` - Primary discovery (flutter_blue_plus)
- `lib/src/services/universal_ble_discovery_service.dart` - Cross-platform discovery (universal_ble)
- `lib/src/services/ble/linux_ble_discovery_service.dart` - Linux-specific (if exists)

**Configuration:**
- `lib/main.dart` - Contains `bleDeviceMappings` (to be removed)

**New Files to Create:**
- `lib/src/services/device_matcher.dart` - Name-based matching utility
- `test/unit/services/device_matcher_test.dart` - Tests for DeviceMatcher

## References & Documentation

**Original Issue:**
- Users on Android 9 and 12 report Decent Scale and Skale2 not appearing in device discovery
- Devices don't appear in logs even at scan time (completely filtered out)
- Hypothesis: Old Android BLE stack only matches UUIDs in primary advertisement packet, not scan response

**Design Documents:**
- BLE Scan Proposal: `doc/plans/ble-scan-proposal.md`
- This Design Document: `doc/plans/2026-02-23-ble-scan-refactor-design.md`
- Implementation Plan: `doc/plans/2026-02-23-ble-scan-refactor.md`

**Reference Implementation:**
- `github.com/decentespresso/de1app` - Original Decent app (TCL-based, authoritative for DE1 protocol)

**Technical References:**
- Bluetooth SIG Base UUID: `0000xxxx-0000-1000-8000-00805f9b34fb`
- Android BLE Scan Throttling: 5 scans per 30 seconds since Android 7
- Android BLE Issues: UUID filters only match primary packet, not scan response
- BlueZ (Linux): Software-side UUID filtering, subject to filter-merge conflicts
- flutter_blue_plus documentation: [pub.dev](https://pub.dev/packages/flutter_blue_plus)
- universal_ble documentation: [pub.dev](https://pub.dev/packages/universal_ble)

## Quick Start for Implementation

1. **Clone and checkout:**
   ```bash
   git clone <repo-url>
   cd reaprime
   git checkout fix/ble-uuids
   ```

2. **Verify current state:**
   ```bash
   git log --oneline -10  # Should show 6c52dcc at top
   flutter test           # All tests should pass
   flutter analyze        # No errors
   ```

3. **Follow implementation plan:**
   - Read `doc/plans/2026-02-23-ble-scan-refactor.md`
   - Use TDD approach: test → fail → implement → pass → commit
   - 17 tasks, each is 2-5 minutes

4. **Run with simulated devices:**
   ```bash
   flutter run --dart-define=simulate=1
   ```

5. **Test with real hardware:**
   - Decent Scale, Skale2 on Android 9/12 (primary targets)
   - Other scales for regression testing





















