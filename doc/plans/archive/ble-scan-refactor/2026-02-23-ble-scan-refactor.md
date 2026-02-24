# BLE Scan Refactor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace fragile UUID-based BLE scan filtering with robust name-based discovery and post-connection service verification.

**Architecture:** Unfiltered BLE scans with software-side name matching via `DeviceMatcher` utility. Service verification during `onConnect()` ensures correct device type. Eliminates `MachineParser` from discovery flow.

**Tech Stack:** Flutter, Dart, flutter_blue_plus, universal_ble, RxDart

---

## Prerequisites & Context

### Branch & Codebase State

**Branch:** `fix/ble-uuids`  
**Last commit:** `6c52dcc add proposal for scan rewrite`

**Verify you're on the right branch:**
```bash
git branch --show-current  # Should show: fix/ble-uuids
git log --oneline -5       # Should show 6c52dcc at top
```

**Design Document:** See `doc/plans/2026-02-23-ble-scan-refactor-design.md` for full architectural context and rationale.

### Completed Work on This Branch

✅ **BleServiceIdentifier** model and device migrations already implemented (commits `c2e37c7` through `9901e05`):

- `lib/src/models/device/ble_service_identifier.dart` - UUID abstraction with automatic short ↔ long conversion
- All 14 scale implementations migrated: DecentScale, Skale2, Felicita, Eureka, Acaia (2), Hiroia, BlackCoffee, Atomheart, Difluid, Varia, SmartChef, Bookoo
- UnifiedDe1 and Bengle migrated
- Discovery services use `BleServiceIdentifier` in `deviceMappings`

**Current Discovery Flow:**
1. Build list of service UUIDs from `deviceMappings`
2. Call `FlutterBluePlus.startScan(withServices: [uuids])`
3. Scan results filtered by BLE stack (Android) or software (BlueZ)
4. Match device by service UUID → lookup factory in `deviceMappings`
5. Create device → add to list

**Problem:**
- Android BLE stack only matches UUIDs in **primary advertisement packet**
- Many devices (Decent Scale, Skale2) put UUIDs in **scan response** instead
- Result: Devices never appear in scan results on Android 9/12
- BlueZ has filter-merge conflicts when multiple apps scan

### What We're Building

**New Discovery Flow:**
1. Start **unfiltered** scan: `FlutterBluePlus.startScan(oneByOne: true)` - NO `withServices`
2. Receive ALL BLE devices in scan results
3. Match by **advertised name** using `DeviceMatcher` utility
4. Add matched devices to list (NOT connected yet)
5. User selects device → `onConnect()` called
6. Device discovers services → verifies expected service UUID exists
7. If verification fails → throw exception, disconnect, remove from list

**Solution:** Name-based discovery + service verification = platform-resilient discovery.

### Key Files & Locations

**Files You'll Modify:**
- `lib/src/services/blue_plus_discovery_service.dart` - Primary discovery service (~250 lines)
- `lib/src/services/universal_ble_discovery_service.dart` - Cross-platform discovery (~200 lines)
- `lib/main.dart` - Contains `bleDeviceMappings` dictionary (~line 200, to be removed)
- All scale implementations in `lib/src/models/device/impl/*/` - Add service verification to `onConnect()`
- `lib/src/models/device/impl/de1/unified_de1/unified_de1.dart` - Add model warning

**Files You'll Create:**
- `lib/src/services/device_matcher.dart` - New utility for name-based matching
- `test/unit/services/device_matcher_test.dart` - Tests for DeviceMatcher

**Files You'll Delete:**
- `lib/src/models/device/impl/machine_parser.dart` - No longer needed

### Important Implementation Notes

**BleServiceIdentifier Usage:**
- All devices already have: `static final serviceIdentifier = BleServiceIdentifier.short('xxxx')`
- Service verification uses: `serviceIdentifier.long` (128-bit format) for matching
- Also check `.short` for compatibility with platforms that return short UUIDs
- Example: `if (!services.contains(serviceIdentifier.long) && !services.contains(serviceIdentifier.short)) { throw ... }`

**Discovery Service Behavior:**
- Discovery service creates device instances
- Discovery service does NOT call `onConnect()`
- Connection happens when user selects device from UI
- Service verification runs in device's `onConnect()` method

**MachineParser Removal:**
- Currently: MachineParser connects during scan to read model register, determine DE1 vs Bengle
- New: DeviceMatcher routes by name ("DE1" → UnifiedDe1, "Bengle" → Bengle)
- Safety: UnifiedDe1 logs warning if model >= 128 (indicates Bengle hardware)

**TDD Workflow:**
1. Write test with expected behavior
2. Run test → verify FAIL
3. Implement minimal code to pass
4. Run test → verify PASS
5. Commit with descriptive message
6. Move to next task

### Verification Commands

**Testing:**
```bash
# Run specific test file
flutter test test/unit/services/device_matcher_test.dart

# Run all tests
flutter test

# Run tests with verbose output
flutter test --reporter expanded

# Static analysis
flutter analyze

# Check specific file
flutter analyze lib/src/services/device_matcher.dart
```

**Running App:**
```bash
# Simulated devices (no hardware needed)
flutter run --dart-define=simulate=1

# Standard run (requires hardware)
./flutter_with_commit.sh run

# Run on specific device
flutter devices                    # List devices
flutter run -d <device-id>         # Run on specific device
```

