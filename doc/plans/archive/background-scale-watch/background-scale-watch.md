# Persistent Background Scale Watch

**Branch:** `feature/background-scale-watch` (created). **Completion:** local commit, no push/PR.

## Context

When the machine is connected and the preferred scale is offline, `ConnectionManager` today runs periodic 15s BLE scan bursts in `AndroidScanMode.lowLatency` with exponential backoff (5s→60s cap, [connection_manager.dart:154](lib/src/controllers/connection_manager.dart)). Two consequences:

- A scale powered on during a backoff gap waits up to **60s + scan time** to connect.
- Each `lowLatency` burst monopolizes the Android radio and **starves DE1 GATT traffic** — observed as a 10s GATT write timeout on the MMR write behind `POST /api/v1/machine/calibration` → HTTP 500 (log from 2026-07-14 19:23).

**Goal:** on Android, replace the backoff-burst loop with **one persistent, low-duty-cycle, OS-filtered scan** ("watch") that runs whenever *machine connected && preferred scale set && scale not connected && not blocked by power mode*. Scale powers on → connected in ~1–5s; DE1 link keeps ≥60% of radio time. Non-Android platforms keep the existing backoff behavior byte-for-byte.

**Key mechanism:** Android scan modes are duty cycles (`balanced` ≈ 2s on / 3s off). The universal_ble fork (git 6a5abe4) supports `ScanFilter.withNamePrefix` (OS/controller-level filtering — survives screen-off, host woken only on match) and `AndroidOptions.scanMode`. The preferred scale's advertised name is recoverable without scanning from `RememberedDevicesController` (persists `{id, name, type}`; getter `remembered` at remembered_devices_controller.dart:40). No MAC-address filter exists in the fork, so name prefix (full remembered name ⇒ exact-ish match) is the filter.

## Established facts (verified)

- Live `UniversalBleDiscoveryService.scanForDevices` **ignores** the domain `ScanFilter` param entirely: hardcoded unfiltered scan (line 160), `lowLatency` (line 172), 15s duration (line 201), cancellable wait machinery at lines 99–125, re-entry guard `_isScanning` (line 27). All device matching is Dart-side via `DeviceMatcher`. Results flow through broadcast `devices` stream → `DeviceController` merge → `deviceStream` (BehaviorSubject; consumers `.skip(1)` the replay).
- universal_ble has **one global scan session** — watch and burst scans must be arbitrated.
- Loop being replaced: `_maybeSchedulePreferredScaleReconnect` (665–679), gate `_shouldRetryPreferredScale` (681–686), cancel `_cancelPreferredScaleReconnect` (688–692). Schedule call sites: 240, 527, 546, 568, 697, 800. Cancel call sites: 239, 451, 709, 857, disconnectScale, dispose (1240–1252).
- `EarlyConnectWatcher` (connection/early_connect_watcher.dart) is the existing connect-on-sight pattern: `deviceStream.skip(1)`, one-shot connect on preferred-id match.
- `De1StateManager` has a second, independent wake-time burst trigger (de1_state_manager.dart:373–395) that must be reconciled.
- `Platform.isAndroid` is false under `flutter test` — capability must be **injectable**, not Platform-checked (the existing Platform-gated scaleFilter at connection_manager.dart:478 is dead weight and untested).
- `UniversalBle.setInstance(UniversalBlePlatform)` exists in the fork (universal_ble.dart:17) → the service-level watch is unit-testable on host with a fake platform.
- `ConnectionManager` is constructed (main.dart:326) **before** `RememberedDevicesController` (main.dart:338); the latter's deps all exist by line 323, so the block can be hoisted.
- Android platform constraints: scans >30min silently downgrade to opportunistic (→ self-restart every ~25min); **unfiltered** scans are suspended when screen off (filtered ones keep running); ≤5 scan starts per 30s (fine at this cadence).

## Design decisions & deviations from the original plan

The step-by-step implementation list lived here during development; the
commit chain is now authoritative for *what* changed. What follows is the
*why* that the diff can't show:

