# Scenario: shot state WebSocket + persisted stop reason

End-to-end check of `/ws/v1/machine/shotState` — the shot sequencer's state +
decision feed (why a step advanced, why the shot stopped) — and of the
`stopReason` field persisted onto the resulting shot record.

Requires gateway mode `tracking` or `disabled` (the sequencer only runs
app-side SAW then). The feed itself is available regardless — it just stays
`idle` when nothing is sequenced.

## Preconditions

```bash
scripts/sb-dev.sh start --connect-machine MockDe1 --connect-scale MockScale
BASE=http://localhost:8080
WS=ws://localhost:8080
```

## Feed idles and replays on connect

```bash
# First frame arrives immediately (BehaviorSubject replay): an idle state frame.
websocat -n1 "$WS/ws/v1/machine/shotState" | jq '{event, state, shotId}'
# {"event":"state","state":"idle","shotId":null}
```

## A full shot produces state frames, decisions, and a stop reason

Open the stream in the background, pull a simulated shot, stop it via the API:

```bash
websocat "$WS/ws/v1/machine/shotState" > /tmp/shotstate.jsonl &
WS_PID=$!

curl -sf -X PUT "$BASE/api/v1/machine/state/espresso" >/dev/null
sleep 6   # let the mock shot preheat and start pouring

# Stop via REST — this stop must be attributed to apiStop, not machineEnded.
curl -sf -X PUT "$BASE/api/v1/machine/state/idle" >/dev/null
sleep 6   # post-stop settling window + finalization

kill $WS_PID
jq -c '{event, state, reason: .decision.reason}' /tmp/shotstate.jsonl
```

Expected output hints (exact frames vary with the mock's pacing):

- `{"event":"state","state":"preheating",...}` then `"pouring"` — shot phases.
- Possibly `{"event":"decision",...,"reason":"profileAdvance"}` /
  `"profileSkip"` — step transitions during the pour.
- `{"event":"decision","state":"pouring","reason":"apiStop"}` — the REST stop,
  attributed to its source.
- `{"event":"state","state":"finished",...}` then a final
  `{"event":"state","state":"idle","shotId":null}` re-seed.
- Every mid-shot frame carries the same non-null `shotId`.

## The stop reason is persisted onto the shot record

```bash
# The latest shot's id matches the shotId seen on the stream, and stopReason
# records why it ended.
curl -sf "$BASE/api/v1/shots/latest" | jq '{id, stopReason}'
# {"id":"<same as the stream's shotId>","stopReason":"apiStop"}
```

Letting the shot run to the mock profile's natural end (no API stop) persists
`"machineEnded"` instead; an app-side stop-at-weight ends it with
`"targetWeight"`.

## Postconditions

```bash
scripts/sb-dev.sh stop
```
