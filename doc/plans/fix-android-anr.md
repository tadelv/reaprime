# Fix: Android ANR on scheduled wake-up

## Problem

At 05:55, a scheduled wake-up triggers the DE1 to wake from sleep. The BLE stack becomes congested/unresponsive, causing:
1. BLE write timeouts (15s) in `BatteryController._tick()` → `setUsbChargerMode()`
2. Event loop congestion — `/shots/latest` response times degrade from 16ms → 650ms
3. After ~5 minutes of degraded state, Android triggers an ANR on the foreground service and kills the app

## Root Cause

After wake-up, the BLE connection becomes stale/degraded. Instead of catching the timeout and continuing (leaving a dead connection alive), we should treat a BLE timeout as a signal that the connection is dead and disconnect.

## Tasks

- [x] **1. Disconnect on BLE write timeout** — In `UnifiedDe1Transport`, when a BLE write times out (FlutterBluePlusException with timeout), trigger a disconnect of the device. This forces a clean reconnect cycle instead of leaving a stale connection that will keep timing out and congesting the event loop.

- [ ] **1b. Integration test BLE timeout recovery** — Use local Streamline-Bridge MCP server to test how well the new disconnect/reconnect performs in practice (simulate timeout scenario, verify reconnect cycle works cleanly).

- [ ] **2. Optimize `getLatestShot()` query** — The Visualizer plugin polls `/api/v1/shots/latest` every 10s. Currently `getLatestShot()` does `ORDER BY timestamp DESC LIMIT 1` loading the full row including `measurementsJson` (which can be large). Two improvements:
  - a. Add a DB index on `timestamp` for the `shot_records` table
  - b. Create a lightweight variant that excludes `measurementsJson` (or return `toJsonWithoutMeasurements()` from the handler, matching what the paginated list endpoint already does)

- [ ] **2b. MCP smoke test for shots/latest and Visualizer plugin** — Use the MCP server to:
  - Start the app in simulate mode, pull a shot, and verify `/api/v1/shots/latest` returns correct metadata without measurements.
  - Test the Visualizer plugin's event-driven upload flow (requires user to supply Visualizer credentials).

- [x] **3. Investigate wake-up scan BLE congestion** — Understand why the BLE scan + reconnect after wake-up floods the event loop (response times degrade to 330ms even before any write timeout). Look at the scan flow, notification subscriptions, and whether we can throttle/debounce BLE events during reconnection.

### Task 3: Investigation Notes

**Wake-up flow (sleeping → idle):**
1. `PresenceController._checkSchedules()` fires every 30s, matches schedule, calls `de1.requestState(MachineState.schedIdle)` — this is a BLE write to the *already connected* DE1.
2. DE1 wakes, transitions sleeping → idle. `De1StateManager._handleScalePowerManagement()` detects the transition.
3. If no scale is connected (likely after `ScalePowerMode.disconnect` during sleep), `_triggerScaleScan()` runs `_deviceController.scanForDevices(autoConnect: true)`.
4. `scanForDevices()` starts an unfiltered BLE scan via `FlutterBluePlus.startScan(oneByOne: true)` for 15 seconds.
5. When the DE1 is found during the scan, `_createDeviceFromName()` calls `DeviceMatcher.match()` → `UnifiedDe1(transport)`.
6. The DE1 goes through `onConnect()` → `_transport.connect()` → `_bleConnect()`:
   - `discoverServices()` (can retry up to 3x)
   - 2 characteristic reads (stateInfo, shotSettings)
   - 6 `subscribe()` calls (each calls `setNotifyValue(true)`)
   - `requestConnectionPriority(high)` on Android
   - Then 6+ MMR reads for machine info
7. Meanwhile, BatteryController._tick() fires every 60s and calls `setUsbChargerMode()` — another BLE write.

**Congestion sources during this window:**
- The BLE scan itself generates advertisement events flooding through FlutterBluePlus
- Simultaneous scan + connection attempts compete for the BLE adapter
- 6 notification subscriptions + multiple reads all happen serially but each generates adapter traffic
- BatteryController tick can collide with the reconnection sequence

**Potential mitigations:**
- a. Use `scanForSpecificDevices()` instead of `scanForDevices()` when we know the device IDs — targeted scan is shorter (8s vs 15s) and reduces advertisement noise
- b. Lower BLE transport priority during reconnection (Android: `ConnectionPriority.balanced` until subscriptions are set up)
- c. Debounce/skip BatteryController tick if a BLE reconnect is in progress
- d. Consider whether the DE1 needs re-discovery at all after wake — it's already connected (PresenceController just wrote to it successfully). The scan is only for the *scale*, but `scanForDevices()` is unfiltered and will re-discover the DE1 too
