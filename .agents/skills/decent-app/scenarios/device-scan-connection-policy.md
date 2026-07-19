# Scenario: device scan connection policy

Verifies that explicit REST and WebSocket scans preserve occupied machine and
scale slots, that omitted `connect` defaults to `true`, and that
`connect=false` remains discovery-only.

## Preconditions

```bash
scripts/sb-dev.sh start --connect-machine MockDe1 --connect-scale MockScale
BASE=http://localhost:8080
```

Wait for both simulated devices to report `connected`:

```bash
curl -sf "$BASE/api/v1/devices" | jq '[.[] | select(.state == "connected") | .id]'
```

Save the connected IDs:

```bash
BEFORE=$(curl -sf "$BASE/api/v1/devices" \
  | jq -c '[.[] | select(.state == "connected") | .id] | sort')
```

## REST default scan

```bash
curl -sf "$BASE/api/v1/devices/scan"
AFTER=$(curl -sf "$BASE/api/v1/devices" \
  | jq -c '[.[] | select(.state == "connected") | .id] | sort')
test "$AFTER" = "$BEFORE"
```

The request waits for a scan-first connection cycle. Both original IDs remain
connected and no replacement connection is attempted.

## REST discovery-only scan

```bash
curl -sf "$BASE/api/v1/devices/scan?connect=false"
AFTER=$(curl -sf "$BASE/api/v1/devices" \
  | jq -c '[.[] | select(.state == "connected") | .id] | sort')
test "$AFTER" = "$BEFORE"
```

The scan updates discovery results without changing either occupied slot.

## WebSocket default scan

```bash
printf '%s\n' '{"command":"scan","quick":false}' \
  | websocat -n1 "ws://localhost:8080/ws/v1/devices"
AFTER=$(curl -sf "$BASE/api/v1/devices" \
  | jq -c '[.[] | select(.state == "connected") | .id] | sort')
test "$AFTER" = "$BEFORE"
```

Omitting `connect` is equivalent to `connect=true`. `quick=false` waits for the
scan result; it does not change connection policy.

## WebSocket discovery-only scan

```bash
printf '%s\n' '{"command":"scan","connect":false,"quick":false}' \
  | websocat -n1 "ws://localhost:8080/ws/v1/devices"
AFTER=$(curl -sf "$BASE/api/v1/devices" \
  | jq -c '[.[] | select(.state == "connected") | .id] | sort')
test "$AFTER" = "$BEFORE"
```

## Postconditions

```bash
scripts/sb-dev.sh stop
```

## Real-hardware extension

Repeat the REST and WebSocket default scans with an attached DE1 and scale.
Confirm from the device LEDs, app status, and logs that neither BLE link drops
or reconnects. Ambiguous multi-device selection and Bengle integrated-scale
precedence require the corresponding physical devices and remain separate
hardware validation steps.
