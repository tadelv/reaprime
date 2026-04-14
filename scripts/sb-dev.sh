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
    if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
      kill "$(cat "$PIDFILE")" 2>/dev/null || true
    fi
    cleanup_runtime
    return 1
  fi

  if [[ -n "$machine" ]]; then
    connect_machine "$machine" || true
  fi
}

cleanup_runtime() {
  if [[ -f "$HOLDER_PIDFILE" ]]; then
    kill "$(cat "$HOLDER_PIDFILE")" 2>/dev/null || true
    rm -f "$HOLDER_PIDFILE"
  fi
  rm -f "$PIDFILE" "$STDIN_FIFO"
}

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

case "$cmd" in
  help|-h|--help) usage; exit 0 ;;
  start) start_cmd "$@" ;;
  stop) stop_cmd ;;
  *) echo "Not yet implemented: $cmd" >&2; exit 2 ;;
esac
