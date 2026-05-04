# Scenario: Bengle cup-warmer + capability discovery

Verifies the first Bengle peripheral surface end-to-end: `GET /api/v1/machine/capabilities` lists `cupWarmer` when a Bengle is connected, `GET /api/v1/machine/cupWarmer` returns the current setpoint, `POST /api/v1/machine/cupWarmer` writes a new setpoint, and out-of-range writes are rejected at 400 before reaching the device.

## Preconditions

```bash
scripts/sb-dev.sh start --connect-machine MockBengle --connect-scale MockScale
```

## Steps

### 1. Capability discovery

```bash
curl -sf http://localhost:8080/api/v1/machine/capabilities | jq -e '.capabilities | index("cupWarmer") != null'
```

Exit 0 → `cupWarmer` present in the capability list.

### 2. Read initial setpoint (off)

```bash
curl -sf http://localhost:8080/api/v1/machine/cupWarmer | jq -e '.temperature == 0'
```

MockBengle boots with `_cupWarmerTemp = 0.0`. Exit 0 → off.

### 3. Set a valid setpoint

```bash
curl -sf -X POST http://localhost:8080/api/v1/machine/cupWarmer \
  -H 'Content-Type: application/json' \
  -d '{"temperature": 60}' \
  -o /dev/null -w '%{http_code}\n'
```

Expected: `202`.

### 4. Confirm the new setpoint

```bash
curl -sf http://localhost:8080/api/v1/machine/cupWarmer | jq -e '.temperature == 60'
```

Exit 0 → MockBengle stored the value.

### 5. Reject out-of-range

```bash
curl -s -X POST http://localhost:8080/api/v1/machine/cupWarmer \
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
