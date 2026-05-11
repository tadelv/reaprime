# Debug scale control (simulate mode)

Exercise the debug endpoints that control MockScale behavior.
Requires simulate mode (`sb-dev start` uses `--dart-define=simulate=1`).

## Preconditions

- `sb-dev start` running
- MockScale connected (may need manual connect first):
  ```bash
  curl -s -X PUT 'localhost:8080/api/v1/devices/connect?deviceId=Mock%20Scale'
  ```

## Steps

### 1. Verify scale data flowing

```bash
# Weight stream should return data
curl -s -X PUT localhost:8080/api/v1/scale/tare
# Expected: null (200 OK)
```

### 2. Stall weight emission

```bash
curl -s -X POST localhost:8080/api/v1/debug/scale/stall | jq .
# Expected: {"status":"stalled"}
```

Scale stays "connected" but stops emitting weight snapshots.

### 3. Resume weight emission

```bash
curl -s -X POST localhost:8080/api/v1/debug/scale/resume | jq .
# Expected: {"status":"resumed"}
```

Weight data should flow again. Verify with tare:
```bash
curl -s -X PUT localhost:8080/api/v1/scale/tare
# Expected: null (200 OK)
```

### 4. Simulate disconnect

```bash
curl -s -X POST localhost:8080/api/v1/debug/scale/disconnect | jq .
# Expected: {"status":"disconnected"}
```

Scale operations should now fail:
```bash
curl -s -X PUT localhost:8080/api/v1/scale/tare
# Expected: {"error":"No scale connected"} (500)
```

### 5. Verify in logs

```bash
sb-dev logs -n 20 --filter "DebugHandler\|ScaleController\|ConnectionManager"
```

Expected log lines:
- `DebugHandler - Simulating data stall on MockScale`
- `DebugHandler - Resuming MockScale data emission`
- `DebugHandler - Simulating MockScale disconnect`
- `ScaleController - scale connection update: disconnected`

## Postconditions

- Scale disconnected after step 4
- Reconnect with: `curl -s -X PUT 'localhost:8080/api/v1/devices/connect?deviceId=Mock%20Scale'`
