# Streamline Bridge Skill Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace `packages/mcp-server/` with a project skill (`.claude/skills/streamline-bridge/` + `doc/skills/streamline-bridge/`) and a POSIX lifecycle helper (`scripts/sb-dev.sh`). Delete the MCP package. Leave specs (`assets/api/rest_v1.yml`, `assets/api/websocket_v1.yml`) as the single source of truth for endpoint knowledge.

**Architecture:** Agents read authoritative OpenAPI + AsyncAPI specs directly, call endpoints with `curl`, listen to WebSocket streams with `websocat`, and drive the Flutter dev loop through `sb-dev.sh` (start/stop/reload/status/logs). Skill lives as plain markdown under `doc/skills/` so any agent can read it; `.claude/skills/streamline-bridge/SKILL.md` is a thin Claude Code shim, `AGENTS.md` mirrors the same discovery for other agents.

**Tech Stack:** Bash, curl, websocat, jq, mkfifo/named pipes, Flutter CLI. No build step.

**Design doc:** `doc/plans/2026-04-14-streamline-bridge-skill-design.md` — read first for context, trade-offs, and risks.

**Working branch:** `refactor/mcp-skill-replacement` (already checked out).

---

## Phase 1: Build `sb-dev.sh`

This is the load-bearing piece. The skill is useless if `sb-dev` is flaky. Build it incrementally, testing each command against a real `flutter run` session in simulate mode before moving on.

### Task 1: Scaffold `scripts/sb-dev.sh` with command dispatcher

**Files:**
- Create: `scripts/sb-dev.sh`

**Step 1: Create the file with the dispatcher and `help` command**

```bash
#!/usr/bin/env bash
# sb-dev.sh — Streamline Bridge dev-session manager
#
# Manages a `flutter run` process for simulate-mode development. Replaces
# the lifecycle tools from the old packages/mcp-server/ package.
#
# Runtime state lives under $SB_RUNTIME_DIR (default /tmp/streamline-bridge-$USER).

set -euo pipefail

RUNTIME_DIR="${SB_RUNTIME_DIR:-/tmp/streamline-bridge-${USER:-default}}"
PIDFILE="$RUNTIME_DIR/flutter.pid"
HOLDER_PIDFILE="$RUNTIME_DIR/holder.pid"
STDIN_FIFO="$RUNTIME_DIR/stdin"
LOGFILE="$RUNTIME_DIR/flutter.log"
FLAGSFILE="$RUNTIME_DIR/last-flags"
HOST="${SB_HOST:-localhost}"
PORT="${SB_PORT:-8080}"
BASE_URL="http://$HOST:$PORT"

cmd="${1:-help}"
shift || true

usage() {
  cat <<'EOF'
sb-dev.sh — Streamline Bridge dev-session manager

Usage:
  sb-dev start [--platform macos] [--connect-machine MockDe1] [--connect-scale MockScale] [--dart-define k=v]
  sb-dev stop
  sb-dev restart           — cold restart with the same flags as the last start
  sb-dev reload            — hot reload (preserves app state)
  sb-dev hot-restart       — hot restart (resets app state, reloads code)
  sb-dev status            — pid + http reachability + devices
  sb-dev logs [-n 50] [--filter text]
  sb-dev help

Env:
  SB_RUNTIME_DIR  runtime state directory (default: /tmp/streamline-bridge-$USER)
  SB_HOST         host for curl checks (default: localhost)
  SB_PORT         port for curl checks (default: 8080)
EOF
}

case "$cmd" in
  help|-h|--help) usage; exit 0 ;;
  *) echo "Not yet implemented: $cmd" >&2; exit 2 ;;
esac
```

**Step 2: Make executable and run help**

```bash
chmod +x scripts/sb-dev.sh
scripts/sb-dev.sh help
```

Expected: prints the usage block, exit 0.

**Step 3: Commit**

```bash
git add scripts/sb-dev.sh
git commit -m "scripts: scaffold sb-dev.sh dispatcher"
```

---

### Task 2: Implement `sb-dev start`

**Files:**
- Modify: `scripts/sb-dev.sh`

**Step 1: Add start command, runtime helpers, and flag parsing**

Replace the `case "$cmd" in` block with the following and add helper functions above it:

```bash
init_runtime() {
  mkdir -p "$RUNTIME_DIR"
}

is_running() {
  [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null
}

wait_ready() {
  local start timeout=120
  start=$(date +%s)
  while (( $(date +%s) - start < timeout )); do
    if curl -sf "$BASE_URL/api/v1/devices" >/dev/null 2>&1; then
      echo "HTTP server ready"
      return 0
    fi
    if ! is_running; then
      echo "Flutter process exited before becoming ready. Last logs:" >&2
      tail -n 30 "$LOGFILE" >&2 || true
      return 1
    fi
    sleep 1
  done
  echo "Timed out after ${timeout}s waiting for HTTP ready" >&2
  return 1
}

connect_machine() {
  local name="$1" start
  curl -sf "$BASE_URL/api/v1/devices/scan?connect=true" >/dev/null || {
    echo "Scan request failed" >&2
    return 1
  }
  start=$(date +%s)
  while (( $(date +%s) - start < 15 )); do
    local devices
    devices=$(curl -sf "$BASE_URL/api/v1/devices" || echo "[]")
    if echo "$devices" | grep -qi "\"name\":\"$name\"" && echo "$devices" | grep -q '"state":"connected"'; then
      echo "Connected to $name"
      return 0
    fi
    sleep 1
  done
  echo "Timed out waiting for $name to connect" >&2
}

start_cmd() {
  init_runtime
  if is_running; then
    echo "Already running (pid=$(cat "$PIDFILE"))" >&2
    return 1
  fi

  local platform="" machine="" scale=""
  local -a extra_defines=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --platform) platform="$2"; shift 2 ;;
      --connect-machine) machine="$2"; shift 2 ;;
      --connect-scale) scale="$2"; shift 2 ;;
      --dart-define) extra_defines+=("--dart-define=$2"); shift 2 ;;
      *) echo "Unknown flag: $1" >&2; return 2 ;;
    esac
  done

  # Persist flags for `sb-dev restart`
  {
    [[ -n "$platform" ]] && printf '%s\n' "--platform $platform"
    [[ -n "$machine" ]] && printf '%s\n' "--connect-machine $machine"
    [[ -n "$scale" ]] && printf '%s\n' "--connect-scale $scale"
    for d in "${extra_defines[@]}"; do printf '%s\n' "--dart-define ${d#--dart-define=}"; done
  } > "$FLAGSFILE"

  local -a defines=("--dart-define=simulate=1")
  [[ -n "$machine" ]] && defines+=("--dart-define=preferredMachineId=$machine")
  [[ -n "$scale" ]] && defines+=("--dart-define=preferredScaleId=$scale")
  defines+=("${extra_defines[@]}")

  local -a platform_flag=()
  [[ -n "$platform" ]] && platform_flag=(-d "$platform")

  # Fresh fifo each run
  rm -f "$STDIN_FIFO"
  mkfifo "$STDIN_FIFO"

  # Persistent writer so flutter's reader never sees EOF
  tail -f /dev/null > "$STDIN_FIFO" &
  echo $! > "$HOLDER_PIDFILE"

  # Spawn flutter with stdin from the fifo, logs redirected
  nohup ./flutter_with_commit.sh run "${platform_flag[@]}" "${defines[@]}" \
    < "$STDIN_FIFO" > "$LOGFILE" 2>&1 &
  echo $! > "$PIDFILE"

  echo "Started flutter (pid=$(cat "$PIDFILE")), waiting for HTTP server..."
  if ! wait_ready; then
    echo "Start failed. Run 'sb-dev logs' to inspect." >&2
    return 1
  fi

  if [[ -n "$machine" ]]; then
    connect_machine "$machine" || true
  fi
}

case "$cmd" in
  help|-h|--help) usage; exit 0 ;;
  start) start_cmd "$@" ;;
  *) echo "Not yet implemented: $cmd" >&2; exit 2 ;;
esac
```

**Step 2: Run `sb-dev start` against real Flutter**

```bash
scripts/sb-dev.sh start --platform macos
```

Expected: "Started flutter (pid=NNNN), waiting for HTTP server...", then "HTTP server ready" within ~60s.

In another terminal (or after the command returns):
```bash
curl -sf http://localhost:8080/api/v1/devices | jq .
```
Expected: JSON array, possibly empty.

**Step 3: Verify state files exist**

```bash
ls -la /tmp/streamline-bridge-$USER/
```

Expected: `flutter.pid`, `holder.pid`, `stdin` (fifo), `flutter.log`, `last-flags`.

**Step 4: Kill the flutter process manually to clean up (we haven't written stop yet)**

```bash
kill "$(cat /tmp/streamline-bridge-$USER/flutter.pid)"
kill "$(cat /tmp/streamline-bridge-$USER/holder.pid)" 2>/dev/null || true
rm -rf /tmp/streamline-bridge-$USER/
```

**Step 5: Commit**

```bash
git add scripts/sb-dev.sh
git commit -m "scripts: sb-dev start with ready probe + auto-connect"
```

---

### Task 3: Implement `sb-dev stop` (and fix PID cascade)

**Files:**
- Modify: `flutter_with_commit.sh` (one-line fix so wrapper PID = flutter PID)
- Modify: `scripts/sb-dev.sh` (stop_cmd + cleanup_runtime, wire cleanup into start error path)

**Step 0: Fix `flutter_with_commit.sh` to `exec flutter ...`**

Line 87 of `flutter_with_commit.sh` currently reads `flutter "$COMMAND" \`. Change to `exec flutter "$COMMAND" \`. Rationale: without `exec`, the bash wrapper is the parent of `flutter`, and `kill $wrapper_pid` leaves the Dart VM child orphaned. With `exec`, the wrapper process image is replaced by flutter, so `$!` captured by sb-dev is the actual flutter PID — `kill` cascades cleanly. Behavior for non-run commands (test, analyze) is unchanged because `exec` still captures the same exit code that the calling shell sees.

**Step 1: Add `stop_cmd` and `cleanup_runtime` helpers**

Add above the `case` block:

```bash
cleanup_runtime() {
  if [[ -f "$HOLDER_PIDFILE" ]]; then
    kill "$(cat "$HOLDER_PIDFILE")" 2>/dev/null || true
    rm -f "$HOLDER_PIDFILE"
  fi
  rm -f "$PIDFILE" "$STDIN_FIFO"
}

# Also wire cleanup into start_cmd's error path: wherever start_cmd has
# `return 1` after a failure (wait_ready, mkfifo, etc.), call cleanup_runtime
# first. Add the call so a failed start doesn't leak fifo + holder + pidfile.
# Specifically replace the wait_ready failure branch in start_cmd with:
#
#   if ! wait_ready; then
#     echo "Start failed. Run 'sb-dev logs' to inspect." >&2
#     cleanup_runtime
#     return 1
#   fi

stop_cmd() {
  if ! is_running; then
    echo "Not running"
    cleanup_runtime
    return 0
  fi
  local pid
  pid=$(cat "$PIDFILE")

  # Graceful quit via fifo — flutter run honors 'q'
  echo q > "$STDIN_FIFO" || true

  local start
  start=$(date +%s)
  while (( $(date +%s) - start < 5 )); do
    if ! kill -0 "$pid" 2>/dev/null; then
      break
    fi
    sleep 0.2
  done

  if kill -0 "$pid" 2>/dev/null; then
    echo "Flutter did not quit gracefully, sending SIGKILL" >&2
    kill -9 "$pid" 2>/dev/null || true
  fi
  cleanup_runtime
  echo "Stopped"
}
```

Add to the `case`:

```bash
    stop) stop_cmd ;;
