# Scenario: Bengle integrated scale end-to-end

Verifies that when a Bengle is the connected machine, the integrated scale is auto-attached as a virtual scale (no external scale connection needed), capability discovery advertises `integratedScale`, the `/api/v1/scale/*` REST surface and `/ws/v1/scale/snapshot` stream both flow through the integrated scale, and software stop-at-weight (SAW) ends an espresso shot when the integrated scale weight crosses the profile target.

## Preconditions

```bash
scripts/sb-dev.sh start --connect-machine MockBengle
```

No `--connect-scale` flag. On Bengle the integrated scale always wins — external scale scanning is skipped, and `preferredScaleId` is ignored. See `doc/DeviceManagement.md` → "Bengle integrated scale".

## Steps

### 1. Capability discovery lists both Bengle surfaces

```bash
curl -sf http://localhost:8080/api/v1/machine/capabilities | jq .
```

Expected:

```json
{ "capabilities": ["cupWarmer", "integratedScale"] }
```

Quick assertions:

```bash
curl -sf http://localhost:8080/api/v1/machine/capabilities \
  | jq -e '.capabilities | index("integratedScale") != null and index("cupWarmer") != null'
```

Exit 0 → both identifiers present.

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

### 4. Run a shot — software SAW stops at the profile target weight

Upload the bundled flow profile (target weight = 42 g):

```bash
curl -sf -X POST http://localhost:8080/api/v1/machine/profile \
  -H 'Content-Type: application/json' \
  --data @assets/defaultProfiles/Flow_profile_for_straight_espresso.json
```

Tare, then start the espresso shot:

```bash
curl -s -X PUT http://localhost:8080/api/v1/scale/tare
curl -sX PUT http://localhost:8080/api/v1/machine/state/espresso
```

Watch the machine snapshot stream — `MockDe1` simulates flow, `MockBengle` integrates flow into weight, `ShotController` projects `weight + flow * multiplier` against `targetYield` (42 g for this profile) and drives the machine to `idle` once the projection crosses the target:

```bash
websocat --no-async-stdio -n -U -t --max-messages-rev 200 \
  ws://localhost:8080/ws/v1/machine/snapshot | jq -c '{state, substate}'
```

Expected sequence ends with `state == "idle"` once the integrated scale crosses ~42 g (projection causes the cutoff slightly before the literal reading). Logs show:

```bash
sb-dev logs -n 60 --filter "ShotController\|target weight"
```

Expected log line: `Target weight 42.0g reached (projected: ...). Stopping shot.`

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
- **Target weight is profile-driven**, not a global default. The bundled `Flow_profile_for_straight_espresso.json` ships with `target_weight: 42.0`. Workflow target weight (when set via `/api/v1/workflow`) overrides per-run; this scenario relies on the profile value alone for simplicity.
- **Stop is software SAW**, identical to the external-scale path — `ShotController` makes the stop decision; the integrated scale just sources weight via `BengleVirtualScale` instead of a BLE scale.
