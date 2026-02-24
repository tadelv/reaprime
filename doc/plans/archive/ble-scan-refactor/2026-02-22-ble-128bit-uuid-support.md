# BLE 128-bit UUID Support Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix BLE scale discovery on Android 9/12 by supporting both 16-bit and 128-bit UUIDs in scanning and device operations.

**Architecture:** Create `BleServiceIdentifier` model to encapsulate UUID conversion. Update all BLE devices to use static identifiers with 128-bit operations. Modify discovery services to scan for both short and long UUID formats simultaneously.

**Tech Stack:** Flutter, Dart, flutter_blue_plus, universal_ble, RxDart

---

## Prerequisites & Context

**Branch:** You are currently on branch `fix/ble-uuids`

**Design Document:** See `doc/plans/2026-02-22-ble-128bit-uuid-support-design.md` for full architectural context.

**Problem:** Users report BLE scales (Decent Scale, Skale2) not appearing in device discovery on Android 9 and 12. Scales never appear in logs, even at scan time. Hypothesis: older BLE firmware/stacks may not properly recognize 16-bit short UUIDs.

**Solution:** Dual-UUID scanning - scan for both short (e.g., `fff0`) and expanded 128-bit (e.g., `0000fff0-0000-1000-8000-00805f9b34fb`) UUIDs simultaneously. Use 128-bit format for all post-discovery operations.

**Key Files to Understand:**
- Current UUID usage: All devices use `static String serviceUUID = 'fff0'` pattern
- Discovery services: `lib/src/services/blue_plus_discovery_service.dart`, `lib/src/services/universal_ble_discovery_service.dart`
- Device mappings: `lib/main.dart` around line 200
- Example device: `lib/src/models/device/impl/skale/skale2_scale.dart`

**Important Notes:**
- Solo Barista scale uses `fff0` UUID but instantiates `EurekaScale` (same protocol)
- Standard battery service/characteristic: `180f`/`2a19` (used by many scales)
- Test directory structure: `test/unit/models/` for model tests
- Always run `flutter analyze` after changes to catch errors early
- TDD approach: write test, verify fail, implement, verify pass, commit

**Verification Commands:**
```bash
# Run specific test file
flutter test test/unit/models/ble_service_identifier_test.dart

# Run all tests
flutter test

# Static analysis
flutter analyze

# Run app in simulator mode (no hardware needed)
flutter run --dart-define=simulate=1
```

---

## Task 1: Implement BleServiceIdentifier Model

**Files:**
- Create: `lib/src/models/device/ble_service_identifier.dart`
- Create: `test/unit/models/ble_service_identifier_test.dart`

**Step 1: Write failing test for short UUID expansion**

Create `test/unit/models/ble_service_identifier_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/models/device/ble_service_identifier.dart';

void main() {
  group('BleServiceIdentifier', () {
    test('short constructor expands to Bluetooth SIG base UUID', () {
      final identifier = BleServiceIdentifier.short('fff0');
      
      expect(identifier.short, equals('fff0'));
      expect(identifier.long, equals('0000fff0-0000-1000-8000-00805f9b34fb'));
    });
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/unit/models/ble_service_identifier_test.dart`

Expected: FAIL with "BleServiceIdentifier not found"

**Step 3: Write minimal BleServiceIdentifier implementation**

Create `lib/src/models/device/ble_service_identifier.dart`:

```dart
class BleServiceIdentifier {
  final String? _short;
  final String? _long;

  BleServiceIdentifier.short(String uuid16bit)
      : _short = uuid16bit.toLowerCase(),
        _long = null;

  String get short {
    if (_short != null) return _short!;
    // Extract short from long if it matches base UUID pattern
    if (_long != null && _long!.startsWith('0000') && _long!.endsWith('-0000-1000-8000-00805f9b34fb')) {
      return _long!.substring(4, 8);
    }
    throw StateError('Cannot extract short UUID from custom 128-bit UUID');
  }

  String get long {
    if (_long != null) return _long!;
    if (_short != null) {
      // Bluetooth SIG base UUID expansion
      return '0000${_short!}-0000-1000-8000-00805f9b34fb';
    }
    throw StateError('No UUID available');
  }
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/unit/models/ble_service_identifier_test.dart`