```

**Step 2: Test full start/stop cycle**

```bash
scripts/sb-dev.sh start --platform macos
curl -sf http://localhost:8080/api/v1/devices >/dev/null && echo "reachable"
scripts/sb-dev.sh stop
curl -sf http://localhost:8080/api/v1/devices >/dev/null 2>&1 && echo "STILL REACHABLE (bad)" || echo "stopped cleanly"
ls /tmp/streamline-bridge-$USER/ 2>&1
```

Expected output (in order):
- "Started flutter (pid=...)" + "HTTP server ready"
- "reachable"
- "Stopped"
- "stopped cleanly"
- `flutter.log` and `last-flags` remain, `flutter.pid`/`holder.pid`/`stdin` removed.

**Step 3: Verify no orphaned flutter processes**

```bash
pgrep -a -f "flutter run" || echo "no orphans"
```

Expected: "no orphans".

**Step 4: Commit**

```bash
git add scripts/sb-dev.sh
git commit -m "scripts: sb-dev stop with graceful quit + SIGKILL fallback"
```

---

### Task 4: Implement `sb-dev status` and `sb-dev logs`

**Files:**
- Modify: `scripts/sb-dev.sh`

**Step 1: Add `status_cmd` and `logs_cmd`**

```bash
status_cmd() {
  if is_running; then
    echo "Running (pid=$(cat "$PIDFILE"))"
    if curl -sf "$BASE_URL/api/v1/devices" >/dev/null 2>&1; then
      echo "HTTP: reachable at $BASE_URL"
      curl -sf "$BASE_URL/api/v1/devices" | jq -c '.' 2>/dev/null || true
    else
      echo "HTTP: not yet reachable"
    fi
  else
    echo "Not running"
  fi
}

logs_cmd() {
  local count=50 filter=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n|--count) count="$2"; shift 2 ;;
      --filter) filter="$2"; shift 2 ;;
      *) echo "Unknown flag: $1" >&2; return 2 ;;
    esac
  done
  if [[ ! -f "$LOGFILE" ]]; then
    echo "No log file yet at $LOGFILE" >&2
    return 1
  fi
  if [[ -n "$filter" ]]; then
    grep -i -- "$filter" "$LOGFILE" | tail -n "$count" || true
  else
    tail -n "$count" "$LOGFILE"
  fi
}
```

Add to the `case`:

```bash
    status) status_cmd ;;
    logs) logs_cmd "$@" ;;
```

**Step 2: Test**

```bash
scripts/sb-dev.sh status
# Expected: "Not running"

scripts/sb-dev.sh start --platform macos
scripts/sb-dev.sh status
# Expected: Running (pid=...), HTTP: reachable..., device JSON

scripts/sb-dev.sh logs -n 5
# Expected: last 5 flutter log lines

scripts/sb-dev.sh logs --filter "Flutter run" -n 3
# Expected: filtered subset

scripts/sb-dev.sh stop
```

**Step 3: Commit**

```bash
git add scripts/sb-dev.sh
git commit -m "scripts: sb-dev status + logs"
```

---

### Task 5: Implement `sb-dev reload` and `sb-dev hot-restart`

**Files:**
- Modify: `scripts/sb-dev.sh`

**Step 1: Add `reload_cmd` and `hot_restart_cmd`**

```bash
wait_for_pattern_after() {
  local pattern="$1" timeout="$2" start_line="$3"
  local start
  start=$(date +%s)
  while (( $(date +%s) - start < timeout )); do
    # Only scan new lines since start_line
    if tail -n +"$((start_line + 1))" "$LOGFILE" 2>/dev/null | grep -qi -- "$pattern"; then
      return 0
    fi
    sleep 0.2
  done
  return 1
}