- **Capability interface instead of base-class defaults.** The plan put
  default no-op watch methods on `DeviceDiscoveryService`, but nearly every
  service and test fake `implements` (not `extends`) that class, so defaults
  don't reach them — ~18 classes would have needed stubs. `DeviceWatchCapable`
  (`lib/src/models/device/device_watch.dart`) is the idiomatic replacement:
  only `UniversalBleDiscoveryService` implements it, `DeviceController`
  selects with `whereType<DeviceWatchCapable>()`.
- **The `shouldWatch` gate doubles as the connect-outcome probe.**
  `ConnectionManager.connectScale` swallows its own errors, so `ScaleWatch`
  observes success as the gate flipping false (scale connected) and failure
  as it staying true → restart the watch scan. No new error channel needed.
- **Bengle rule re-applied on the watch path.** Watch-driven connects bypass
  `_runScalePhase`, whose Bengle branch makes the integrated scale own the
  scale slot. Without re-applying it (arm-time check + `_connectScaleFromWatch`
  wrapper), a sighted external preferred scale could steal the slot during
  the virtual-attach window. Caught in self-review; regression test in
  `test/integration/connection_manager_bengle_scale_test.dart`.
- **Start-window races.** `_startWatchScan`'s awaited `UniversalBle.startScan`
  opens a window where (a) `stopDeviceWatch` can race the start, leaving an
  orphaned OS scan, and (b) a burst can race it, making the watch claim
  active while the burst's end-of-scan stop actually killed it (dead watch
  until the 25-min refresh). Both guarded after the await; tests in the
  `start-window races` group.
- **Fire-and-forget scan-stream cancels.** Awaiting
  `StreamSubscription.cancel()` can resolve through the root zone, which
  deadlocks fakeAsync tests; the ordering is not load-bearing (a stray advert
  just takes the normal `_deviceScanned` path), so watch-internal cancels are
  `unawaited` (`_cancelWatchScanSub`).
- **Name-prefix filtering removed after hardware testing (2026-07-15).** The
  plan's premise — `withNamePrefix` as an OS/controller-level filter that
  survives screen-off — is false for the universal_ble fork: with a name
  prefix set it passes an EMPTY filter list to the Android scanner and
  filters plugin-side (Kotlin, case-sensitive `startsWith` on the advertised
  name). Worse, the prefix source was wrong: `RememberedDevicesController`
  stores `Device.name`, which for most scale impls is a friendly constant
  ("Felicita Arc", "Bookoo Mini Scale") that never matches the advertised
  name — so the watch silently discovered nothing (manual tap worked because
  bursts are unfiltered with fuzzy Dart matching). The watch now scans
  unfiltered in balanced mode; the duty cycle was always the real win. A
  future improvement could persist the ADVERTISED name at discovery time and
  restore plugin-side prefix filtering to cut platform-channel traffic.
- **Legacy loop retained, not removed.** The 5s→60s backoff-burst loop is the
  active path on non-Android platforms and the runtime fallback when
  `startScaleWatch` throws (`onWatchUnavailable`).

## Verification (end-to-end)

1. `flutter analyze` + full `flutter test` (run `bundle_skins.sh` first in fresh worktrees).
2. `sb-dev` simulate smoke: machine+scale connect, disconnect scale, confirm reconnect and no scanning-indicator flicker.
3. Real tablet (user-assisted): DE1 connected, scale off → log shows one balanced filtered scan start, **no repeated 15s lowLatency bursts**; power scale on → connected ≤5s; while scale off, loop `curl POST /api/v1/machine/calibration` several minutes → no 500/GATT timeout; screen off ≥2min then power scale on → still connects; >30min soak → 25-min restart visible in log; Bluetooth toggle off/on → watch resumes.

## Risks / edge cases

- **Remembered-name drift** (firmware rename breaks the OS filter silently): log WARNING when a watch is armed >N min with no sighting; do not auto-burst.
- **Preferred id with no remembered record** (import/dart-define): unfiltered `lowPower` watch — accepts screen-off suspension.
- **MockScale sentinel:** covered by arm-time device check (+ Step 7).
- **Dispose ordering:** CM disarms watch before controller disposal; fan-out tolerates closed subjects.
- **Machine recovery:** `shouldWatch` gate (machine connected) naturally disarms during recovery; recovery bursts arbitrate at the service layer.
- **Non-Android:** `supportsDeviceWatch` false everywhere → byte-for-byte legacy behavior.
