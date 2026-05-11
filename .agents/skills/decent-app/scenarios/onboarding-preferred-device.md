# Scenario: preferred device fast-path

Verifies `/api/v1/settings` round-trips `preferredMachineId` / `preferredScaleId` correctly and that `null` clears them. This is the fast-path the onboarding flow uses to skip device selection on subsequent boots.

## Preconditions

```bash
scripts/sb-dev.sh start --connect-machine MockDe1 --connect-scale MockScale
BASE=http://localhost:8080
```

## Auto-connect populated the preferences

```bash
curl -sf "$BASE/api/v1/settings" | jq '{preferredMachineId, preferredScaleId}'
```

Expect:

```json
{"preferredMachineId": "MockDe1", "preferredScaleId": "MockScale"}
```

Both fields round-trip the dart-define identifiers (no space), not the REST-visible `name` values (`Mock Scale` with a space). See `simulated-devices.md` for the naming split.

## Overwrite with fake IDs

```bash
curl -sf -X POST "$BASE/api/v1/settings" \
  -H 'content-type: application/json' \
  -d '{"preferredMachineId": "DE1-FAKE-12345"}' \
  | jq .preferredMachineId   # "DE1-FAKE-12345"

curl -sf -X POST "$BASE/api/v1/settings" \
  -H 'content-type: application/json' \
  -d '{"preferredScaleId": "SCALE-FAKE-99999"}' \
  | jq .preferredScaleId    # "SCALE-FAKE-99999"
```

Confirm both persisted:

```bash
curl -sf "$BASE/api/v1/settings" | jq '{preferredMachineId, preferredScaleId}'
```

## Clear with null

```bash
curl -sf -X POST "$BASE/api/v1/settings" \
  -H 'content-type: application/json' \
  -d '{"preferredMachineId": null}' \
  | jq .preferredMachineId   # null

curl -sf -X POST "$BASE/api/v1/settings" \
  -H 'content-type: application/json' \
  -d '{"preferredScaleId": null}' \
  | jq .preferredScaleId    # null
```

Verify:

```bash
curl -sf "$BASE/api/v1/settings" | jq '{preferredMachineId, preferredScaleId}'
# {"preferredMachineId": null, "preferredScaleId": null}
```

## Postconditions

```bash
scripts/sb-dev.sh stop
```
