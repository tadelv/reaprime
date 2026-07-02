# Combustion Probe — Hardware Validation Protocol

Manual sign-off checklist for Combustion Inc Predictive Thermometer integration on the **Android DE1 tablet** (primary platform). Use this document after Phase 3 implementation is code-complete and simulate/E2E tests pass.

**Related:** [PRD.md](PRD.md) · [IMPLEMENTATION.md](IMPLEMENTATION.md) · [SPIKE-universal-ble-discovery.md](SPIKE-universal-ble-discovery.md) · E2E recipe [combustion-probe-steam-stop.md](../../../.agents/skills/decent-app/scenarios/combustion-probe-steam-stop.md)

---

## 1. Purpose

Validate real-hardware behavior that simulate mode and unit tests cannot cover:

- Concurrent BLE: DE1/Bengle + scale + Combustion probe on one tablet
- Probe discovery after machine wake-from-sleep
- Stop-at-temperature latency and accuracy during milk steaming
- Live fixture capture to replace spec-derived test data

**Audience:** Engineer performing sign-off before merging Combustion probe integration to `main`.

---

## 2. Prerequisites

| Item | Requirement |
|------|-------------|
| **Hardware** | Android DE1 tablet, DE1 or Bengle machine, compatible scale, Combustion Predictive Thermometer |
| **Probe state** | Probe powered on; Combustion mobile app **not** connected (preserves BLE connection budget) |
| **App build** | Decent.app build with Combustion integration (not `--dart-define=simulate=1`) |
| **Network** | Optional: USB debugging for `adb logcat`; REST on port 8080 for scripted checks |
| **Reference thermometer** | Calibrated reference (optional but recommended for stop-accuracy sign-off) |

### Log retrieval (Android)

```bash
adb shell run-as net.tadel.reaprime cat app_flutter/log.txt
adb logcat | rg -i 'Combustion|SteamSequencer|SensorController|UniversalBle'
```

---

## 3. Firmware and specification pins

Record these values on every sign-off run. Implementation targets the **DRAFT** Combustion BLE spec — behavior may drift with probe firmware updates.

