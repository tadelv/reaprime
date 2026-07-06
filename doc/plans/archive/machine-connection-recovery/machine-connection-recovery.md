# Machine connection recovery (zombie links + auto-reconnect)

## Incident

2026-07-06, real DE1 tablet (teclast m50mini, Android 14). A power outage at
~08:50 killed the DE1. The app detected the transport disconnect cleanly at
08:54 (`Transport disconnected: Connection Timeout`), emitted
`machineDisconnected`, and then **did nothing for six hours** — no scan ran
between 08:54 and the 15:02 app restart, because nothing in the app ever
retries a machine connection automatically (full `connect()` is only called
from UI taps).

After the 15:02 restart the app reconnected, but the DE1's BLE side was flaky
(two MMR read timeouts during init). A GATT write then timed out; the
transport's fail-fast path cleared the queue (by design — see below) but never
verified the link. The connection silently died shortly after with **no
disconnect event delivered**, leaving the app in a zombie state:

- `DisconnectSupervisor` only reacts to `disconnected` stream events → never
  fired → `_machineConnected` stayed true forever.
- The preferred-scale reconnect loop kept scanning every ~20s but ignores
  machines entirely (`scaleOnly`).
- Even a manual full `connect()` would have skipped the machine phase
  (`if (_machineConnected)` short-circuit). Only an app restart escapes.

## Corrected diagnosis note (important)

The scan reports listing `DE1 (F1:9F..., machine)` during the zombie window do
**not** prove the DE1 was advertising: `DeviceController.scanForDevices()`
returns the cumulative device registry (connected devices are deliberately
kept in `matchedDevices`). Live advertisements are only visible at the
`UniversalBle.scanStream` level. Fix 2 therefore lives in the transport, not
in `ConnectionManager` scan-result inspection (which would false-positive on
every healthy scan).

## Fixes

### 1. Link verification on GATT operation timeout (transport)

`UniversalBleTransport._onOperationTimeout` deliberately does not tear down
the connection on a single timeout — a forced disconnect mid profile-upload
wedges DE1 firmware (see comment on `write()`). That stays. Added on top:

- After clearing the queue, fire an **async probe**:
  `UniversalBle.getConnectionState()`. If the OS reports the device
  disconnected (the incident's likely state — the disconnect *event* was
  lost, but polled state is truthful), declare the link dead.
- Track **consecutive** operation timeouts (reset on any successful
  read/write). At 3 in a row, declare the link dead even if the OS still
  claims connected — 30s+ of failed ops is beyond saving, including for an
  in-flight profile upload.
- "Declare dead" = idempotent: emit `disconnected` on the connection-state
  subject (starts the normal recovery cascade: UnifiedDe1 → De1Controller
  reset → DisconnectSupervisor → fix 3), clear the queue, and fire a
  best-effort `UniversalBle.disconnect()` so the OS handle doesn't block the
  next connect.

Single timeout + healthy OS link ⇒ behavior unchanged (clear queue, rethrow).

### 2. Advertising-while-connected detection (transport)

A DE1 never advertises while it holds a connection (codified in
`De1Interface.cachedFlowEstimation` docs). While the transport believes it is
connected, it listens to `UniversalBle.scanStream` for its own deviceId.
Seeing an advert triggers the same OS probe (throttled to one per 5s);
OS-confirmed disconnected ⇒ declare dead.

Deliberately probe-confirmed only: `UniversalBleTransport` is shared by
scales/sensors, and some peripherals legitimately advertise while connected —
an advert alone must not tear down a link. The residual gap (device
advertising while the OS *also* wrongly claims connected, with no GATT ops in
flight) is closed within minutes by fix 1's escalation the next time any
periodic op runs (e.g. BatteryController's USB-charger MMR writes).

This piggybacks on existing scans (scale-reconnect loop, UI scans) — adverts
only flow while some scan is running; the transport starts none itself.

### 3. Machine auto-reconnect loop (ConnectionManager)

Mirror of the preferred-scale reconnect loop, for the machine:

- `DisconnectSupervisor` gains an unexpected-only machine-disconnect callback
  (same pattern the scale side already has); expected disconnects
  (`markExpectingDisconnect`, `disconnectMachine`) do not trigger it.
- On unexpected machine disconnect with a `preferredMachineId` configured,
  `ConnectionManager` enters recovery mode: full `connect()` retries with the
  same 5s→60s exponential backoff used for scales. The loop reschedules
  itself after each attempt that ends without a machine (including attempts
  silently dropped by the concurrent-connect guard) and exits when the
  machine connects, on deliberate disconnect, or on dispose.
- Gated on `preferredMachineId` so a background retry can never pop a
  machine-picker ambiguity; the id is always set after any successful
  connect, so real-world coverage is total.

Known trade-off: recovery scans are full unfiltered scans; on Android in
background these are throttled by the OS. Acceptable — the DE1 tablet runs
foreground — and a filtered machine-scan variant can be added later if needed.

## Test tiers

- **Unit (transport):** fake `UniversalBlePlatform` via `UniversalBle.setInstance`
  — probe-on-timeout, consecutive escalation + reset, advert probe path,
  throttle, ignore foreign/not-connected adverts.
- **Unit/integration (ConnectionManager):** real DisconnectSupervisor +
  SettingsController with mock scanner/controllers (existing harness) —
  unexpected vs expected disconnect, backoff rearm, cancel on
  connect/deliberate disconnect, no-preferred gate.
- **End-to-end:** n/a (no REST/WS surface change); full suite + analyze.