Expected: PASS

**Step 5: Commit**

```bash
git add lib/src/models/device/ble_service_identifier.dart test/unit/models/ble_service_identifier_test.dart
git commit -m "feat: add BleServiceIdentifier with short UUID expansion"
```

---

## Task 2: Add Long UUID Constructor

**Files:**
- Modify: `lib/src/models/device/ble_service_identifier.dart`
- Modify: `test/unit/models/ble_service_identifier_test.dart`

**Step 1: Write failing test for long UUID constructor**

Add to `test/unit/models/ble_service_identifier_test.dart`:

```dart
test('long constructor with base UUID pattern extracts short form', () {
  final identifier = BleServiceIdentifier.long('0000ff08-0000-1000-8000-00805f9b34fb');
  
  expect(identifier.short, equals('ff08'));
  expect(identifier.long, equals('0000ff08-0000-1000-8000-00805f9b34fb'));
});

test('long constructor with custom UUID cannot extract short form', () {
  final identifier = BleServiceIdentifier.long('06c31822-8682-4744-9211-febc93e3bece');
  
  expect(identifier.long, equals('06c31822-8682-4744-9211-febc93e3bece'));
  expect(() => identifier.short, throwsStateError);
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/unit/models/ble_service_identifier_test.dart`

Expected: FAIL with "No named constructor 'long'"

**Step 3: Add long constructor**

Add to `lib/src/models/device/ble_service_identifier.dart`:

```dart
BleServiceIdentifier.long(String uuid128bit)
    : _short = null,
      _long = uuid128bit.toLowerCase();
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/unit/models/ble_service_identifier_test.dart`

Expected: PASS

**Step 5: Commit**

```bash
git add lib/src/models/device/ble_service_identifier.dart test/unit/models/ble_service_identifier_test.dart
git commit -m "feat: add long UUID constructor to BleServiceIdentifier"
```

---

## Task 3: Add Both Constructor and Validation

**Files:**
- Modify: `lib/src/models/device/ble_service_identifier.dart`
- Modify: `test/unit/models/ble_service_identifier_test.dart`

**Step 1: Write failing tests for both constructor and validation**

Add to `test/unit/models/ble_service_identifier_test.dart`:

```dart
test('both constructor accepts explicit short and long UUIDs', () {
  final identifier = BleServiceIdentifier.both('fff0', '0000fff0-0000-1000-8000-00805f9b34fb');
  
  expect(identifier.short, equals('fff0'));
  expect(identifier.long, equals('0000fff0-0000-1000-8000-00805f9b34fb'));
});

test('short constructor validates 4 hex chars', () {
  expect(() => BleServiceIdentifier.short('fff'), throwsArgumentError);
  expect(() => BleServiceIdentifier.short('fffff'), throwsArgumentError);
  expect(() => BleServiceIdentifier.short('gggg'), throwsArgumentError);
});

test('long constructor validates UUID pattern', () {
  expect(() => BleServiceIdentifier.long('invalid'), throwsArgumentError);
  expect(() => BleServiceIdentifier.long('0000fff0'), throwsArgumentError);
});

test('both constructor requires at least one UUID', () {
  expect(() => BleServiceIdentifier.both('', ''), throwsArgumentError);
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/unit/models/ble_service_identifier_test.dart`

Expected: Multiple FAILs for missing constructor and validation

**Step 3: Add both constructor and validation**

Update `lib/src/models/device/ble_service_identifier.dart`:

