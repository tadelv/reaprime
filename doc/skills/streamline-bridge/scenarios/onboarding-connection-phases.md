# Scenario: onboarding connection phases

Verifies that after `sb-dev start --connect-machine MockDe1 --connect-scale MockScale`, the app has walked through the onboarding connect flow and both devices are in the expected state. Also confirms the auto-connected IDs were persisted as preferences.

## Preconditions

```bash
scripts/sb-dev.sh start --connect-machine MockDe1 --connect-scale MockScale
BASE=http://localhost:8080
```

## Steps

### Machine is connected and reporting state

```bash
curl -sf "$BASE/api/v1/machine/state" | jq '{state}'
```

Expect a valid snapshot with a `state` field (e.g. `"idle"`). Any 500 here means `withDe1()` hasn't picked up the MockDe1 — scan is still pending or auto-connect failed. Re-run `sb-dev status`.

### Scale is connected

```bash
curl -sf "$BASE/api/v1/scale" | jq .
```

HTTP 200.

### Devices endpoint lists MockDe1

```bash
curl -sf "$BASE/api/v1/devices" \
  | jq -e '.[] | select(.name == "MockDe1" and .state == "connected")'
```

Exit 0 confirms MockDe1 appears and is connected.

### Preferred IDs were saved from auto-connect

```bash
curl -sf "$BASE/api/v1/settings" | jq '{preferredMachineId, preferredScaleId}'
```

Both fields should be non-null after onboarding has run to completion.

## Postconditions

```bash
scripts/sb-dev.sh stop
```