reload_cmd() {
  if ! is_running; then
    echo "Not running" >&2
    return 1
  fi
  local before
  before=$(wc -l < "$LOGFILE")
  echo r > "$STDIN_FIFO"
  if wait_for_pattern_after "reloaded" 30 "$before"; then
    echo "Hot reload complete"
    tail -n +"$((before + 1))" "$LOGFILE" | grep -i "reloaded" | head -1
  else
    echo "Timed out waiting for reload confirmation" >&2
    return 1
  fi
}

hot_restart_cmd() {
  if ! is_running; then
    echo "Not running" >&2
    return 1
  fi
  local before
  before=$(wc -l < "$LOGFILE")
  echo R > "$STDIN_FIFO"
  if wait_for_pattern_after "restarted" 60 "$before"; then
    echo "Hot restart complete"
    tail -n +"$((before + 1))" "$LOGFILE" | grep -i "restarted" | head -1
  else
    echo "Timed out waiting for restart confirmation" >&2
    return 1
  fi
}
```

Add to the `case`:

```bash
    reload) reload_cmd ;;
    hot-restart) hot_restart_cmd ;;
```

**Step 2: Test hot reload end-to-end**

```bash
scripts/sb-dev.sh start --platform macos --connect-machine MockDe1
scripts/sb-dev.sh status
# Make a trivial dart edit (e.g. whitespace in lib/main.dart or lib/src/app.dart)
scripts/sb-dev.sh reload
# Expected: "Hot reload complete" within ~5s, followed by the matching log line
```

Revert the whitespace edit if you made one.

**Step 3: Test hot restart**

```bash
scripts/sb-dev.sh hot-restart
# Expected: "Hot restart complete" within ~60s
scripts/sb-dev.sh stop
```

**Step 4: Commit**

```bash
git add scripts/sb-dev.sh
git commit -m "scripts: sb-dev reload + hot-restart via fifo writes"
```

---

### Task 6: Implement `sb-dev restart` (cold) using persisted flags

**Files:**
- Modify: `scripts/sb-dev.sh`

**Step 1: Add `restart_cmd` that reads `$FLAGSFILE` and re-invokes `start_cmd`**

```bash
restart_cmd() {
  local -a saved_args=()
  if [[ -f "$FLAGSFILE" ]]; then
    while IFS= read -r line; do
      # shellcheck disable=SC2206
      saved_args+=($line)
    done < "$FLAGSFILE"
  fi
  stop_cmd || true
  start_cmd "${saved_args[@]}"
}
```

Add to the `case`:

```bash
    restart) restart_cmd ;;
```

**Step 2: Test**

```bash
scripts/sb-dev.sh start --platform macos --connect-machine MockDe1
scripts/sb-dev.sh restart
# Expected: stop, then start with the same --platform and --connect-machine
scripts/sb-dev.sh status
# Expected: running + MockDe1 connected
scripts/sb-dev.sh stop
```

**Step 3: Commit**

```bash
git add scripts/sb-dev.sh
git commit -m "scripts: sb-dev restart replays saved flags"
```

---

### Task 7: Hardening pass — shellcheck + review follow-ups + final smoke test

**Files:**
- Modify: `scripts/sb-dev.sh` (shellcheck clean, guard `shift 2`, optional jq warning, `connect_machine` fixes)

This task rolls up follow-up items surfaced during T2 and T4 reviews. Each item is small and tightly scoped; make them in one commit.

**Step 0: Apply review follow-ups before running shellcheck**

**0a. Guard `shift 2` against missing values** in both `start_cmd` and `logs_cmd` flag loops. Under `set -u`, `shift 2` with only one arg followed by `$2` reference dies with "unbound variable" — cryptic. Replace each `shift 2` call with a guarded version:

```bash
case "$1" in
  --platform)
    [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; return 2; }
    platform="$2"; shift 2 ;;
  # ... same pattern for --connect-machine, --connect-scale, --dart-define in start_cmd
  # ... same pattern for -n|--count and --filter in logs_cmd
```

Apply at every `shift 2` site in `start_cmd` and `logs_cmd`.

**0b. Fix `connect_machine` quiet failure modes** (T2 review findings 4–6):

- Add an explicit `return 1` at the end of `connect_machine` after the timeout message so the return code is not an implicit falsy leftover.
- Change the grep pattern from `grep -qi "..."` to `grep -qiF "..."` (`-F` = fixed string) so device names containing regex metacharacters don't break matching. Apply to both grep calls.
- The two independent `grep`s in `connect_machine` don't actually verify that the **same** device entry both has the right name AND is connected. Replace the combined check with a `jq` expression that parses the JSON properly:

```bash
if echo "$devices" | jq -e --arg name "$name" '.[] | select(.name == $name and .state == "connected")' >/dev/null 2>&1; then
  echo "Connected to $name"
  return 0
fi
```

If `jq` is a hard dependency, that's fine (T7 optional step 0c adds a warning). If you prefer to keep it grep-only, use a more specific pattern but document the limitation.

**0c. (Optional) Warn once at script top if `jq` is missing.** Near the top of the script, after the env var declarations:

```bash
if ! command -v jq >/dev/null 2>&1; then
  echo "warning: jq not found; status and connect-machine output will be limited" >&2
