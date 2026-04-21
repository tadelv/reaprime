# Comms Harden — Phase 6 (polish)

**Branch:** `feature/comms-phase-6-polish` off `integration/comms-harden-rest`.
**Scope:** the six remaining E-cluster items in the comms-harden roadmap (20, 24, 27, 28, 29, 30). All pure hygiene — no runtime-semantics changes expected beyond item 20.
**Completion:** two sub-PRs into `integration/comms-harden-rest`, then `integration/comms-harden-rest` → `main` as the capstone PR for the whole hardening effort.

## Items

| # | What | Shape |
|---|------|-------|
| 20 | Disconnect detection keyed by `deviceId`, not `device.name` | runtime-visible (telemetry key + reconnect detection) |
| 24 | Magic durations → named constants | mechanical |
| 27 | Populate `ScanReport.adapterStateAtStart/End` | thin plumb |
| 28 | Cache `DeviceController.devices` getter | perf micro-fix |
| 29 | Multicast adapter state across *all* BLE services (or document single-adapter assumption) | either fix or doc |
| 30 | Document `ConnectionPhase` state machine | doc |

## Delivery

### PR 6A — item 20 (disconnect detection by deviceId)

**Why separate:** touches runtime behaviour — disconnect tracking, telemetry custom-key names. Easier to land and verify independently than in a bundle of polish.

**Files:**
- `lib/src/controllers/device_controller.dart`
  - `_previousDeviceNames: Set<String>` → `_previousDeviceIds: Set<String>` (keyed by `Device.id`).
  - `_disconnectedAt: Map<String, DateTime>` → keyed by `Device.id`.
  - Diff computation (lines 208–250) swaps to ids.
  - Telemetry custom key: `reconnection_duration_$deviceName` → `reconnection_duration_$deviceId`.
  - Log strings keep `device.name` *in the message body* (human readable) but track by id.
  - `_updateDeviceCustomKeys`: `device_${device.name}_type` — keep as name (user-facing diagnostic string, not used for correlation). Document why.

**Migration audit — required before touching code:**
1. Grep every `device.name` / `_previousDeviceNames` / `_disconnectedAt` reference.
2. Split into (a) *correlation* keys (must move to id) vs (b) *display* strings (stay name, documented).
3. Check any external surface — WebSocket events, REST, telemetry dashboards — that embeds `reconnection_duration_<name>` custom keys. If anything downstream watches for that pattern, call it out before flipping.
4. Check test fixtures for identical-name devices; add one if none exists.

**Tests:**
- New unit test in `test/controllers/device_controller_test.dart` (create if missing): two devices with the *same advertised name* but different ids — one disconnects, the other shouldn't be flagged. Also: device reconnects with a *different* name (firmware-update scenario) — tracking still resolves by id.
- Existing tests that assert on `_disconnectedAt` keys / telemetry key strings must be updated.

**Risk:** low. One user-visible change — telemetry custom-key string shape. Production dashboards consume custom keys only if somebody set them up; we did not.

---

### PR 6B — items 24, 27, 28, 29, 30 (bundle)

All under `lib/src/controllers/` + `lib/src/services/ble/` + `doc/`. Mechanical polish.

**Item 24 — magic numbers → constants.**
- New file `lib/src/controllers/connection/connection_timings.dart` with:
  ```dart
  class ConnectionTimings {
    static const scanDuration = Duration(seconds: 15);
    static const earlyConnectTimeout = Duration(seconds: 30);
    static const preScanDeviceCheckTimeout = Duration(seconds: 2);
    static const postScanSettleDelay = Duration(milliseconds: 200);
    static const shotSettingsDebounce = Duration(milliseconds: 100);
    static const profileDownloadGuard = Duration(milliseconds: 500);
  }
  ```
- Replace inline literals at the 7 sites in the roadmap. Keep per-transport constants (`_postConnectDelay`, `_discoveryRetryDelay`, etc.) where they are — those are transport-implementation internals, not controller-level timings.
- `DisconnectExpectations.ttl` (already a constant) stays where it is.

**Item 27 — adapter state in ScanReport.**
- `ScanReportBuilder.build({...})` gains `required AdapterState adapterStateAtStart` and `required AdapterState adapterStateAtEnd` parameters.
- `ScanOrchestrator.run()` captures the start state immediately before scanning, passes to builder at build time. End state: read again at build. Source: `_deviceScanner.adapterStateStream` via a new `currentAdapterState` getter on `DeviceScanner` (`BehaviorSubject.value`).
- Test: extend `scan_report_builder_test.dart` (if exists) or add one asserting both fields populated from injected state.

**Item 28 — cache `DeviceController.devices`.**
- Add `List<Device>? _flatDevicesCache;` invalidated to `null` in `_serviceUpdate` (the sole mutation point).
- Getter returns cached list (wrapped `List.unmodifiable`) or rebuilds on miss.
- Keep `fold` logic unchanged.

**Item 29 — adapter-state multicast.**
- Current: `initialize()` only subscribes to `adapterStateStream` of each `BleDiscoveryService` and forwards each event. Correct in principle; check if events *actually* compose (e.g. service A says `on`, service B says `unknown` — current code passes both through). If not already a problem in practice:
  - Document single-adapter assumption in doc-comment on `_adapterStateStream`, note that multi-adapter merging is TODO.
  - Or: merge with a reducer (`on` if any on, else `off` if any off, else `unknown`) — preferred if trivial.
- Decision at implementation time based on whether a sensible merge exists; if not, document and move on.

**Item 30 — ConnectionPhase state machine doc.**
- Add an ASCII diagram to `doc/DeviceManagement.md` or a dedicated `doc/connection-phases.md`:
  ```
  idle → scanning → connectingMachine → connectingScale → ready
                                     ↘ ready (no scale)
         (any phase) → error → idle
  ```
- List the transition-owner per edge (`ConnectionManager._connectImpl`, `connectMachine`, etc.) so a future reader can find where transitions happen.
- Inline docstring on `ConnectionPhase` enum pointing at the doc.
- No code change. Illegal-transition enforcement deferred — scope creep.

## Verification

**Analyze + unit + integration:**
- `flutter analyze` clean.
- `flutter test` — all green, no skips beyond existing.

**End-to-end smoke (M50Mini + real DE1Pro):**
- Cold connect, disconnect, reconnect cycle per `.agents/skills/streamline-bridge/verification.md`.
- Check `flutter logs` for the new `reconnection_duration_<deviceId>` key format after a reconnect (item 20 verification).
- No regressions in connect/disconnect timing.

Because the effort is mostly constant-rename + doc, smoke test only once at the end of 6B (or at 6A if the audit surfaces behavior risk).

## Post-merge

Once both sub-PRs land in `integration/comms-harden-rest`:
1. Move all `doc/plans/comms-phase-*.md` + `comms-harden.md` + `comms-code-review.md` → `doc/plans/archive/comms-harden/` (per CLAUDE.md).
2. Audit `doc/Api.md`, `doc/DeviceManagement.md` for drift vs the Phase 2–5 changes.
3. Open `integration/comms-harden-rest` → `main` PR. Body: short recap of items resolved, pointer to the archived plan folder.
