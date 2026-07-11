# Scenario: Bengle cup-warmer + capability discovery

Verifies the first Bengle peripheral surface end-to-end: `GET /api/v1/machine/capabilities` lists `cupWarmer` when a Bengle is connected, `GET /api/v1/machine/cupWarmer` returns the current setpoint plus the live mat temperature (`currentTemperature`, `null` when the firmware has no valid reading), `PUT /api/v1/machine/cupWarmer` writes a new setpoint, and out-of-range writes are rejected at 400 before reaching the device.

## Preconditions

```bash
scripts/sb-dev.sh start --connect-machine MockBengle
```

(No `--connect-scale`: on Bengle the integrated scale always wins and `preferredScaleId` is ignored.)

## Steps

### 1. Capability discovery

```bash
curl -sf http://localhost:8080/api/v1/machine/capabilities | jq -e '.capabilities | index("cupWarmer") != null'
```

Exit 0 → `cupWarmer` present in the capability list.

### 2. Read initial setpoint (off) + live mat temperature placeholder

```bash
curl -sf http://localhost:8080/api/v1/machine/cupWarmer | jq -e '.temperature == 0 and .currentTemperature == null'
```

MockBengle boots with `_cupWarmerTemp = 0.0` and no simulated mat reading — `currentTemperature` is `null` (the "no valid reading" placeholder case; field firmware without the MatCurrentTemp register behaves the same). Exit 0 → off + placeholder.

### 3. Set a valid setpoint

```bash
curl -sf -X PUT http://localhost:8080/api/v1/machine/cupWarmer \
  -H 'Content-Type: application/json' \
  -d '{"temperature": 60}' \
  -o /dev/null -w '%{http_code}\n'
```

Expected: `200`. (Also enables the warmer — a target `> 0` = on; the FW enable register is app-managed.)

### 4. Confirm the new setpoint

```bash
curl -sf http://localhost:8080/api/v1/machine/cupWarmer | jq -e '.temperature == 60'
```

Exit 0 → MockBengle stored the value.

### 5. Reject out-of-range

```bash
curl -s -X PUT http://localhost:8080/api/v1/machine/cupWarmer \
  -H 'Content-Type: application/json' \
  -d '{"temperature": 100}' \
  -o /dev/null -w '%{http_code}\n'
```

Expected: `400`. App enforces 0.0–80.0 °C before hitting the wire.

### 6. Capability discovery returns empty list when DE1 is connected

Restart the app with a plain MockDe1 to verify the capability list reflects the connected machine, not the build:

```bash
scripts/sb-dev.sh stop
scripts/sb-dev.sh start --connect-machine MockDe1 --connect-scale MockScale
curl -sf http://localhost:8080/api/v1/machine/capabilities | jq -e '.capabilities == []'
curl -s http://localhost:8080/api/v1/machine/cupWarmer -o /dev/null -w '%{http_code}\n'
```

Expected: empty `capabilities`, and the cupWarmer GET returns `404`.

## Postconditions

```bash
scripts/sb-dev.sh stop
```