```dart
class BleServiceIdentifier {
  final String? _short;
  final String? _long;

  static final _shortPattern = RegExp(r'^[0-9a-fA-F]{4}$');
  static final _longPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  BleServiceIdentifier.short(String uuid16bit)
      : _short = _validateShort(uuid16bit),
        _long = null;

  BleServiceIdentifier.long(String uuid128bit)
      : _short = null,
        _long = _validateLong(uuid128bit);

  BleServiceIdentifier.both(String? short, String? long)
      : _short = short != null && short.isNotEmpty ? _validateShort(short) : null,
        _long = long != null && long.isNotEmpty ? _validateLong(long) : null {
    if (_short == null && _long == null) {
      throw ArgumentError('At least one UUID (short or long) must be provided');
    }
  }

  static String _validateShort(String uuid) {
    if (!_shortPattern.hasMatch(uuid)) {
      throw ArgumentError('Short UUID must be exactly 4 hex characters: $uuid');
    }
    return uuid.toLowerCase();
  }

  static String _validateLong(String uuid) {
    if (!_longPattern.hasMatch(uuid)) {
      throw ArgumentError('Long UUID must match pattern xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx: $uuid');
    }
    return uuid.toLowerCase();
  }

  String get short {
    if (_short != null) return _short!;
    if (_long != null && _long!.startsWith('0000') && _long!.endsWith('-0000-1000-8000-00805f9b34fb')) {
      return _long!.substring(4, 8);
    }
    throw StateError('Cannot extract short UUID from custom 128-bit UUID');
  }

  String get long {
    if (_long != null) return _long!;
    if (_short != null) {
      return '0000${_short!}-0000-1000-8000-00805f9b34fb';
    }
    throw StateError('No UUID available');
  }
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/unit/models/ble_service_identifier_test.dart`

Expected: PASS

**Step 5: Commit**

```bash
git add lib/src/models/device/ble_service_identifier.dart test/unit/models/ble_service_identifier_test.dart
git commit -m "feat: add both constructor and UUID validation to BleServiceIdentifier"
```

---

## Task 4: Add Equality and Hashing

**Files:**
- Modify: `lib/src/models/device/ble_service_identifier.dart`
- Modify: `test/unit/models/ble_service_identifier_test.dart`

**Step 1: Write failing tests for equality and hashing**

Add to `test/unit/models/ble_service_identifier_test.dart`:

```dart
test('identifiers with same long form are equal', () {
  final id1 = BleServiceIdentifier.short('fff0');
  final id2 = BleServiceIdentifier.long('0000fff0-0000-1000-8000-00805f9b34fb');
  
  expect(id1, equals(id2));
  expect(id1.hashCode, equals(id2.hashCode));
});

test('identifiers with different long forms are not equal', () {
  final id1 = BleServiceIdentifier.short('fff0');
  final id2 = BleServiceIdentifier.short('ff08');
  
  expect(id1, isNot(equals(id2)));
});

test('can be used as Map keys', () {
  final map = <BleServiceIdentifier, String>{};
  final key1 = BleServiceIdentifier.short('fff0');
  final key2 = BleServiceIdentifier.long('0000fff0-0000-1000-8000-00805f9b34fb');
  
  map[key1] = 'value';
  expect(map[key2], equals('value'));
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/unit/models/ble_service_identifier_test.dart`

Expected: FAIL with "Expected: <Instance of 'BleServiceIdentifier'>"

**Step 3: Add equality and hashCode overrides**

Add to `lib/src/models/device/ble_service_identifier.dart`:

```dart
@override
bool operator ==(Object other) {
  if (identical(this, other)) return true;
  return other is BleServiceIdentifier && other.long == long;
}

@override
int get hashCode => long.hashCode;
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/unit/models/ble_service_identifier_test.dart`

Expected: PASS

**Step 5: Commit**

```bash
git add lib/src/models/device/ble_service_identifier.dart test/unit/models/ble_service_identifier_test.dart
git commit -m "feat: add equality and hashing to BleServiceIdentifier for Map key usage"
```

---

## Task 5: Update Skale2Scale with BleServiceIdentifier

**Files:**
- Modify: `lib/src/models/device/impl/skale/skale2_scale.dart`

**Step 1: Add static BleServiceIdentifier properties**

Update `lib/src/models/device/impl/skale/skale2_scale.dart`:

Import at top of file:
```dart
import 'package:reaprime/src/models/device/ble_service_identifier.dart';
```

Replace existing static String declarations with:
```dart
class Skale2Scale implements Scale {
  static final BleServiceIdentifier serviceIdentifier = 
    BleServiceIdentifier.short('ff08');
  static final BleServiceIdentifier weightCharacteristic = 
    BleServiceIdentifier.short('ef81');
  static final BleServiceIdentifier commandCharacteristic = 
    BleServiceIdentifier.short('ef80');
  static final BleServiceIdentifier buttonCharacteristic = 
    BleServiceIdentifier.short('ef82');
  static final BleServiceIdentifier batteryService = 
    BleServiceIdentifier.short('180f');
  static final BleServiceIdentifier batteryCharacteristic = 
    BleServiceIdentifier.short('2a19');
  
  // Remove old static String declarations:
  // static String serviceUUID = 'ff08';
  // static String weightCharacteristicUUID = 'ef81';
  // etc.
```

