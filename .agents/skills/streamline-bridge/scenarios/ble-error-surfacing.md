# Scenario: BLE error surfacing on `ws/v1/devices`

Verifies that transport-layer BLE failures are surfaced as structured
`connectionStatus.error` objects on the devices WebSocket, that sticky errors
clear on recovery, and that expected "natural" disconnects (e.g. sleep) do
**not** emit errors.

Error kinds covered: `adapterOff`, `scaleConnectFailed`, `scaleDisconnected`,
`scanFailed`, `bluetoothPermissionDenied`. Full taxonomy lives in
[`assets/api/websocket_v1.yml`](../../../../assets/api/websocket_v1.yml) and
[`doc/Skins.md`](../../../../doc/Skins.md#handling-connection-errors).

## Preconditions

Most of these scenarios require real BLE behaviour — simulated devices never
fail. Run on the Android tablet (or another real target) pointed at an actual
DE1 + scale:

```bash
# On the tablet (or equivalent), the app is built and running normally.
# From your dev machine, either sb-dev against a local build, or just point
# curl/websocat at the tablet's IP.
TABLET=http://<tablet-ip>:8080
BASE=$TABLET
```

If you only want to exercise the WebSocket payload shape (not the real BLE
edge), you can still run `scripts/sb-dev.sh start` in simulate mode and
inspect the stream — but you will not observe any error kinds except what the
debug endpoints drive.

Keep a WebSocket subscribed in a second terminal for every scenario below:

```bash
websocat -n -t "$BASE/ws/v1/devices" | jq '.connectionStatus'
```

## 1. Adapter off emits `adapterOff`

1. Subscribe to `ws/v1/devices` (command above).
2. Turn Bluetooth **off** on the tablet. Either:
   - Manually in Android Settings, or
   - Via adb:
     ```bash
     adb shell service call bluetooth_manager 8
     ```
3. Observe an update on the WS with:

```json
{
  "phase": "...",
  "error": {
    "kind": "adapterOff",
    "severity": "error",
    ...
  }
}
```

4. Turn Bluetooth back on (adb `service call bluetooth_manager 6`, or
   Settings). Expect a follow-up update where `connectionStatus.error` is
   `null`.

## 2. Scale connect timeout emits `scaleConnectFailed`

1. Power **off** the scale (or take it out of range).
2. Subscribe to `ws/v1/devices`.
3. Trigger a scan that attempts to connect:

```bash
curl -s -X POST "$BASE/api/v1/devices/scan?connect=true"
```

4. Wait ~15s for the connect attempt to time out.
5. On the WS, expect:

```json
{
  "error": {
    "kind": "scaleConnectFailed",
    "severity": "error",
    "deviceName": "Decent Scale",
    "message": "...",
    "details": {"exception": "..."}
  }
}
```

Note: `connectionStatus.error` is **only** on the WS — the REST
`GET /api/v1/devices` snapshot does not carry it. Watch the WS, not curl.

6. Power the scale back on and re-run the scan. `connectionStatus.error` goes
   to `null` when the connect succeeds.

## 3. Sleep flow does NOT emit `scaleDisconnected`

Regression guard: a deliberate machine→sleep transition must not be reported
as a BLE error.

1. Scale connected, machine idle, WS subscribed.
2. Put the machine to sleep:

```bash
curl -s -X PUT "$BASE/api/v1/machine/state/sleeping"
```

3. Watch the WS. Expect the scale's `state` field to transition naturally
   (`connected` → `disconnected`) **without** a `connectionStatus.error`
   update. The last non-null `error` value, if any, should be whatever it was
   before the sleep — no new error fires.

## 4. Unexpected scale drop emits `scaleDisconnected`

1. Scale connected, machine **active** (not sleeping), WS subscribed.
2. Power off the scale or walk it out of range.
3. After the transport notices the drop, expect on the WS:

```json
{
  "error": {
    "kind": "scaleDisconnected",
    "severity": "error",
    "deviceName": "Decent Scale",
    ...
  }
}
```

4. Reconnect the scale (curl connect or let the auto-reconnect loop pick it
   up). `connectionStatus.error` clears to `null`.

## 5. Successful scan clears sticky `scanFailed` / `bluetoothPermissionDenied`

Scan-origin errors are sticky: they persist in `connectionStatus.error` until
a subsequent scan succeeds.

1. WS subscribed.
2. Induce a sticky error. Easiest paths:
   - **Adapter off mid-scan:**
     ```bash
     curl -s -X POST "$BASE/api/v1/devices/scan" &
     adb shell service call bluetooth_manager 8
     ```
     Expect `kind: "scanFailed"` (or `adapterOff` depending on timing).
   - **Permission denied:** on Android, revoke Bluetooth permission for the
     app in Settings → Apps → Streamline Bridge → Permissions, then trigger a
     scan. Expect `kind: "bluetoothPermissionDenied"`.
3. Confirm the error remains in `connectionStatus.error` across a couple of
   WS updates (it is sticky — not cleared until a successful scan).
4. Restore the precondition (turn adapter on / grant permission).
5. Trigger a fresh scan:

```bash
curl -s -X POST "$BASE/api/v1/devices/scan"
```

6. On the WS, expect `connectionStatus.error` to transition to `null` once
   the scan completes successfully.

## Postconditions

- Restore Bluetooth adapter on, scale powered on and in range, permissions
  granted.
- If you started sb-dev locally:
  ```bash
  scripts/sb-dev.sh stop
  ```
