# Scenario: display brightness 0-100

End-to-end check of the display brightness surface: REST get/put, WebSocket `setBrightness` command, validation, and low-battery toggle.

Covers the shapes that replaced the old `dim` / `restore` endpoints — those are asserted absent.

## Preconditions

```bash
scripts/sb-dev.sh start --connect-machine MockDe1 --connect-scale MockScale
BASE=http://localhost:8080
```

## Initial state

```bash
curl -sf "$BASE/api/v1/display" | jq .
```

Expect `brightness: 100`, `requestedBrightness: 100`, `lowBatteryBrightnessActive: false`.

## REST brightness writes

```bash
curl -sf -X PUT "$BASE/api/v1/display/brightness" \
  -H 'content-type: application/json' \
  -d '{"brightness": 50}' | jq '{brightness, requestedBrightness}'
# {"brightness": 50, "requestedBrightness": 50}

curl -sf -X PUT "$BASE/api/v1/display/brightness" \
  -H 'content-type: application/json' \
  -d '{"brightness": 0}' | jq .brightness   # 0

curl -sf -X PUT "$BASE/api/v1/display/brightness" \
  -H 'content-type: application/json' \
  -d '{"brightness": 100}' | jq .brightness # 100 — OS-managed restore
```

## Validation (all three expected 400)

```bash
for payload in '{"brightness": 150}' '{"brightness": -10}' '{"brightness": "high"}'; do
  curl -s -o /tmp/sb-err -w '%{http_code}\n' -X PUT "$BASE/api/v1/display/brightness" \
    -H 'content-type: application/json' -d "$payload"
  cat /tmp/sb-err; echo
done
```

Each iteration should print `400` followed by `{"error":"brightness must be an integer 0-100"}`.

## Old endpoints removed

```bash
curl -s -o /dev/null -w '%{http_code}\n' -X POST "$BASE/api/v1/display/dim"     # 404
curl -s -o /dev/null -w '%{http_code}\n' -X POST "$BASE/api/v1/display/restore" # 404
```

## WebSocket setBrightness

Open the display channel and drive it with `command: setBrightness`:

```bash
websocat --no-async-stdio -n -t --max-messages-rev 2 \
  ws://localhost:8080/ws/v1/display <<'EOF' | jq '{brightness, requestedBrightness}'
{"command":"setBrightness","brightness":30}
{"command":"setBrightness","brightness":100}
EOF
```

Expect two snapshots: first with `brightness: 30`, second with `brightness: 100`. The legacy `{"command":"dim"}` message is silently ignored — there is no "old dim" round-trip to assert.

## lowBatteryBrightnessLimit setting toggle

```bash
curl -sf -X POST "$BASE/api/v1/settings" \
  -H 'content-type: application/json' \
  -d '{"lowBatteryBrightnessLimit": true}' | jq .lowBatteryBrightnessLimit
# true

curl -sf -X POST "$BASE/api/v1/settings" \
  -H 'content-type: application/json' \
  -d '{"lowBatteryBrightnessLimit": false}' | jq .lowBatteryBrightnessLimit
# false
```

## Postconditions

```bash
scripts/sb-dev.sh stop
```
