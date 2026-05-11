# Bengle LED strip v2

Exercises the full LED strip v2 API on a `MockBengle`: PUT configuration, verify response, commit, reset.

## Preconditions

- A running Decent instance with `simulate=1,scale` (MockBengle auto-discovered)
- `curl` and `jq` available

## Procedure

### 1. Verify capability

```bash
curl -s http://localhost:8080/api/v1/machine/capabilities | jq
```

Expect `ledStrip` in the `capabilities` array.

### 2. Read initial (all-off)

```bash
curl -s http://localhost:8080/api/v1/machine/ledStrip | jq
```

Expect all zones sleeping/awake → `"000000000000"`.

### 3. Write a config

```bash
curl -s -X PUT http://localhost:8080/api/v1/machine/ledStrip \
  -H 'Content-Type: application/json' \
  -d '{
    "frontStrip": {"sleeping": "0000FFFF0000", "awake": "FFFF80000000"},
    "backStrip":  {"sleeping": "000000000000", "awake": "FFFFFFFFFFFF"},
    "frontSwitch":{"sleeping": "FFFF00000000", "awake": "000000000000"}
  }' | jq
```

Expect `{"status": "accepted"}` (status 200).

### 4. Read back

```bash
curl -s http://localhost:8080/api/v1/machine/ledStrip | jq
```

Expect the same values just written.

### 5. Commit

```bash
curl -s -X POST http://localhost:8080/api/v1/machine/ledStrip/commit \
  -H 'Content-Type: application/json' \
  -d '{}'
```

Expect 202.

### 6. Overwrite cache without committing

```bash
curl -s -X PUT http://localhost:8080/api/v1/machine/ledStrip \
  -H 'Content-Type: application/json' \
  -d '{"frontStrip":{"sleeping":"000000000000","awake":"000000000000"},
       "backStrip":{"sleeping":"000000000000","awake":"000000000000"},
       "frontSwitch":{"sleeping":"000000000000","awake":"000000000000"}}'
```

### 7. Reset — should restore committed values

```bash
curl -s -X POST http://localhost:8080/api/v1/machine/ledStrip/reset \
  -H 'Content-Type: application/json' \
  -d '{}' | jq
```

Expect the config from step 3 (`frontStrip.sleeping: 0000FFFF0000`, etc.), not the all-off from step 6.

### 8. Plain DE1 returns 404

If you connect a plain DE1 or MockDe1 (no `simulate=1`), all four endpoints return 404:

```bash
curl -s http://localhost:8080/api/v1/machine/ledStrip | jq
curl -s -X PUT http://localhost:8080/api/v1/machine/ledStrip -H 'Content-Type: application/json' -d '{}' | jq
curl -s -X POST http://localhost:8080/api/v1/machine/ledStrip/commit -H 'Content-Type: application/json' -d '{}' | jq
curl -s -X POST http://localhost:8080/api/v1/machine/ledStrip/reset -H 'Content-Type: application/json' -d '{}' | jq
```

All four return `{"error": "ledStrip not supported"}` with status 404.
