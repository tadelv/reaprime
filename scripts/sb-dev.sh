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
