# BLE 128-bit UUID Support Design

**Date:** 2026-02-22  
**Status:** Draft - Awaiting Review  
**Author:** Claude (Sonnet 4.5)

## Problem Statement

Users report BLE scales (Decent Scale, Skale2) not appearing in device discovery on Android 9 and Android 12. Logs show only DE1 machines are scanned/processed - scales never appear even at scan time. Hypothesis: older BLE firmware/stacks may not properly advertise or recognize 16-bit short UUIDs, requiring full 128-bit UUID support.

## Current State

**UUID Format:** Most devices use 16-bit short UUIDs:
- Acaia: `1820`
- Felicita: `ffe0`
- Decent Scale, Eureka, SmartChef, Varia: `fff0` (disambiguated by name)
- Skale2: `ff08`
- Exception: Hiroia already uses 128-bit: `06c31822-8682-4744-9211-febc93e3bece`

**Discovery:** `BluePlusDiscoveryService` and `UniversalBleDiscoveryService` scan with short UUIDs in filter, match against `deviceMappings` dictionary.

**Service/Characteristic Access:** Devices use short UUID strings throughout (`serviceUUID`, `dataUUID`, etc.)

## Solution: Dual-UUID Discovery with 128-bit Operations

### Design Goals

1. **Maximum compatibility:** Support both short and expanded 128-bit UUIDs in discovery
2. **No breaking changes:** Devices working today continue to work
3. **Standard compliance:** Use Bluetooth SIG base UUID for expansion
4. **Consistent operations:** Use 128-bit UUIDs for all post-discovery operations

### Approach

**Dual-UUID Discovery:** Scan for both short and 128-bit UUIDs simultaneously. BLE stacks that recognize either format will match.

**128-bit Operations:** After discovery, use only 128-bit UUIDs for service/characteristic access.

## Architecture

### Component 1: BleServiceIdentifier Model

**Purpose:** Encapsulate BLE UUID representation with automatic conversion between 16-bit and 128-bit formats.

**Location:** `lib/src/models/device/ble_service_identifier.dart`

**Class Design:**

```dart
class BleServiceIdentifier {
  final String? _short;   // 'fff0'
  final String? _long;    // '0000fff0-0000-1000-8000-00805f9b34fb'
  
  // Constructors
  BleServiceIdentifier.short(String uuid16bit);
  BleServiceIdentifier.long(String uuid128bit);
  BleServiceIdentifier.both(String short, String long);
  
  // Getters with lazy expansion
  String get short => _short ?? _extractShort(_long!);
  String get long => _long ?? _expandToLong(_short!);
}
```

**Expansion Rules:**

- **Short → Long:** Bluetooth SIG base UUID: `0000${short}-0000-1000-8000-00805f9b34fb`
- **Long → Short:** Extract bytes 4-8 if matches base UUID pattern, otherwise null

**Validation:**

- At least one UUID required (short or long)
- Short: 4 hex chars (case-insensitive)
- Long: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` pattern
- Throw `ArgumentError` on invalid input

**Equality/Hashing:**

- Two identifiers equal if their long forms match
- Hash based on normalized long form
- Enables use as Map keys

### Component 2: Device Implementation Updates

**Each BLE device class:**

1. Defines static `BleServiceIdentifier` for service and all characteristics
2. Uses `.long` form for all transport operations
3. Removes old `static String serviceUUID` fields

**Example (Skale2Scale):**

```dart
class Skale2Scale implements Scale {
  // Discovery identifier
  static final BleServiceIdentifier serviceIdentifier = 
    BleServiceIdentifier.short('ff08');
  
  // Characteristic identifiers
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
  
  // All operations use .long:
  Future<void> _initScale() async {
    await _transport.subscribe(
      serviceIdentifier.long,
      weightCharacteristic.long,
      _parseWeightNotification,
    );
    
    final batteryData = await _transport.read(
      batteryService.long,
      batteryCharacteristic.long,
    );
  }
  