| Pin | Value to record |
|-----|-----------------|
| **Combustion BLE spec** | [probe_ble_specification.rst](https://github.com/combustion-inc/combustion-documentation/blob/main/probe_ble_specification.rst) — **DRAFT** |
| **Probe firmware version** | _____________ (from Combustion app or probe label) |
| **Decent.app commit / build** | _____________ |
| **Machine model** | DE1 / Bengle: _____________ |
| **Machine firmware** | _____________ |
| **Scale model** | _____________ |
| **`universal_ble` package** | 2.0.4 @ `6a5abe4` (tadelv fork) unless upgraded |

If probe firmware differs from the version used during development, re-run the fixture capture section (§7) and note any parse or discovery regressions.

---

## 4. Fixture provenance

Phase 0 (SP-001) committed **spec-derived synthetic** fixtures — not live hardware captures:

| File | Status |
|------|--------|
| `test/fixtures/combustion/adv_normal_1.hex` | Synthetic (spec layout) |
| `test/fixtures/combustion/adv_normal_2.hex` | Synthetic (spec layout) |
| `test/fixtures/combustion/adv_instant_read_1.hex` | Synthetic (spec layout) |
| `test/fixtures/combustion/scan_response.hex` | Synthetic (Probe Status UUID) |

See `test/fixtures/combustion/README.md` for byte layout.

**Hardware validation deliverable:** Replace at least one normal-mode primary advertisement and the scan-response payload with **live captures** from the DE1 tablet (§7). Update the README provenance table with capture date, probe firmware, and capture context.

---

## 5. Pre-flight checks

Complete before scenario testing.

- [ ] Machine connects and reaches `idle` via app UI or `GET /api/v1/machine/state`
- [ ] Scale connects and reports weight on `/ws/v1/scale/snapshot` (or UI)
- [ ] Combustion probe appears in device discovery list
- [ ] Probe listed in `GET /api/v1/sensors` with vendor **Combustion Inc**
- [ ] `GET /ws/v1/sensors/{probeId}/snapshot` emits temperature frames (~250 ms interval in normal advertising mode)
- [ ] Preferred probe settings (`preferredSteamProbeId`, `preferredShotProbeId`) set if multiple sensors present

---

## 6. Test scenarios

### 6.1 Concurrent connection — DE1 + scale + probe

**Goal:** Confirm all three peripherals coexist without discovery drops, connection failures, or ANR-style BLE congestion (NFR-3).

| Step | Action | Pass criteria |
|------|--------|---------------|
| 1 | Cold start app with machine, scale, and probe powered and in range | All three appear in device list within two scan cycles |
| 2 | Connect machine, then scale (normal user flow) | `ConnectionStatus` reaches `ready`; probe still visible in sensor list |
| 3 | Verify probe temperature stream while machine + scale connected | WS snapshot updates continuously; no parse errors in log |
| 4 | Pull one espresso shot with scale connected | Shot completes; scale weight recorded; probe stream unaffected |
| 5 | Run steam session (§6.3) with all three connected | Steam completes or stop-at-temp fires; no disconnect storm in log |

**Sign-off**

- [ ] Pass — all steps met
- [ ] Fail — notes: _____________

---

### 6.2 Wake-from-sleep discovery

**Goal:** Probe remains discoverable and streaming after DE1 sleep→idle transition ([android-anr-fix lesson](../archive/android-anr-fix/fix-android-anr.md), SPIKE §4).

| Step | Action | Pass criteria |
|------|--------|---------------|
| 1 | Establish steady state: machine `idle`, scale connected, probe streaming | Baseline confirmed |
| 2 | Put DE1 to sleep (power button or idle timeout per machine settings) | Machine state transitions to sleep |
| 3 | Wait ≥ 30 s | App remains responsive; foreground service active if configured |
| 4 | Wake machine to `idle` (tap screen / power) | `De1StateManager` triggers scale re-scan path; machine reconnects |
| 5 | Within 60 s of wake, verify probe | Probe still in `GET /api/v1/sensors`; temperature frames resume |
| 6 | Optional: repeat sleep/wake cycle 3× | Probe rediscovery succeeds each cycle |

**Sign-off**

- [ ] Pass — probe discoverable after wake
- [ ] Fail — notes: _____________

---

### 6.3 Stop-at-temperature — latency and accuracy

**Goal:** App-side steam stop fires when probe reading crosses target; latency acceptable for milk steaming (NFR-4: ~250 ms advertising interval + processing).

**Setup**

1. Set `stopAtTemperature` to a reachable target (e.g. **55 °C** for water/milk test, or product-realistic **65 °C**).
2. Set preferred steam probe to the Combustion sensor if multiple sensors exist.
3. Confirm `gatewayMode` is not `full` (OD-6: app-side stop inert in full gateway mode).

| Step | Action | Pass criteria |
|------|--------|---------------|
| 1 | Subscribe to machine state WS and probe snapshot WS | Both streams active |
| 2 | `PUT /api/v1/machine/state/steam` (or UI steam) | Machine enters `steam` |
| 3 | Heat milk/water until probe approaches target | Probe temp monotonic rise in WS frames |
| 4 | Observe stop event | Machine returns to `idle` within **≤ 2 advertising intervals** (~500 ms) after probe reading ≥ target |
| 5 | Check logs | `SteamSequencer` logs app-side stop with probe temp and target |
| 6 | `GET /api/v1/steams/latest` + full record | `milkTemperature` populated on late frames; `stopAtTemperature` matches workflow |
| 7 | Optional accuracy | Probe-reported stop temp within **±2 °C** of reference thermometer at stop moment |

**Expected latency budget**

| Component | Typical |
|-----------|---------|
| Combustion normal-mode advertising | ~250 ms |
| App parse + sequencer compare | < 100 ms |
| Machine state transition to `idle` | machine-dependent |
| **Total (probe cross → idle request)** | **≤ ~500 ms** under nominal conditions |

**Sign-off**

- [ ] Pass — stop fires once per session; latency within budget; `milkTemperature` recorded
- [ ] Fail — notes: _____________

---

### 6.4 Probe disconnect mid-steam (safety)

**Goal:** `_probeLost` disables stop-at-temp; no false stop from stale temperature (FR-S6).

| Step | Action | Pass criteria |
|------|--------|---------------|
| 1 | Start steam with `stopAtTemperature > 0` | Steam active |
| 2 | Power off probe or move out of range | Probe disconnect logged |
| 3 | Continue steam briefly | Machine does **not** stop solely due to stale last-known temp |
| 4 | Check logs | `probeLost` or equivalent warning; no erroneous idle request |

**Sign-off**

- [ ] Pass
- [ ] Fail — notes: _____________

---

### 6.5 Shot probe temperature (Phase 3)

**Goal:** Live and persisted probe temperature during espresso (FR-B1–B5).

| Step | Action | Pass criteria |
|------|--------|---------------|
| 1 | Set preferred shot probe to Combustion sensor | Setting saved |
| 2 | Pull a shot with probe in cup/pitcher | Realtime shot UI shows probe temp when connected |
| 3 | `GET /api/v1/shots/latest` (full record) | `probeTemperature` non-null on at least one snapshot frame |

**Sign-off**

- [ ] Pass
- [ ] Fail — notes: _____________

---

## 7. Live fixture capture procedure

Perform once per probe firmware version under test.

1. Enable verbose BLE logging or use a one-shot debug capture path during discovery.
2. With probe in **normal mode**, record from `BleDevice`:
   - Primary advertisement manufacturer block (hex)
   - Scan response bytes if Probe Status UUID is scan-response-only
   - Advertised name field (often serial number)
3. Repeat in **Instant Read mode** if the probe supports toggling modes.
4. Save captures:
   - `test/fixtures/combustion/adv_normal_1.hex` — overwrite with live primary adv (or add `adv_live_1.hex` and update tests)
   - `test/fixtures/combustion/scan_response.hex` — overwrite if live scan response differs
5. Update `test/fixtures/combustion/README.md` provenance table:

   | Field | Example |
   |-------|---------|
   | Capture date | 2026-07-02 |
   | Probe firmware | x.y.z |
   | Tablet | Android DE1 |
   | Mode | normal / instant read |
   | Source | Live BLE capture |

6. Run `flutter test test/models/device/impl/combustion/` — parser tests must stay green with live fixtures.

**Sign-off**

- [ ] Live fixtures committed (or attached to sign-off PR)
- [ ] README provenance updated
- [ ] Parser unit tests pass with live data

---

## 8. Regression smoke (software)

Run on the same build before hardware sign-off completes:

```bash
flutter test
flutter analyze
```

Optional E2E in simulate mode (API surface only):

```bash
scripts/sb-dev.sh start --connect-machine MockDe1
# Follow .agents/skills/decent-app/scenarios/combustion-probe-steam-stop.md
scripts/sb-dev.sh stop
```

---

## 9. Sign-off record

| Field | Value |
|-------|-------|
| **Date** | |
| **Tester** | |
| **Tablet serial / ID** | |
| **Probe serial / firmware** | |
| **Machine + scale** | |
| **Decent.app version / commit** | |
| **§6.1 Concurrent** | Pass / Fail |
| **§6.2 Wake-from-sleep** | Pass / Fail |
| **§6.3 Stop-at-temp** | Pass / Fail |
| **§6.4 Disconnect safety** | Pass / Fail |
| **§6.5 Shot probe temp** | Pass / Fail |
| **§7 Live fixtures** | Done / N/A |
| **Overall** | **APPROVED / BLOCKED** |

**Blocked criteria:** Any §6.1–§6.3 failure blocks merge. §6.4–§6.5 and §7 failures require explicit risk acceptance and follow-up issue.

**Approver signature:** _________________________ **Date:** _____________
