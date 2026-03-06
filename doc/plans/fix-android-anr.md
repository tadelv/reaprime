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

- [ ] **2. Optimize `getLatestShot()` query** — The Visualizer plugin polls `/api/v1/shots/latest` every 10s. Currently `getLatestShot()` does `ORDER BY timestamp DESC LIMIT 1` loading the full row including `measurementsJson` (which can be large). Two improvements:
  - a. Add a DB index on `timestamp` for the `shot_records` table
  - b. Create a lightweight variant that excludes `measurementsJson` (or return `toJsonWithoutMeasurements()` from the handler, matching what the paginated list endpoint already does)

- [ ] **3. Investigate wake-up scan BLE congestion** — Understand why the BLE scan + reconnect after wake-up floods the event loop (response times degrade to 330ms even before any write timeout). Look at the scan flow, notification subscriptions, and whether we can throttle/debounce BLE events during reconnection.
