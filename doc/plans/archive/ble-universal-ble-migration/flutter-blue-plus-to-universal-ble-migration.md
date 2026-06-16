# Migration: flutter_blue_plus → universal_ble

**Status:** Plan (not yet implemented)
**Branch:** see "Branch & PR scope" below
**Author:** drafted via grill-with-docs session, 2026-06-15

## Why

The app currently runs **two** BLE stacks:

- `flutter_blue_plus` (fbp) — Android, iOS, macOS, Linux
- `universal_ble` — Windows only

Two stacks means two sets of transport implementations, two discovery
services, two error models, and double the surface to maintain and reason
about. The *only* original reason fbp was chosen over universal_ble was that
fbp had Android **high-priority connection intervals**
(`requestConnectionPriority`) and universal_ble did not.

That rationale is now gone:

1. universal_ble 2.x **has** `requestConnectionPriority` (Android/iOS/macOS;
   throws `notSupported` on Linux/Windows/Web).
2. The app **no longer uses** the high-priority feature — `setTransportPriority`
   is effectively a no-op in the active path.

So consolidating onto a single stack (universal_ble) removes real tech debt
with no feature regression. universal_ble already powers Windows, so it is
proven against this app's protocol on at least one platform.

### Rejected alternatives

- **Consolidate onto flutter_blue_plus instead** (drop universal_ble, write an
  fbp Windows path via `flutter_blue_plus_winrt`). Rejected: fbp's WinRT backend
  is separately maintained and was historically the weakest link; universal_ble's
  Windows support is first-class. Direction of travel is toward universal_ble.
- **Keep both stacks indefinitely.** Rejected: that is the status quo debt this
  work exists to remove.
- **Keep fbp on Linux permanently** (migrate only Android/Apple). Considered
  because BlueZ is the riskiest path, but rejected once Linux was confirmed
  testable on real hardware (see Verification). Linux ships verified, last.

## Key finding: MTU is not load-bearing

universal_ble exposes **no API to request/modify MTU**. fbp's code requests
`mtu: 517` on every platform, which looked like a blocker. It is not:

Every DE1 BLE payload is **≤ 20 bytes**, which fits the default ATT MTU of 23
(20 usable bytes):

| Write | Size | Source |
|-------|------|--------|
| MMR read/write frame | `ByteData(20)` | `unified_de1.mmr.dart` |
| Firmware/MMR chunk | `4 + 16 = 20` | `unified_de1.firmware.dart:113-129` |
| shotSettings | `Uint8List(9)` | `unified_de1.dart:441` |
| Profile header/frame | `Uint8List(5)` / `Uint8List(8)` | `unified_de1.profile.dart` |
| requestedState | `Uint8List(1)` | `unified_de1.dart:262` |

Reads (MMR = 20 bytes) and notifications (shotSample ≈ 19 bytes, stateInfo
small) are all ≤ 20 bytes. The Decent Scale protocol uses 7-byte frames
(`sb-045`). The `requestMtu(517)` is precautionary throughput headroom, **not**
a correctness requirement. universal_ble's lack of MTU control is therefore a
non-blocker.

> Smoke-check item, not a blocker: confirm universal_ble's Android backend does
> not *lower* the negotiated MTU below 23. A 20-byte write needs exactly MTU 23.
> Default Android MTU is 23, so this is expected fine, but verify on the m50mini.

## Decisions (from the grilling session)

1. **Sequencing:** incremental, per-platform, behind the existing `main.dart`
   discovery-service switch. Order: **macOS/iOS → Android → Linux**. fbp stays in
   `pubspec.yaml` until every platform is smoke-verified, then removed in one
   final commit.
2. **Workarounds:** build the universal_ble transport **clean** — do **not**
   port fbp's GATT-133 retry, post-connect settle delays, or BlueZ cache-refresh
   scans up front. Lean on universal_ble's global command queue
   (`QueueType.global`). Smoke on real hardware, then re-add **only** mitigations
   that prove necessary. The MMR-read retry (`sb-061`) is transport-agnostic
   (lives in `unified_de1.mmr.dart`) and stays regardless.