fi
```

This is a friendly hint, not a hard dependency — `status_cmd`'s `|| true` already tolerates missing `jq`, but a one-time warning helps users diagnose why output looks different.

**Step 1: Run shellcheck**

```bash
shellcheck scripts/sb-dev.sh
```

Expected: no warnings. Fix any that appear (suppress with `# shellcheck disable=SC...` only with a justification comment).

**Step 2: Full end-to-end smoke**

```bash
scripts/sb-dev.sh start --platform macos --connect-machine MockDe1 --connect-scale MockScale
scripts/sb-dev.sh status
curl -sf http://localhost:8080/api/v1/machine/state | jq .
scripts/sb-dev.sh reload
scripts/sb-dev.sh logs -n 10
scripts/sb-dev.sh stop
pgrep -a -f "flutter run" || echo "no orphans"
```

Expected: every step succeeds; no orphans.

**Step 3: Commit**

```bash
git add scripts/sb-dev.sh
git commit -m "scripts: sb-dev shellcheck clean"
```

**Known issues surfaced during T7 that are out of scope here but worth carrying forward:**

- **Upstream race in `lib/src/services/simulated_device_service.dart:33-36`.** `scanForDevices()` early-returns when `enabledDevices` is empty, and on first call after boot the settings listener hasn't yet merged enabled devices. sb-dev's `connect_machine` works around this with a re-scan loop, but the app-side bug should also be fixed (e.g., `await _settingsService.ready` before the early return). File as a follow-up; not blocking this refactor.
- **`wait_ready` port ownership.** The HTTP probe can latch onto a stale server (e.g. a leftover playwright listener on port 8080). Cheap hardening: wait for `API Web server running` in `$LOGFILE` (from `lib/src/services/webserver_service.dart:232`) before trusting port 8080. Defer to a follow-up.
- **`restart_cmd` flag round-trip** via `$FLAGSFILE` doesn't survive values containing spaces (e.g. real BLE device names like "Acaia Pyxis"). Current `MockDe1`/`MockScale` names are safe. Consider NUL-delimited storage for flags in a follow-up.

---

## Phase 2: Write the skill

### Task 8: Write `doc/skills/streamline-bridge/lifecycle.md`

**Files:**
- Create: `doc/skills/streamline-bridge/lifecycle.md`

**Step 1: Write the file**

Content (~80 lines) covering:
- What `sb-dev.sh` is and why (one paragraph).
- Command reference table (mirrors `sb-dev help` output plus examples for common flag combinations).
- Recipe: "start with MockDe1 + MockScale, run a smoke test, stop".
- When to use `reload` vs `hot-restart` vs `stop && start` (preserves state / resets state / fresh DB).
- Windows caveat: POSIX-only (`mkfifo`, process substitution). Windows contributors use `flutter run` in a real terminal and read `doc/skills/streamline-bridge/rest.md` + `websocket.md` for the rest.
- Runtime state location (`/tmp/streamline-bridge-$USER/`) and how to nuke it if things get wedged.

**Step 2: Commit**

```bash
git add doc/skills/streamline-bridge/lifecycle.md
git commit -m "skill: streamline-bridge lifecycle recipes"
```

---

### Task 9: Write `doc/skills/streamline-bridge/rest.md`

**Files:**
- Create: `doc/skills/streamline-bridge/rest.md`

**Step 1: Write the file**

Content (~50 lines) covering:
- Authoritative spec pointer: `assets/api/rest_v1.yml`. "Always read this before making calls — don't guess paths or payload shapes."
- Base URL and override: `SB_HOST`/`SB_PORT` env vars (match sb-dev).
- Example curl calls, one per verb (GET/PUT/POST). Use real endpoints from `rest_v1.yml`: `/api/v1/machine/state`, `/api/v1/machine/state/{state}`, `/api/v1/machine/settings`.
- Gotchas not in the spec:
  - `/api/v1/machine/state` returns 500 before a DE1 is connected. Use `/api/v1/devices` for liveness.
  - Profile POST requires the full profile JSON; check `sb-dev status` first.
  - Shot history endpoints can return large payloads; always filter.
- One-line pointer to `sb-dev status` as the fastest "is anything connected" check.

**Step 2: Commit**

```bash
git add doc/skills/streamline-bridge/rest.md
git commit -m "skill: streamline-bridge REST recipes"
```

---

### Task 10: Write `doc/skills/streamline-bridge/websocket.md`

**Files:**
- Create: `doc/skills/streamline-bridge/websocket.md`

**Step 1: Write the file**

Content (~60 lines) covering:
- Authoritative spec pointer: `assets/api/websocket_v1.yml` (AsyncAPI 3.0). All channels + message shapes.
- Install note: `brew install websocat` / `apt install websocat`. Fallback to `wscat` (`npm i -g wscat`).
- One-shot snapshot pattern (the default — bounded, safe across Bash tool calls):
  ```bash
  timeout 3 websocat -t ws://localhost:8080/ws/v1/machine/snapshot | jq .
  websocat -n -t --max-messages 5 ws://localhost:8080/ws/v1/machine/snapshot
  ```
- Background subscription pattern (only when you need cross-turn tailing):
  ```bash
  websocat -t ws://localhost:8080/ws/v1/machine/snapshot > /tmp/sb-stream.log 2>&1 &
  echo $! > /tmp/sb-stream.pid
  tail -n 50 /tmp/sb-stream.log
  kill "$(cat /tmp/sb-stream.pid)" && rm /tmp/sb-stream.pid
  ```
