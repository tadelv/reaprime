# Quick Connect — direct device connection without scanning

## Why

On app startup (and on auto-reconnect after a transient BLE drop), the full
scan → match → connect cycle takes 10-15 seconds. Most of that time is spent
scanning for devices we already know about — the preferred machine and scale
have connected before, their device IDs are persisted, and the BLE/serial
stacks can connect directly by device ID without scanning first.

Today the flow is always:

1. Scan all devices (BLE unfiltered scan, serial port enumeration + probing)
2. Match each result through `DeviceMatcher.match()` (BLE) or `_detectDevice()`
   (serial) to identify the device class
3. `EarlyConnectWatcher` connects preferred devices as they appear mid-scan
4. Full scan timeout before giving up

Quick connect skips steps 1-2 for known devices: construct the transport and
device directly from persisted metadata, connect immediately, and fall back to
the full scan only if the direct connect fails.

## What Changes

- **Enrich `RememberedDevice`** with two new fields:
  `DeviceImplementation implementation` (which concrete class to construct)
  and `TransportType transportType` (which transport: BLE, serial, WiFi).
  `RememberedDevice` becomes the source of truth for preferred-device
  metadata, not just a display record.

- **Move `TransportType`** from `unified_de1_transport.dart` to
  `data_transport.dart`. Add `TransportType get transportType` to
  `DataTransport` so every transport self-reports its type. Add `wifi`
  variant. `UnifiedDe1Transport` reads from `_transport.transportType`
  instead of `is`-check inference.

- **Add `DeviceImplementation` enum** — one value per concrete device class
  (`unifiedDe1`, `bengle`, `decentScale`, `acaiaScale`, etc.). Persisted as
  the wire contract (same pattern as `DeviceType.name`).

- **Add `DeviceImplementation get implementation`** and
  **`TransportType get transportType`** to the `Device` interface. Each
  concrete device class returns its enum value (one-liner). `transportType`
  delegates to the underlying transport.

- **Create `DeviceFactory`** in `lib/src/services/` — maps
  `DeviceImplementation` → concrete `Device` constructor. Used by
  `tryQuickConnect` to construct devices without name-matching.

- **Add `tryQuickConnect(RememberedDevice)` to `DeviceDiscoveryService`**
  (default: `return null`). Each transport-specific discovery service
  implements it:
  - **BLE:** `getSystemDevices` on Apple (cache lookup), direct
    `UniversalBle.connect(deviceId)` on Android/Linux/Windows. Construct
    `BleDevice` + `UniversalBleTransport` + `DeviceFactory.create()` →
    `connect()` → `onConnect()`. GATT-133 retry (1 retry, ~1s delay).
    Identity check: verify `onConnect()` succeeded and model matches for
    machines. Short timeout (~5-10s).
  - **Serial:** open `SerialPort(storedPath)`, run existing `_detectDevice()`
    active probe, verify result matches expected `DeviceImplementation`.
    If match → `onConnect()` → return. If not → close port, return `null`.
  - **WiFi:** reuse existing `WifiIpCache` + manual endpoint logic. Lower
    priority — can ship after BLE + serial.

- **Expose `tryQuickConnect` through `DeviceScanner` / `DeviceController`** —
  iterates services, returns first success.

- **Add `adoptDevice()` / `adoptScale()` to controllers** —
  `De1Controller.adoptDevice(De1Interface)` and
  `ScaleController.adoptScale(Scale)` skip `onConnect()` (already done by
  `tryQuickConnect`) and wire up stream subscriptions directly.

- **Inject `RememberedDevicesController` into `ConnectionManager`** —
  registry lookup for preferred-device metadata.