3. **Error boundary:** introduce a domain `BleConnectException`
   (`{code, description, function, cause}`) thrown from `services/ble/`. Each
   transport maps its native exception (`UniversalBleException` /
   `FlutterBluePlusException`) into it. `connection_manager` checks the domain
   type instead of `FlutterBluePlusException`. Rename telemetry keys
   `fbp_code` → `ble_code` (etc.). This removes the only fbp-type leak outside
   `services/ble/` and is a prerequisite for dropping the dep.
4. **Discovery:** consolidate the three discovery services
   (`BluePlusDiscoveryService`, `LinuxBleDiscoveryService`,
   `UniversalBleDiscoveryService`) into the single, Windows-proven
   `UniversalBleDiscoveryService`, enhanced to cover macOS bonded/system devices
   (`getSystemDevices`) and preferred-device handling. Unfiltered-scan +
   name-match is already the documented approach (`sb-044`).
5. **Connection priority:** keep `setTransportPriority` on the `BLETransport`
   interface. Wire universal_ble's `requestConnectionPriority` where supported
   (Android/iOS/macOS), no-op elsewhere. Feature is currently unused but the
   seam is cheap to keep.
6. **Scope:** full consolidation — fbp removed entirely at the end. All four
   platforms are verifiable on real hardware.

## Current state (architecture map)

### Transport abstraction (unchanged by this work)
- `lib/src/models/device/transport/data_transport.dart` — `DataTransport`
- `lib/src/models/device/transport/ble_transport.dart` — `BLETransport`
  (`discoverServices`, `subscribe`, `read`, `write`, `setTransportPriority`)
- `lib/src/models/device/ble_service_identifier.dart` — `BleServiceIdentifier`
  (128-bit UUID matching)
- `lib/src/services/device_matcher.dart` — `DeviceMatcher.match()` (name-based)
- `lib/src/services/ble/char_subscriptions.dart` — `CharSubscriptions`
  (idempotent subscribe; the `sb-030` fix)

### fbp implementations (to be removed)
- `lib/src/services/ble/blue_plus_transport.dart` — generic (iOS/macOS)
- `lib/src/services/ble/android_blue_plus_transport.dart` — Android (GATT-133
  retry, post-connect settle, MTU-after-connect, disconnect throttle)
- `lib/src/services/ble/linux_blue_plus_transport.dart` — Linux (BlueZ cache
  refresh, `StateError` recovery)
- `lib/src/services/blue_plus_discovery_service.dart` — Android/iOS/macOS
  discovery (+ macOS `systemDevices`)
- `lib/src/services/ble/linux_ble_discovery_service.dart` — Linux discovery
  (BlueZ pending-queue, manual scan duration, inter-device delays)
- `connection_manager.dart:5-6,239` — the one fbp-type leak

### universal_ble implementations (exist; to be completed + made universal)
- `lib/src/services/ble/universal_ble_transport.dart` — implements
  `BLETransport`. Today: no error mapping, no priority, own subscription map.
- `lib/src/services/universal_ble_discovery_service.dart` — Windows today;
  becomes the single discovery service.

### Selection logic
- `lib/main.dart:280-294` — `Platform.isLinux → LinuxBle`,
  `Platform.isWindows → UniversalBle`, else `BluePlus`. This switch is the
  per-platform migration lever.

## Migration phases

Each phase ends with a real-hardware smoke (machine + scale + a shot) before the
next begins. Run `flutter analyze` + `flutter test` every phase.

### Phase 0 — Transport hardening (platform-agnostic, no behaviour switch)
- Add `BleConnectException` domain type (`lib/src/models/device/transport/`).
- Map `UniversalBleException` → `BleConnectException` / `BleTimeoutException`
  inside `universal_ble_transport.dart`.
