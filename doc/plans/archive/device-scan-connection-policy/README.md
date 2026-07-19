# Device scan and connection policy

## Status

Accepted for PR #476. Tracking issue: #477.

This document records the design as directed by the maintainer during review of the original field bug. Items marked **Maintainer direction** were explicitly chosen in discussion. Items marked **Implementation consequence** follow from those choices.

## Origin

An explicit skin scan called the same `ConnectionManager.connect()` path used by startup and recovery. That path could remembered-machine quick-connect before discovery, create a fresh DE1 object for the same peripheral, and pass it to `De1Controller.adoptDevice()`. Replacing the existing controller object produced an observable DE1 disconnect/re-attach even though the physical BLE link had not failed.

Adding `_machineConnected` to the quick-connect guard prevents that exact re-adoption. It was considered insufficient because an explicit scan is also expected to discover and connect a missing scale, surface non-preferred alternatives, preserve already-working slots, and sequence machine/scale decisions consistently.

## Two connection intents

### Automatic startup and recovery

**Maintainer direction:** Startup, unexpected-machine recovery, and Android USB-attach recovery use the automatic `connect()` policy.

These paths retain remembered-machine direct connection, preferred-device connection during scanning, and early stop. Their goal is fastest restoration of the expected configuration. USB attach remains in this category because the Android attach event is only an incomplete hint; after a short settle it still needs remembered-port probing or scan fallback.

A live machine must never enter remembered-machine quick-connect. Occupied slots are authoritative controller state, not the presence of a discovered object.

### Explicit scans

**Maintainer direction:** Native user scans, REST scans, and `ws/v1/devices` scan commands use `scanAndConnect()` when `connect=true`. They complete discovery before connection policy runs. `connect=false` remains discovery-only.

Explicit scans do not remembered-machine quick-connect, connect preferred devices during the scan, or early-stop discovery. This ensures the result set can include newly introduced scales and non-preferred alternatives before policy makes a choice.

## Slot policy

**Maintainer direction:** Machine and scale are independently fillable slots.

- A genuinely connected controller slot is preserved. Discovery never replaces it automatically, even when its ID differs from the saved preference.
- A missing slot auto-connects its preferred device when found.
- If the preferred device is absent or fails and alternatives exist, selection is ambiguous.
- Without a preferred ID, exactly one candidate auto-connects; multiple candidates are ambiguous.
- Explicit `PUT /api/v1/devices/connect` or the matching WebSocket command remains the intentional way to select a replacement.

**Maintainer direction:** A scale may connect when no machine is found. The overall phase remains `idle`, because `ready` still requires a machine. The scan UI shows the connected/found scale as a partial result rather than claiming that no devices were found.

## Ordered ambiguity and retained candidates

**Maintainer direction:** Machine ambiguity resolves before scale ambiguity. Machine and scale ambiguity are not exposed independently or simultaneously.

A scan selection session retains the immutable scan snapshot, machine and scale candidates, preferred IDs captured at scan time, and scan-report state. When a machine picker is shown, scale policy waits. A successful machine selection continues deterministically with the retained scale candidates:

1. Connect the selected machine.
2. If it is Bengle, attach its integrated scale and finish.
3. Otherwise auto-connect an unambiguous missing scale or emit scale ambiguity.

A newer full scan, disconnect, cancellation, or disposal invalidates the old selection session. Picker selection is accepted only for the current session's candidate set, preventing stale UI actions from completing superseded policy.

## Bengle precedence

**Maintainer direction:** Bengle always owns the scale slot through its integrated scale. External scale candidates discovered before machine selection are retained but ignored if the selected machine is Bengle. If an external scale is already attached when Bengle becomes the machine, the scale controller performs a handoff to the integrated scale; this is the sole occupied-scale exception. This is why machine policy must resolve before scale policy.

## Preferred-scale watch

**Maintainer direction:** Preferred-scale background reacquisition pauses while scale ambiguity is pending. It must not auto-connect the old preferred scale while the user is choosing. Successful explicit scale selection persists the new preferred ID. While that scale is connected no watch is needed; on a later disconnect, reacquisition targets the new preferred ID.

A queued scale-only recovery remains an automatic policy operation. When drained after another connection cycle it keeps preferred-scale early-connect behavior; it must not inherit explicit-scan settings merely because it was queued behind one.

## Scan report contract

The scan report represents the complete scan-and-connect selection session, not discovery alone. It is emitted when automatic connection work and any required picker continuation complete. If a newer scan supersedes a pending selection, the old session is finalized as cancelled. Connection attempts made after picker selection belong to the same report.

This contract avoids publishing an apparently final immutable report and then mutating hidden builder state with later machine or scale results.

## Retry semantics

**Maintainer direction:** Visible scan controls and explicit discovery actions use `scanAndConnect()`. Automatic recovery paths use `connect()`.

A generic connection-error retry is classified by intent:

- unexpected-disconnect recovery retries use `connect()`;
- failed explicit connection attempts and visible “scan again” controls use `scanAndConnect()`;
- adapter-off, permission-denied, and scan-start failures show remediation text rather than a retry button.

Machine connection failure must remain visible if scale policy continues. A phase transition caused by scale connection must not erase the explanation for the missing machine.

## REST and WebSocket compatibility

**Maintainer direction:** Wire shapes and defaults remain unchanged.

- REST `/api/v1/devices/scan` defaults `connect` to `true`.
- WebSocket `{"command":"scan"}` defaults `connect` to `true`.
- Explicit `connect=false` remains discovery-only.
- `quick=true` remains fire-and-forget at the transport interface; it does not re-enable remembered-machine quick-connect or in-scan early connection for an explicit scan.

Behavioral compatibility is intentionally not exact: blocking explicit scans now wait for complete discovery and may return later, occupied slots are preserved, and ambiguity/automatic selection follows the missing-slot policy above.

## Rejected alternatives

### Only guard remembered-machine quick-connect

Rejected by maintainer direction. It fixes the false DE1 re-adoption but does not define missing-scale auto-connect, complete alternative discovery, ordered ambiguity, or retained selection state.

### Make explicit scans discovery-only

Initially implemented, then explicitly reversed by the maintainer. `connect=true` remains the default and explicit scans fill missing slots automatically.

### Independent or simultaneous machine and scale ambiguity

Rejected by maintainer direction. It conflicts with Bengle integrated-scale precedence and complicates clients. Machine selection completes first, then scale policy runs.

### Automatically replace an occupied slot

Rejected by maintainer direction. A working machine or scale remains connected regardless of discovered alternatives or preference mismatch. Replacement requires explicit selection.