**Step 2: Replace UUID string literals with identifier.long**

Find and replace in all methods:
- `serviceUUID` → `serviceIdentifier.long`
- `weightCharacteristicUUID` → `weightCharacteristic.long`
- `commandCharacteristicUUID` → `commandCharacteristic.long`
- `buttonCharacteristicUUID` → `buttonCharacteristic.long`
- `batteryServiceUUID` → `batteryService.long`
- `batteryCharacteristicUUID` → `batteryCharacteristic.long`

**Step 3: Run analyzer**

Run: `flutter analyze lib/src/models/device/impl/skale/skale2_scale.dart`

Expected: No errors or warnings

**Step 4: Run tests**

Run: `flutter test`

Expected: All tests PASS

**Step 5: Commit**

```bash
git add lib/src/models/device/impl/skale/skale2_scale.dart
git commit -m "refactor: migrate Skale2Scale to BleServiceIdentifier"
```

---

## Task 6: Update DecentScale with BleServiceIdentifier

**Files:**
- Modify: `lib/src/models/device/impl/decent_scale/scale.dart`

**Step 1: Add static BleServiceIdentifier properties**

Update `lib/src/models/device/impl/decent_scale/scale.dart`:

Import at top:
```dart
import 'package:reaprime/src/models/device/ble_service_identifier.dart';
```

Replace static String with:
```dart
class DecentScale implements Scale {
  static final BleServiceIdentifier serviceIdentifier = 
    BleServiceIdentifier.short('fff0');
  static final BleServiceIdentifier dataCharacteristic = 
    BleServiceIdentifier.short('fff4');
  static final BleServiceIdentifier writeCharacteristic = 
    BleServiceIdentifier.short('36f5');
```

**Step 2: Replace UUID literals with identifier.long**

Replace all occurrences:
- `serviceUUID` → `serviceIdentifier.long`
- `dataUUID` → `dataCharacteristic.long`
- `writeUUID` → `writeCharacteristic.long`

**Step 3: Run analyzer**

Run: `flutter analyze lib/src/models/device/impl/decent_scale/scale.dart`

Expected: No errors

**Step 4: Commit**

```bash
git add lib/src/models/device/impl/decent_scale/scale.dart
git commit -m "refactor: migrate DecentScale to BleServiceIdentifier"
```

---

## Task 7: Update Remaining Scale Implementations (Batch 1)

**Files:**
- Modify: `lib/src/models/device/impl/felicita/arc.dart`
- Modify: `lib/src/models/device/impl/eureka/eureka_scale.dart`
- Modify: `lib/src/models/device/impl/acaia/acaia_scale.dart`
- Modify: `lib/src/models/device/impl/acaia/acaia_pyxis_scale.dart`

**Step 1: Update FelicitaArc**

```dart
import 'package:reaprime/src/models/device/ble_service_identifier.dart';

class FelicitaArc implements Scale {
  static final BleServiceIdentifier serviceIdentifier = 
    BleServiceIdentifier.short('ffe0');
  static final BleServiceIdentifier dataCharacteristic = 
    BleServiceIdentifier.short('ffe1');
```

Replace `serviceUUID` → `serviceIdentifier.long`, `dataUUID` → `dataCharacteristic.long`

**Step 2: Update EurekaScale**

```dart
import 'package:reaprime/src/models/device/ble_service_identifier.dart';

class EurekaScale implements Scale {
  static final BleServiceIdentifier serviceIdentifier = 
    BleServiceIdentifier.short('fff0');
  static final BleServiceIdentifier dataCharacteristic = 
    BleServiceIdentifier.short('fff1');
  static final BleServiceIdentifier commandCharacteristic = 
    BleServiceIdentifier.short('fff2');
  static final BleServiceIdentifier batteryService = 
    BleServiceIdentifier.short('180f');
  static final BleServiceIdentifier batteryCharacteristic = 
    BleServiceIdentifier.short('2a19');
```

