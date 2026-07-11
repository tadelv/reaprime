# Scenario: Bengle LED strip + live preview

Verifies the LED strip surface end-to-end: `GET /api/v1/machine/capabilities` lists `ledStrip` when a Bengle is connected, `GET`/`PUT /api/v1/machine/ledStrip` round-trip the 3-zone × 2-mode configuration, `POST .../commit` re-asserts it (202), `POST .../reset` re-hydrates the cache and returns the refreshed state, and the live-preview pair `POST .../preview` / `POST .../preview/clear` is accepted (202) without touching the stored configuration.

## Preconditions

```bash
scripts/sb-dev.sh start --connect-machine MockBengle
```

`MockBengle` has no physical strips: `preview`/`preview/clear` are accepted but visually no-ops, and its `commit`/`reset` model an NVM snapshot (commit stores, reset restores). On real hardware every palette `PUT` already persists (the firmware registers are disk-backed) and `reset` re-reads whatever was last written — see the notes.

## Steps

### 1. Capability discovery lists `ledStrip`

```bash
curl -sf http://localhost:8080/api/v1/machine/capabilities \
  | jq -e '.capabilities | index("ledStrip") != null'
```

Exit 0 → the LED endpoints are available on this machine.

### 2. Read initial configuration (all-off)

```bash
curl -sf http://localhost:8080/api/v1/machine/ledStrip \
  | jq -e '.frontStrip.awake == "000000000000" and .backStrip.awake == "000000000000"'
```

On real hardware the cache is hydrated from the machine's four stored palette registers on connect, so this GET returns whatever the machine has stored (all-off only as a fallback when that read fails, until the first `PUT` or `/reset`). `MockBengle` has no firmware to read — its cache starts all-off, which is what this step asserts.

### 3. Write a configuration

```bash
curl -sf -X PUT http://localhost:8080/api/v1/machine/ledStrip \
  -H 'Content-Type: application/json' \
  -d '{
    "frontStrip": {"sleeping": "0000FFFF0000", "awake": "FFFF80000000"},
    "backStrip":  {"sleeping": "000000000000", "awake": "FFFFFFFFFFFF"},
    "frontSwitch":{"sleeping": "FFFF00000000", "awake": "000000000000"}
  }' | jq -e '.status == "accepted"'
```

Status 200. (`frontSwitch` is accepted for API symmetry but has no register — the physical switch light mirrors the front strip in firmware.)

### 4. Read back

```bash
curl -sf http://localhost:8080/api/v1/machine/ledStrip \
  | jq -e '.frontStrip.awake == "FFFF80000000" and .backStrip.awake == "FFFFFFFFFFFF"'
```

### 5. Commit

```bash
curl -s -o /dev/null -w '%{http_code}\n' \
  -X POST http://localhost:8080/api/v1/machine/ledStrip/commit
```

Expected: `202`. On real hardware this re-asserts the cached palette (palette writes already persist); on `MockBengle` it snapshots the cache for `reset`.

### 6. Overwrite, then reset restores the committed config

```bash
curl -sf -X PUT http://localhost:8080/api/v1/machine/ledStrip \
  -H 'Content-Type: application/json' \
  -d '{"frontStrip":{"sleeping":"000000000000","awake":"000000000000"},
       "backStrip":{"sleeping":"000000000000","awake":"000000000000"},
       "frontSwitch":{"sleeping":"000000000000","awake":"000000000000"}}' > /dev/null

curl -sf -X POST http://localhost:8080/api/v1/machine/ledStrip/reset \
  | jq -e '.frontStrip.sleeping == "0000FFFF0000"'
```

Status 200 with the step-3 configuration — the mock restores its committed snapshot. (Real hardware: reset re-reads the firmware palette, which holds whatever was last written.)

### 7. Live preview (does not touch the stored config)

```bash
curl -s -o /dev/null -w '%{http_code}\n' \
  -X POST http://localhost:8080/api/v1/machine/ledStrip/preview \
  -H 'Content-Type: application/json' \
  -d '{"front": "FFFF00000000", "back": "00000000FFFF"}'

curl -sf http://localhost:8080/api/v1/machine/ledStrip \
  | jq -e '.frontStrip.sleeping == "0000FFFF0000"'
```

Expected: `202`, and the stored configuration is unchanged (preview writes only the live colour registers). On real hardware the strips show red/blue immediately, regardless of awake/sleep state; `MockBengle` has no strips so only the status code is observable.

### 8. Clear the preview

```bash
curl -s -o /dev/null -w '%{http_code}\n' \
  -X POST http://localhost:8080/api/v1/machine/ledStrip/preview/clear
```

Expected: `202`. Real hardware: the strips return to the cached awake palette.

### 9. Preview validation

```bash
# Empty object: missing keys preview as black (Color16 defensive default):
curl -s -o /dev/null -w '%{http_code}\n' \
  -X POST http://localhost:8080/api/v1/machine/ledStrip/preview \
  -H 'Content-Type: application/json' -d '{}'
# Non-object body is rejected:
curl -s -o /dev/null -w '%{http_code}\n' \
  -X POST http://localhost:8080/api/v1/machine/ledStrip/preview \
  -H 'Content-Type: application/json' -d '[1,2,3]'
```

Expected: `202` then `400`.

## Postconditions

```bash
scripts/sb-dev.sh stop
```

## Notes

- **`404` on a plain DE1.** Restart with `--connect-machine MockDe1` and all six endpoints (`GET`/`PUT /ledStrip`, `commit`, `reset`, `preview`, `preview/clear`) return `404 {"error": "ledStrip not supported"}` — the capability probe in step 1 is how skins should decide whether to show the Lighting page.
- **A preview never survives a sleep/wake edge.** The firmware copies the active stored palette into the live registers on every state transition, clobbering any preview.
- **Clearing a preview restores the cached awake palette.** `preview/clear` restores from the app-side cache, which on real hardware is hydrated from the machine's stored palette on connect — the strips return to the machine's real awake colours. Only when that connect-time hydration failed (and before any `PUT`/`reset`) is the cache still all-off, in which case clearing a preview writes black.
- **Colours are 16-bit per channel in JSON, 8-bit on the wire.** The firmware takes each channel's high byte (`0x00RRGGBB`) and read-back byte-replicates (`0xAB → 0xABAB`), so 8-bit sources round-trip losslessly.
