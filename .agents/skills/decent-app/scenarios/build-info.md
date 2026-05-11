# Scenario: build info endpoint

Verifies `GET /api/v1/info` returns the compile-time build metadata the plugin runtime and UI rely on.

## Preconditions

```bash
scripts/sb-dev.sh start --connect-machine MockDe1 --connect-scale MockScale
```

## Steps

```bash
curl -sf http://localhost:8080/api/v1/info | jq .
```

Expected keys (all strings except `appStore`, which is bool):

- `commit`
- `commitShort`
- `branch`
- `buildTime`
- `version`
- `buildNumber`
- `appStore`
- `fullVersion`

One-shot assertion:

```bash
curl -sf http://localhost:8080/api/v1/info \
  | jq -e 'has("commit") and has("commitShort") and has("branch")
           and has("buildTime") and has("version") and has("buildNumber")
           and has("appStore") and has("fullVersion")'
```

Exit 0 → all fields present. Non-zero → missing a field; inspect the raw response.

## Postconditions

```bash
scripts/sb-dev.sh stop
```