- Bidirectional channels (the Devices channel accepts commands): example of piping JSON into `websocat` stdin.
- Parsing with jq: `… | jq -c 'select(.substate == "pouring")'`.

**Step 2: Commit**

```bash
git add doc/skills/streamline-bridge/websocket.md
git commit -m "skill: streamline-bridge WebSocket recipes"
```

---

### Task 11: Write `doc/skills/streamline-bridge/simulated-devices.md`

**Files:**
- Create: `doc/skills/streamline-bridge/simulated-devices.md`

**Step 1: Write the file**

Content (~60 lines) covering:
- Why simulate mode exists (no hardware, deterministic, CI-friendly).
- Toggles: `--dart-define=simulate=1` (both), `simulate=machine`, `simulate=scale`, or the in-app settings switch.
- Available mock devices: `MockDe1`, `MockScale`. Case-sensitive.
- Auto-connect fast-path: `sb-dev start --connect-machine MockDe1 --connect-scale MockScale` sets `preferredMachineId`/`preferredScaleId` dart-defines, bypassing the device selection screen.
- Typical scenarios:
  - Unit/widget tests — no app running.
  - Integration flow — `sb-dev start --connect-machine MockDe1`.
  - Shot flow — both mocks + profile POST + tare via WebSocket + observe state.
- Cleaning state: cold restart (`stop && start`) vs hot restart (preserves DB, resets runtime state).

**Step 2: Commit**

```bash
git add doc/skills/streamline-bridge/simulated-devices.md
git commit -m "skill: streamline-bridge simulated device guide"
```

---

### Task 12: Write `doc/skills/streamline-bridge/verification.md`

**Files:**
- Create: `doc/skills/streamline-bridge/verification.md`

**Step 1: Write the file**

Content (~80 lines) covering:
- When to verify via running app vs unit tests (aligns with `.claude/skills/tdd-workflow/`).
- Generic smoke-test recipe:
  ```bash
  sb-dev start --connect-machine MockDe1
  sb-dev status
  curl -sf http://localhost:8080/api/v1/machine/state | jq .
  # exercise the feature...
  sb-dev reload
  curl ...
  sb-dev logs -n 30 --filter error
  sb-dev stop
  ```
- "Added a new REST endpoint" recipe:
  1. Implement handler + register route.
  2. `sb-dev reload`.
  3. curl the new endpoint.
  4. Update `assets/api/rest_v1.yml` **in the same commit** as the handler change.
  5. Update `doc/Api.md`.
- "Changed a WebSocket message shape" recipe:
  1. Implement the change.
  2. `sb-dev reload`.
  3. `timeout 3 websocat -t ws://localhost:8080/ws/v1/machine/snapshot | jq .`
  4. Update `assets/api/websocket_v1.yml`.
  5. Update `doc/Api.md` / `doc/Plugins.md` if events changed.
- Pre-PR checklist echoing `CLAUDE.md`: plans archived, docs updated, `flutter test` green, `flutter analyze` clean.
- Reinforcement: **stale spec → stale agent knowledge**. The skill only works if the specs stay current.

**Step 2: Commit**

```bash
git add doc/skills/streamline-bridge/verification.md
git commit -m "skill: streamline-bridge verification recipes"
```

---

### Task 13: Write `doc/skills/streamline-bridge/README.md`

**Files:**
- Create: `doc/skills/streamline-bridge/README.md`

**Step 1: Write the file**

Content (~60 lines). This is the tool-agnostic entry point. Structure:

- Heading: "Streamline Bridge — agent skill".
- One paragraph orientation: what the skill covers (dev loop + REST + WebSocket against a simulate-mode Flutter app) and who it's for (any agent that can read markdown).
- Routing table pointing at sibling files:

  | Task | File |
  |---|---|
  | Start/stop/reload the app | `lifecycle.md` |
  | Call REST endpoints, add endpoints | `rest.md` |
  | Read/write WebSocket streams | `websocket.md` |
  | Work with MockDe1/MockScale | `simulated-devices.md` |
  | Smoke-test a code change | `verification.md` |

- "Authoritative sources" section listing `assets/api/rest_v1.yml`, `assets/api/websocket_v1.yml`, `scripts/sb-dev.sh`, `CLAUDE.md`/`AGENTS.md`.
- Short "Prerequisites" note: `bash`, `curl`, `jq`, `websocat`, `flutter`. Mention `mkfifo` / POSIX shell for `sb-dev.sh`.

**Step 2: Commit**

```bash
git add doc/skills/streamline-bridge/README.md
git commit -m "skill: streamline-bridge README entry point"
```

---

### Task 14: Write `.claude/skills/streamline-bridge/SKILL.md`

**Files:**
- Create: `.claude/skills/streamline-bridge/SKILL.md`

**Step 1: Write the file**

