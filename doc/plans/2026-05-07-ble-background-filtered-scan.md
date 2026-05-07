# Plan: BLE background filtered scan (#107)

**Date:** 2026-05-07
**Issue:** [#107 — BLE scan returns no results when screen is off](https://github.com/tadelv/reaprime/issues/107)
**Priority:** P0
**Status:** approved

## Problem

`scanAndConnectScale` (triggered by `De1StateManager` on wake-from-sleep) calls `ConnectionManager.connect(scaleOnly: true)`. This runs an unfiltered `FlutterBluePlus.startScan(oneByOne: true)`. Android throttles unfiltered BLE scans when screen is off → zero results. Filtered scans (by service UUID, remote ID) bypass throttling because filtering happens at hardware/firmware level.

## Approach

Add a **filtered scan path** using BLE service UUIDs + remote ID. The general `connect()` path stays unfiltered. Only `scaleOnly` on Android uses the filtered path.

### Filter strategy

Single scan with two filters (flutter_blue_plus "or" behavior):

1. `withServices` — all known scale service UUIDs (aggregated from scale impl classes)
2. `withRemoteIds: [preferredScaleId]` — only when a preferred scale ID is set

No retry (user triggers manually). No change to non-preferred scale behavior (picker still raised, API clients can handle).

### Decision summary

| Decision | Choice |
|----------|--------|
| Filter type | `withServices` (scale service UUIDs) + `withRemoteIds` |
| Name filtering? | No. Deferred. Service UUIDs are more universal and reliable. |
| Retry? | No. Manual trigger by user. |
| Non-preferred scale in background | Keep current behavior (picker). API clients may handle. |
| Platform | Android only. `Platform.isAndroid` gate in ConnectionManager. |
| ScanFilter model | `preferredDeviceId: String?` + `deviceTypes: Set<DeviceType>?` |
| UUID aggregation | `DeviceMatcher.serviceUuidsFor(DeviceType)` — reads existing static `serviceIdentifier` fields |
| Acaia UUIDs | New `advertisedServiceUuids` static getter on `AcaiaScale` (3 UUIDs) |
| Plumb through chain | ConnectionManager → ScanOrchestrator → DeviceScanner → DeviceController → DeviceDiscoveryService → BluePlusDiscoveryService |
| REST API exposure | Deferred. Added to Obsidian TODO. |
| Serial/simulated services | Ignore ScanFilter for now. TODO in Obsidian. |
| Full connect path | Unchanged — unfiltered scan. |

### Architecture

```
ConnectionManager._connectImpl(scaleOnly: true)
  → builds ScanFilter(preferredDeviceId: id, deviceTypes: {DeviceType.scale})  // Android only
  → ScanOrchestrator.runScan(scaleFilter: filter)
    → DeviceScanner.scanForDevices(filter: filter)
      → DeviceController._runScan(filter: filter)
        → BluePlusDiscoveryService.scanForDevices(filter: filter)
          // At BLE edge: imports DeviceMatcher.serviceUuidsFor(DeviceType.scale)
          // Converts String → Guid, builds withServices + withRemoteIds
          // Calls FlutterBluePlus.startScan(withServices: [...], withRemoteIds: [...], oneByOne: true)
        → Other services: filter is null → unfiltered scan (unchanged)
```

### New model

```dart
/// lib/src/models/device/scan_filter.dart (NEW)
class ScanFilter {
  final String? preferredDeviceId;
  final Set<DeviceType>? deviceTypes;  // null = all, {scale} = only scales
  
  const ScanFilter({this.preferredDeviceId, this.deviceTypes});
  
  bool get isFiltered =>
      preferredDeviceId != null ||
      (deviceTypes != null && deviceTypes!.isNotEmpty);
}
```

### New method

```dart
/// lib/src/services/device_matcher.dart
static List<String> serviceUuidsFor(DeviceType type) => switch (type) {
  DeviceType.scale => [
    DecentScale.serviceIdentifier.long,
    Skale2Scale.serviceIdentifier.long,
    FelicitaArc.serviceIdentifier.long,
    BlackCoffeeScale.serviceIdentifier.long,
    BookooScale.serviceIdentifier.long,
    EurekaScale.serviceIdentifier.long,
    SmartChefScale.serviceIdentifier.long,
    VariaAkuScale.serviceIdentifier.long,
    DifluidScale.serviceIdentifier.long,
    HiroiaScale.serviceIdentifier.long,
    AtomheartScale.serviceIdentifier.long,
    ...AcaiaScale.advertisedServiceUuids,
  ],
  DeviceType.machine => [
    UnifiedDe1.serviceIdentifier.long,
    Bengle.serviceIdentifier.long,
  ],
  DeviceType.sensor => [],  // No BLE sensors yet
};
```

### New static getter

```dart
/// lib/src/models/device/impl/acaia/acaia_scale.dart
static const advertisedServiceUuids = [
  '49535343-fe7d-4ae5-8fa9-9fafd205e455',
  '49535343-1e4d-4bd9-ba61-23c647249616',
  '49535343-8841-43f4-a8d4-ecbe34729bb3',
];
```

## Files to change

| File | Change |
|------|--------|
| `lib/src/models/device/scan_filter.dart` | **New.** `ScanFilter` value class |
| `lib/src/models/device/device.dart` | Add optional `ScanFilter?` param to `DeviceDiscoveryService.scanForDevices()` |
| `lib/src/models/device/device_scanner.dart` | Add optional `ScanFilter?` param to `scanForDevices()` |
| `lib/src/services/device_matcher.dart` | Add `serviceUuidsFor(DeviceType)` static method |
| `lib/src/services/blue_plus_discovery_service.dart` | Import `ScanFilter`, `DeviceMatcher`. In `scanForDevices()`, if filter provided, call `startScan(withServices: ..., withRemoteIds: ..., oneByOne: true)` |
| `lib/src/controllers/device_controller.dart` | Pass filter through to `service.scanForDevices(filter:)` |
| `lib/src/controllers/connection/scan_orchestrator.dart` | Accept optional `ScanFilter?` in `runScan()`, pass to `_scanner.scanForDevices()` |
| `lib/src/controllers/connection_manager.dart` | In `_connectImpl(scaleOnly: true)`: build `ScanFilter` when `Platform.isAndroid`, pass to `runScan()` |
| `lib/src/models/device/impl/acaia/acaia_scale.dart` | Add `advertisedServiceUuids` static const getter |

All other discovery services (`LinuxBleDiscoveryService`, `UniversalBleDiscoveryService`, serial services, simulated) — no changes (filter param added to interface, ignored in body).

## Testing

### Unit tests

- `ScanFilter.isFiltered` for null/empty/populated cases
- `DeviceMatcher.serviceUuidsFor(DeviceType.scale)` returns expected UUIDs
- `DeviceMatcher.serviceUuidsFor(DeviceType.machine)` returns expected UUIDs
- `BluePlusDiscoveryService` passes `withServices` + `withRemoteIds` when filter is provided
- `AcaiaScale.advertisedServiceUuids` returns 3 UUIDs

### Integration tests

- `scanAndConnectScale` with mock discovery service: verify filter params reach `startScan`
- Full connect path: verify no filter (unfiltered scan unchanged)

### End-to-end

- Real hardware: lock screen, wake DE1, verify scale reconnects via filtered scan
- Simulated mode: verify `FlutterBluePlus.startScan` receives correct filter parameters

## Open questions (resolved)

1. ~~Names vs service UUIDs for filtering?~~ → Service UUIDs. More universal, works at hardware level.
2. ~~Retry?~~ → No. User triggers manually.
3. ~~Non-preferred scale auto-connect?~~ → Keep current behavior. API clients handle picker.
4. ~~Apply on all platforms?~~ → Android only.
5. ~~Where to aggregate UUIDs?~~ → `DeviceMatcher.serviceUuidsFor()`, reading existing static `serviceIdentifier` fields.
6. ~~Acaia runtime UUIDs?~~ → New `advertisedServiceUuids` static getter with all 3 variants.
