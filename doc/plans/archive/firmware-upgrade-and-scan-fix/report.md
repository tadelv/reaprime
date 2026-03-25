# Firmware Upgrade & BLE Scan Disconnect Fix

Branch: `fix/firmware-upgrade`

## 1. Firmware Upload Improvements

### Problem
Firmware uploads over serial (USB) were unreliable — the machine's UART receive buffer could overrun during SPI flash writes because the app wrote chunks too fast without adequate pacing.

### Changes

#### Batch-paced serial writes (`unified_de1.firmware.dart`)
- Replaced the per-chunk 5ms delay with batched writes: 8 chunks per batch, 400ms pause between batches.
- Over BLE, `writeWithResponse` provides natural backpressure via ACKs — no pacing needed.
- Over serial on macOS, there is no TX buffer size control (no `TIOCGSERIAL` equivalent — macOS only offers `IOSSDATALAT` for receive-side latency). Application-level pacing is the only option.
- Pacing is gated on `Platform.isMacOS && transportType == TransportType.serial` to avoid unnecessary delays on BLE or other platforms.

#### Serial write robustness (`serial_service_desktop.dart`)
- `_port.open()` now properly awaited.
- `_write()` rewritten to handle short/partial writes by looping with `timeout: 0` (blocking infinite wait).
- Added `_port.drain()` after writes to ensure bytes are physically transmitted before proceeding.
- Extended the 20ms inter-write flow-control delay to macOS (was Linux-only).

#### Transport type exposure (`unified_de1_transport.dart`)
- Exposed `transportType` getter on `UnifiedDe1Transport` so firmware upload code can check transport type.

### Serial Buffering Research
- The `flutter_libserialport` fork (AurelienBallier) has **zero Dart-level buffering** — writes pass directly to libserialport's C FFI calls.
- `sp_blocking_write()` / `sp_nonblocking_write()` pass through to the OS kernel buffer.
- `sp_drain()` blocks until the OS buffer is physically transmitted.
- macOS has no ioctl to resize serial TX/RX ring buffers (unlike Linux's `TIOCGSERIAL`). The only tunable is `IOSSDATALAT` (receive-side latency timer).

### Prior commits on branch
- `35173eb` — Added time estimate to firmware upgrade progress display
- `1f820f0` — Improved BLE timeout handling during firmware operations
- `bec1433` — Added automatic retry for BLE read/write operations after successful reconnect

---

## 2. False Device Disconnect During BLE Scans

### Problem
On Android tablets, the DE1 machine would frequently disconnect and reconnect during BLE scans triggered by state transitions (e.g., sleep → wake, needsWater → idle). This caused unnecessary full reconnection cycles: De1Controller reset, BLE service discovery, profile upload, settings sync — all taking several seconds and disrupting the user experience.

### Root Cause
Traced the exact chain in `DeviceController`:

1. `scanForDevices()` (lines 82-97) **mutates `_devices[service]` directly** before scans start, removing non-connected devices from the per-service lists.
2. When any service emits during the scan (e.g., `SerialServiceAndroid` emitting `[]`), `_serviceUpdate()` runs.
3. `_serviceUpdate()` computes `this.devices` by aggregating ALL services — but the BLE service's list was already cleaned in step 1.
4. The name-based set diff against **stale `_previousDeviceNames`** sees the cleaned device as "disconnected."
5. When the BLE scan later re-discovers the device, it's reported as "reconnected after 0s."
6. `ConnectionManager`'s early-connect listener triggers `connectMachine()`, causing a full reset cycle.

Secondary concern: on Android, the `connectionState.first.timeout(2s)` check during pre-scan cleanup could falsely return `disconnected` for genuinely connected devices if the BLE stack is busy processing a state transition notification.

### Fix (`device_controller.dart`)
Two changes in commit `01ca6ce`:

1. **Sync `_previousDeviceNames` after pre-scan cleanup** — after removing non-connected devices from the lists, update the baseline so subsequent `_serviceUpdate()` calls during the scan don't see false diffs.

2. **Skip disconnect/reconnect detection while `isScanning` is true** — intermediate device list changes during a scan are transient noise. The scan produces the authoritative list when it completes. Genuine disconnects that happen outside of scans are still detected normally.

### Verification
Tested on Android tablet (M50Mini, Android 14) connected to DE1Pro over BLE with Decent Scale:

| Scenario | Result |
|----------|--------|
| Sleep → wake (with scale) | DE1 stable, scale connects ~2s |
| Sleep → wake (without scale) | DE1 stable, no false events |
| needsWater → idle (refill) | DE1 stable |
| Manual scan from native UI | DE1 stable, scale connects |
| Scale power off | Real disconnect detected correctly |
| Scale reconnect via scan | DE1 stable, scale connects |
| Scan with scale off | DE1 stable, no false events |
| Sleep → wake (scale slow connect ~20s) | DE1 stable, scale eventually connects |

All 525 unit/integration tests pass.