Replace all UUID literals with `.long` accessors.

**Step 3: Update AcaiaScale**

```dart
import 'package:reaprime/src/models/device/ble_service_identifier.dart';

class AcaiaScale implements Scale {
  static final BleServiceIdentifier serviceIdentifier = 
    BleServiceIdentifier.short('1820');
  static final BleServiceIdentifier characteristic = 
    BleServiceIdentifier.short('2a80');
```

Replace `serviceUUID` → `serviceIdentifier.long`, `characteristicUUID` → `characteristic.long`

**Step 4: Update AcaiaPyxisScale**

Same pattern as AcaiaScale - add identifiers, replace string literals.

**Step 5: Run analyzer**

Run: `flutter analyze lib/src/models/device/impl/`

Expected: No errors

**Step 6: Commit**

```bash
git add lib/src/models/device/impl/felicita/ lib/src/models/device/impl/eureka/ lib/src/models/device/impl/acaia/
git commit -m "refactor: migrate Felicita, Eureka, Acaia scales to BleServiceIdentifier"
```

---

## Task 8: Update Remaining Scale Implementations (Batch 2)

**Files:**
- Modify: `lib/src/models/device/impl/hiroia/hiroia_scale.dart`
- Modify: `lib/src/models/device/impl/blackcoffee/blackcoffee_scale.dart`
- Modify: `lib/src/models/device/impl/atomheart/atomheart_scale.dart`
- Modify: `lib/src/models/device/impl/difluid/difluid_scale.dart`

**Step 1: Update HiroiaScale (custom 128-bit UUID)**

```dart
import 'package:reaprime/src/models/device/ble_service_identifier.dart';

class HiroiaScale implements Scale {
  static final BleServiceIdentifier serviceIdentifier = 
    BleServiceIdentifier.long('06c31822-8682-4744-9211-febc93e3bece');
  static final BleServiceIdentifier dataCharacteristic = 
    BleServiceIdentifier.long('06c31824-8682-4744-9211-febc93e3bece');
  static final BleServiceIdentifier writeCharacteristic = 
    BleServiceIdentifier.long('06c31823-8682-4744-9211-febc93e3bece');
```

Replace UUID literals with `.long` accessors.

**Step 2: Update BlackCoffeeScale**

```dart
import 'package:reaprime/src/models/device/ble_service_identifier.dart';

class BlackCoffeeScale implements Scale {
  static final BleServiceIdentifier serviceIdentifier = 
    BleServiceIdentifier.short('ffb0');
  static final BleServiceIdentifier dataCharacteristic = 
    BleServiceIdentifier.short('ffb2');
```

**Step 3: Update AtomheartScale and DifluidScale**

Apply same pattern - add identifiers for each UUID, replace string literals.

**Step 4: Run analyzer**

Run: `flutter analyze lib/src/models/device/impl/`

Expected: No errors

**Step 5: Commit**

```bash
git add lib/src/models/device/impl/hiroia/ lib/src/models/device/impl/blackcoffee/ lib/src/models/device/impl/atomheart/ lib/src/models/device/impl/difluid/
git commit -m "refactor: migrate Hiroia, BlackCoffee, Atomheart, Difluid scales to BleServiceIdentifier"
```

---

## Task 9: Update Remaining Scale Implementations (Batch 3)

**Files:**
- Modify: `lib/src/models/device/impl/varia/varia_aku_scale.dart`
- Modify: `lib/src/models/device/impl/smartchef/smartchef_scale.dart`
- Modify: `lib/src/models/device/impl/bookoo/miniscale.dart`

**Step 1-3: Update each scale**

Apply same pattern for VariaAkuScale, SmartChefScale, BookooScale.

**Step 4: Run analyzer**

Run: `flutter analyze lib/src/models/device/impl/`

Expected: No errors

**Step 5: Commit**

```bash
git add lib/src/models/device/impl/varia/ lib/src/models/device/impl/smartchef/ lib/src/models/device/impl/bookoo/
git commit -m "refactor: migrate Varia, SmartChef, Bookoo scales to BleServiceIdentifier"
```

