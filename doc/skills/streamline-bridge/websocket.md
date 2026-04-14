# WebSocket recipes

Subscribing to Streamline Bridge's live channels from a shell with `websocat`. The **authoritative** channel reference is `assets/api/websocket_v1.yml` (AsyncAPI 3.0) — every channel address, message shape, and bidi command lives there. Read the spec first; don't guess channel paths or payloads.

## Install

Primary tool: `websocat`.

```bash
brew install websocat                     # macOS
apt install websocat                      # Debian / Ubuntu
cargo install websocat                    # anywhere with rust
```

Fallback if websocat isn't available: `npm install -g wscat`. All examples below use websocat flags.

## One-shot snapshot — the default

Each `Bash` tool call is a fresh shell, so bounded reads (no background state) are the safe default. Two ways to bound:

```bash
# GNU timeout (Linux, or macOS with `brew install coreutils` → `gtimeout`)
timeout 3 websocat -t ws://localhost:8080/ws/v1/machine/snapshot | jq .

# Message count — portable, no timeout dependency
websocat -n -t --max-messages 5 ws://localhost:8080/ws/v1/machine/snapshot
```

macOS ships without GNU `timeout`; use `gtimeout` from coreutils or prefer `--max-messages`.

## Background subscription

For long-lived tailing across multiple Bash calls, persist the pid to a file (shell variables do not survive between calls):

```bash
websocat -t ws://localhost:8080/ws/v1/machine/snapshot > /tmp/sb-stream.log 2>&1 &
echo $! > /tmp/sb-stream.pid
# … do other work in later Bash calls …
tail -n 50 /tmp/sb-stream.log
kill "$(cat /tmp/sb-stream.pid)" && rm /tmp/sb-stream.pid
```

## Bidirectional channels

`ws/v1/devices` and `ws/v1/display` accept commands as well as emit state. Payload shape lives in the spec (`DevicesCommand`, `DisplayCommand`) — check before sending. Example: kick off a scan on the devices channel.

```bash
echo '{"command": "scan", "connect": false, "quick": true}' \
  | websocat -n -t ws://localhost:8080/ws/v1/devices
```

The field is `command`, not `cmd`. `DevicesCommand.command` enum: `scan`, `connect`, `disconnect` (`connect` / `disconnect` also need `deviceId`).

## jq parsing

Extract a single field from the machine snapshot stream:

```bash
timeout 3 websocat -t ws://localhost:8080/ws/v1/machine/snapshot | jq -c '.pressure'
```

Filter events — only pouring substates:

```bash
timeout 5 websocat -t ws://localhost:8080/ws/v1/machine/snapshot \
  | jq -c 'select(.state.substate == "pouring")'
```

## See also

- `lifecycle.md` — starting / restarting the flutter process before any of this works.
- `rest.md` — when the data you want is a single GET, not a stream.