- **Modify `ConnectionManager._executeConnect()`** — before
  `ScanOrchestrator.runScan()`, look up preferred machine/scale in the
  registry, call `deviceController.tryQuickConnect()`. On success → adopt
  device → `_finalizePhase()`. On `null` → fall through to existing scan
  path unchanged. Partial success (machine connected, scale didn't) →
  scale-only scan. Quick-connect is tried in **all** connect cycles
  (startup, manual reconnect, recovery mode).

- **Migration:** old `RememberedDevice` records (missing `implementation`
  and `transportType`) load with nulls. On first load, infer
  `implementation` from `name` via `DeviceMatcher` name-matching logic.
  `transportType` is inferred from `deviceId` format for old records only
  (new records get it from `Device.transportType`). Quick-connect works on
  first launch after update — no second-launch wait.

No breaking changes. The scan path is unchanged — it's the fallback. The
`ConnectionStatus` phase stream is unchanged on the happy path (quick-connect
is invisible — no new phases, no new status fields). Skins see the existing
`connectingMachine → connectingScale → ready` transitions, just faster.

## Goals / Non-Goals

**Goals:**
- Skip scanning for known preferred devices on startup and reconnect.
- Fall back to full scan gracefully when quick-connect fails.
- Enrich `RememberedDevice` with enough metadata to construct the right
  device class + transport without name-matching or port-probing.
- One code path for all connect cycles (startup, manual, recovery).

**Non-Goals:**
- Replacing the scan path — scan is the fallback and stays unchanged.
- Quick-connect for non-preferred devices (only preferred machine/scale).
- Multi-transport failover (if BLE quick-connect fails, don't try WiFi for
  the same physical device — fall back to scan, which discovers all
  transports).
- Quick-connect for sensors (scope is machine + scale, matching
  preferred-device model).
- New API endpoints or WebSocket changes.
- New `ConnectionStatus` phases or fields.

## Decisions

### Decision: Enrich `RememberedDevice`, not a separate metadata store
**Choice:** Extend `RememberedDevice` with `implementation` + `transportType`.
Use it as the preferred-device source of truth.
**Why:** `RememberedDevice` already persists `{id, name, type}`, is
cross-transport, has `fromDevice()`, and has 4 test files. Adding two fields
is additive to the JSON — old records decode fine. A separate metadata store
would duplicate the registry and add migration complexity.
**Alternative:** Keep preferred IDs as plain strings, add a parallel
`PreferredDeviceMetadata` record — rejected (more moving parts, zero
benefit).

### Decision: `tryQuickConnect` on `DeviceDiscoveryService`, exposed via `DeviceScanner`
**Choice:** Each discovery service implements `tryQuickConnect(RememberedDevice)`
(default: `return null`). `DeviceController` exposes it through `DeviceScanner`.
`ConnectionManager` calls it before `ScanOrchestrator.runScan()`.
**Why:** Respects the hard rule (BLE imports stay in `lib/src/services/ble/`).
`ConnectionManager` already depends on `DeviceScanner` — no new dependency.
The fake `DeviceScanner` in tests can return `null` to force the scan path.
**Alternative:** A new `QuickConnectResolver` that knows concrete service
types — rejected (breaks transport abstraction).

### Decision: `tryQuickConnect` returns a connected-and-ready `Device`
**Choice:** The full connect cycle (transport + `onConnect()` + identity check)
happens inside `tryQuickConnect`. Returns a ready `Device` or `null`.
**Why:** `ConnectionManager` gets a clean decision point: device or null. The
retry (GATT-133) and identity check live inside the attempt, not in the
controller. The controller's `adoptDevice()` skips `onConnect()` and wires
subscriptions directly.
**Alternative:** Return a device with transport connected but `onConnect()`
not called — rejected (ambiguous return, fallback decision can't be made
synchronously).

### Decision: `DeviceImplementation` enum as the device-class identifier
**Choice:** An enum with one value per concrete device class. Persisted as
the wire contract. Mapped to constructors via `DeviceFactory`.
**Why:** Type-safe, exhaustive (compiler warns on new devices), self-
documenting. Mirrors the existing `DeviceType` pattern. A string class
identifier would be brittle (renames orphan records).
**Alternative:** Store the advertised name and reuse `DeviceMatcher.match()` —
rejected (still calls the parser; name can be misleading — Bengle advertising
as "DE1").

### Decision: `DeviceFactory` in `lib/src/services/`
**Choice:** A dedicated class that maps `DeviceImplementation` → `Device`
constructor. Both BLE and serial discovery services use it.
**Why:** Single source of truth for construction. `DeviceMatcher` stays
untouched for the scan path. `DeviceMatcher` could later delegate to
`DeviceFactory` internally, but that's a separate cleanup.
**Alternative:** Put the factory on `DeviceMatcher` — rejected (muddies its
responsibility). Put it on `DeviceImplementation` enum — rejected (inverts
dependency direction — models would import implementations).

### Decision: `transportType` on `DataTransport`, not inferred from ID
**Choice:** Move `TransportType` to `data_transport.dart`. Add
`TransportType get transportType` to `DataTransport`. Each transport
self-reports. `Device` exposes it by delegating to its transport.
**Why:** `TransportType` already exists in `UnifiedDe1Transport` (used as a
dispatch mechanism for BLE vs serial read/write/connect). Moving it to the
common base is a natural lift — transports know their own type, no string
parsing heuristic. `UnifiedDe1Transport` already infers via `is` checks; this
replaces the inference with a direct read.
**Alternative:** Infer `transportType` from `deviceId` format — rejected for
new records (heuristic). Used only for old-record migration.

### Decision: Quick-connect in all connect cycles
**Choice:** `_executeConnect()` always tries quick-connect first — startup,
manual reconnect, recovery mode. One code path, no flags.
**Why:** The most common disconnect scenario is a transient BLE link drop —
device is still there, quick-connect reconnects in ~2-3s vs ~10-15s for full
scan. If the device is truly gone, quick-connect fails after timeout and scan
runs immediately. The extra time is imperceptible compared to the scan that
follows.
**Alternative:** Quick-connect only for startup — rejected (misses the
highest-value case: recovery from transient disconnects).

### Decision: Quick-connect is invisible in the phase stream
**Choice:** No new `ConnectionPhase`. No new `ConnectionStatus` field. The
phase stream stays at `idle` during the quick-connect attempt. On success:
`idle → connectingMachine → connectingScale → ready` (or directly to
`connectingMachine → ready` if both succeed). On failure: `idle → scanning`
(existing flow). The `StatusPublisher` transition table is unchanged.
**Why:** The phases describe what's happening (connecting to machine), not
how we got there (scan vs direct). No API contract changes for skins.
**Alternative:** New `quickConnecting` phase — rejected (API contract change,
all skins need updating, no user benefit for a ~3s invisible optimization).

### Decision: Migration via name inference, no explicit migration code
**Choice:** Old `RememberedDevice` records load with nulls for new fields.
On load, infer `implementation` from `name` via `DeviceMatcher` name-matching.
Infer `transportType` from `deviceId` format (MAC/UUID → BLE, `/dev/` →
serial, `wifi:` → WiFi). Quick-connect works on first launch after update.
**Why:** `DeviceMatcher` already does name → class mapping. Running it once
on load for old records is free. No migration code, no version checks.
**Alternative:** Wait for organic enrichment on next connect — rejected
(quick-connect wouldn't work until second launch after update).

### Decision: GATT-133 retry inside `tryQuickConnect`
**Choice:** On GATT-133 / `BleConnectException`, wait ~1s, retry once. If
second attempt fails, return `null` → scan fallback.
**Why:** GATT-133 on cold boot is common on Android (Teclast tablets). Without
retry, quick-connect would fail on every cold boot — the most common case.
`EarlyConnectWatcher` already uses this retry pattern; we replicate it.

### Decision: Identity check during `onConnect()`
**Choice:** After `transport.connect()` + `device.onConnect()`, verify the
device identity. For machines: compare `v13Model` against the stored
`implementation` (UnifiedDe1 vs Bengle). For scales: `BleServiceIdentifier`
verification during `onConnect()` already catches wrong services. If identity
doesn't match, disconnect and return `null`.
**Why:** Catches the "different device at same address" case (rare but
possible). The check is cheap — `onConnect()` already reads `v13Model` for
machines.

## Data Flow

```
  App startup / reconnect
       │
       ▼
  ConnectionManager._executeConnect()
       │
       ├─ Look up preferred machine + scale in RememberedDevicesController
       │  (by preferredMachineId / preferredScaleId)
       │
       ├─ For machine: deviceController.tryQuickConnect(machineRemembered)
       │    │
       │    ├─ BLE: getSystemDevices (Apple) / direct connect (Android)
       │    │       → BleDevice(deviceId:) → UniversalBleTransport
       │    │       → DeviceFactory.create(implementation, transport)
       │    │       → transport.connect() → device.onConnect()
       │    │       → identity check (model match)
       │    │       → return connected Device or null
       │    │
       │    ├─ Serial: SerialPort(storedPath) → _detectDevice()
       │    │         → verify match → onConnect() → return Device or null
       │    │
       │    └─ WiFi: WifiIpCache → connect → onConnect() → return Device or null
       │
       ├─ If machine returned: adoptDevice() → De1Controller
       │  If scale returned: adoptScale() → ScaleController
       │  Both success → _finalizePhase() → ready. DONE.
       │
       ├─ If machine null → fall through to ScanOrchestrator.runScan()
       │  (existing scan → match → EarlyConnectWatcher → connect)
       │
       └─ If machine adopted but scale null → scale-only scan
          (scanAndConnectScale)
```

## Risks / Trade-offs

- **Platform BLE feasibility (iOS):** CoreBluetooth requires a `CBPeripheral`
  object from scanning or `retrieveConnectedPeripherals`. `getSystemDevices`
  handles this — if the device is in the system cache, we get it. If not,
  `tryQuickConnect` returns `null` immediately (no timeout waste) and scan
  runs. On Android (primary platform), direct connect by MAC works without
  scanning.

- **Stale serial port path:** USB device moved to a different port yields a
  stale stored path. `SerialPort(path)` open fails → `tryQuickConnect`
  returns `null` → scan re-probes all ports and finds the device at its new
  path. The existing `_detectDevice` identity check also catches "different
  device at same port."

- **GATT-133 on cold boot:** Handled by internal retry (1 retry, ~1s delay).
  If both attempts fail, scan fallback runs — `EarlyConnectWatcher` does its
  own retry. No regression.

- **BLE supervision timeout:** Quick-connect doesn't change the machine-first
  then scale ordering. The 3s deferral (from the BLE supervision timeout fix)
  applies to the wake-from-sleep path, not the initial connect path. No
  additional timing concerns.

- **`Device` interface change:** Adding two getters to `Device` touches ~20
  device classes. Each is a one-liner. The change is additive — no existing
  code breaks. `SimulatedDevice` and mock devices also implement the getters.

- **`RememberedDevice` wire contract:** `implementation` and `transportType`
  are persisted as enum `.name` strings. Old records without these fields
  load with nulls. The `fromJson` implementation already handles missing
  fields gracefully (returns `null` for unknown types). Renaming a
  `DeviceImplementation` value would orphan stored records — same constraint
  as the existing `DeviceType.name` contract.

- **`ConnectionManager` blast radius:** 109 incoming references in the
  knowledge graph. But the change is additive — a new code path before the
  existing scan path. The existing scan path is unchanged. Tests with the
  fake scanner verify both paths.

## Impact

- **New code:**
  - `lib/src/services/device_factory.dart` — `DeviceImplementation` → `Device`
    constructor map.
  - `DeviceImplementation` enum (location: `lib/src/models/device/`).
- **Modified:**
  - `lib/src/models/device/transport/data_transport.dart` — `TransportType`
    enum moves here, gains `wifi`. `DataTransport` gains
    `TransportType get transportType`.
  - `lib/src/services/ble/universal_ble_transport.dart` — implements
    `transportType` getter.
  - `lib/src/services/serial/serial_service_desktop.dart` — implements
    `transportType` getter on `_DesktopSerialPort`.
  - `lib/src/models/device/transport/web_socket_transport.dart` — implements
    `transportType` getter on `WsTransport`.
  - `lib/src/models/device/impl/de1/unified_de1/unified_de1_transport.dart`
    — reads `_transport.transportType` instead of `is`-check inference.
    `TransportType` enum removed from this file (moved to `data_transport.dart`).
  - `lib/src/models/device/device.dart` — `Device` interface gains
    `DeviceImplementation get implementation` and
    `TransportType get transportType`.
  - ~20 device implementation files — one-liner getter implementations.
  - `lib/src/models/device/remembered_device.dart` — gains
    `implementation` + `transportType` fields, updated `toJson`/`fromJson`/
    `fromDevice`, migration inference.
  - `lib/src/models/device/device.dart` (`DeviceDiscoveryService`) — gains
    `Future<Device?> tryQuickConnect(RememberedDevice)` (default: `null`).
  - `lib/src/models/device/device_scanner.dart` (`DeviceScanner`) — gains
    `Future<Device?> tryQuickConnect(RememberedDevice)`.
  - `lib/src/controllers/device_controller.dart` — implements
    `tryQuickConnect` (iterates services).
  - `lib/src/services/universal_ble_discovery_service.dart` — implements
    `tryQuickConnect` (BLE path).
  - `lib/src/services/serial/serial_service_desktop.dart` — implements
    `tryQuickConnect` (serial path).
  - `lib/src/services/serial/serial_service_android.dart` — implements
    `tryQuickConnect` (serial path).
  - `lib/src/controllers/de1_controller.dart` — gains `adoptDevice()`.
  - `lib/src/controllers/scale_controller.dart` — gains `adoptScale()`.
  - `lib/src/controllers/connection_manager.dart` — injects
    `RememberedDevicesController`, modifies `_executeConnect()`.
  - `lib/src/controllers/remembered_devices_controller.dart` —
    `fromDevice()` enriched, migration inference on load.
  - `main.dart` — pass `RememberedDevicesController` to `ConnectionManager`.
- **Lower priority (can ship after):**
  - `lib/src/services/wifi/wifi_scale_discovery_service.dart` — implements
    `tryQuickConnect` (WiFi path).
- **Docs:**
  - `doc/DeviceManagement.md` — quick-connect flow, updated connection flow
    diagram.
  - `doc/AI_BLE_NOTES.md` — quick-connect GATT-133 retry pattern.
- **Unchanged:** `DeviceMatcher`, `ScanOrchestrator`, `EarlyConnectWatcher`,
  `PolicyResolver`, `StatusPublisher`, `DisconnectSupervisor`, API endpoints,
  WebSocket schema, skins.

## Testing

Layered:

1. **Pure unit tests** (no mocks):
   - `DeviceFactory` — each `DeviceImplementation` → correct `Device` class.
   - `RememberedDevice` — encoding/decoding with new fields, old-record
     migration inference, `fromDevice()` enrichment.
   - `DataTransport.transportType` — each transport returns correct type.
   - `Device.implementation` — each device class returns correct enum.

2. **Discovery service tests** (platform mocks):
   - `UniversalBleDiscoveryService.tryQuickConnect` — mock `UniversalBle`
     statics. Test: success, failure, GATT-133 retry, identity mismatch,
     `getSystemDevices` cache miss on Apple.
   - `SerialServiceDesktop.tryQuickConnect` — mock `SerialPort`. Test:
     known-port detection, wrong device, port gone.

3. **ConnectionManager integration tests** (fake scanner):
   - Quick-connect succeeds → no scan → ready.
   - Quick-connect returns null → scan runs → connects normally.
   - Partial success → machine adopted, scale-only scan.
   - Recovery mode → retry tries quick-connect first.

4. **Controller tests:**
   - `adoptDevice()` / `adoptScale()` — subscriptions wired, `onConnect()`
     not called, `connectionState` is `connected`.

## Implementation Phases

### Phase 0 — Branch
- Cut feature branch from `main` (`feature/quick-connect`).

### Phase 1 — Foundation: types & getters (no behavior change)
- Move `TransportType` enum → `data_transport.dart`, add `wifi`.
- Add `TransportType get transportType` to `DataTransport`.
- Implement in `UniversalBleTransport`, `_DesktopSerialPort`, `WsTransport`.
- Update `UnifiedDe1Transport` to read `_transport.transportType`.
- Define `DeviceImplementation` enum.
- Add `DeviceImplementation get implementation` + `TransportType get
  transportType` to `Device` interface.
- One-liner implementations across all device classes.
- Create `DeviceFactory`.
- Tests: pure unit tests for getters, factory, enum values.

### Phase 2 — Data model: enrich `RememberedDevice` (no behavior change)
- Add `implementation` + `transportType` fields.
- `toJson`/`fromJson` — old records load with nulls.
- `fromDevice()` captures both new fields.
- Migration inference: name → `implementation` for old records.
- Tests: encoding/decoding, migration, enrichment.

### Phase 3 — Interface: `tryQuickConnect` contract (no behavior change)
- `Future<Device?> tryQuickConnect(RememberedDevice)` on
  `DeviceDiscoveryService` (default: `null`).
- Expose through `DeviceScanner` / `DeviceController`.
- Tests: fake scanner with configurable returns.

### Phase 4 — BLE quick-connect
- Implement in `UniversalBleDiscoveryService`.
- `getSystemDevices` on Apple, direct `connect(deviceId)` elsewhere.
- GATT-133 retry, identity check, short timeout.
- Tests: mock `UniversalBle` statics.

### Phase 5 — Serial quick-connect
- Implement in `SerialServiceDesktop` + `SerialServiceAndroid`.
- Open known port, run `_detectDevice()`, verify match.
- Tests: mock `SerialPort`.

### Phase 5b — WiFi quick-connect (lower priority)
- Implement in `WifiScaleDiscoveryService` using `WifiIpCache`.
- Tests: mock WebSocket.

### Phase 6 — Controller adoption + ConnectionManager integration (behavior change)
- `adoptDevice()` / `adoptScale()` on controllers.
- Inject `RememberedDevicesController` into `ConnectionManager`.
- Modify `_executeConnect()`: quick-connect → adopt → ready. Null → scan.
- Partial success → scale-only scan.
- Tests: ConnectionManager integration with fake scanner.

### Phase 7 — Wire-up + docs
- Pass `RememberedDevicesController` to `ConnectionManager` in `main.dart`.
- Update `doc/DeviceManagement.md`, `doc/AI_BLE_NOTES.md`.
- Archive this plan doc to `doc/plans/archive/quick-connect/`.
- `flutter test` + `flutter analyze`.
- Smoke test: `scripts/sb-dev.sh start --connect-machine MockDe1`
  (quick-connect returns null for simulated devices → scan fallback →
  verifies no regression).

## Related Files

### Source of truth (read before starting)
- `doc/AI_BLE_NOTES.md` — BLE footguns, transport threading, connection lifecycle.
- `doc/DeviceManagement.md` — connection flow, phase transitions, device policy.
- `lib/src/services/device_matcher.dart` — name → device class matching.
- `lib/src/controllers/connection_manager.dart` — connect orchestration.
- `lib/src/controllers/connection/early_connect_watcher.dart` — mid-scan connect.
- `lib/src/controllers/connection/scan_orchestrator.dart` — scan lifecycle.
- `lib/src/models/device/remembered_device.dart` — persisted device metadata.
- `lib/src/models/device/impl/de1/unified_de1/unified_de1_transport.dart` —
  existing `TransportType` enum + dispatch.
- `lib/src/models/device/transport/data_transport.dart` — transport base interface.

### Obsidian notes
- `Decent/ReaPrime/BLE Supervision Timeout on Scale Connect.md` — radio
  contention timing, GATT-133, connection lifecycle footguns.

### Knowledge graph
- Community 4 ("controllers-state") — `DeviceMatcher`, `ConnectionManager`,
  `RememberedDevice`, `ScanOrchestrator`, `EarlyConnectWatcher`,
  `UniversalBleDiscoveryService`, `SettingsController` all in this cluster.
- `DeviceMatcher` has 0 external callers outside
  `UniversalBleDiscoveryService` (and tests) — bypass is a single call-site
  change.
- `ConnectionManager` has 109 incoming references — highest blast radius,
  but the change is additive (new path before existing scan).