---

## Task 10: Update UnifiedDe1 with BleServiceIdentifier

**Files:**
- Modify: `lib/src/models/device/impl/de1/unified_de1/unified_de1.dart`

**Step 1: Add BleServiceIdentifier for DE1**

```dart
import 'package:reaprime/src/models/device/ble_service_identifier.dart';

class UnifiedDe1 implements De1Interface {
  static final BleServiceIdentifier advertisingIdentifier = 
    BleServiceIdentifier.short('ffff');
  
  // Replace static String advertisingUUID = 'ffff';
```

**Step 2: Replace UUID usage in UnifiedDe1Transport**

Check `lib/src/models/device/impl/de1/unified_de1/unified_de1_transport.dart` for characteristic UUIDs and add identifiers as needed.

**Step 3: Run analyzer**

Run: `flutter analyze lib/src/models/device/impl/de1/`

Expected: No errors

**Step 4: Commit**

```bash
git add lib/src/models/device/impl/de1/
git commit -m "refactor: migrate UnifiedDe1 to BleServiceIdentifier"
```

---

## Task 11: Update BluePlusDiscoveryService

**Files:**
- Modify: `lib/src/services/blue_plus_discovery_service.dart`

**Step 1: Update constructor signature**

Change:
```dart
Map<String, Future<Device> Function(BLETransport)> deviceMappings;

BluePlusDiscoveryService({
  required Map<String, Future<Device> Function(BLETransport)> mappings,
}) : deviceMappings = mappings.map((k, v) {
       return MapEntry(Guid(k).str, v);
     });
```

To:
```dart
import 'package:reaprime/src/models/device/ble_service_identifier.dart';

Map<BleServiceIdentifier, Future<Device> Function(BLETransport)> deviceMappings;

BluePlusDiscoveryService({
  required Map<BleServiceIdentifier, Future<Device> Function(BLETransport)> mappings,
}) : deviceMappings = mappings;
```

**Step 2: Update scanForDevices to generate dual-UUID filter**

Find `scanForDevices()` method and update:

```dart
@override
Future<void> scanForDevices() async {
  // Generate dual-UUID filter (both short and long for each device)
  final scanUuids = <Guid>[];
  for (final identifier in deviceMappings.keys) {
    scanUuids.add(Guid(identifier.short));
    scanUuids.add(Guid(identifier.long));
  }

  var subscription = FlutterBluePlus.onScanResults.listen((results) {
    // ... existing result handling ...
    
    final s = r.advertisementData.serviceUuids.firstWhereOrNull(
      (adv) {
        // Match against both short and long forms
        return deviceMappings.keys.any(
          (id) => id.short == adv.str || id.long == adv.str,
        );
      },
    );
    
    if (s == null) {
      _log.fine(/* ... */);
      return;
    }
    
    // Find matching identifier
    final matchedIdentifier = deviceMappings.keys.firstWhereOrNull(
      (id) => id.short == s.str || id.long == s.str,
    );
    
    if (matchedIdentifier == null) return;
    
    final deviceFactory = deviceMappings[matchedIdentifier];
    if (deviceFactory == null) return;
    
    // ... rest of existing logic ...
  });

  // ... existing subscription setup ...

  await FlutterBluePlus.startScan(
    withServices: scanUuids,
    oneByOne: true,
  );
  
  // ... rest of existing scan logic ...
}
```

**Step 3: Update scanForSpecificDevices similarly**

Apply same dual-UUID logic to `scanForSpecificDevices()` method.

**Step 4: Run analyzer**

Run: `flutter analyze lib/src/services/blue_plus_discovery_service.dart`

Expected: No errors

**Step 5: Commit**

```bash
git add lib/src/services/blue_plus_discovery_service.dart
git commit -m "feat: update BluePlusDiscoveryService for dual-UUID scanning"
```

---

## Task 12: Update UniversalBleDiscoveryService

**Files:**
- Modify: `lib/src/services/universal_ble_discovery_service.dart`

**Step 1: Update constructor signature**

