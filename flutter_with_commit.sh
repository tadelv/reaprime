#!/usr/bin/env bash
set -e

# --- Collect git info safely ---
COMMIT=$(git rev-parse HEAD 2>/dev/null || echo unknown)
COMMIT_SHORT=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)
BUILD_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# --- At least one argument must be the flutter subcommand ---
if [ $# -lt 1 ]; then
  echo "Usage: $0 <flutter command> [arguments...]"
  echo
  echo "Examples:"
  echo "  $0 run -d chrome"
  echo "  $0 build apk --release"
  exit 1
fi

# First argument = flutter subcommand (run, build, test, etc.)
COMMAND="$1"
shift # remove the command from the list

# All remaining arguments go untouched into flutter
EXTRA_ARGS=("$@")

# --- Run flutter with injected commit information ---
flutter "$COMMAND" \
  --dart-define=COMMIT="$COMMIT" \
  --dart-define=COMMIT_SHORT="$COMMIT_SHORT" \
  --dart-define=BRANCH="$BRANCH" \
  --dart-define=BUILD_TIME="$BUILD_TIME" \
  "${EXTRA_ARGS[@]}"
