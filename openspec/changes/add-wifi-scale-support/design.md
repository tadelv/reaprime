## Context

The Half Decent Scale (HDS) is one physical scale reachable over three transports at once: BLE, USB, and WiFi. The app already implements two — `DecentScale` (BLE) and `HDSSerial` (USB), both under `lib/src/models/device/impl/decent_scale/`. This change adds the third.

The driver is radio contention: on a DE1 tablet, machine and scale are both BLE GATT connections sharing one radio. Moving the scale to WiFi frees the radio for the machine. The win is reliability, so the connection's reliability machinery (recognition gate, snapshot watchdog, reachability-driven presence, IP caching — with reconnect owned by `ConnectionManager`, not the scale) is the substance of the work, not an add-on.

The codebase has a clean transport-injection seam: a `Scale` depends on an injected `DataTransport`; `ScaleController` and `ConnectionManager` never touch transport specifics. BLE scales take a `BLETransport`; the USB HDS takes a `SerialTransport`. Both `BLETransport` and `SerialTransport` extend the minimal `DataTransport` (`connect`/`disconnect`/`dispose`/`connectionState`) with their own I/O methods. A WiFi scale slots in with a new `DataTransport` subclass and a new `Scale` implementation; nothing above the seam changes.

Two discovery precedents exist. BLE: scan → `(BLETransport, advertisedName)` → `DeviceMatcher.match()` → `Scale`. USB: enumerate serial ports → on name `"Half Decent Scale"` construct `HDSSerial` **directly**, bypassing `DeviceMatcher`. WiFi follows the USB precedent — it constructs its scale directly — because `DeviceMatcher.match()` is BLE-transport-coupled and a network service is not a BLE advertisement.

Protocol and discovery facts are confirmed from the `decentespresso/openscale` firmware source (authoritative). Reliability constraints (resolve-once/cache-IP, prefer IPv4, recognition gate) come from the firmware authors' own tooling and are mirrored by the prior-art Decenza app (`Kulitorum/Decenza`), which ships this feature in Qt/C++.

## Goals / Non-Goals

**Goals:**
- Stream weight from an HDS over WiFi with reliability equal to or better than BLE under radio contention.
- DNS-SD auto-discovery + manual-IP fallback, day 1, on all five supported platforms.
- Keep the WiFi scale a distinct device with a transport-scoped identity (`deviceId = "wifi:<host>"`).
- Reuse the existing `Scale` / `ScaleController` / `ConnectionManager` seam unchanged.
- Survive mDNS flakiness and network churn via IP caching, reachability-driven presence, a snapshot watchdog, and a single (manager-owned) reconnect policy.

**Non-Goals:**
- WiFi provisioning of the scale. The scale's own AP captive portal handles joining a network; the app only discovers/connects an already-provisioned scale.
- Merging/deduplicating the BLE, USB, and WiFi identities of one physical scale. Explicitly out of scope — three entries is acceptable.
- `wss://` / TLS, authentication, or QoS tuning (DSCP). The endpoint is unauthenticated cleartext, same trust model as BLE; QoS (Decenza sets DSCP EF + `TCP_NODELAY`) is not reachable from Dart's WebSocket API and is deferred.
- Changing the `Scale` interface or any controller behavior.

## Decisions

### Decision: `bonsoir` for DNS-SD across all platforms
**Choice:** Add `bonsoir` for service discovery.
**Why:** It is the only Flutter package covering all five targets (Android, iOS, macOS, Windows, Linux). On Android it wraps `NsdManager`, which resolves `.local` / DNS-SD natively and holds the multicast plumbing inside the framework — so **no app-managed `MulticastLock` and no foreground service** are needed for discovery. On Apple it wraps Bonjour; on Linux it uses Avahi.
**Alternatives considered:**
- `nsd` — equally native (NsdManager/Bonjour) but **no Linux support**; rejected because Linux is a supported platform.
- `multicast_dns` (official) — pure-Dart UDP; on Android it does not acquire the `MulticastLock`, so responses are filtered and discovery silently returns nothing on many devices. Rejected for the primary platform.
- Hand-rolled mDNS (what Decenza did) — only necessary because Qt couldn't resolve `.local` on Android. The Flutter ecosystem makes this avoidable; rejected as needless risk.