```markdown
---
name: streamline-bridge
description: Use when touching the Flutter app, its REST/WebSocket API, profiles, shots, or simulated devices, or whenever exercising a code change against a running Streamline Bridge instance. Covers the dev loop (sb-dev start/reload/stop), REST calls via curl, WebSocket streams via websocat, and smoke-test verification.
---

# Streamline Bridge

Streamline Bridge is a Flutter gateway app for Decent Espresso machines. It exposes a REST API on port 8080 and WebSocket channels under `/ws/v1/*`. This skill tells you how to drive it in simulate mode for development and testing.

**Authoritative sources (read these before acting):**
- REST spec: `assets/api/rest_v1.yml`
- WebSocket spec: `assets/api/websocket_v1.yml`
- Lifecycle helper: `scripts/sb-dev.sh`

**Full skill content lives in `doc/skills/streamline-bridge/`.** Read the sub-file matching your task:

| Task | File |
|---|---|
| Start/stop/reload the app | `doc/skills/streamline-bridge/lifecycle.md` |
| Call REST endpoints / add endpoints | `doc/skills/streamline-bridge/rest.md` |
| Read/write WebSocket streams | `doc/skills/streamline-bridge/websocket.md` |
| Work with MockDe1/MockScale | `doc/skills/streamline-bridge/simulated-devices.md` |
| Smoke-test a code change | `doc/skills/streamline-bridge/verification.md` |

**Rule of thumb:** if you're about to guess an endpoint path, payload shape, or WebSocket channel, stop and read the relevant spec file first. If you're about to run `flutter run` by hand, use `sb-dev start` instead — it handles the fifo-backed stdin, auto-connect, and cleanup.
```

**Step 2: Commit**

```bash
git add .claude/skills/streamline-bridge/SKILL.md
git commit -m "skill: streamline-bridge SKILL.md Claude Code entry"
```

---

### Task 15: Update `AGENTS.md`

**Files:**
- Modify: `AGENTS.md`

**Step 1: Read current `AGENTS.md` to find a sensible insertion point**

```bash
cat AGENTS.md
```

**Step 2: Add a new section (near the top, after project intro) pointing at the skill**

Section content:

```markdown
## Working with Streamline Bridge (all agents)

The authoritative dev-loop skill lives in `doc/skills/streamline-bridge/`. Any agent that can read markdown can use it — no MCP, no plugin install.

- **Entry point:** `doc/skills/streamline-bridge/README.md`
- **Routing:** the README has a table pointing at sub-files for lifecycle, REST, WebSocket, simulated devices, and verification.
- **Lifecycle helper:** `scripts/sb-dev.sh` (POSIX shell) manages `flutter run` in simulate mode — start, stop, hot reload, logs, status.
- **Authoritative specs:** `assets/api/rest_v1.yml` (OpenAPI 3.0) and `assets/api/websocket_v1.yml` (AsyncAPI 3.0). Always read the relevant spec before making calls — don't guess endpoint paths or payload shapes.

Prerequisites: `bash`, `curl`, `jq`, `websocat`, `flutter`, and POSIX `mkfifo` (macOS/Linux). Windows contributors run `flutter run` in a real terminal — see `doc/skills/streamline-bridge/lifecycle.md` for the Windows caveat.
```

**Step 3: Commit**

```bash
git add AGENTS.md
git commit -m "docs: point AGENTS.md at streamline-bridge skill"
```

---

## Phase 3: Dry-run — use the skill, don't trust it yet

### Task 16: Dry-run the skill against a real dev flow

**Files:** none (this task is verification-only).

**Step 1: Exercise every recipe end-to-end**

Run these in order, from a clean state. Do not cheat — if a step fails, the docs are wrong, not your memory.

```bash
# Clean slate
rm -rf /tmp/streamline-bridge-$USER/
pgrep -a -f "flutter run" && echo "kill existing first"

# From lifecycle.md
scripts/sb-dev.sh start --platform macos --connect-machine MockDe1 --connect-scale MockScale

# From rest.md
scripts/sb-dev.sh status
curl -sf http://localhost:8080/api/v1/devices | jq .
curl -sf http://localhost:8080/api/v1/machine/state | jq .
curl -sf http://localhost:8080/api/v1/machine/settings | jq .

# From websocket.md
timeout 3 websocat -t ws://localhost:8080/ws/v1/machine/snapshot | head -n 10 | jq .

# From verification.md
scripts/sb-dev.sh logs -n 20 --filter error || echo "no errors"
scripts/sb-dev.sh reload   # should complete even with no code change
scripts/sb-dev.sh stop
pgrep -a -f "flutter run" || echo "no orphans"
```

**Step 2: If any step fails, patch the relevant skill file first, commit the patch, then re-run**

The point of this task is that **the docs have to be right before MCP is deleted**. A broken recipe here means the migration will silently regress the developer experience.

**Step 3: No commit unless a doc patch is needed**

---

## Phase 4: Delete the MCP package

### Task 17: Find and remove all references to `packages/mcp-server/`

**Files:** TBD — depends on what grep finds.

**Step 1: Grep for references before deleting**

```bash
rg -n "mcp-server|mcp_server" --glob '!packages/mcp-server/**' --glob '!doc/plans/archive/**'
```

Expected locations (based on current state):
- `CLAUDE.md` — MCP Server architecture section, "Using MCP for verification" paragraph, "When using MCP hot reload" guidance, "Adding MCP tools" workflow, documentation list.
- `pubspec.yaml` — check whether `packages/mcp-server` is referenced as a dev dep or in path dependencies.
- Root `package.json` / `Makefile` / CI workflows — check for build/install hooks.
- `doc/RELEASE.md` or other docs referencing the MCP server.

**Step 2: Note each location; do not modify yet**

Write a short list to use in Task 18 + 19.

**Step 3: No commit yet**

---

### Task 18: Update `CLAUDE.md`

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Make these edits, in order**

1. Delete the `### MCP Server` subsection under "Architecture" entirely.
2. Replace the paragraph "**Using MCP for verification:** ..." under "MCP Server" with a pointer:
   > **Using `sb-dev` for verification:** Prefer `scripts/sb-dev.sh` + `curl` + `websocat` over manual `flutter run`. See `doc/skills/streamline-bridge/verification.md` for smoke-test recipes and per-change workflows.
3. Replace the "**When using MCP hot reload:** Always try `app_hot_reload` first ..." line (in the Conventions & Gotchas section or wherever it lives) with:
   > **When using `sb-dev` hot reload:** Prefer `sb-dev reload` (preserves state). Use `sb-dev hot-restart` if reload fails or state must reset. Use `sb-dev stop && sb-dev start` for a cold restart (fresh DB).
4. Delete the "Adding MCP tools" entry under "Common Workflows".
5. Under the "Adding a New API Endpoint" workflow, replace step 4 (the one about adding an MCP tool) with:
   > 4. Update `assets/api/rest_v1.yml` (or `websocket_v1.yml`) **in the same commit** as the handler change.
6. Under "Documentation", add a line:
   > - **`doc/skills/streamline-bridge/`** — Dev-loop skill (sb-dev, REST, WebSocket, simulated devices, verification recipes). Entry point: `doc/skills/streamline-bridge/README.md`.

**Step 2: Run `flutter analyze` as a sanity check** (nothing code-relevant changed, but habits):

```bash
flutter analyze
```

Expected: same issue count as before this task.

**Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: replace MCP references in CLAUDE.md with skill pointers"
```

---

### Task 19: Delete `packages/mcp-server/`

**Files:**
- Delete: `packages/mcp-server/` (entire directory)
- Modify: any file found in Task 17 that references `mcp-server` outside of archived plans

**Step 1: Check the root for package manifests that might reference the MCP package**

```bash
rg -n "mcp-server" package.json pubspec.yaml Makefile .github/workflows/ 2>/dev/null || echo "no matches"
```

If matches are found, remove those references.

**Step 2: Delete the directory**

```bash
git rm -rf packages/mcp-server
```

**Step 3: Verify nothing else breaks**

```bash
flutter pub get
flutter analyze
flutter test
```

Expected: all pass. Issue count matches the pre-task baseline.

**Step 4: Commit**

```bash
git commit -m "chore: delete packages/mcp-server — replaced by streamline-bridge skill"
```

---

## Phase 5: Final verification + PR

### Task 20: Run the full verification suite

**Files:** none.

**Step 1: Final end-to-end**

```bash
flutter analyze
flutter test
scripts/sb-dev.sh start --platform macos --connect-machine MockDe1
scripts/sb-dev.sh status
curl -sf http://localhost:8080/api/v1/machine/state | jq .
timeout 3 websocat -t ws://localhost:8080/ws/v1/machine/snapshot | head -5
scripts/sb-dev.sh reload
scripts/sb-dev.sh stop
pgrep -a -f "flutter run" || echo "no orphans"
```

Expected: each step succeeds.

**Step 2: Archive the plan and design doc**

```bash
mkdir -p doc/plans/archive/streamline-bridge-skill
git mv doc/plans/2026-04-14-streamline-bridge-skill.md doc/plans/archive/streamline-bridge-skill/
git mv doc/plans/2026-04-14-streamline-bridge-skill-design.md doc/plans/archive/streamline-bridge-skill/
git commit -m "docs: archive streamline-bridge skill plan and design"
```

**Step 3: Ask the user** whether to push and open a PR, per project convention in `CLAUDE.md`.

---

## Risks and escape hatches

1. **Flutter `run` refuses pipe stdin on some macOS/Flutter combo.**
   - Mitigation: the existing `AppManager` uses plain pipes and works today, so we have a working precedent.
   - Fallback: wrap `flutter_with_commit.sh run` in `expect -c 'spawn ... ; interact'` or `script -q /dev/null …`, or document "quit + start" instead of hot reload. Decide during Phase 1 if it comes up.

2. **`timeout` is GNU-specific; macOS may need `gtimeout` (from coreutils).**
   - Mitigation: websocat has `--max-messages` and `-n` (one-shot mode) — prefer those in the docs. Mention `gtimeout` for macOS users without coreutils.

3. **`websocat` not installed.**
   - Mitigation: install note at the top of `websocket.md`. Fallback command with `wscat` for users with Node installed.

4. **Context bloat** in `SKILL.md` — if agents load all sub-files eagerly.
   - Mitigation: `SKILL.md` routing table is the lever. Keep the body short. Sub-files are loaded on demand.

5. **Spec drift** — the whole skill falls apart if specs go stale.
   - Mitigation: `verification.md` is explicit, and `CLAUDE.md` has the "update spec in same commit" rule baked in. Optional follow-up (not in this plan): a pre-commit hook that flags modified handlers without a spec diff.
