# Phase 0 Spike — `universal_ble` Discovery for Combustion Probe

**Status:** Not started  
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
| Does `BleDevice` expose `manufacturerData` on Android? | ☐ Yes / ☐ No / ☐ Partial | |
| Does `BleDevice` expose `manufacturerIds`? | ☐ Yes / ☐ No | |
| Does `BleDevice` expose `services` / `serviceUuids` from scan? | ☐ Yes / ☐ No | |
| Are scan-response UUIDs distinct from primary adv UUIDs? | ☐ Yes / ☐ No / ☐ N/A | |
| Same checks on macOS (secondary)? | ☐ Done / ☐ Skipped | |

**Package version tested:** `universal_ble` _____________  
**Flutter/Dart SDK:** _____________  
**Hardware:** _____________ (tablet model, Android version)

### 2. Real Combustion advertisement capture

Capture at least **2–3** advertisement payloads with probe powered on, Combustion app **not** connected (or connection slot available).

| Capture # | Context | Primary adv hex | Scan response hex | Name field | Mfg ID visible? | Service UUID location |
|-----------|---------|-----------------|-------------------|------------|-----------------|----------------------|
| 1 | Normal mode | | | | ☐ | primary / scan response / both |
| 2 | Normal mode (repeat) | | | | ☐ | |
| 3 | Instant Read mode (if available) | | | | ☐ | |

**Store fixtures at:** `test/fixtures/combustion/adv_normal_1.hex` (create during spike)

**Probe firmware version (if known):** _____________

### 3. Coexistence smoke (optional but recommended)

With DE1/Bengle + scale connected on same tablet:

| Scenario | Result | Notes |
|----------|--------|-------|
| Combustion visible in scan while machine + scale connected | ☐ Pass / ☐ Fail | |
| Adv-only parse produces plausible temperature | ☐ Pass / ☐ Fail | |
| GATT connect attempt (if tested) succeeds with 3rd connection | ☐ Pass / ☐ Fail / ☐ Not tested | |

### 4. Wake-from-sleep (optional)

Per [android-anr-fix](../archive/android-anr-fix/fix-android-anr.md) — BLE congestion during machine wake:

| Scenario | Result | Notes |
|----------|--------|-------|
| Probe still discoverable after DE1 sleep→idle transition | ☐ Pass / ☐ Fail / ☐ Not tested | |

---

## Go / no-go decision

**Advertising-only MVP feasible with current `universal_ble`?**

- ☐ **GO** — manufacturer data and/or service UUIDs available in scan callbacks; fixtures captured; proceed to IMPLEMENTATION §13 step 1
- ☐ **GO with fork/PR** — need `universal_ble` enhancement; file issue/PR: _____________
- ☐ **NO-GO (GATT required for v1)** — document why: _____________

**Signed off by:** _____________  
**Date:** _____________

---

## Recommended implementation path (fill after spike)

Based on results above, engineering should choose:

| Path | When to use |
|------|-------------|
| **A. Adv-only + `matchFromScanMetadata`** | Mfg data or service UUIDs available without connect |
| **B. Adv-only + `universal_ble` patch** | Metadata exists on native side but not exposed in Dart API |
| **C. GATT connect on discover** | Adv parsing not feasible; accept connection-slot cost |

**Chosen path:** ☐ A / ☐ B / ☐ C

**Rationale:**

```
(free text)
```

---

## Deliverables

- [ ] Completed checklist tables above
- [ ] Hex fixtures committed to `test/fixtures/combustion/`
- [ ] Go/no-go decision recorded
- [ ] If fork/PR needed: link to issue/PR
- [ ] Update [IMPLEMENTATION.md §3](IMPLEMENTATION.md#3-phase-0--engineering-spike-blocking) with summary paragraph

---

## Post-ship lifecycle

When Combustion integration ships:

- If this spike contains durable findings (platform quirks, fixture provenance): move to `doc/plans/archive/combustion-probe/SPIKE-universal-ble-discovery.md`
- If superseded entirely by code and tests: delete

See [PRD §13 Document lifecycle](PRD.md#13-document-lifecycle).
