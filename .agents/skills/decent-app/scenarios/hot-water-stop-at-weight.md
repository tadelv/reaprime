# Scenario: hot water stop-at-weight

End-to-end check of native hot-water stop-at-weight: the `stopHotWaterAtWeight`
REST setting, plus the behaviour — taring the scale and stopping the dispense
once the scale reaches the configured hot-water volume target (treated as grams).

When a scale is connected and `stopHotWaterAtWeight` is on (default), entering
`hotWater` tares the scale, then the dispense is stopped (machine → `idle`) once
the projected weight reaches the target. The machine's own volume/time stop
stays as a backstop and is not modified.

## Preconditions

```bash
scripts/sb-dev.sh start --connect-machine MockDe1 --connect-scale MockScale
BASE=http://localhost:8080
```

## Setting surface (REST)

```bash
# Default is true.
curl -sf "$BASE/api/v1/settings" | jq .stopHotWaterAtWeight   # true

# Toggle off and back on; the response echoes the new value.
curl -sf -X POST "$BASE/api/v1/settings" \
  -H 'content-type: application/json' \
  -d '{"stopHotWaterAtWeight": false}' >/dev/null
curl -sf "$BASE/api/v1/settings" | jq .stopHotWaterAtWeight    # false

curl -sf -X POST "$BASE/api/v1/settings" \
  -H 'content-type: application/json' \
  -d '{"stopHotWaterAtWeight": true}' >/dev/null
curl -sf "$BASE/api/v1/settings" | jq .stopHotWaterAtWeight    # true
```

Bad type is rejected:

```bash
curl -s -o /tmp/sb-err -w '%{http_code}\n' -X POST "$BASE/api/v1/settings" \
  -H 'content-type: application/json' -d '{"stopHotWaterAtWeight": "yes"}'
cat /tmp/sb-err; echo   # 400 {"message":"stopHotWaterAtWeight must be a boolean"}
```

## Stop-at-weight behaviour

Set a small hot-water volume target (treated as the gram target) so the
simulated scale reaches it quickly:

```bash
# targetHotWaterVolume is part of shot settings; read the current ones,
# then write back with a small volume. (MockDe1 defaults to 100.)
curl -sf "$BASE/api/v1/machine/shotSettings" 2>/dev/null || true
curl -sf -X POST "$BASE/api/v1/machine/shotSettings" \
  -H 'content-type: application/json' \
  -d '{"steamSetting":0,"targetSteamTemp":150,"targetSteamDuration":30,"targetHotWaterTemp":85,"targetHotWaterVolume":5,"targetHotWaterDuration":30,"targetShotVolume":0,"groupTemp":90}' >/dev/null
```

Start hot water (as a group-head controller / skin would) and watch the state
channel return to `idle` once the scale passes the target:

```bash
# In one shell, follow machine state:
websocat -n -t ws://localhost:8080/ws/v1/machine/snapshot &
WS=$!

# Trigger the dispense:
curl -sf -X PUT "$BASE/api/v1/machine/state/hotWater" >/dev/null

# Expect: state transitions to "hotWater", the scale is tared (weight ~0),
# then within a couple of seconds the state returns to "idle" — the app
# requested the stop at the target weight. Look for a log line:
#   HotWaterSequencer - Arming hot water stop-at-weight: target 5 g
#   HotWaterSequencer - Hot water target 5 g reached ... stopping
kill $WS 2>/dev/null
```

Confirm via logs:

```bash
scripts/sb-dev.sh logs --filter HotWaterSequencer -n 20
```

With `stopHotWaterAtWeight` set to `false`, repeating the dispense leaves the
stop to the machine's native volume/time target — no `HotWaterSequencer`
arming line appears.

## Postconditions

```bash
scripts/sb-dev.sh stop
```

> Note: the macOS desktop build does not stay resident in headless/CI sessions,
> so this recipe is intended for the Android tablet or Linux builds. The same
> flow is covered deterministically in-process by
> `test/integration/hot_water_sequencer_integration_test.dart` and
> `test/controllers/hot_water_sequencer_test.dart`.