### Decision: WiFi scale constructed directly by the discovery service, not via `DeviceMatcher`
**Choice:** `WifiScaleDiscoveryService` constructs `HDSWifi` itself from a resolved endpoint.
**Why:** `DeviceMatcher.match()` takes a `BLETransport` + advertised name; a DNS-SD service has neither. This mirrors the existing USB HDS path, which also bypasses the matcher.
**Alternative:** Generalize `DeviceMatcher` to be transport-agnostic — larger blast radius, touches the BLE path, not justified for one device type.

### Decision: New `WebSocketTransport extends DataTransport`
**Choice:** A thin transport wrapping `web_socket_channel`, exposing `sendMessage(String)` and `Stream<String>` of inbound text frames, plus the base `connect`/`disconnect`/`dispose`/`connectionState`.
**Why:** Honors the project rule that 3rd-party library types stay behind the transport boundary, and keeps `HDSWifi` unit-testable against a fake transport. The shape resembles `SerialTransport` (text in/out) but the protocol differs entirely (JSON vs. binary frames), so no parsing is shared with `HDSSerial`.
**Alternative:** Let `HDSWifi` hold the `WebSocketChannel` directly — violates the boundary rule and hurts testability. Rejected.

### Decision: Recognition gate before reporting connected
**Choice:** After the WebSocket opens and the handshake is sent, arm a ~3–5s recognition timer; the first frame with `grams` (or a `status` frame) flips state to connected. Timeout → fail.
**Why:** A bare WebSocket upgrade succeeding does not prove the endpoint is an HDS (especially for manual-IP entry pointed at the wrong host). The gate prevents persisting/announcing a non-scale as a connected scale. This is also Decenza's behavior.

### Decision: Connection identity and address scheme
**Choice:** `deviceId = "wifi:<host>"` where `<host>` is the user-entered address or the discovered hostname. The persisted preferred-scale record stores this string; it is recognizable by the `wifi:` prefix.
**Why:** Transport-scoped, stable across reconnects, and trivially distinguishable from BLE (MAC) and USB (port) IDs. Matches the "distinct device" decision and mirrors Decenza's `wifi:` address prefix.

### Decision: Resolve-once + IP cache, prefer IPv4
**Choice:** On first connect, resolve the service/hostname to an IPv4 address and cache it keyed by host. Reconnects try the cached IP first; only on failure do we re-resolve via mDNS. A successful resolve to a new IP replaces the cache.
**Why:** The firmware authors' own stress tooling notes repeated mDNS lookups fail intermittently under load, and AAAA lookups block ~5s before IPv4 fallback. Caching the IPv4 address makes reconnect fast and resilient. Self-healing on stale cache.

## Connect state machine + reconnect ownership

**Reconnect is owned by `ConnectionManager`, not `HDSWifi`** — one reconnect policy across all transports (BLE, USB, WiFi). `HDSWifi` owns only the WebSocket-specific *connect* concerns (handshake, recognition gate, snapshot watchdog) and reports a drop by emitting `disconnected`; the manager's existing preferred-scale reconnect re-connects it.

> **Revised decision (was: in-scale backoff loop).** The first cut had `HDSWifi` run its own resolve→connect→recognize→**backoff** reconnect loop and emit `connecting` (never `disconnected`) to keep the manager out. Real-hardware testing showed why that's wrong: the app *already* reconnects scales in `ConnectionManager` (`_maybeSchedulePreferredScaleReconnect`), so we had **two divergent reconnect policies**, and emitting perpetual `connecting` made the scale behave unlike every other device (confusing `DeviceController`/status). Two owners also raced for one of the HDS's **few WebSocket-client slots**. Collapsing to one owner (the manager) fixes all three.

`HDSWifi`'s per-connection state machine (one shot per `onConnect()`):

```
   onConnect()  ─────────────────────────────────────────────┐
        │                                                     │ ConnectionManager
        ▼                                                     │ calls onConnect()
   ┌─────────────┐                                            │ again after a drop
   │ CONNECTING  │  transport = factory()  (cached IP→host)   │ (preferred-scale
   │  open ws    │  send rate 10k / events on / status        │  reconnect, ~5s)
   └──────┬──────┘                                            │
   ws ok  │   ws error / close-before-recognize → _failAttempt → onConnect() throws
          ▼                                                    │
   ┌──────────────┐  timeout → _failAttempt (throws)           │
   │ RECOGNIZING  │  await first grams/status frame            │
   └──────┬───────┘                                            │
   frame  │                                                    │
          ▼                                                    │
   ┌──────────────┐  frame received → pet watchdog ◄───┐       │
   │ CONNECTED    │                                    │       │
   │ emit snapshots, arm watchdog                       │      │
   └──────┬───────┘ ──────────────────────────────────┘       │
          │ socket close │ watchdog stall │ power_off          │
          ▼                                                    │
   _reportLost → emit DISCONNECTED, tear down ─────────────────┘
```