- Switch `universal_ble_transport.dart` to reuse `CharSubscriptions` (parity with
  the fbp transports; keep `char_subscriptions_test.dart` green).
- Wire `setTransportPriority` → `requestConnectionPriority` (guard
  `notSupported`).
- Migrate `connection_manager._buildConnectError` to the domain type; rename
  telemetry keys `fbp_*` → `ble_*`.
- Add fbp→`BleConnectException` mapping too (so detail survives while fbp is
  still in the tree).
- Tests: unit-test the exception mapping; `FakeBleTransport` is transport-
  agnostic and unaffected.
- **No `main.dart` change yet** — Windows already exercises this path.

### Phase 1 — macOS + iOS
- Enhance `UniversalBleDiscoveryService`: bonded/system devices via
  `getSystemDevices`, preferred-device handling, adapter-state parity.
- `main.dart`: route macOS + iOS to `UniversalBleDiscoveryService` +
  `UniversalBleTransport`.
- Smoke: macOS shot; iOS shot. Watch bonded-device reconnect.

### Phase 2 — Android
- `main.dart`: route Android to universal_ble.
- Smoke on **m50mini**, focus on the `sb-060` cold-connect case (the documented
  fbp Android notify-setup race). If the first-MMR-read timeout recurs, the
  `sb-061` retry already covers it; only add transport-level mitigation if smoke
  shows it's insufficient.
- Confirm MTU ≥ 23 negotiated (the smoke-check note above).

### Phase 3 — Linux (last, riskiest)
- `main.dart`: route Linux to universal_ble; delete the Linux fbp discovery path.
- Smoke on a Linux box against a real DE1 over BlueZ. BlueZ quirks the fbp path
  worked around (stale cache, scan-before-connect) may or may not recur on
  universal_ble's BlueZ backend — re-add mitigations only if observed.

### Phase 4 — Remove flutter_blue_plus
- Delete the three fbp transports + two fbp discovery services + fbp mapping.
- Remove `flutter_blue_plus` from `pubspec.yaml`; `flutter pub get`; regenerate
  plugin registrants.
- Final full smoke on each platform + `flutter test` + release APK build.

## Risk register

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Android cold-connect notify race (`sb-060`) recurs on universal_ble | Medium | `sb-061` MMR retry is transport-agnostic; smoke on m50mini; add settle/retry only if needed |
| BlueZ quirks recur on universal_ble Linux backend | Medium | Linux last; smoke on real hardware; re-add cache-refresh only if observed |
| universal_ble lowers MTU below 23 on some Android | Low | 20-byte frames need exactly 23; verify negotiated MTU during Phase 2 smoke |
| Lost telemetry grouping after `fbp_code` → `ble_code` rename | Low | Accept; structured detail preserved under new keys |
| macOS bonded-device reconnect differs from `systemDevices` | Low | Phase 1 smoke covers reconnect explicitly |
| BLE regression escapes CI (native + timing) | High if skipped | Per-platform real-hardware smoke is a hard gate per `feedback_real_hw_smoke` |

## Verification

Real hardware available for all four: **Android (m50mini), macOS, iOS, Linux.**
Each phase gates on a real shot (connect machine + scale, run a shot, confirm
weight/flow + clean disconnect). CI (`flutter analyze` + `flutter test`) is
necessary but **not sufficient** — it misses native-stream and platform-timing
regressions (`feedback_real_hw_smoke`).

## Rollback

Each phase is a single `main.dart` switch flip per platform; reverting one
phase is reverting that branch arm. fbp stays in the tree until Phase 4, so any
phase can fall back to the fbp path by reverting its `main.dart` change without
touching dependencies.

## Branch & PR scope

This migration is **unrelated** to the gradle/plugin-upgrade work already in
PR #333 on `chore/android-kotlin-upgrade`. Recommend a **separate branch + PR**
so #333 stays reviewable and this large change lands on its own. Confirm with
the maintainer before implementing (CLAUDE.md branching policy).
