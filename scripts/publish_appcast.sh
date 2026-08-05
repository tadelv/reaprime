#!/usr/bin/env bash
# Publish the Sparkle appcast for a tagged macOS release.
#
# Usage:
#   publish_appcast.sh <zip> <release-notes.md> <download-url-prefix> <channel> <key-file> <output>
#
#   <channel>          "beta" or "stable" (no channel is written for stable).
#   <key-file>         Path to the EdDSA private key, or "-" to read it from
#                      standard input (for a GitHub Actions secret).
#   <output>           Where the generated appcast.xml is written.
#
# Fails unless the ZIP's CFBundleVersion is strictly greater than every item
# already in the deployed feed, so Sparkle can always select the new update.
set -euo pipefail
source "$(dirname "$0")/appcast_helpers.sh"

ZIP="${1:?usage: publish_appcast.sh <zip> <notes.md> <url-prefix> <channel> <key-file> <output>}"
NOTES="${2:?}"
PREFIX="${3:?}"
CHANNEL="${4:?}"
KEY_FILE="${5:?}"
OUTPUT="${6:?}"

FEED_URL="https://decentespresso.github.io/decaid/appcast.xml"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp "$ZIP" "$STAGING/"
ZIP_BASENAME="$(basename "$ZIP")"
cp "$NOTES" "$STAGING/${ZIP_BASENAME%.zip}.md"

if curl -fsSL "$FEED_URL" -o "$STAGING/appcast.xml" 2>/dev/null; then
  echo "Fetched existing appcast from $FEED_URL"
else
  echo "No existing appcast reachable; generating a fresh feed"
fi

BUILD="$(zip_read_build "$ZIP")"
[ -n "$BUILD" ] || { echo "FAIL: could not read CFBundleVersion from $ZIP"; exit 1; }
echo "Release CFBundleVersion: $BUILD"

if [ -f "$STAGING/appcast.xml" ]; then
  MAX="$(appcast_max_build "$STAGING/appcast.xml")"
  echo "Existing feed max CFBundleVersion: ${MAX:-none}"
  assert_build_increasing "$BUILD" "$MAX"
fi

ARGS=(generate_appcast
  --ed-key-file "$KEY_FILE"
  --download-url-prefix "$PREFIX"
  --embed-release-notes
  --versions "$BUILD"
  --maximum-deltas 0
  --maximum-versions 0)
if [ "$CHANNEL" = "beta" ]; then
  ARGS+=(--channel beta)
elif [ "$CHANNEL" != "stable" ]; then
  echo "FAIL: unknown channel '$CHANNEL' (expected 'stable' or 'beta')" >&2
  exit 1
fi

echo "Running generate_appcast (channel: $CHANNEL)..."
"${ARGS[@]}" "$STAGING"

EXPECTED_CHANNEL=""
[ "$CHANNEL" = "beta" ] && EXPECTED_CHANNEL="beta"
appcast_assert_item "$STAGING/appcast.xml" "$BUILD" "${PREFIX}${ZIP_BASENAME}" "$EXPECTED_CHANNEL"
xmllint --noout "$STAGING/appcast.xml"
echo "Feed validated: version $BUILD, channel '${CHANNEL}'"

mkdir -p "$(dirname "$OUTPUT")"
cp "$STAGING/appcast.xml" "$OUTPUT"
echo "Appcast written to $OUTPUT"
