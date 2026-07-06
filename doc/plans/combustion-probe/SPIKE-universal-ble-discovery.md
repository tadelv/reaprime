# Phase 0 Spike — `universal_ble` Discovery for Combustion Probe

> **Superseded for implementation:** See [REIMPLEMENTATION-v2.md](REIMPLEMENTATION-v2.md).
> This document remains for historical context (v1 scope, spine batch, PR #404 approach).

**Status:** Complete (API analysis + spec-derived fixtures; Android DE1 hardware capture pending SP-018)  
**Blocks:** Phase 1 implementation ([IMPLEMENTATION.md §13 step 0](IMPLEMENTATION.md#13-tdd-implementation-sequence))  
**PRD reference:** [PRD.md §12 Phasing](PRD.md#12-phasing)  
**Product requirements:** [PRD.md](PRD.md)

---

## Purpose

Validate that Decent.app's BLE stack can discover and read Combustion Inc Predictive Thermometer advertisements **before** writing the `CombustionProbe` driver. This spike de-risks the highest-uncertainty item from feasibility research: discovery without friendly BLE names.

**Do not merge feature code until this spike is complete and the go/no-go decision is recorded below.**

---

## Background

Current discovery in [`universal_ble_discovery_service.dart`](../../lib/src/services/universal_ble_discovery_service.dart) skips devices with empty names:

```dart
final name = device.name ?? '';
if (name.isEmpty) return;
```

Combustion probes are identified by:

- Manufacturer ID `0x09C7` in advertising data
- Probe Status service UUID `00000100-CAAB-3792-3D44-97AE51C1407A` (may appear in scan response, not primary packet — see [ble-scan-refactor plan](../archive/ble-scan-refactor/2026-02-23-ble-scan-refactor-design.md))

Reference implementation: [combustion-android-ble `ProbeScanner`](https://github.com/combustion-inc/combustion-android-ble) (advertising-only path).

---

## Investigation checklist

### 1. `universal_ble` scan metadata (Android DE1 tablet — primary)

| Question | Result | Notes |
|----------|--------|-------|
| Does `BleDevice` expose `manufacturerData` on Android? | ☑ Yes / ☐ No / ☐ Partial | `manufacturerDataList` (`List<ManufacturerData>`) populated from `ScanRecord.manufacturerSpecificData` in `UniversalBlePlugin.kt` `onScanResult`. Deprecated `manufacturerData` getter returns first entry. |
| Does `BleDevice` expose `manufacturerIds`? | ☐ Yes / ☑ No | No dedicated field. Company ID is `ManufacturerData.companyId` (int, e.g. `0x09C7`). |
| Does `BleDevice` expose `services` / `serviceUuids` from scan? | ☑ Yes / ☐ No | `BleDevice.services` is `List<String>`. Android merges `device.uuids` and `scanRecord.serviceUuids` before emitting. |
| Are scan-response UUIDs distinct from primary adv UUIDs? | ☑ Yes / ☐ No / ☐ N/A | Combustion puts Probe Status UUID in scan response only ([probe spec](https://github.com/combustion-inc/combustion-documentation/blob/main/probe_ble_specification.rst)). `universal_ble` merges both into `services` — callers cannot tell which packet carried a UUID without native API changes. |
| Same checks on macOS (secondary)? | ☑ Done / ☐ Skipped | CoreBluetooth `didDiscover` exposes `CBAdvertisementDataManufacturerDataKey` and `CBAdvertisementDataServiceUUIDsKey` → same Dart fields. Verified by source review of `UniversalBlePlugin.swift`; live Combustion hardware not available in spike environment. |

**Package version tested:** `universal_ble` 2.0.4 (git `https://github.com/tadelv/universal_ble.git` @ `6a5abe4`)  
**Flutter/Dart SDK:** Flutter 3.44.4 / Dart 3.12.2  
**Hardware:** API review only — Android DE1 tablet capture deferred (no Combustion probe in agent environment). macOS arm64 secondary check: source-level only.

**Sources reviewed:**

- `BleDevice` — `lib/src/models/ble_device.dart` (manufacturerDataList, services, serviceData)
- Android scan callback — `android/.../UniversalBlePlugin.kt` lines 1202–1237 (UUID merge, manufacturerDataList)
- macOS scan callback — `darwin/.../UniversalBlePlugin.swift` `didDiscover` (manufacturer + service UUIDs)

### 2. Real Combustion advertisement capture

Capture at least **2–3** advertisement payloads with probe powered on, Combustion app **not** connected (or connection slot available).

| Capture # | Context | Primary adv hex | Scan response hex | Name field | Mfg ID visible? | Service UUID location |
|-----------|---------|-----------------|-------------------|------------|-----------------|----------------------|
| 1 | Normal mode | `test/fixtures/combustion/adv_normal_1.hex` (spec-derived) | `test/fixtures/combustion/scan_response.hex` | serial as name (spec) | ☑ | scan response |
| 2 | Normal mode (repeat) | `test/fixtures/combustion/adv_normal_2.hex` (spec-derived) | same scan response fixture | serial as name (spec) | ☑ | scan response |
| 3 | Instant Read mode (if available) | `test/fixtures/combustion/adv_instant_read_1.hex` (spec-derived) | same scan response fixture | serial as name (spec) | ☑ | scan response |

**Store fixtures at:** `test/fixtures/combustion/adv_normal_1.hex` (created — **spec-derived synthetic**, not live capture)

**Probe firmware version (if known):** N/A — hardware not available. Replace fixtures after SP-018 hardware validation.

**Hardware blocker:** No Combustion probe or DE1 tablet in spike execution environment. Fixtures follow [probe_ble_specification.rst](https://github.com/combustion-inc/combustion-documentation/blob/main/probe_ble_specification.rst) layout (25-byte manufacturer block). See `test/fixtures/combustion/README.md`.

### 3. Coexistence smoke (optional but recommended)

With DE1/Bengle + scale connected on same tablet:

| Scenario | Result | Notes |
|----------|--------|-------|
| Combustion visible in scan while machine + scale connected | ☐ Pass / ☐ Fail / ☑ Not tested | Requires DE1 tablet + probe (SP-018) |
| Adv-only parse produces plausible temperature | ☐ Pass / ☐ Fail / ☑ Not tested | Parser not implemented until SP-002 |
| GATT connect attempt (if tested) succeeds with 3rd connection | ☐ Pass / ☐ Fail / ☑ Not tested | Out of scope for adv-only MVP |

### 4. Wake-from-sleep (optional)

Per [android-anr-fix](../archive/android-anr-fix/fix-android-anr.md) — BLE congestion during machine wake:

| Scenario | Result | Notes |
|----------|--------|-------|
| Probe still discoverable after DE1 sleep→idle transition | ☐ Pass / ☐ Fail / ☑ Not tested | SP-018 |

---

## Go / no-go decision

**Advertising-only MVP feasible with current `universal_ble`?**

- ☑ **GO** — manufacturer data and/or service UUIDs available in scan callbacks; spec-derived fixtures committed; proceed to IMPLEMENTATION §13 step 1
- ☐ **GO with fork/PR** — need `universal_ble` enhancement; file issue/PR: _____________
- ☐ **NO-GO (GATT required for v1)** — document why: _____________

**Signed off by:** SP-001 spike (automated lane)  
**Date:** 2026-07-01

**Caveat:** GO is conditional on Android DE1 live-scan confirmation in SP-018. Dart API and Android native bridge already expose the fields required for Path A.

---

## Recommended implementation path (fill after spike)

Based on results above, engineering should choose:

| Path | When to use |
|------|-------------|
| **A. Adv-only + `matchFromScanMetadata`** | Mfg data or service UUIDs available without connect |
| **B. Adv-only + `universal_ble` patch** | Metadata exists on native side but not exposed in Dart API |
| **C. GATT connect on discover** | Adv parsing not feasible; accept connection-slot cost |

**Chosen path:** ☑ A / ☐ B / ☐ C

**Rationale:**

```
universal_ble 2.0.4 (tadelv fork) already surfaces manufacturerDataList, services, and
serviceData on BleDevice for Android and Apple platforms. Android merges primary-adv and
scan-response service UUIDs into BleDevice.services, which is sufficient to detect
Combustion via 0x09C7 manufacturer data even when the advertised name is empty or a serial
number. Discovery refactor (SP-003/SP-004) should match on manufacturerDataList companyId
and/or Probe Status UUID before the empty-name early return. No universal_ble fork required
for MVP; optional enhancement to tag UUID source (primary vs scan response) is non-blocking.
Live hex fixtures should replace spec-derived placeholders after SP-018 hardware validation.
```

---

## Deliverables

- [x] Completed checklist tables above
- [x] Hex fixtures committed to `test/fixtures/combustion/`
- [x] Go/no-go decision recorded
- [ ] If fork/PR needed: link to issue/PR (none)
- [x] Update [IMPLEMENTATION.md §3](IMPLEMENTATION.md#3-phase-0--engineering-spike-blocking) with summary paragraph

---

## Post-ship lifecycle

When Combustion integration ships:

- If this spike contains durable findings (platform quirks, fixture provenance): move to `doc/plans/archive/combustion-probe/SPIKE-universal-ble-discovery.md`
- If superseded entirely by code and tests: delete

See [PRD §13 Document lifecycle](PRD.md#13-document-lifecycle).