**Git Workflow:**
```bash
# Check branch
git branch --show-current

# Stage changes
git add <files>

# Commit
git commit -m "feat: descriptive message"

# View recent commits
git log --oneline -10

# Check status
git status
```

### Device Name Reference

**For DeviceMatcher implementation, here are the advertised names:**

| Device Class | Advertised Name(s) | Implementation |
|--------------|-------------------|----------------|
| DecentScale | `"Decent Scale"` | DecentScale |
| Skale2Scale | `"Skale2"` | Skale2Scale |
| FelicitaArc | `"Felicita"`, `"Felicita Arc"` | FelicitaArc |
| EurekaScale | `"Eureka"`, `"Precisa"`, `"CFS-9002"`, `"Solo Barista"`, `"LSJ-001"` | EurekaScale |
| AcaiaScale | `"ACAIA"`, `"Acaia Lunar"`, `"Acaia Pearl"` | AcaiaScale |
| AcaiaPyxisScale | `"Acaia Pyxis"` | AcaiaPyxisScale |
| HiroiaScale | `"Hiroia"`, `"Jimmy"` | HiroiaScale |
| BlackCoffeeScale | `"Black"` (prefix) | BlackCoffeeScale |
| AtomheartScale | `"Atomheart"`, `"Eclair"` | AtomheartScale |
| DifluidScale | `"Difluid"` | DifluidScale |
| VariaAkuScale | `"Varia"`, `"AKU"` | VariaAkuScale |
| SmartChefScale | `"SmartChef"` | SmartChefScale |
| BookooScale | `"Bookoo"` | BookooScale |
| UnifiedDe1 | `"DE1"`, `"nrf5x"`, `"de1"` (prefix) | UnifiedDe1 |
| Bengle | `"Bengle"` | Bengle |

**Matching Strategy Notes:**
- Use exact match for unique names: `name == 'Decent Scale'`
- Use prefix for variations: `nameLower.startsWith('felicita')`
- Use contains for flexible names: `nameLower.contains('acaia')`
- Case-insensitive: Convert to lowercase before checking
- Order matters: Check Pyxis before generic Acaia (specificity)

---

## Task 1: Implement DeviceMatcher Utility

**Files:**
- Create: `lib/src/services/device_matcher.dart`
- Create: `test/unit/services/device_matcher_test.dart`

**Step 1: Write failing test for exact name match**

Create `test/unit/services/device_matcher_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/decent_scale/scale.dart';
import 'package:reaprime/src/models/device/impl/skale/skale2_scale.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';
import 'package:reaprime/src/services/device_matcher.dart';

@GenerateMocks([BLETransport])
import 'device_matcher_test.mocks.dart';

void main() {
  group('DeviceMatcher', () {
    late MockBLETransport mockTransport;

    setUp(() {
      mockTransport = MockBLETransport();
      when(mockTransport.id).thenReturn('AA:BB:CC:DD:EE:FF');
    });

    test('exact match for Decent Scale', () async {
      final device = await DeviceMatcher.match(
        transport: mockTransport,
        advertisedName: 'Decent Scale',
      );

      expect(device, isNotNull);
      expect(device, isA<DecentScale>());
    });

    test('exact match for Skale2', () async {
      final device = await DeviceMatcher.match(
        transport: mockTransport,
        advertisedName: 'Skale2',
      );

      expect(device, isNotNull);
      expect(device, isA<Skale2Scale>());
    });

    test('returns null for unknown name', () async {
      final device = await DeviceMatcher.match(
        transport: mockTransport,
        advertisedName: 'Unknown Device',
      );

      expect(device, isNull);
    });
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/unit/services/device_matcher_test.dart`

Expected: FAIL with "DeviceMatcher not found"

**Step 3: Write minimal DeviceMatcher implementation**

Create `lib/src/services/device_matcher.dart`:

```dart
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/decent_scale/scale.dart';
import 'package:reaprime/src/models/device/impl/skale/skale2_scale.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';

class DeviceMatcher {
  static Future<Device?> match({
    required BLETransport transport,
    required String advertisedName,
  }) async {
    final name = advertisedName;

    // Exact matches
    if (name == 'Decent Scale') return DecentScale(transport: transport);
    if (name == 'Skale2') return Skale2Scale(transport: transport);

    return null;
  }
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/unit/services/device_matcher_test.dart`

Expected: PASS

**Step 5: Commit**

```bash
git add lib/src/services/device_matcher.dart test/unit/services/device_matcher_test.dart
git commit -m "feat: add DeviceMatcher with exact name matching"
```

---

## Task 2: Add Prefix and Contains Matching

**Files:**
- Modify: `lib/src/services/device_matcher.dart`
- Modify: `test/unit/services/device_matcher_test.dart`

**Step 1: Write failing tests for prefix/contains matching**

Add to `test/unit/services/device_matcher_test.dart`:

