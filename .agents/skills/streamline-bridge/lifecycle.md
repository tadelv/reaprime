# sb-dev lifecycle

`scripts/sb-dev.sh` is a POSIX Bash helper that drives `flutter run` in simulate mode for development work. It owns the flutter child process, exposes hot reload / hot restart / cold restart, and tails the combined log — replacing the old MCP lifecycle tools (`app_start`, `app_stop`, etc). It targets macOS and Linux contributors. Windows users should run `flutter run --dart-define=simulate=1` directly in a terminal and skip this file.

## Prerequisites

Hard dependencies on `PATH`:

- `bash`
- `curl`
- `jq` — sb-dev errors out at startup if missing
- `mkfifo` (part of coreutils)
- `flutter`

## Commands

All commands are run from the repo root as `scripts/sb-dev.sh <cmd>`.

### `start`

Spawns `flutter run` via `./flutter_with_commit.sh run` with `--dart-define=simulate=1` always injected, waits up to 120s for `GET /api/v1/devices` to respond, then (if `--connect-machine` was passed) scans and waits up to 30s for the named device to report `connected`.

Flags:

- `--platform <name>` — forwarded as `-d <name>` to flutter (`macos`, `linux`, `chrome`, etc).
- `--connect-machine <id>` — sets `--dart-define=preferredMachineId=<id>` and triggers a post-boot scan loop. Use `MockDe1` in simulate mode.
- `--connect-scale <id>` — sets `--dart-define=preferredScaleId=<id>`. Use `MockScale`. Note: the scale's REST `name` field is `"Mock Scale"` (with space); the flag takes the dart-define identifier without a space.
- `--dart-define key=val` — repeatable passthrough for extra defines.

```bash
scripts/sb-dev.sh start --connect-machine MockDe1 --connect-scale MockScale
```

### `stop`

Writes `q` to the stdin fifo (the key `flutter run` honours for a graceful quit), waits up to 5s, then falls back to `SIGKILL`. Cleans up the fifo and pid files.

```bash
scripts/sb-dev.sh stop
```

### `status`

Reports running pid, whether `http://localhost:8080/api/v1/devices` is reachable, and the current device list from that endpoint.

```bash
scripts/sb-dev.sh status
```

### `logs`

Tails `$SB_RUNTIME_DIR/flutter.log`. `-n` / `--count` controls how many lines (default 50). `--filter <text>` does a case-insensitive grep first.

```bash
scripts/sb-dev.sh logs -n 200
scripts/sb-dev.sh logs --filter 'scale'
```

### `reload`

Sends `r` to flutter's stdin and waits up to 30s for a `Reloaded N libraries` line in the log. Preserves app state.

```bash
scripts/sb-dev.sh reload
```

### `hot-restart`

Sends `R` and waits up to 60s for `Restarted application in Nms`. Resets the widget tree but keeps the flutter process and VM running.

```bash
scripts/sb-dev.sh hot-restart
```

### `restart`

Cold restart: `stop` followed by `start`, replaying the flags persisted in `$SB_RUNTIME_DIR/last-flags`. Use when neither hot reload nor hot restart is enough.

```bash
scripts/sb-dev.sh restart
```

## Reload vs hot-restart vs cold restart

- **`reload`** preserves app state (widget tree, ephemeral variables, current route). Use for most Dart source edits. Typical completion: under 5s.
- **`hot-restart`** resets the widget tree and rebuilds from `main()` but keeps the process running. Use when stale state confuses the UI, or when you edit code that only runs during widget-tree construction. Typical: 10–30s.
- **`restart`** is `stop && start` with the last flags. Use for native-side changes (Android / iOS / desktop shell), plugin registration changes, async init path changes, or when you suspect a corrupted on-disk DB or runtime dir.

## Runtime state

Everything sb-dev owns lives under `$SB_RUNTIME_DIR` (default `/tmp/streamline-bridge-$USER/`):

- `flutter.pid` — flutter process id
- `holder.pid` — a `tail -f /dev/null` writer that keeps the stdin fifo open so flutter never sees EOF
- `stdin` — named pipe; flutter's stdin reads from it (`r`, `R`, `q` are written here)
- `flutter.log` — combined stdout + stderr
- `last-flags` — the flags from the most recent `start`, used by `restart`

`SB_HOST` and `SB_PORT` override the host/port used for `curl` checks (default `localhost:8080`).

## If things get wedged

Escape hatch when state on disk disagrees with what is actually running:

```bash
scripts/sb-dev.sh stop || true
rm -rf /tmp/streamline-bridge-$USER/
pgrep -af flutter_tools.snapshot   # should be empty
```

Then `sb-dev start` cleanly.

## Windows

`sb-dev.sh` is POSIX-only — it relies on `mkfifo`, named pipes, and process substitution. Windows contributors should run `flutter run --dart-define=simulate=1` in a regular terminal and use the other skill files (`rest.md`, `websocket.md`, `simulated-devices.md`) as normal.
