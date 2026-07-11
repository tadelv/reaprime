# Scenario: Bengle load-cell calibration end-to-end

Verifies the two-point load-cell calibration wizard over REST: `GET /api/v1/machine/capabilities` lists `scaleCalibration` when a Bengle is connected, `POST /api/v1/machine/scale/calibrate` runs the `zero` → `left` → `right` procedure (each call is non-blocking on the device side and returns the terminal calibration result), `abort` is accepted with `202`, and malformed requests are rejected at `400` before reaching the device.

## Preconditions

```bash
scripts/sb-dev.sh start --connect-machine MockBengle
```

`MockBengle`'s calibration always succeeds instantly (no real load cells to settle). On real hardware each `zero`/`left`/`right` call blocks the HTTP request for the firmware run (~15 s settle+average, bounded by a 30 s deadline) — the wizard is still non-blocking on the machine: the app polls the packed `ScaleCalState` word and the shot surfaces stay live.

## Steps

### 1. Capability discovery lists `scaleCalibration`

```bash
curl -sf http://localhost:8080/api/v1/machine/capabilities \
  | jq -e '.capabilities | index("scaleCalibration") != null'
```

Exit 0 → the wizard endpoint is available on this machine.

### 2. Zero the empty platform

```bash
curl -sf -X POST http://localhost:8080/api/v1/machine/scale/calibrate \
  -H 'Content-Type: application/json' -d '{"command":"zero"}' | jq .
```

Expected:

```json
{ "success": true, "finalStep": "complete", "pointStatus": "none" }
```

On real hardware run this with NOTHING on the platform — the firmware rejects a later latch with `noZero` if the cells were never zeroed.

### 3. Latch point 1 — reference mass on the LEFT half

```bash
curl -sf -X POST http://localhost:8080/api/v1/machine/scale/calibrate \
  -H 'Content-Type: application/json' -d '{"command":"left","grams":500}' \
  | jq -e '.success == true and .pointStatus == "incomplete"'
```

Exit 0. `pointStatus: incomplete` means the point latched and the firmware is waiting for the sibling point — nothing is persisted yet. Use a whole-gram mass (the firmware reads the reference back at whole-gram resolution).

### 4. Latch point 2 — the SAME mass on the RIGHT half solves + persists

```bash
curl -sf -X POST http://localhost:8080/api/v1/machine/scale/calibrate \
  -H 'Content-Type: application/json' -d '{"command":"right","grams":500}' \
  | jq -e '.success == true and .pointStatus == "ok"'
```

Exit 0. `pointStatus: ok` = both points solved; the firmware persisted and applied the new per-cell calibration.

### 5. Abort is accepted with 202

```bash
curl -s -o /dev/null -w '%{http_code}\n' \
  -X POST http://localhost:8080/api/v1/machine/scale/calibrate \
  -H 'Content-Type: application/json' -d '{"command":"abort"}'
```

Expected: `202`.

### 6. Validation rejects bad requests at 400

```bash
# left without the required grams:
curl -s -o /dev/null -w '%{http_code}\n' \
  -X POST http://localhost:8080/api/v1/machine/scale/calibrate \
  -H 'Content-Type: application/json' -d '{"command":"left"}'
# unknown command:
curl -s -o /dev/null -w '%{http_code}\n' \
  -X POST http://localhost:8080/api/v1/machine/scale/calibrate \
  -H 'Content-Type: application/json' -d '{"command":"wiggle"}'
```

Expected: `400` twice.

## Postconditions

```bash
scripts/sb-dev.sh stop
```

## Notes

- **A calibration failure is still HTTP 200.** The HTTP layer reports transport success; the calibration outcome is data — clients branch on the body's `success`/`pointStatus`/`message` (a busy wizard returns `200 {"success": false, "message": "calibration already in progress"}`, not `409`).
- **`404` on a plain DE1.** Restart with `--connect-machine MockDe1` and any calibrate POST returns `404 {"error": "scale calibration not supported"}` — the capability probe in step 1 is how skins should decide whether to show the wizard.
- **Field firmware caveat.** Older single-point field firmware only latches `zero` (its step numbering differs; the app keys completion off the SubState so `zero` still terminates correctly); `left`/`right` need the two-point firmware.