```dart
import 'package:reaprime/src/models/device/impl/felicita/arc.dart';
import 'package:reaprime/src/models/device/impl/acaia/acaia_scale.dart';
import 'package:reaprime/src/models/device/impl/acaia/acaia_pyxis_scale.dart';

// In the test group:

test('prefix match for Felicita', () async {
  final device = await DeviceMatcher.match(
    transport: mockTransport,
    advertisedName: 'Felicita Arc',
  );

  expect(device, isNotNull);
  expect(device, isA<FelicitaArc>());
});

test('contains match for Acaia', () async {
  final device = await DeviceMatcher.match(
    transport: mockTransport,
    advertisedName: 'ACAIA LUNAR',
  );

  expect(device, isNotNull);
  expect(device, isA<AcaiaScale>());
});

test('contains match for Acaia Pyxis', () async {
  final device = await DeviceMatcher.match(
    transport: mockTransport,
    advertisedName: 'Acaia Pyxis',
  );

  expect(device, isNotNull);
  expect(device, isA<AcaiaPyxisScale>());
});

test('matching is case-insensitive', () async {
  final device = await DeviceMatcher.match(
    transport: mockTransport,
    advertisedName: 'acaia pearl',
  );

  expect(device, isNotNull);
  expect(device, isA<AcaiaScale>());
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/unit/services/device_matcher_test.dart`

Expected: Multiple FAILs for new test cases

**Step 3: Add prefix/contains matching logic**

Update `lib/src/services/device_matcher.dart`:

```dart
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/acaia/acaia_pyxis_scale.dart';
import 'package:reaprime/src/models/device/impl/acaia/acaia_scale.dart';
import 'package:reaprime/src/models/device/impl/decent_scale/scale.dart';
import 'package:reaprime/src/models/device/impl/felicita/arc.dart';
import 'package:reaprime/src/models/device/impl/skale/skale2_scale.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';

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

    // Prefix matches
    if (nameLower.startsWith('felicita')) return FelicitaArc(transport: transport);

    // Contains matches
    if (nameLower.contains('acaia')) {
      if (nameLower.contains('pyxis')) return AcaiaPyxisScale(transport: transport);
      return AcaiaScale(transport: transport);
    }

    return null;
  }
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/unit/services/device_matcher_test.dart`

Expected: PASS

**Step 5: Commit**

```bash
git add lib/src/services/device_matcher.dart test/unit/services/device_matcher_test.dart
git commit -m "feat: add prefix and contains matching to DeviceMatcher"
```

---

## Task 3: Add All Remaining Device Matches

**Files:**
- Modify: `lib/src/services/device_matcher.dart`
- Modify: `test/unit/services/device_matcher_test.dart`

**Step 1: Write tests for all remaining devices**

Add to `test/unit/services/device_matcher_test.dart`:

```dart
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1.dart';
import 'package:reaprime/src/models/device/impl/bengle/bengle.dart';
import 'package:reaprime/src/models/device/impl/eureka/eureka_scale.dart';
import 'package:reaprime/src/models/device/impl/smartchef/smartchef_scale.dart';
import 'package:reaprime/src/models/device/impl/varia/varia_aku_scale.dart';
import 'package:reaprime/src/models/device/impl/hiroia/hiroia_scale.dart';
import 'package:reaprime/src/models/device/impl/difluid/difluid_scale.dart';
import 'package:reaprime/src/models/device/impl/blackcoffee/blackcoffee_scale.dart';
import 'package:reaprime/src/models/device/impl/atomheart/atomheart_scale.dart';
import 'package:reaprime/src/models/device/impl/bookoo/miniscale.dart';

// Add these tests:

test('DE1 exact match', () async {
  final device = await DeviceMatcher.match(
    transport: mockTransport,
    advertisedName: 'DE1',
  );

  expect(device, isA<UnifiedDe1>());
});

test('nrf5x matches to DE1', () async {
  final device = await DeviceMatcher.match(
    transport: mockTransport,
    advertisedName: 'nrf5x',
  );

  expect(device, isA<UnifiedDe1>());
});

test('Bengle exact match', () async {
  final device = await DeviceMatcher.match(
    transport: mockTransport,
    advertisedName: 'Bengle',
  );

  expect(device, isA<Bengle>());
});

test('Eureka Precisa matches to EurekaScale', () async {
  final device = await DeviceMatcher.match(
    transport: mockTransport,
    advertisedName: 'Eureka Precisa',
  );

  expect(device, isA<EurekaScale>());
});

test('Solo Barista matches to EurekaScale', () async {
  final device = await DeviceMatcher.match(
    transport: mockTransport,
    advertisedName: 'Solo Barista',
  );

  expect(device, isA<EurekaScale>());
});

test('SmartChef matches', () async {
  final device = await DeviceMatcher.match(
    transport: mockTransport,
    advertisedName: 'SmartChef Scale',
  );

  expect(device, isA<SmartChefScale>());
});

test('Varia AKU matches', () async {
  final device = await DeviceMatcher.match(
    transport: mockTransport,
    advertisedName: 'Varia AKU',
  );

  expect(device, isA<VariaAkuScale>());
});

test('Hiroia Jimmy matches', () async {
  final device = await DeviceMatcher.match(
    transport: mockTransport,
    advertisedName: 'Hiroia Jimmy',
  );

  expect(device, isA<HiroiaScale>());
});

test('Difluid matches', () async {
  final device = await DeviceMatcher.match(
    transport: mockTransport,
    advertisedName: 'Difluid R2',
  );

  expect(device, isA<DifluidScale>());
});

test('BlackCoffee matches', () async {
  final device = await DeviceMatcher.match(
    transport: mockTransport,
    advertisedName: 'Black Mirror',
  );

  expect(device, isA<BlackCoffeeScale>());
});

test('Atomheart matches', () async {
  final device = await DeviceMatcher.match(
    transport: mockTransport,
    advertisedName: 'Atomheart Eclair',
  );

  expect(device, isA<AtomheartScale>());
});

test('Bookoo matches', () async {
  final device = await DeviceMatcher.match(
    transport: mockTransport,
    advertisedName: 'Bookoo Mini',
  );

  expect(device, isA<BookooScale>());
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/unit/services/device_matcher_test.dart`