```dart
import 'package:reaprime/src/models/device/ble_service_identifier.dart';

Map<BleServiceIdentifier, Future<Device> Function(BLETransport)> deviceMappings;

UniversalBleDiscoveryService({
  required Map<BleServiceIdentifier, Future<Device> Function(BLETransport)> mappings,
}) : deviceMappings = mappings;
```

**Step 2: Update scanForDevices with dual-UUID filter**

```dart
@override
Future<void> scanForDevices() async {
  log.info("mappings: ${deviceMappings}");
  log.fine("Clearing stale connections");
  _currentlyScanning.clear();

  var sub = UniversalBle.scanStream.listen((result) async {
    // ... existing logic ...
    await _deviceScanned(result);
  });

  // Generate dual-UUID filter
  final List<String> services = [];
  if (!Platform.isLinux) {
    for (final identifier in deviceMappings.keys) {
      services.add(BleUuidParser.string(identifier.short));
      services.add(BleUuidParser.string(identifier.long));
    }
  }

  final filter = ScanFilter(withServices: services);
  await UniversalBle.startScan(scanFilter: filter);

  // Get system devices with both UUID formats
  final systemDeviceServices = <String>[];
  for (final identifier in deviceMappings.keys) {
    systemDeviceServices.add(BleUuidParser.string(identifier.short));
    systemDeviceServices.add(BleUuidParser.string(identifier.long));
  }
  
  final systemDevices = await UniversalBle.getSystemDevices(
    withServices: systemDeviceServices,
  );
  
  // ... rest of existing logic ...
}
```

**Step 3: Update _deviceScanned matching logic**

```dart
Future<void> _deviceScanned(BleDevice device) async {
  _currentlyScanning.add(device.deviceId);
  
  for (String uid in device.services) {
    // Match against both short and long forms
    final matchedIdentifier = deviceMappings.keys.firstWhereOrNull(
      (id) => BleUuidParser.string(id.short) == uid || 
              BleUuidParser.string(id.long) == uid,
    );
    
    if (matchedIdentifier != null && 
        _devices.containsKey(device.deviceId.toString()) == false) {
      final initializer = deviceMappings[matchedIdentifier];
      if (initializer != null) {
        _devices[device.deviceId.toString()] = await initializer(
          UniversalBleTransport(device: device),
        );
        // ... rest of existing logic ...
      }
    }
  }
  
  _currentlyScanning.remove(device.deviceId);
}
```

**Step 4: Run analyzer**

Run: `flutter analyze lib/src/services/universal_ble_discovery_service.dart`

Expected: No errors

**Step 5: Commit**

```bash
git add lib/src/services/universal_ble_discovery_service.dart
git commit -m "feat: update UniversalBleDiscoveryService for dual-UUID scanning"
```

---

## Task 13: Update main.dart Device Mappings

**Files:**
- Modify: `lib/main.dart`

**Step 1: Replace String keys with BleServiceIdentifier references**

Find the `bleDeviceMappings` section around line 200 and replace:

```dart
// OLD:
final bleDeviceMappings = {
  UnifiedDe1.advertisingUUID.toUpperCase():
      (t) => MachineParser.machineFrom(transport: t),
  FelicitaArc.serviceUUID.toUpperCase(): (t) async {
    return FelicitaArc(transport: t);
  },
  DecentScale.serviceUUID.toUpperCase(): (t) async {
    // ... disambiguation logic ...
  },
  // ... etc
};

// NEW:
final bleDeviceMappings = {
  UnifiedDe1.advertisingIdentifier: (t) => MachineParser.machineFrom(transport: t),
  FelicitaArc.serviceIdentifier: (t) async => FelicitaArc(transport: t),
  DecentScale.serviceIdentifier: (t) async {
    final name = t.name.toLowerCase();
    if (name.contains('cfs-9002') ||
        name.contains('eureka') ||
        name.contains('precisa')) {
      return EurekaScale(transport: t);
    } else if (name.contains('solo barista') ||
        name.contains('lsj-001')) {
      // Solo Barista uses the same protocol as Eureka Precisa
      return EurekaScale(transport: t);
    } else if (name.contains('smartchef')) {
      return SmartChefScale(transport: t);
    } else if (name.contains('aku') || name.contains('varia')) {
      return VariaAkuScale(transport: t);
    }
    return DecentScale(transport: t);
  },
  BookooScale.serviceIdentifier: (t) async => BookooScale(transport: t),
  AcaiaScale.serviceIdentifier: (t) async => AcaiaScale(transport: t),
  AcaiaPyxisScale.serviceIdentifier: (t) async => AcaiaPyxisScale(transport: t),
  Skale2Scale.serviceIdentifier: (t) async => Skale2Scale(transport: t),
  HiroiaScale.serviceIdentifier: (t) async => HiroiaScale(transport: t),
  DifluidScale.serviceIdentifier: (t) async => DifluidScale(transport: t),
  BlackCoffeeScale.serviceIdentifier: (t) async => BlackCoffeeScale(transport: t),
  AtomheartScale.serviceIdentifier: (t) async => AtomheartScale(transport: t),
};
```

