# Scenario: Bengle integrated scale end-to-end

Verifies that when a Bengle is the connected machine, the integrated scale is auto-attached as a virtual scale (no external scale connection needed), capability discovery advertises `integratedScale` and `stopAtWeight`, the `/api/v1/scale/*` REST surface and `/ws/v1/scale/snapshot` stream both flow through the integrated scale, and **autonomous** stop-at-weight (SAW) ends an espresso shot: the app reflects the workflow's `targetYield` into the machine's SAW target and defers the final yield stop to the machine (`machineHasAutonomousSAW`), which `MockBengle` simulates firmware-side.

## Preconditions

```bash
scripts/sb-dev.sh start --connect-machine MockBengle
```

No `--connect-scale` flag. On Bengle the integrated scale always wins — external scale scanning is skipped, and `preferredScaleId` is ignored. See `doc/DeviceManagement.md` → "Bengle integrated scale".

## Steps

### 1. Capability discovery lists the Bengle surfaces

```bash
curl -sf http://localhost:8080/api/v1/machine/capabilities | jq .
```

Expected:

```json
{ "capabilities": ["cupWarmer", "integratedScale", "ledStrip", "stopAtWeight"] }
```

Quick assertions:

```bash
curl -sf http://localhost:8080/api/v1/machine/capabilities \
  | jq -e '.capabilities | index("integratedScale") != null and index("stopAtWeight") != null'
```

Exit 0 → both identifiers present. `stopAtWeight` advertises that the machine firmware runs its own stop-at-weight from the integrated scale — there is no dedicated SAW endpoint; the target rides `PUT /api/v1/workflow` (`context.targetYield`).

### 2. Scale snapshot stream is alive without an external scale

```bash
websocat --no-async-stdio -n -U -t --max-messages-rev 5 \
  ws://localhost:8080/ws/v1/scale/snapshot | jq -c .
```

Expected: snapshot frames with `weight`, `weightFlow`, etc. — the virtual `BengleVirtualScale` is feeding `ScaleController`. No `{"status":"disconnected"}` frames.

### 3. Tare zeroes the integrated scale

```bash
curl -s -X PUT http://localhost:8080/api/v1/scale/tare
```

Expected: `200 OK`, empty body.

Re-sample the snapshot and confirm weight is ~0 (MockBengle resets `_tareOffset` to the current accumulated weight, so the next emission reads near zero):

```bash
websocat --no-async-stdio -n -U -t --max-messages-rev 1 \
  ws://localhost:8080/ws/v1/scale/snapshot | jq '.weight'
```

Expected: a value within ~±0.1 g of zero.

### 4. Run a shot — the machine's autonomous SAW stops at the workflow target yield

Set the workflow target yield (the single source of truth for SAW — `BengleSawBridge` reflects it into the machine's `EndOfShotWeight` target after a short debounce):

```bash
curl -sf -X PUT http://localhost:8080/api/v1/workflow \
  -H 'Content-Type: application/json' \
  -d '{"context": {"targetYield": 42.0}}' | jq .
```

Tare, then start the espresso shot:

```bash
curl -s -X PUT http://localhost:8080/api/v1/scale/tare
curl -sX PUT http://localhost:8080/api/v1/machine/state/espresso
```

Watch the machine snapshot stream — `MockDe1` simulates flow, `MockBengle` integrates flow into weight and (simulating the Bengle firmware's autonomous SAW) requests `idle` itself once the integrated-scale weight crosses the 42 g target. The app's `ShotSequencer` deliberately does **not** issue its own final-yield stop on a Bengle (`machineHasAutonomousSAW` — no double stop); it observes the machine-side stop and reports it as `machineEnded`:

```bash
websocat --no-async-stdio -n -U -t --max-messages-rev 200 \
  ws://localhost:8080/ws/v1/machine/snapshot | jq -c '{state, substate}'
```

Expected sequence ends with `state == "idle"` once the integrated scale crosses ~42 g.

Confirm the app deferred to the machine — the shotState feed advertises the autonomous SAW (the idle re-seed frame carries the flag between shots too), and the persisted shot records the machine-side stop:

```bash
websocat --no-async-stdio -n -U -t --max-messages-rev 1 \
  ws://localhost:8080/ws/v1/machine/shotState | jq -e '.machineHasAutonomousSAW == true'
curl -sf http://localhost:8080/api/v1/shots/latest | jq -e '.stopReason == "machineEnded"'
```

Both exit 0.

### 5. No external scale connection ever happened

```bash
curl -sf http://localhost:8080/api/v1/devices | jq '.[] | select(.type=="scale") | {name, state}'
```

Expected: empty (no external scale was scanned for or connected). The integrated scale exposes itself via `/api/v1/scale/*` and `/ws/v1/scale/snapshot` without appearing as a discoverable device.

## Postconditions

```bash
scripts/sb-dev.sh stop
```

## Notes

- **Why no `--connect-scale`?** On Bengle, `ConnectionManager` skips the external-scale phase entirely (see `doc/DeviceManagement.md`). Passing `--connect-scale MockScale` will be ignored / overridden by the integrated-scale auto-attach.
- **Target yield is workflow-driven.** `WorkflowContext.targetYield` is the single source of truth for the SAW target; there is deliberately no `POST /machine/saw`-style endpoint. The default workflow ships with `targetYield: 36.0`, so the bridge arms 36 g on connect even before step 4 sets 42 g.
- **The stop is autonomous (firmware-side on real hardware).** The app's `ShotSequencer` bypasses only the FINAL target-yield stop on `BengleInterface` machines; per-step weight exits still run app-side. On real hardware the target lands in the `EndOfShotWeight` MMR (`0x00803864`, ×100) and the Bengle firmware ends the shot itself; `MockBengle` simulates that firmware behavior in-process.