Notes:
- **Watchdog** stays in `HDSWifi` because only the scale can see a *silent* stall — frames stopping without the socket closing. Its job is now narrow: detect the stall and **emit `disconnected`** (it no longer drives reconnect). Generation-token + cancellable-timer idiom (cf. `De1Controller._shotSettingsDebounce`) guards every callback.
- **One reconnect policy:** on `disconnected`, `DisconnectSupervisor` (if the drop was unexpected) → `_maybeSchedulePreferredScaleReconnect` → `connect(scaleOnly:true)` after `preferredScaleReconnectDelay` (5s) → re-scan → discovery re-emits `wifi:<host>` → `connectToScale` → `onConnect()` again. Serialized through the manager, which also gives the HDS time to free its single client slot.
- **Caveat (consistent with BLE/USB):** the manager only auto-reconnects a scale **while a machine is connected** (`_shouldRetryPreferredScale`). Standalone scale-only use won't auto-reconnect — same as every other scale today.
- **Recognition failure** (connect error or timeout) throws out of `onConnect()`, which `ScaleController`/`ConnectionManager` already handle (manual-entry validation surfaces the failure; a background reconnect just retries on the next cycle).
- **No `ConnectionManager` changes required** — its scale-reconnect is transport-agnostic (keys off `ScaleController.connectionState`).

## App-start reconnect through `ConnectionManager`

The BLE/USB preferred-scale flow is scan → match preferred `deviceId` → connect. A WiFi scale is a *stored endpoint*, not something a passive scan surfaces the same way. Resolution:

- `WifiScaleDiscoveryService` holds a set of **known endpoints** = discovered services ∪ persisted manual endpoints. When `ConnectionManager` runs a scan, the service emits a scale device for each known endpoint (discovered or persisted) so the existing "match preferred `deviceId`" logic works unchanged.
- For a persisted WiFi scale whose mDNS service isn't currently visible, the service still emits a device built from the stored `wifi:<host>` address; the connect attempt then drives the RESOLVING→CONNECTING path (cached IP first). This keeps all the network/resolve logic inside the scale/transport/discovery layer and leaves `ConnectionManager` untouched.
- Net effect: `ConnectionManager` treats a WiFi preferred scale exactly like any other preferred scale — it sees a candidate device with the matching `deviceId` and calls `connectToScale`.

## Risks / Trade-offs

- **mDNS unreliable / absent (esp. Linux without Avahi)** → Manual-IP fallback is day-1 and doubles as the universal escape hatch; IP caching reduces reliance on repeated resolution.
- **Android cleartext `ws://` blocked by network-security-config** → `web_socket_channel` on non-web uses `dart:io` sockets, which bypass Android's network-security-config, so it's expected to work without `usesCleartextTraffic`. Treated as a **smoke-test verification item**, not a pre-emptive manifest change — avoid loosening cleartext policy app-wide if unnecessary.
- **Apple local-network gate** → Missing `NSBonjourServices` / `NSLocalNetworkUsageDescription` makes discovery silently return nothing and looks like a bug. Mitigation: explicit Info.plist + entitlement tasks, verified on a real device.
- **Three entries for one scale confuses users** → Accepted trade-off per the identity decision; mitigate with clear labeling (e.g. "Half Decent Scale (WiFi)").
- **DHCP changes the scale's IP** → Cached IP fails → fall back to mDNS re-resolution; manual-IP users may need to re-enter if they hard-coded an IP and have no mDNS. Documented behavior.
- **2.4 GHz WiFi/BT coexistence on cheap tablets** → The contention win is strongest on 5 GHz WiFi; on shared-antenna 2.4 GHz radios the benefit is smaller. Setup guidance, not a code concern.
- **New dependency surface (`bonsoir`)** → Adds native plugin code on five platforms. Mitigation: it's the most actively maintained option and the discovery layer is isolated behind `WifiScaleDiscoveryService`, so swapping it later is contained.
