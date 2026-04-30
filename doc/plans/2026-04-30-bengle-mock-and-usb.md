# Bengle: MockBengle + Real USB Discovery (steps 2 + 3)

**Branch:** `feat/bengle-mock-and-usb`
**Roadmap:** [ReaPrime Integration](obsidian://open?vault=mule&file=Professional%2FDecent%2FBengle%2FReaPrime%20Integration), steps 2 + 3.
**Predecessor:** [PR #207](https://github.com/tadelv/reaprime/pull/207) shipped step 1 (foundation). `Bengle extends UnifiedDe1 implements BengleInterface` with `beforeFirmwareUpload` override; capability mixins deferred to steps 4–7.

## Goal

One PR delivers:

1. **`MockBengle`** — `BengleInterface` instance surfaced via the simulated-device discovery, so the rest of the app can exercise a Bengle without hardware.
2. **Real USB discovery for Bengle** — extend desktop + Android serial detection to identify a Bengle USB device and instantiate `Bengle` (not `UnifiedDe1`) on the existing `SerialTransport`.
3. **Machine debug view Bengle-aware** — `De1DebugView` shows device class and a placeholder Bengle section.

BLE discovery already done in PR #207. Bengle USB hardware is on hand for smoke-testing.

No capability mixins. `MockBengle` and a USB-connected `Bengle` behave as `UnifiedDe1` + the FW-prelude override. Step 4 (cup warmer) is the first capability-bearing PR.

## Non-goals

- Capability mixins (cup warmer / integrated scale / LED / milk probe).
- New REST/WS endpoints.
- Bengle-specific BLE service UUID verification (Bengle inherits DE1's `ffff` for now; revisit if FW differs).
- Standalone MMR-probe module / USB-device-table abstraction. Both rejected as over-scoped — see "Design" rationale.

## Current state

- **`MockDe1`** (`lib/src/models/device/impl/mock_de1/mock_de1.dart`) implements `De1Interface` directly (no transport). Constructor takes `deviceId` (default `"MockDe1"`). `updateFirmware` is faked at the public level — `_updateFirmware` template never runs, so `beforeFirmwareUpload` doesn't fire on mocks.
- **`Bengle`** (`lib/src/models/device/impl/bengle/bengle.dart`) — 21 lines, `extends UnifiedDe1 implements BengleInterface`, overrides `name` and `beforeFirmwareUpload`.
- **USB detect** today: `productName == "DE1"` shortcut (desktop `serial_service_desktop.dart:230`, Android `serial_service_android.dart:204`) → `UnifiedDe1(transport:)`. Fallback opens port, collects raw output, calls `isDE1()` (`utils.dart:26`) which checks for `[M]` prefix, then constructs `UnifiedDe1`. Desktop already extracts `port.vendorId` / `port.productId` (lines 205–206, 381–382) for stable IDs but doesn't match on them.
- **`v13Model`** is a 16-bit MMR int (`MMRItem.v13Model`, `de1.models.dart:217`); read in `UnifiedDe1.onConnect` (`unified_de1.dart:170`). Values `>= 128` mean Bengle hardware. Authoritative DE1-vs-Bengle signal once a transport is connected.
- **Bengle USB protocol confirmed** (manually verified): base protocol identical to DE1 — `[M]` echo + standard MMR framing. Bengle may add new prefix letters; existing parsers ignore unknown prefixes.
- **Simulated devices:** `SimulatedDevicesTypes` enum in `settings_service.dart:420` (`machine`, `scale`, `sensor`). `SimulatedDeviceService.scanForDevices()` (`simulated_device_service.dart:37`) inserts `MockDe1()` when `machine` is enabled. **Settings UI iterates `SimulatedDevicesTypes.values`** (`settings_view.dart:455`) — adding an enum value auto-renders a toggle, no UI code change. `fromString` uses `firstWhereOrNull(values)` — auto-handles too. Webserver settings handler (`settings_handler.dart:211`) likewise.
- **Downstream consumers** (`ConnectionManager`, `De1Controller`, scan orchestrator, web handlers) all type on `De1Interface`. `Bengle` and `MockBengle` slot in unchanged.
- **Machine debug view:** `De1DebugView` (`lib/src/sample_feature/sample_item_details_view.dart`, route `/debug_details`) takes `De1Interface`; rendered from `SampleItemListView` (route `/debug`). No Bengle awareness today.

## Design

### Step 2 — `MockBengle`

`class MockBengle extends MockDe1 implements BengleInterface`.

- `BengleInterface extends De1Interface`. `MockDe1` already implements `De1Interface`. Subclass + add `implements BengleInterface` → satisfied with zero method duplication.
- Constructor passes `deviceId` through; default `"MockBengle"`.
- Override `name` for distinct visibility. Match `MockDe1`'s convention (verify what `MockDe1.name` returns; mirror the format).
- No `beforeFirmwareUpload` override on the mock — `MockDe1.updateFirmware` is fake at the public level, so the template hook never fires. YAGNI.

**Plumbing:**
- Add `bengle` to `SimulatedDevicesTypes` enum.
- `SimulatedDeviceService.scanForDevices()`: new branch — `if (enabledDevices.contains(SimulatedDevicesTypes.bengle)) _devices['MockBengle'] = MockBengle();`.
- `_parseSimulateFlag` (`main.dart:108`): no code change required. `simulate=1` already maps to `SimulatedDevicesTypes.values.toSet()` — auto-includes `bengle`. `simulate=bengle` and `simulate=machine,bengle` work via existing `fromString` (already `firstWhereOrNull(values)`).
- Settings UI: zero changes — auto-renders.

**`simulate=1` behavior change:** auto-includes the new `bengle`, so `simulate=1` now surfaces two simulated machines (`MockDe1` + `MockBengle`). `ConnectionManager`'s preferred-device policy picks one. Acceptable — `simulate=1` is legacy. **Document in PR description** so anyone running it spots the change.

### Step 3 — Real USB discovery

Three small, independent additions to existing detection:

1. **`productName == "Bengle"` shortcut** alongside the existing `"DE1"` shortcut (both desktop + Android). Cheap. May not match today's hardware (Bengle may not yet expose this productName), but trivial future-proofing — once FW exposes it, this is the path of least latency.

2. **VID:PID shortcut** before the fallback. With Bengle hardware present, the actual VID:PID can be discovered today (procedure below). Same for DE1. Hard-coded constants in a small shared file consulted by both serial services — no need for a generic table abstraction.

3. **Extend the fallback** (the only path that's not an exact early shortcut): once the existing receive-and-check confirms `[M]` (i.e. it's a DE1-family device), issue an MMR read for `v13Model`, and pick `Bengle` if `>= 128`, else `UnifiedDe1`.

The fallback already opens the port and collects messages — adding one MMR request/response is the minimal extension. The MMR read encoding for serial is the same one `UnifiedDe1Transport._serialConnect` uses; lift the bytes-encoding/decoding helpers from `unified_de1.mmr.dart` into a small shared util if needed (`_packMMRInt` / `_unpackMMRInt` are already pure functions). No new "probe module" — just inline the read in the fallback path.

**Why no probe module / no class-swap pre-fast-path:** the only path that doesn't already know the class is the fallback path. The two shortcut paths (productName + VID:PID) are deterministic — no probe needed. Adding a generic probe layer would force every detection through the same code path and require lifting transport connect/disconnect machinery out of `UnifiedDe1Transport`; that's a refactor for a problem that doesn't exist after the shortcut layers cover known hardware.

**Why class dispatch (vs single `UnifiedDe1` with a flag):** capability mixins (steps 4–7) are class-level — `device is LedStripCapability` is the architecture decision in the Obsidian note. Splitting now keeps that cheap; a flag-based design would have to be reverted later.

**Risk: Bengle USB may not match `[M]` prefix today.** Bengle FW may add new prefix letters. Per user, the *base* protocol is preserved, so `isDE1()` will keep matching. If a Bengle hardware variant ever ships without `[M]`, the fallback drops it — but that's a regression we'd notice immediately on smoke test. Smoke-testing real Bengle USB during this PR is the safety net.

### Step 4 — Debug view

`De1DebugView` (`lib/src/sample_feature/sample_item_details_view.dart`):

1. Header label: show `"Bengle"` if `widget.machine is BengleInterface`, else `"DE1"`.
2. Capability section: if `widget.machine is BengleInterface`, render a placeholder (`"Bengle: no capabilities surfaced yet."`). Replaces nothing today; gives steps 4–7 a slot to populate.

Don't extract a `BengleDebugSection` widget yet — premature. Inline conditional. Re-evaluate when capabilities arrive.

## Files

**Create:**
- `lib/src/models/device/impl/bengle/mock_bengle.dart`
- `lib/src/services/serial/usb_ids.dart` — small file with `const de1UsbIds = [(vid, pid), …]` and `const bengleUsbIds = …` plus simple match helpers.
- `test/models/device/impl/bengle/mock_bengle_test.dart` — type identity + `name`.
- `test/services/serial/usb_ids_test.dart` — match helpers.
- `test/services/simulated_device_service_test.dart` — emits `MockBengle` when `bengle` enabled (or extend if file exists).

**Modify:**
- `lib/src/settings/settings_service.dart` — add `bengle` to `SimulatedDevicesTypes`.
- `lib/src/services/simulated_device_service.dart` — `bengle` branch in `scanForDevices()`.
- `lib/src/services/serial/serial_service_desktop.dart` — Bengle productName shortcut + VID:PID match + extend fallback to read v13Model and dispatch class.
- `lib/src/services/serial/serial_service_android.dart` — same.
- `lib/src/services/serial/utils.dart` — possibly lift `_packMMRInt` / `_unpackMMRInt` from `unified_de1.mmr.dart` here (or a sibling file) so the fallback can encode the MMR read without depending on `UnifiedDe1`.
- `lib/src/sample_feature/sample_item_details_view.dart` — `De1DebugView` Bengle-aware header + placeholder capability section.

**Docs:**
- `doc/DeviceManagement.md` — Bengle USB recognition path + `MockBengle` simulate flag.
- Obsidian note: tick steps 2 + 3 on merge.

## Test plan

Per `.claude/skills/tdd-workflow/`. Tier choices:

- **Unit (`flutter test`):**
  - `MockBengle`: type identity (`is BengleInterface`, `is De1Interface`), `name` matches convention, `deviceId` defaults sensibly.
  - VID:PID match helpers: known DE1 pair → `de1`; known Bengle pair → `bengle`; unknown → no match.
  - MMR pack/unpack helpers (if lifted): existing tests, if any, follow the move.
- **Integration (`flutter test`, multi-component):**
  - `SimulatedDeviceService` emits `MockBengle` when `SimulatedDevicesTypes.bengle` enabled and not when only `machine` is.
  - Serial-service detection path with a fake transport that echoes a v13Model `>= 128` → `Bengle`; fake transport echoing `< 128` → `UnifiedDe1`. Use the existing fake-transport infra if present; if not, decide pragmatically — may be cheaper to cover this case in end-to-end smoke than build new fake-transport plumbing.
- **End-to-end smoke** via `scripts/sb-dev.sh` (per `.agents/skills/streamline-bridge/verification.md`):
  - Simulated path: `flutter run --dart-define=simulate=bengle` → `MockBengle` appears in `GET /api/v1/devices/scan`; connect via API; profile send + state requests succeed.
  - **Real Bengle USB path** (hardware on hand): plug Bengle, run app, verify `Bengle` instance constructed (not `UnifiedDe1`); check debug view shows "Bengle" header; connect, profile, run a shot. Capture log output for PR description.

## Verification + completion

1. `flutter test` clean.
2. `flutter analyze` clean.
3. End-to-end smoke (simulated + real Bengle USB) per above.
4. Move plan to `doc/plans/archive/bengle-mock-and-usb/` (per CLAUDE.md archive policy — keep design, drop step-by-step).
5. Update Obsidian roadmap with PR link + step 2/3 checkbox state on merge.

## Risks + open questions

- **Bengle VID:PID** — to be obtained from the hardware on hand. Procedure below.
- **MMR read in fallback** — first time we encode an MMR request outside `UnifiedDe1Transport`. Verify the bytes-on-the-wire match what `_serialConnect` does. Cross-check by tracing what `UnifiedDe1Transport._serialConnect` writes for an MMR read, then mirror it in the fallback.
- **Bengle protocol prefix letters** — confirmed Bengle preserves DE1 base protocol. New prefix letters fine; `isDE1()` only checks for `[M]`.
- **`simulate=1` two-machine UX** — accepted as legacy behavior change. Document in PR.

## Implementation sequence

1. **Step 2 — `MockBengle`**
   1. Add `MockBengle extends MockDe1 implements BengleInterface` + unit test.
   2. Extend `SimulatedDevicesTypes` enum + `SimulatedDeviceService.scanForDevices()`.
   3. Verify settings UI toggle appears (auto-iter); webserver settings handler accepts `"bengle"`.
2. **Step 3 — USB detection**
   1. Obtain Bengle + DE1 VID:PID (procedure below). Land them in `usb_ids.dart`.
   2. Add `productName == "Bengle"` + VID:PID shortcut to desktop service, alongside DE1 shortcut.
   3. Extend desktop fallback: post-`isDE1()` confirm, send MMR-read for v13Model, decode 16-bit int, pick `Bengle` if `>= 128`.
   4. Mirror to Android service.
   5. Lift MMR pack/unpack to shared util if the in-place encoding is too coupled to `UnifiedDe1Transport`.
3. **Step 4 — Debug view**
   1. `De1DebugView` Bengle-aware header + placeholder capability section.
4. **Wrap-up**
   1. Update `doc/DeviceManagement.md`.
   2. Smoke: simulated MockBengle path + real Bengle USB path.
   3. Archive plan; open PR; tick Obsidian roadmap.

## Obtaining Bengle VID:PID (with hardware on hand)

Pick one:

- **In-app log line.** Add a temporary `_log.info("USB scan: name=$productName vid=${vid?.toRadixString(16)} pid=${pid?.toRadixString(16)}")` in `_performScan` (desktop) / `_detectDevice` (Android). Run app, plug Bengle, copy values from log, drop the line.
- **macOS:** `system_profiler SPUSBDataType | grep -A 10 -i bengle` — reads `Vendor ID:` and `Product ID:`.
- **Linux:** `lsusb` (compact `vid:pid` listing) or `dmesg | tail` after plug-in.
- **Windows:** Device Manager → Bengle device → Properties → Details → Hardware IDs → `USB\VID_xxxx&PID_yyyy`.

Cross-check with FW source / John for cases where the descriptor changes between FW versions.