  Future<void> tare() async {
    await _transport.write(
      serviceIdentifier.long,
      commandCharacteristic.long,
      Uint8List.fromList([0x10]),
      withResponse: false,
    );
  }
}
```

**Affected Files (~16 implementations):**

- `lib/src/models/device/impl/acaia/acaia_scale.dart`
- `lib/src/models/device/impl/acaia/acaia_pyxis_scale.dart`
- `lib/src/models/device/impl/felicita/arc.dart`
- `lib/src/models/device/impl/eureka/eureka_scale.dart`
- `lib/src/models/device/impl/skale/skale2_scale.dart`
- `lib/src/models/device/impl/decent_scale/scale.dart`
- `lib/src/models/device/impl/hiroia/hiroia_scale.dart`
- `lib/src/models/device/impl/blackcoffee/blackcoffee_scale.dart`
- `lib/src/models/device/impl/atomheart/atomheart_scale.dart`
- `lib/src/models/device/impl/difluid/difluid_scale.dart`
- `lib/src/models/device/impl/varia/varia_aku_scale.dart`
- `lib/src/models/device/impl/smartchef/smartchef_scale.dart`
- `lib/src/models/device/impl/bookoo/miniscale.dart`
- `lib/src/models/device/impl/de1/unified_de1/unified_de1.dart`
- Plus any other BLE devices

**Migration Pattern:**

1. Add static `BleServiceIdentifier` properties for service and characteristics
2. Replace all string UUID literals with `identifier.long`
3. Remove old `static String` UUID fields

### Component 3: Discovery Service Updates

**BluePlusDiscoveryService:**

**Current signature:**
```dart
Map<String, Future<Device> Function(BLETransport)> deviceMappings;
```

**New signature:**
```dart
Map<BleServiceIdentifier, Future<Device> Function(BLETransport)> deviceMappings;
```

**Scan filter generation:**

```dart
Future<void> scanForDevices() async {
  // Generate dual-UUID filter
  final scanUuids = <Guid>[];
  for (final identifier in deviceMappings.keys) {
    scanUuids.add(Guid(identifier.short));  // short form
    scanUuids.add(Guid(identifier.long));   // expanded form
  }
  
  await FlutterBluePlus.startScan(
    withServices: scanUuids,
    oneByOne: true,
  );
}
```

**Note on `oneByOne` flag:** This flag controls whether flutter_blue_plus emits scan results individually as they arrive (`true`) or batches them (`false`). The current implementation uses `oneByOne: true` to process devices immediately during discovery. We'll preserve this behavior to maintain compatibility with the existing discovery flow.

**Match logic:**

```dart
// Match advertised UUID against mapping keys
final advertisedUuid = r.advertisementData.serviceUuids.first;
final matchedIdentifier = deviceMappings.keys.firstWhereOrNull(
  (id) => id.short == advertisedUuid.str || id.long == advertisedUuid.str,
);
```

**UniversalBleDiscoveryService:**

Similar changes:
- Accept `Map<BleServiceIdentifier, ...>` in constructor
- Convert identifiers to `BleUuidParser.string()` for both short and long forms
- Expand scan filter to include both UUID formats

**Location:**
- `lib/src/services/blue_plus_discovery_service.dart`
- `lib/src/services/universal_ble_discovery_service.dart`
- `lib/src/services/ble/linux_ble_discovery_service.dart` (if exists)

### Component 4: Device Mappings (main.dart)

**Current:**
```dart
final bleDeviceMappings = {
  'FFE0': (t) async => FelicitaArc(transport: t),
  'FFF0': (t) async => DecentScale(transport: t),
  // ...
};
```

**New:**
```dart
final bleDeviceMappings = {
  FelicitaArc.serviceIdentifier: (t) async => FelicitaArc(transport: t),
  DecentScale.serviceIdentifier: (t) async => DecentScale(transport: t),
  Skale2Scale.serviceIdentifier: (t) async => Skale2Scale(transport: t),
  HiroiaScale.serviceIdentifier: (t) async => HiroiaScale(transport: t),
  // ...
};
```

**Benefits:**
- Type-safe UUID references
- Each device owns its UUID definition
- No manual string duplication
- Clear which devices support which discovery modes

## Data Flow

### Discovery Flow

1. **Scan Start:** Discovery service generates dual-UUID filter (both short and long for each device)
2. **Advertisement:** BLE stack matches against either short or long UUID
3. **Match:** Discovery service looks up device factory by matching `BleServiceIdentifier`
4. **Create Device:** Factory instantiates device with transport

### Device Operation Flow

1. **Connect:** Transport connects to device
2. **Service Discovery:** Device uses `serviceIdentifier.long` to discover services
3. **Characteristic Access:** Device uses `characteristicIdentifier.long` for subscribe/read/write
4. **Data Exchange:** Normal protocol operations

## Testing Strategy

### Unit Tests

**BleServiceIdentifier:**
- Short → Long expansion (Bluetooth SIG base UUID)
- Long → Short extraction (base UUID pattern)
- Custom 128-bit UUID handling (Hiroia case)
- Validation: invalid formats throw `ArgumentError`
- Equality/hashing: identifiers with same long form are equal

**Discovery Services:**
- Dual-UUID filter generation
- Advertisement matching (short UUID advertised)
- Advertisement matching (long UUID advertised)
- Device factory lookup by `BleServiceIdentifier`

### Integration Tests

**Real Hardware Testing:**
- Test with Decent Scale on Android 9/12
- Test with Skale2 on Android 9/12
- Verify Hiroia (already 128-bit) still works
- Verify other scales (Felicita, Acaia, etc.) still work

### Regression Testing

- Run full test suite: `flutter test`
- Verify no existing functionality broken
- Test device reconnection after disconnect
- Test multiple simultaneous scale connections

## Migration Plan

### Phase 1: Core Infrastructure
1. Implement `BleServiceIdentifier` class
2. Add unit tests for UUID conversion/validation
3. Update discovery services to accept `BleServiceIdentifier` mappings

### Phase 2: Device Updates (Parallel)
1. Update each device implementation with static identifiers
2. Replace string UUIDs with `.long` accessors
3. Test each device individually with simulated mode

### Phase 3: Integration
1. Update `main.dart` device mappings
2. Run full test suite
3. Test with real hardware (Decent Scale, Skale2)

### Phase 4: Validation
1. Deploy to test users experiencing connectivity issues
2. Collect logs confirming scales appear in discovery
3. Monitor for any regressions

## Risks & Mitigations

**Risk 1: Breaking working devices**
- *Mitigation:* Dual-UUID approach - scan for both formats, existing devices continue to work

**Risk 2: BLE stack doesn't support long UUIDs**
- *Mitigation:* Bluetooth SIG base UUID is part of BLE spec, should be universally supported

**Risk 3: Real-world compatibility issues with 128-bit UUIDs**
- *Mitigation:* Phased rollout to real hardware testing with affected users. Start with Decent Scale and Skale2 on Android 9/12, then expand to other devices. Monitor logs and gather feedback before wider deployment.

**Risk 4: Custom UUIDs (Hiroia) break during refactor**
- *Mitigation:* Special handling in `BleServiceIdentifier` for non-base-UUID patterns

## Success Criteria

1. Decent Scale and Skale2 appear in device discovery on Android 9/12
2. All existing working devices continue to connect
3. No regressions in test suite
4. Logs show scales being scanned and processed

## References

- Bluetooth SIG Base UUID: `00000000-0000-1000-8000-00805f9b34fb`
- Bluetooth Core Specification: [Section 3.2.1 - UUID Format](https://www.bluetooth.com/specifications/assigned-numbers/)
- flutter_blue_plus documentation: [UUID handling](https://pub.dev/packages/flutter_blue_plus)
- de1app reference implementation: `github.com/decentespresso/de1app`