**Step 2: Run analyzer**

Run: `flutter analyze lib/main.dart`

Expected: No errors

**Step 3: Run full test suite**

Run: `flutter test`

Expected: All tests PASS

**Step 4: Commit**

```bash
git add lib/main.dart
git commit -m "feat: migrate device mappings to BleServiceIdentifier"
```

---

## Task 14: Manual Testing with Real Hardware

**Prerequisites:**
- Access to Decent Scale or Skale2
- Android device running Android 9 or 12
- Cable for deployment

**Step 1: Build and deploy to Android device**

```bash
flutter build apk --debug
adb install build/app/outputs/flutter-apk/app-debug.apk
```

**Step 2: Enable verbose logging**

Run app with: `./flutter_with_commit.sh run --verbose`

**Step 3: Test Decent Scale discovery**

1. Turn on Decent Scale
2. Tap scan button in app
3. Check logs for:
   - Scale appears in scan results
   - Scale UUID matched (both short and long logged)
   - Device created successfully
4. Verify scale connects and reports weight

**Step 4: Test Skale2 discovery**

Repeat Step 3 with Skale2 scale.

**Step 5: Test with other scales (if available)**

Test Felicita, Acaia, or any other available scale to ensure no regressions.

**Step 6: Document results**

Create `doc/testing/2026-02-22-ble-uuid-hardware-test.md` with:
- Device tested
- Android version
- Discovery success/failure
- Connection success/failure
- Any errors or warnings in logs

---

## Task 15: Final Integration and Documentation

**Files:**
- Modify: `CLAUDE.md`
- Create: `doc/testing/2026-02-22-ble-uuid-hardware-test.md`

**Step 1: Update CLAUDE.md with UUID approach**

Add to the "Conventions & Gotchas" section:

```markdown
- **BLE UUIDs:** All BLE devices use `BleServiceIdentifier` for services and characteristics. Discovery scans for both 16-bit short and 128-bit long UUIDs for maximum compatibility. Device operations use 128-bit format exclusively.
```

**Step 2: Run full test suite one final time**

Run: `flutter test`

Expected: All tests PASS

**Step 3: Run analyzer on entire codebase**

Run: `flutter analyze`

Expected: No errors or warnings

**Step 4: Commit documentation**

```bash
git add CLAUDE.md doc/testing/
git commit -m "docs: update CLAUDE.md with BLE UUID approach and add hardware test results"
```

**Step 5: Final commit and summary**

```bash
git log --oneline --graph -15
```

Review commit history to ensure clean, logical progression.

---

## Verification Checklist

Before considering this task complete, verify:

- [ ] All unit tests pass for `BleServiceIdentifier`
- [ ] All device implementations migrated to `BleServiceIdentifier`
- [ ] Discovery services scan for both short and long UUIDs
- [ ] Device mappings in `main.dart` use static identifiers
- [ ] No analyzer errors or warnings
- [ ] Full test suite passes
- [ ] Decent Scale discovered on Android 9/12 (real hardware test)
- [ ] Skale2 discovered on Android 9/12 (real hardware test)
- [ ] No regressions with other scales
- [ ] Documentation updated in CLAUDE.md

## Success Criteria

1. Decent Scale and Skale2 appear in device discovery logs on Android 9/12
2. Scales connect and report weight data successfully
3. Existing working devices (Hiroia, Felicita, etc.) continue to work
4. No test failures or analyzer errors
5. Clean commit history with logical progression
