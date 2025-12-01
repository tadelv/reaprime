#!/usr/bin/env bash
set -e

# --- Collect git info safely ---
COMMIT=$(git rev-parse HEAD 2>/dev/null || echo unknown)
COMMIT_SHORT=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)
BUILD_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# --- Command required ---
if [ $# -lt 1 ]; then
  echo "Usage: $0 <flutter command> [arguments...]"
  exit 1
fi

COMMAND="$1"
shift

EXTRA_ARGS=("$@")

# --- Handle 'flutter build <target> ...' correctly ---
if [ "$COMMAND" = "build" ]; then
    if [ ${#EXTRA_ARGS[@]} -lt 1 ]; then
      echo "Error: flutter build requires a target (e.g., macos)"
      exit 1
    fi

    TARGET="${EXTRA_ARGS[0]}"
    REMAINDER=("${EXTRA_ARGS[@]:1}")

    flutter build "$TARGET" \
      --dart-define=COMMIT="$COMMIT" \
      --dart-define=COMMIT_SHORT="$COMMIT_SHORT" \
      --dart-define=BRANCH="$BRANCH" \
      --dart-define=BUILD_TIME="$BUILD_TIME" \
      "${REMAINDER[@]}"

    exit $?
fi

# --- All other commands (flutter run, test, analyze, etc.) ---
flutter "$COMMAND" \
  --dart-define=COMMIT="$COMMIT" \
  --dart-define=COMMIT_SHORT="$COMMIT_SHORT" \
  --dart-define=BRANCH="$BRANCH" \
  --dart-define=BUILD_TIME="$BUILD_TIME" \
  "${EXTRA_ARGS[@]}"
