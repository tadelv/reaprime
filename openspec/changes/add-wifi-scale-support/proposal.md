## Why

On a DE1 tablet the machine and the scale are both BLE GATT connections sharing a single Bluetooth radio. They contend for connection events, and on tablets with weak Bluetooth this degrades both links — dropped weight samples, laggy machine state, reconnect churn. The Half Decent Scale (HDS) can also stream over WiFi. Moving the scale onto WiFi leaves the BLE radio serving only the machine, improving the reliability of both connections. Reliability under contention is the point of this change, not range or convenience.

## What Changes

- Add a third transport for the Half Decent Scale: **WiFi (WebSocket)**, alongside the existing BLE (`DecentScale`) and USB (`HDSSerial`) implementations.
- Add **DNS-SD auto-discovery** of the HDS on the local network (browse `_decentscale._tcp`, resolve to an IP), surfaced into the existing unified device stream.
- Add a **manual-IP fallback** so a WiFi scale can be added by address when discovery is unavailable (locked-down networks, Linux without Avahi, or any discovery failure). This is a day-1 capability, not a follow-up.
- Treat the WiFi HDS as a **distinct device** with its own address (`deviceId = "wifi:<host>"`). It is not merged with the BLE/USB identities of the same physical scale; the user picks whichever transport they want.
- Persist a chosen WiFi scale and reconnect to it on app start, honoring the existing preferred-scale policy.
- Add per-platform local-network configuration (iOS/macOS Bonjour declarations + entitlement) so discovery works on all supported platforms.
- Add a new dependency: `bonsoir` for cross-platform DNS-SD. The WebSocket dependency (`web_socket_channel`) is already present.

No breaking changes. The `Scale` interface, `ScaleController`, and `ConnectionManager` are unchanged — the new transport bolts onto the existing seam.

## Capabilities

### New Capabilities
- `wifi-scale-discovery`: Discovering a Half Decent Scale over the local network via DNS-SD (mDNS), plus adding one manually by IP, and surfacing it into the device stream with a stable WiFi-scoped identity. Covers resolve-once/IP-cache behavior and the manual-entry fallback.
- `wifi-scale-connection`: Connecting to and streaming from the HDS over a WebSocket — the JSON wire protocol (weight, status, events), the connect handshake, the HDS-recognition gate, taring/timer/display commands, and the snapshot-watchdog + backoff reconnect loop that makes the link reliable.

### Modified Capabilities
<!-- None. No existing OpenSpec specs; Scale interface / ScaleController / ConnectionManager behavior is unchanged. -->

## Impact

- **New code:**
  - `lib/src/services/` — `WifiScaleDiscoveryService` (extends `DeviceDiscoveryService`; bonsoir browse + manual endpoints; constructs the WiFi scale directly, like the serial HDS path).
  - `lib/src/models/device/transport/` — `WebSocketTransport` (extends `DataTransport`; wraps `web_socket_channel`, keeping the library type behind the transport boundary).
  - `lib/src/models/device/impl/decent_scale/` — new `HDSWifi` scale (sibling of `scale.dart` / `scale_serial.dart`) implementing the `Scale` interface and the JSON protocol.
- **Wiring:** register `WifiScaleDiscoveryService` in `DeviceController._services` (and `main.dart` init).
- **Manual-entry REST API:** `WifiScaleDiscoveryService` is also threaded into `startWebServer` so a new `/api/v1/devices/wifi` handler (`POST`/`DELETE`/`GET`) can drive `addManualEndpoint`/`removeManualEndpoint` — the skin can't call the Dart methods directly. The skin's "Add WiFi Scale" UI calls this endpoint.
- **Dependencies:** add `bonsoir` to `pubspec.yaml`. `web_socket_channel ^3.0.3` already present.
- **Platform config:**
  - iOS/macOS `Info.plist`: `NSBonjourServices` = `_decentscale._tcp`, `NSLocalNetworkUsageDescription` string; sandboxed macOS also needs `com.apple.security.network.client`.
  - Android: cleartext `ws://` to local addresses — verify via smoke test (dart:io sockets bypass network-security-config; expected to work without `usesCleartextTraffic`).
  - Linux: bonsoir discovery requires the Avahi daemon; manual-IP is the fallback where absent.
  - Windows: native dns_sd, no special config expected.
- **Docs:** `doc/DeviceManagement.md` (new discovery/connection flow), and `doc/Api.md` only if a device/endpoint surface changes.
- **Unchanged:** `Scale` interface, `ScaleController`, `ConnectionManager`, BLE/USB scale implementations.
