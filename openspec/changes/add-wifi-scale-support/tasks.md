## 1. Dependencies & platform config

- [x] 1.1 Add `bonsoir` to `pubspec.yaml`; run `flutter pub get`; confirm `web_socket_channel ^3.0.3` is present (it is)
- [x] 1.2 iOS: add `NSBonjourServices` (`_decentscale._tcp`) and `NSLocalNetworkUsageDescription` to `ios/Runner/Info.plist`
- [x] 1.3 macOS: add the same `NSBonjourServices` / `NSLocalNetworkUsageDescription` keys to `macos/Runner/Info.plist` and the `com.apple.security.network.client` entitlement to the `.entitlements` files (entitlement already present in both Debug+Release)
- [x] 1.4 Linux/Windows: confirm no build-time config needed (bonsoir plugins self-register); note Avahi runtime dependency for Linux discovery in `doc/DeviceManagement.md` (doc note deferred to task 8.1)

## 2. WebSocketTransport (transport boundary)

- [x] 2.1 Write unit tests for `WebSocketTransport` against a fake channel: connect/disconnect lifecycle, `connectionState` emissions, `sendMessage`, inbound `Stream<String>`, `dispose` cleanup
- [x] 2.2 Implement `WebSocketTransport extends DataTransport` in `lib/src/models/device/transport/`, wrapping `web_socket_channel`; keep the library type fully encapsulated (no leakage to scale/controller code)

## 3. JSON protocol parser

- [x] 3.1 Write unit tests for the frame parser: untyped `{grams, ms}` → weight; `status` → battery/charging; `button`/`power`/`rate`/`error` typed frames; unknown type ignored without error; malformed JSON handled
- [x] 3.2 Implement the parser mapping frames to the domain `Scale` snapshot model

## 4. HDSWifi scale + reliability state machine

- [x] 4.1 Write unit tests (fake transport) for: connect handshake order (`rate 10k` → `events on` → `status`); recognition gate (first `grams`/`status` → connected; timeout → fail); tare/timer/display commands sent; `deviceId == "wifi:<host>"`
- [x] 4.2 Write unit tests for the watchdog + backoff state machine: stalled stream → disconnected → reconnect; exponential backoff (5→10→20→40→60s cap); clean `disconnect()`/`dispose()` cancels pending reconnect (generation-token idiom); stream resume → reconnected
- [x] 4.3 Implement `HDSWifi` in `lib/src/models/device/impl/decent_scale/` implementing the `Scale` interface (currentSnapshot, tare, startTimer/stopTimer/resetTimer, sleep/wakeDisplay), wiring the parser, handshake, recognition gate, and watchdog/backoff state machine
- [x] 4.4 Implement resolve-once + IPv4-preferred IP cache (keyed by host) used by the RESOLVING state; self-heal stale cache on successful re-resolve

## 5. WifiScaleDiscoveryService

- [x] 5.1 Write tests (fake bonsoir/discovery) for: discovering `_decentscale._tcp` → emits a WiFi scale device; no service → no device, no error; discovery-unavailable → no crash
- [x] 5.2 Implement `WifiScaleDiscoveryService extends DeviceDiscoveryService` in `lib/src/services/`; browse `_decentscale._tcp` via bonsoir, resolve IP, construct `HDSWifi` directly (bypassing `DeviceMatcher`, mirroring the serial HDS path)
- [x] 5.3 Add persisted manual endpoints + discovered services as a unified "known endpoints" set; emit a scale device per known endpoint on scan so `ConnectionManager`'s preferred-`deviceId` match works unchanged (app-start reconnect)
- [x] 5.4 Persist/restore manual-IP endpoints via the existing storage layer (shared_preferences); resolved-IP cache held in-memory by `WifiIpCache`

## 6. Wiring & UI

- [x] 6.1 Register `WifiScaleDiscoveryService` in `DeviceController._services` and initialize it in `main.dart`
- [ ] 6.2 Add an "Add WiFi Scale" entry path in the device/settings UI: enter IP, validate via recognition gate, surface failure on unreachable/wrong address; label discovered entries clearly (e.g. "Half Decent Scale (WiFi)")
- [x] 6.3 Confirmed `ScaleController` and `ConnectionManager` require no changes — `HDSWifi.onConnect()` awaits recognition then emits `connected` (exactly what `ScaleController.connectToScale` checks); preferred-scale match works via the stable `wifi:<host>` deviceId. Neither file was modified.

## 7. Verification

- [x] 7.1 `flutter analyze` clean (scoped to new code); `flutter test` green — 1506 tests pass incl. 45 new WiFi-scale tests
- [ ] 7.2 macOS end-to-end smoke test: discover or manually add a real HDS, connect, observe live weight stream, tare, and watchdog reconnect (toggle WiFi) — see `.agents/skills/decent-app/verification.md`
- [ ] 7.3 Android real-device verification: discovery via NsdManager works without a MulticastLock; cleartext `ws://` connects (the `usesCleartextTraffic` smoke-test item) — confirm or, only if it fails, add a scoped network-security-config
- [ ] 7.4 iOS/macOS: confirm discovery returns results with the Info.plist/entitlement in place (silent-empty = missing keys)
- [ ] 7.5 Spot-check Linux (with Avahi) discovery and Windows discovery; verify manual-IP fallback on each platform

## 8. Docs

- [x] 8.1 Update `doc/DeviceManagement.md` with the WiFi discovery + manual-entry flow, the `wifi:<host>` identity, and the Avahi/per-platform notes
- [x] 8.2 No `doc/Api.md` change needed — discovered WiFi scales flow through existing device streams/endpoints; manual-entry is a UI/service action, not a new REST surface
- [x] 8.3 No `doc/plans/` docs were created — the OpenSpec change (`openspec/changes/add-wifi-scale-support/`) is the record of decisions