Expected: Multiple FAILs

**Step 3: Add all device matching logic**

Update `lib/src/services/device_matcher.dart`:

```dart
import 'package:reaprime/src/models/device/device.dart';
import 'package:reaprime/src/models/device/impl/acaia/acaia_pyxis_scale.dart';
import 'package:reaprime/src/models/device/impl/acaia/acaia_scale.dart';
import 'package:reaprime/src/models/device/impl/atomheart/atomheart_scale.dart';
import 'package:reaprime/src/models/device/impl/bengle/bengle.dart';
import 'package:reaprime/src/models/device/impl/blackcoffee/blackcoffee_scale.dart';
import 'package:reaprime/src/models/device/impl/bookoo/miniscale.dart';
import 'package:reaprime/src/models/device/impl/de1/unified_de1/unified_de1.dart';
import 'package:reaprime/src/models/device/impl/decent_scale/scale.dart';
import 'package:reaprime/src/models/device/impl/difluid/difluid_scale.dart';
import 'package:reaprime/src/models/device/impl/eureka/eureka_scale.dart';
import 'package:reaprime/src/models/device/impl/felicita/arc.dart';
import 'package:reaprime/src/models/device/impl/hiroia/hiroia_scale.dart';
import 'package:reaprime/src/models/device/impl/skale/skale2_scale.dart';
import 'package:reaprime/src/models/device/impl/smartchef/smartchef_scale.dart';
import 'package:reaprime/src/models/device/impl/varia/varia_aku_scale.dart';
import 'package:reaprime/src/models/device/transport/ble_transport.dart';

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

    // DE1 family
    if (name == 'DE1' || name == 'nrf5x' || nameLower.startsWith('de1')) {
      return UnifiedDe1(transport: transport);
    }
    if (name == 'Bengle') return Bengle(transport: transport);

    // Prefix matches
    if (nameLower.startsWith('felicita')) return FelicitaArc(transport: transport);
    if (nameLower.startsWith('black')) return BlackCoffeeScale(transport: transport);

    // Contains matches
    if (nameLower.contains('acaia')) {
      if (nameLower.contains('pyxis')) return AcaiaPyxisScale(transport: transport);
      return AcaiaScale(transport: transport);
    }

    if (nameLower.contains('eureka') || nameLower.contains('precisa') || 
        nameLower.contains('cfs-9002')) {
      return EurekaScale(transport: transport);
    }

    if (nameLower.contains('solo barista') || nameLower.contains('lsj-001')) {
      return EurekaScale(transport: transport);
    }

    if (nameLower.contains('smartchef')) return SmartChefScale(transport: transport);
    if (nameLower.contains('aku') || nameLower.contains('varia')) {
      return VariaAkuScale(transport: transport);
    }
    if (nameLower.contains('hiroia') || nameLower.contains('jimmy')) {
      return HiroiaScale(transport: transport);
    }
    if (nameLower.contains('difluid')) return DifluidScale(transport: transport);
    if (nameLower.contains('atomheart') || nameLower.contains('eclair')) {
      return AtomheartScale(transport: transport);
    }
    if (nameLower.contains('bookoo')) return BookooScale(transport: transport);

    return null;
  }
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/unit/services/device_matcher_test.dart`

Expected: PASS

**Step 5: Commit**

```bash
git add lib/src/services/device_matcher.dart test/unit/services/device_matcher_test.dart
git commit -m "feat: add complete device matching for all supported devices"
```

---

## Task 4: Update BluePlusDiscoveryService - Add State Tracking

**Files:**
- Modify: `lib/src/services/blue_plus_discovery_service.dart`

**Step 1: Add _isScanning flag**

At the top of the `BluePlusDiscoveryService` class, add:

```dart
bool _isScanning = false;
```

**Step 2: Add scan state check to scanForDevices**

Update the `scanForDevices()` method to check `_isScanning` at the start:

```dart
@override
Future<void> scanForDevices() async {
  if (_isScanning) {
    _log.warning('Scan already in progress, ignoring request');
    return;
  }

  _isScanning = true;

  try {
    // Existing scan logic...
  } finally {
    _isScanning = false;
  }
}
```

**Step 3: Run analyzer**

Run: `flutter analyze lib/src/services/blue_plus_discovery_service.dart`

Expected: No errors

**Step 4: Commit**

```bash
git add lib/src/services/blue_plus_discovery_service.dart
git commit -m "feat: add scan state tracking to BluePlusDiscoveryService"
```

---

## Task 5: Update BluePlusDiscoveryService - Remove UUID Filtering

**Files:**
- Modify: `lib/src/services/blue_plus_discovery_service.dart`

**Step 1: Remove _buildScanGuids() and _findFactory() methods**

Delete these two methods from the class.

**Step 2: Update scanForDevices to use unfiltered scan**

Replace the `FlutterBluePlus.startScan()` call:

```dart
// OLD:
await FlutterBluePlus.startScan(
  withServices: _buildScanGuids(),
  oneByOne: true,
);

// NEW:
await FlutterBluePlus.startScan(oneByOne: true);
```

**Step 3: Import DeviceMatcher**

Add at top of file:

```dart
import 'package:reaprime/src/services/device_matcher.dart';
```

**Step 4: Update scan result handling to use DeviceMatcher**

Replace the service UUID matching logic in the `onScanResults.listen` callback:

```dart
var subscription = FlutterBluePlus.onScanResults.listen((results) async {
  if (results.isEmpty) return;
  
  ScanResult r = results.last;
  final deviceId = r.device.remoteId.str;
  final name = r.advertisementData.advName;

  // Check if device already exists or is being created
  if (_devices.firstWhereOrNull((d) => d.deviceId == deviceId) != null) {
    _log.fine("duplicate device scanned $deviceId, $name");
    return;
  }

  if (_devicesBeingCreated.contains(deviceId)) {
    _log.fine("device already being created $deviceId, $name");
    return;
  }

  // Try DeviceMatcher
  _devicesBeingCreated.add(deviceId);
  
  if (Platform.isLinux) {
    _pendingDevices.add(_PendingDevice(deviceId, name));
    _log.info("Queued $deviceId for post-scan processing");
  } else {
    _createDeviceFromName(deviceId, name);
  }
}, onError: (e) => _log.warning(e));
```

**Step 5: Run analyzer**

Run: `flutter analyze lib/src/services/blue_plus_discovery_service.dart`

Expected: Errors about `_createDeviceFromName` not existing (we'll add it next)

**Step 6: Commit intermediate progress**

```bash
git add lib/src/services/blue_plus_discovery_service.dart
git commit -m "refactor: remove UUID filtering from BluePlusDiscoveryService"
```

---

## Task 6: Update BluePlusDiscoveryService - Add Name-Based Device Creation

**Files:**
- Modify: `lib/src/services/blue_plus_discovery_service.dart`

**Step 1: Replace _createDevice method with _createDeviceFromName**

Replace the existing `_createDevice` method:

```dart
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

    // Double-check device wasn't added while we were creating it
    if (_devices.firstWhereOrNull((d) => d.deviceId == deviceId) != null) {
      _log.fine("Device $deviceId already added, skipping duplicate");
      return;
    }

    // Add device to list
    _devices.add(device);
    _deviceStreamController.add(_devices);
    _log.info('Device $deviceId "$name" added successfully');

    // Set up cleanup listener
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

**Step 2: Update _PendingDevice class**

Replace the `_PendingDevice` class at the bottom of the file:

```dart
class _PendingDevice {
  final String deviceId;
  final String name;
  _PendingDevice(this.deviceId, this.name);
}
```

**Step 3: Update Linux pending device processing**

Find the Linux-specific processing block and update:

```dart
if (_pendingDevices.isNotEmpty) {
  _log.info("Processing ${_pendingDevices.length} queued BLE devices");
  await Future.delayed(Duration(milliseconds: 200));
  for (final pending in _pendingDevices) {
    await _createDeviceFromName(pending.deviceId, pending.name);
  }
  _pendingDevices.clear();
}
```

**Step 4: Remove old deviceMappings field**

Delete the `deviceMappings` field and constructor parameter - no longer needed.

**Step 5: Run analyzer**

Run: `flutter analyze lib/src/services/blue_plus_discovery_service.dart`

Expected: No errors

**Step 6: Commit**

```bash
git add lib/src/services/blue_plus_discovery_service.dart
git commit -m "feat: implement name-based device creation in BluePlusDiscoveryService"
```

---

## Task 7: Update BluePlusDiscoveryService - Update scanForSpecificDevices

**Files:**
- Modify: `lib/src/services/blue_plus_discovery_service.dart`

**Step 1: Update scanForSpecificDevices to use DeviceMatcher**

Replace the scan results handling in `scanForSpecificDevices()`:

```dart
@override
Future<void> scanForSpecificDevices(List<String> deviceIds) async {
  final bleIds = deviceIds.where(_isBleDeviceId).toList();
  if (bleIds.isEmpty) {
    _log.fine('scanForSpecificDevices: no BLE IDs in $deviceIds, skipping');
    return;
  }

  _log.info('Starting targeted BLE scan for devices $bleIds');

  var subscription = FlutterBluePlus.onScanResults.listen((results) {
    if (results.isEmpty) return;
    final r = results.last;
    final foundId = r.device.remoteId.str;
    final name = r.advertisementData.advName;

    if (_devices.firstWhereOrNull((d) => d.deviceId == foundId) != null) return;
    if (_devicesBeingCreated.contains(foundId)) return;

    _devicesBeingCreated.add(foundId);
    _createDeviceFromName(foundId, name);
  }, onError: (e) => _log.warning('Targeted scan error: $e'));

  FlutterBluePlus.cancelWhenScanComplete(subscription);

  await FlutterBluePlus.adapterState
      .where((val) => val == BluetoothAdapterState.on)
      .first;

  // Unfiltered scan with specific device IDs
  await FlutterBluePlus.startScan(
    withRemoteIds: bleIds,
    oneByOne: true,
  );

  final timeout = Platform.isLinux
      ? const Duration(seconds: 20)
      : const Duration(seconds: 8);
  await Future.delayed(timeout, () async {
    await FlutterBluePlus.stopScan();
  });

  _deviceStreamController.add(_devices.toList());
}
```

**Step 2: Run analyzer**

Run: `flutter analyze lib/src/services/blue_plus_discovery_service.dart`

Expected: No errors

**Step 3: Commit**

```bash
git add lib/src/services/blue_plus_discovery_service.dart
git commit -m "refactor: update scanForSpecificDevices to use name-based matching"
```

---

## Task 8: Update UniversalBleDiscoveryService

**Files:**
- Modify: `lib/src/services/universal_ble_discovery_service.dart`

**Step 1: Add scan state tracking**

Add at top of class:

```dart
bool _isScanning = false;
```

**Step 2: Remove deviceMappings field**

Delete the `deviceMappings` field and its initialization in the constructor.

**Step 3: Add DeviceMatcher import**

```dart
import 'package:reaprime/src/services/device_matcher.dart';
```

**Step 4: Update scanForDevices with scan state check**

Wrap the method in a scan state check:

```dart
@override
Future<void> scanForDevices() async {
  if (_isScanning) {
    log.warning('Scan already in progress, ignoring request');
    return;
  }

  _isScanning = true;

  try {
    // Existing logic...
  } finally {
    _isScanning = false;
  }
}
```

**Step 5: Update scan to be unfiltered**

Replace service filtering logic:

```dart
// OLD:
final List<String> services = [];
if (!Platform.isLinux) {
  for (final identifier in deviceMappings.keys) {
    services.add(BleUuidParser.string(identifier.short));
    services.add(BleUuidParser.string(identifier.long));
  }
}

// NEW:
final List<String> services = []; // Empty = unfiltered

final filter = ScanFilter(withServices: services);
await UniversalBle.startScan(scanFilter: filter);

// Remove getSystemDevices call with services - use empty list
final systemDevices = await UniversalBle.getSystemDevices(
  withServices: [],
);
```

**Step 6: Update _deviceScanned to use DeviceMatcher**

Replace the method:

```dart
Future<void> _deviceScanned(BleDevice device) async {
  _currentlyScanning.add(device.deviceId);

  try {
    final name = device.name ?? '';
    if (name.isEmpty) {
      _currentlyScanning.remove(device.deviceId);
      return;
    }

    if (_devices.containsKey(device.deviceId.toString())) {
      _currentlyScanning.remove(device.deviceId);
      return;
    }

    final matchedDevice = await DeviceMatcher.match(
      transport: UniversalBleTransport(device: device),
      advertisedName: name,
    );

    if (matchedDevice != null) {
      _devices[device.deviceId.toString()] = matchedDevice;
      _deviceStreamController.add(_devices.values.toList());
      log.fine("found new device: ${device.name}");

      _connections[device.deviceId.toString()] = _devices[device.deviceId
              .toString()]!
          .connectionState
          .listen((connectionState) {
        if (connectionState == ConnectionState.disconnected) {
          _devices.remove(device.deviceId.toString());
          _deviceStreamController.add(_devices.values.toList());
        }
      });
    }
  } finally {
    _currentlyScanning.remove(device.deviceId);
  }
}
```

**Step 7: Run analyzer**

Run: `flutter analyze lib/src/services/universal_ble_discovery_service.dart`

Expected: No errors

**Step 8: Commit**

```bash
git add lib/src/services/universal_ble_discovery_service.dart
git commit -m "refactor: update UniversalBleDiscoveryService to use name-based matching"
```

---

## Task 9: Update main.dart - Remove DeviceMapping References

**Files:**
- Modify: `lib/main.dart`

**Step 1: Remove bleDeviceMappings dictionary**

Delete the entire `bleDeviceMappings` block (around line 200).

**Step 2: Update discovery service instantiation**

Find where discovery services are created and remove the `mappings` parameter:

```dart
// OLD:
services.add(
  BluePlusDiscoveryService(mappings: bleDeviceMappings),
);

// NEW:
services.add(
  BluePlusDiscoveryService(),
);

// Similar for UniversalBleDiscoveryService
```

**Step 3: Run analyzer**

Run: `flutter analyze lib/main.dart`

Expected: No errors

**Step 4: Commit**

```bash
git add lib/main.dart
git commit -m "refactor: remove device mappings from main.dart discovery service setup"
```

---

## Task 10: Add Service Verification to Skale2Scale

**Files:**
- Modify: `lib/src/models/device/impl/skale/skale2_scale.dart`

**Step 1: Add service verification to onConnect**

Find the `onConnect()` method and add verification after `discoverServices()`:

```dart
@override
Future<void> onConnect() async {
  if (await _transport.connectionState.first == true) {
    return;
  }
  _connectionStateController.add(ConnectionState.connecting);

  StreamSubscription<bool>? disconnectSub;

  try {
    await _transport.connect();

    disconnectSub = _transport.connectionState
        .where((state) => !state)
        .listen((_) {
      _connectionStateController.add(ConnectionState.disconnected);
      disconnectSub?.cancel();
    });

    final services = await _transport.discoverServices();

    // NEW: Verify expected service exists
    if (!services.contains(serviceIdentifier.long) &&
        !services.contains(serviceIdentifier.short)) {
      throw Exception(
        'Expected service ${serviceIdentifier.long} not found. '
        'Discovered services: $services'
      );
    }

    await _initScale();
    _connectionStateController.add(ConnectionState.connected);
  } catch (e) {
    disconnectSub?.cancel();
    _connectionStateController.add(ConnectionState.disconnected);
    try {
      await _transport.disconnect();
    } catch (_) {}
    rethrow;
  }
}
```

**Step 2: Run analyzer**

Run: `flutter analyze lib/src/models/device/impl/skale/skale2_scale.dart`

Expected: No errors

**Step 3: Commit**

```bash
git add lib/src/models/device/impl/skale/skale2_scale.dart
git commit -m "feat: add service verification to Skale2Scale onConnect"
```

---

## Task 11: Add Service Verification to Remaining Scales (Batch 1)

**Files:**
- Modify: `lib/src/models/device/impl/decent_scale/scale.dart`
- Modify: `lib/src/models/device/impl/felicita/arc.dart`
- Modify: `lib/src/models/device/impl/eureka/eureka_scale.dart`
- Modify: `lib/src/models/device/impl/acaia/acaia_scale.dart`

**Step 1: Add service verification to DecentScale**

Add after `discoverServices()` in `onConnect()`:

```dart
final services = await _transport.discoverServices();

if (!services.contains(serviceIdentifier.long) &&
    !services.contains(serviceIdentifier.short)) {
  throw Exception(
    'Expected service ${serviceIdentifier.long} not found. '
    'Discovered services: $services'
  );
}
```

**Step 2: Add service verification to FelicitaArc**

Same pattern in `onConnect()`.

**Step 3: Add service verification to EurekaScale**

Same pattern in `onConnect()`.

**Step 4: Add service verification to AcaiaScale**

Same pattern in `onConnect()`.

**Step 5: Run analyzer**

Run: `flutter analyze lib/src/models/device/impl/`

Expected: No errors

**Step 6: Commit**

```bash
git add lib/src/models/device/impl/decent_scale/ lib/src/models/device/impl/felicita/ lib/src/models/device/impl/eureka/ lib/src/models/device/impl/acaia/
git commit -m "feat: add service verification to DecentScale, FelicitaArc, EurekaScale, AcaiaScale"
```

---

## Task 12: Add Service Verification to Remaining Scales (Batch 2)

**Files:**
- Modify: `lib/src/models/device/impl/hiroia/hiroia_scale.dart`
- Modify: `lib/src/models/device/impl/blackcoffee/blackcoffee_scale.dart`
- Modify: `lib/src/models/device/impl/atomheart/atomheart_scale.dart`
- Modify: `lib/src/models/device/impl/difluid/difluid_scale.dart`
- Modify: `lib/src/models/device/impl/varia/varia_aku_scale.dart`
- Modify: `lib/src/models/device/impl/smartchef/smartchef_scale.dart`
- Modify: `lib/src/models/device/impl/bookoo/miniscale.dart`
- Modify: `lib/src/models/device/impl/acaia/acaia_pyxis_scale.dart`

**Step 1-8: Add service verification to each scale**

Apply the same service verification pattern to all remaining scales.

**Step 9: Run analyzer**

Run: `flutter analyze lib/src/models/device/impl/`

Expected: No errors

**Step 10: Commit**

```bash
git add lib/src/models/device/impl/hiroia/ lib/src/models/device/impl/blackcoffee/ lib/src/models/device/impl/atomheart/ lib/src/models/device/impl/difluid/ lib/src/models/device/impl/varia/ lib/src/models/device/impl/smartchef/ lib/src/models/device/impl/bookoo/ lib/src/models/device/impl/acaia/
git commit -m "feat: add service verification to all remaining scales"
```

---

## Task 13: Add Service Verification to UnifiedDe1

**Files:**
- Modify: `lib/src/models/device/impl/de1/unified_de1/unified_de1.dart`

**Step 1: Check current onConnect implementation**

`UnifiedDe1` may not have a simple `onConnect()` - it uses a transport wrapper. Check the file structure.

**Step 2: Add service verification in appropriate location**

If `UnifiedDe1` has `onConnect()`, add verification there. Otherwise, add to the connection logic in the transport initialization.

**Step 3: Run analyzer**

Run: `flutter analyze lib/src/models/device/impl/de1/`

Expected: No errors

**Step 4: Commit**

```bash
git add lib/src/models/device/impl/de1/
git commit -m "feat: add service verification to UnifiedDe1"
```

---

## Task 14: Add Model Warning to UnifiedDe1

**Files:**
- Modify: `lib/src/models/device/impl/de1/unified_de1/unified_de1.dart`

**Step 1: Find where model is read from MMR**

Search for `MMRItem.v13Model` or similar model reading logic.

**Step 2: Add warning check after model read**

Add after the model value is retrieved:

```dart
final model = await _readMMRInt(MMRItem.v13Model);

if (model >= 128) {
  _log.warning(
    'Device model=$model indicates Bengle hardware, but initialized as UnifiedDe1. '
    'Device may have advertised incorrect name during discovery. '
    'Functionality may be limited.'
  );
}
```

**Step 3: Run analyzer**

Run: `flutter analyze lib/src/models/device/impl/de1/`

Expected: No errors

**Step 4: Commit**

```bash
git add lib/src/models/device/impl/de1/
git commit -m "feat: add Bengle model warning to UnifiedDe1"
```

---

## Task 15: Remove MachineParser

**Files:**
- Delete: `lib/src/models/device/impl/machine_parser.dart`
- Modify: Any files that import `machine_parser.dart`

**Step 1: Search for MachineParser imports**

Run: `grep -r "machine_parser" lib/`

**Step 2: Remove imports**

Delete any import statements for `machine_parser.dart`.

**Step 3: Delete the file**

```bash
rm lib/src/models/device/impl/machine_parser.dart
```

**Step 4: Run analyzer**

Run: `flutter analyze`

Expected: No errors

**Step 5: Commit**

```bash
git add -A
git commit -m "refactor: remove MachineParser from codebase"
```

---

## Task 16: Update LinuxBleDiscoveryService

**Files:**
- Modify: `lib/src/services/ble/linux_ble_discovery_service.dart`

**Step 1: Apply same changes as BluePlusDiscoveryService**

- Add `_isScanning` flag
- Remove UUID filtering
- Use `DeviceMatcher`
- Update device creation logic

**Step 2: Run analyzer**

Run: `flutter analyze lib/src/services/ble/linux_ble_discovery_service.dart`

Expected: No errors

**Step 3: Commit**

```bash
git add lib/src/services/ble/linux_ble_discovery_service.dart
git commit -m "refactor: update LinuxBleDiscoveryService to use name-based matching"
```

---

## Task 17: Run Full Test Suite

**Files:**
- None (verification step)

**Step 1: Run all tests**

Run: `flutter test`

Expected: All tests PASS

**Step 2: If failures occur, fix them**

Investigate and fix any test failures related to:
- Discovery service changes
- Device creation logic
- Service verification

**Step 3: Run analyzer on entire codebase**

Run: `flutter analyze`

Expected: No errors or warnings

**Step 4: Commit any fixes**

```bash
git add -A
git commit -m "fix: resolve test failures from scan refactor"
```

---

## Task 18: Manual Testing Documentation

**Files:**
- Create: `doc/testing/2026-02-23-ble-scan-refactor-test.md`

**Step 1: Create test documentation template**

```markdown
# BLE Scan Refactor Testing Results

**Date:** 2026-02-23
**Tester:** [Name]
**Branch:** fix/ble-uuids

## Test Environment

- Device: [Android/iOS/Linux/macOS/Windows]
- OS Version: [e.g., Android 12]
- App Version: [git commit hash]

## Test Cases

### Discovery Tests

#### Test 1: Decent Scale Discovery
- [ ] Turn on Decent Scale
- [ ] Tap scan in app
- [ ] Scale appears in device list
- [ ] Logs show: "Matched device ... Decent Scale"
- [ ] Scale connects successfully

**Result:** PASS / FAIL
**Notes:**

#### Test 2: Skale2 Discovery
- [ ] Turn on Skale2
- [ ] Tap scan in app
- [ ] Scale appears in device list
- [ ] Scale connects successfully

**Result:** PASS / FAIL
**Notes:**

#### Test 3: Multiple Devices
- [ ] Turn on DE1 machine + scale
- [ ] Tap scan
- [ ] Both devices appear
- [ ] Both connect successfully

**Result:** PASS / FAIL
**Notes:**

#### Test 4: Unknown Device
- [ ] Scan with non-coffee BLE device nearby
- [ ] Unknown device does NOT appear in list
- [ ] No errors in logs

**Result:** PASS / FAIL
**Notes:**

### Service Verification Tests

#### Test 5: Wrong Device Name
- [ ] If possible, test device with mismatched name/service UUID
- [ ] Device should fail service verification
- [ ] Error logged: "Expected service X not found"
- [ ] Device removed from list

**Result:** PASS / FAIL
**Notes:**

### Regression Tests

#### Test 6: Existing Devices Still Work
- [ ] Test Felicita Arc
- [ ] Test Acaia scale
- [ ] Test Hiroia Jimmy
- [ ] All connect as before

**Result:** PASS / FAIL
**Notes:**

## Issues Found

[List any issues discovered during testing]

## Logs

[Paste relevant log excerpts here]
```

**Step 2: Commit the template**

```bash
git add doc/testing/2026-02-23-ble-scan-refactor-test.md
git commit -m "docs: add manual testing documentation template"
```

---

## Task 19: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Update BLE UUID section in Conventions & Gotchas**

Replace or update the BLE UUID entry:

```markdown
- **BLE Discovery:** Device discovery uses unfiltered scans with name-based matching (`DeviceMatcher`). Service verification happens during `onConnect()` using `BleServiceIdentifier`. All BLE operations use 128-bit UUID format for maximum platform compatibility.
```

**Step 2: Run analyzer**

Run: `flutter analyze`

Expected: No errors

**Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with new BLE discovery approach"
```

---

## Verification Checklist

Before considering this task complete, verify:

- [ ] All unit tests pass for `DeviceMatcher`
- [ ] Discovery services use unfiltered scans
- [ ] All devices have service verification in `onConnect()`
- [ ] `MachineParser` removed from codebase
- [ ] No device mappings in `main.dart`
- [ ] Scan state tracking prevents concurrent scans
- [ ] Full test suite passes
- [ ] No analyzer errors or warnings
- [ ] Manual testing on Android 9/12 (if possible)
- [ ] Documentation updated

## Success Criteria

1. Decent Scale and Skale2 discovered on Android 9/12 (name-based, not UUID filter)
2. Service verification catches mismatched devices
3. All existing devices continue to work
4. No test failures or analyzer errors
5. Clean commit history with logical progression
6. Unfiltered scans work on all platforms

## Notes for Implementer

- If a device doesn't have a simple `onConnect()` method, add service verification in the connection initialization logic
- Service verification should check both `.long` and `.short` forms of the service identifier
- The model warning in `UnifiedDe1` is non-fatal - device continues to operate
- Test with `--dart-define=simulate=1` for basic smoke testing without hardware



