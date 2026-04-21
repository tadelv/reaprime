# Comms Hardening — Phase 3 Implementation Plan

Execution plan for Phase 3 of `doc/plans/comms-harden.md`: the remaining **Cluster B — scan ownership** items that weren't absorbed by Phase 2's scan-API shape refactor. Three items: 10, 11, 23.

After Phase 3, the entirety of Cluster B is resolved and the scan lifecycle has a single, cancellable, well-owned shape.

## Pre-work findings

### Item 11 — uncancellable 15 s scan timer

`lib/src/services/blue_plus_discovery_service.dart:186` (Linux branch) and `:199` (non-Linux branch):

```dart
await Future.delayed(Duration(seconds: 15), () async {
  await FlutterBluePlus.stopScan();
});
```

`Future.delayed` is uncancellable. External `stopScan()` (from `ConnectionManager._checkEarlyStop`) calls `FlutterBluePlus.stopScan()` early, but the `Future.delayed` keeps running and `_isScanning` stays `true` until the delayed closure finishes — at which point it calls `stopScan` *again* (no-op) and only then clears the flag in the outer `finally`. So external stop takes ~15 s to actually free the scanner.

### Item 23 — duplicated pre-scan cleanup blocking scan start

`blue_plus_discovery_service.dart:118–131` and `device_controller.dart:104–123` both do:

```dart
for (final device in <cache>) {
  final state = await device.connectionState.first
      .timeout(const Duration(seconds: 2),
          onTimeout: () => ConnectionState.disconnected);
  ...
}
```

Each loop awaits per-device sequentially. Two layers, up to `2 s × N_devices` of latency added to scan start in the worst case. Logically each layer cleans its own cache, so they aren't strictly redundant — but they can run **concurrently**, not sequentially, and today they don't.

### Item 10 — Linux refresh-scan collides with external stopScan

`linux_ble_discovery_service.dart:_runRefreshScan` (line 369) uses `FlutterBluePlus.startScan` + a 1 s delay + `FlutterBluePlus.stopScan`. It runs **after** the main 15 s scan: once as a cache-prep scan before device creation, and once per retry inside `_createDeviceWithRetry`.

`ConnectionManager._checkEarlyStop` fires when both preferred machine and scale are connected — this can happen *during* the post-main-scan window while a refresh scan is running. `_checkEarlyStop` calls `deviceScanner.stopScan()` → `DeviceController.stopScan()` → service `stopScan()` → `FlutterBluePlus.stopScan()`, which aborts the refresh mid-flight. BlueZ cache is left in an uncertain state and retries can silently fail.

### How Phase 2 (`Future<ScanResult>`) reshapes the problem

After Phase 2, `DeviceScanner.scanForDevices()` returns `Future<ScanResult>` that resolves only when every service has finished. So:

- `_isScanning` stuck true for 15 s (item 11) now blocks more visibly — `ConnectionManager` awaits the Future and can't proceed.
- Race between external `stopScan` and post-main-scan refresh (item 10) is still a silent problem.
- Pre-scan cleanup latency (item 23) shows up directly in connect time, no longer partially hidden by the old early-return semantics.

---

## Goals

After Phase 3:

- `ConnectionManager._checkEarlyStop` + `deviceScanner.stopScan()` land cleanly even if a Linux refresh scan is running — refresh scans aren't externally stoppable.
- The 15 s wait in `BluePlusDiscoveryService.scanForDevices` is cancellable — external stop immediately frees `_isScanning` and the Future completes promptly.
- Per-device connection-state cleanup runs in parallel, capping pre-scan latency at 2 s regardless of device count.
- No duplicate cleanup loops across the two layers — each layer cleans its own cache, but the expensive part (stream await with timeout) only happens once per device overall when possible.

## Non-goals

- Restructuring `linux_ble_discovery_service.dart` beyond the refresh-scan-ownership tweak.
- Changing `ConnectionManager._checkEarlyStop` semantics — only its interaction with the scanner.
- Further `ScanResult` enrichment (e.g. surfacing `failedServices` in `ScanReport`) — belongs to Phase 4's god-class split.

---

## Delivery strategy

One PR, relatively small. Each item is a surgical fix; together they're <200 LoC + tests.

**Branch:** `feature/comms-phase-3-scan-ownership` off `integration/comms-harden-rest`.

**Scope:**

1. **Item 11 (cancellable 15 s wait).** Replace `await Future.delayed(Duration(seconds: 15), () => FlutterBluePlus.stopScan())` with a cancellable `Timer` + `Completer` pair. External `stopScan()` cancels the timer and completes the completer, freeing `_isScanning` promptly. Tested via `fake_async`.

2. **Item 23 (parallel pre-scan cleanup).** Wrap the per-device `connectionState.first.timeout(2s)` loop in `Future.wait(...)`. Same logic, runs concurrently instead of sequentially. Zero semantic change; latency drops from `2s × N` to `2s`. Tested by constructing a service with N hung device streams and asserting scan starts within 2 s of call.

3. **Item 10 (refresh scan owns its lane).** Two options; pick (a):
   - (a) **Ignore external stop during refresh.** Add a `_refreshScanInProgress` flag on `LinuxBleDiscoveryService`; the public `stopScan()` short-circuits when the flag is set, logging a debug line. The main-scan path and `_runRefreshScan` both set/clear the flag around their `startScan`/`stopScan` pair.
   - (b) Introduce a scan-token system where only the token holder can cancel. Larger surface, over-engineered for a single file's concern.

   Go with (a). Document in the service that refresh-scan is internal, not externally-cancellable.

### Tests

- `test/services/ble/blue_plus_discovery_service_test.dart` (new): cancellable-wait + parallel pre-scan cleanup + behavior on external stop mid-15s-wait.
- `test/services/ble/linux_ble_discovery_service_test.dart` (new): external `stopScan` during `_runRefreshScan` is ignored. May be hard to drive without mocking `FlutterBluePlus`; worst case this is a code-review / inspection check rather than an automated test.

### Landmines

- `BluePlusDiscoveryService.scanForDevices` is called from multiple platform branches (Linux vs Android/macOS). The Linux branch has its own scan loop inside `linux_ble_discovery_service.dart` — changes in `BluePlusDiscoveryService` don't affect it. Scope each file independently.
- The cancellable 15 s wait must still fire `stopScan` when it completes normally (scan ran to full duration). Don't break that path.
- `FlutterBluePlus.isScanningNow` is a property that reflects real BLE state. After our cancellable timer fires, real state should also be "not scanning". Assert consistency.

---

## Success criteria

- `flutter test`: full suite green + new tests for items 11 and 23. Item 10 test best-effort.
- `flutter analyze`: clean on changed files.
- Real-hardware smoke on M50Mini tablet:
  - Early-stop scenario (preferred machine + preferred scale both connect fast): scan completes promptly after both connected, not 15 s later.
  - Connect sequence timing unchanged when early-stop doesn't fire.
  - Linux-specific early-stop not validated on real Linux hardware in this pass — rely on logs + inspection.

---

## Open questions

None. Scope is surgical; decisions already made per the plan. Ready to kick off after the plan is committed.
