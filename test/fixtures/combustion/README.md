# Combustion probe BLE fixtures (SP-001)

Synthetic advertisement payloads for parser and discovery tests until live hardware capture (SP-018).

## Format

Each `*.hex` file is a contiguous lowercase hex string (no spaces). Bytes are in wire order.

| File | Contents | Bytes |
|------|----------|-------|
| `adv_normal_1.hex` | Legacy primary advertisement manufacturer block | 25 |
| `adv_normal_2.hex` | Second normal-mode capture (different serial) | 25 |
| `adv_instant_read_1.hex` | Instant Read mode (mode bits = `01`) | 25 |
| `scan_response.hex` | Probe Status service UUID (128-bit) | 16 |

### Manufacturer block layout (25 bytes)

Per [probe_ble_specification.rst](https://github.com/combustion-inc/combustion-documentation/blob/main/probe_ble_specification.rst):

| Offset | Field |
|--------|-------|
| 0–1 | Vendor ID `0x09C7` (little-endian `C7 09`) |
| 2 | Product type `0x01` (Predictive Probe) |
| 3–6 | Serial number (uint32 LE) |
| 7–19 | Raw temperature data (13 bytes, zeros in synthetic fixtures) |
| 20 | Mode/ID (normal `0x00`, instant read `0x01`) |
| 21–24 | Battery/virtual, network, overheating, thermometer prefs (zeros) |

## Provenance

- **Created:** SP-001 Phase 0 spike (2026-07-01)
- **Source:** Protocol spec + `combustion-android-ble` `ProbeAdvertisingData` field layout
- **Not** captured from physical hardware — replace with live captures in SP-018 and update this README.
