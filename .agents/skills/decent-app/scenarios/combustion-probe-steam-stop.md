# Scenario: Combustion probe steam stop-at-temperature

End-to-end check of app-side steam stop-at-temperature driven by a
Combustion Predictive Thermometer (`MockCombustionProbe` in simulate
mode): probe appears in the sensor list, workflow `stopAtTemperature`
round-trips, entering steam records probe temperature, the machine
returns to `idle` when the reading crosses the target, and the persisted
steam record includes `milkTemperature` on late frames.

Mirrors the Bengle milk-probe E2E recipe in
`doc/plans/archive/bengle-milk-probe-and-steam-sequencer/` but uses the
BLE-discovered Combustion sensor path (`SensorController` source #1)
instead of the Bengle bridge adapter.

> **Simulate note:** `MockCombustionProbe` holds a steady ~20 °C (no
> auto-rise like `MockBengle`'s synthesised milk probe). Set
> `stopAtTemperature` to **19.0** so the default reading already meets
> the target and the stop path fires without a debug temperature hook.
> The 60 → 62 °C crossing is covered in-process by
> `test/integration/combustion_steam_stop_integration_test.dart`.

## Preconditions

```bash
scripts/sb-dev.sh start --connect-machine MockDe1
BASE=http://localhost:8080
```

`sb-dev start` injects `--dart-define=simulate=1`, which enables the
`sensor` simulate type and registers `MockCombustionProbe` alongside
`MockDe1`. No external scale is required for this scenario.

Confirm REST is up and the machine is connected:

```bash
scripts/sb-dev.sh status
curl -sf "$BASE/api/v1/machine/state" | jq '{state}'
```

Expect `state` such as `"idle"`. Re-run `sb-dev status` if the machine
is not connected yet.

## Steps

### 1. Combustion probe appears in the sensor list

After the boot scan completes, the simulated Combustion probe is
auto-registered by `SensorController` (no manual connect step):

```bash
curl -sf "$BASE/api/v1/sensors" | jq .
```

Expected: a non-empty array containing an entry with
`id: "MockCombustionProbe"` and `info.vendor: "Combustion Inc"`.

Quick assertion:

```bash
curl -sf "$BASE/api/v1/sensors" \
  | jq -e '.[] | select(.id == "MockCombustionProbe")'
```

Exit 0 confirms the probe is registered.

### 2. PUT workflow with stop-at-temperature target

Deep-merge steam settings. Use **19.0 °C** in simulate mode (see note
above); production skins typically use values such as 65.0 °C.

```bash
curl -sf -X PUT "$BASE/api/v1/workflow" \
  -H 'content-type: application/json' \
  -d '{"steamSettings":{"stopAtTemperature":19.0}}'

curl -sf "$BASE/api/v1/workflow" | jq '.steamSettings.stopAtTemperature'
```

Expected: `19` (or `19.0`).

### 3. Subscribe to probe temperature, then enter steam

In one shell, follow the Combustion probe snapshot stream:

```bash
websocat --no-async-stdio -n -U -t --max-messages-rev 5 \
  "ws://localhost:8080/ws/v1/sensors/MockCombustionProbe/snapshot" | jq -c .
```

Expected frames include `"temperature": 20` (virtual core; steady in
simulate mode).

In another shell (or after the websocat sample above), request steam and
watch the machine return to `idle` once the probe reading meets the
target:

```bash
websocat --no-async-stdio -n -U -t --max-messages-rev 15 \
  ws://localhost:8080/ws/v1/machine/snapshot | jq -c '.state' &
WS=$!

curl -sf -X PUT "$BASE/api/v1/machine/state/steam" >/dev/null

# Expect: state transitions to "steam", then back to "idle" within a few
# seconds — SteamSequencer requests idle when probe temp ≥ target.
wait $WS 2>/dev/null || true
```

Confirm via logs:

```bash
scripts/sb-dev.sh logs --filter SteamSequencer -n 20
```

Look for lines such as:

- `Steam record opened: <uuid>`
- `App-side stop: probe 20°C ≥ target 19°C`

### 4. Verify persisted steam record and milkTemperature

`GET /api/v1/steams/latest` returns metadata only (no measurements).
Fetch the full record by id:

```bash
STEAM_ID=$(curl -sf "$BASE/api/v1/steams/latest" | jq -r '.id')
curl -sf "$BASE/api/v1/steams/$STEAM_ID" | jq '{
  id,
  stopAtTemperature: .workflow.steamSettings.stopAtTemperature,
  framesWithMilkTemp: [.measurements[] | select(.milkTemperature != null) | .milkTemperature]
}'
```

Expected:

- `stopAtTemperature` is `19` (or `19.0`) on the embedded workflow.
- `framesWithMilkTemp` is a non-empty array; the last value is near
  **20** (the simulate probe's default reading).

Single-field check:

```bash
curl -sf "$BASE/api/v1/steams/$STEAM_ID" \
  | jq '[.measurements[] | select(.milkTemperature != null)] | last.milkTemperature'
```

Expected: a number close to `20`.

## Postconditions

```bash
scripts/sb-dev.sh stop
```

> **Deterministic coverage:** The temperature-crossing and
> `probeLost` mid-steam paths are exercised without a running app in
> `test/integration/combustion_steam_stop_integration_test.dart` and
> `test/controllers/steam_sequencer_test.dart`. This recipe validates the
> REST/WebSocket surface agents and skin developers call in simulate mode.
