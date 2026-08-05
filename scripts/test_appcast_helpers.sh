#!/usr/bin/env bash
# Fixture test for scripts/appcast_helpers.sh. Run from the repo root:
#   scripts/test_appcast_helpers.sh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/appcast_helpers.sh

FAILURES=0
fail() { echo "FAIL: $1"; FAILURES=$((FAILURES + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- Fixture appcast: stable build 100, beta build 101 ---
cat > "$TMP/fixture.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Decaid Changelog</title>
    <item>
      <title>Version 2.0.0</title>
      <sparkle:version>101</sparkle:version>
      <sparkle:channel>beta</sparkle:channel>
      <enclosure url="https://github.com/decentespresso/decaid/releases/download/v2.0.0/decaid-macos-2.0.0.zip"
                 sparkle:edSignature="AA==" type="application/octet-stream"/>
    </item>
    <item>
      <title>Version 1.9.0</title>
      <sparkle:version>100</sparkle:version>
      <enclosure url="https://github.com/decentespresso/decaid/releases/download/v1.9.0/decaid-macos-1.9.0.zip"
                 sparkle:edSignature="BB==" type="application/octet-stream"/>
    </item>
  </channel>
</rss>
XML

MAX="$(appcast_max_build "$TMP/fixture.xml")"
[ "$MAX" = "101" ] || fail "appcast_max_build expected 101, got '$MAX'"
echo "ok: appcast_max_build = $MAX"

assert_build_increasing 102 101 && echo "ok: 102 > 101 accepted"
if assert_build_increasing 101 101 >/dev/null 2>&1; then
  fail "assert_build_increasing accepted equal build 101"
fi
if assert_build_increasing 100 101 >/dev/null 2>&1; then
  fail "assert_build_increasing accepted lower build 100"
fi

# --- Fake release ZIP ---
mkdir -p "$TMP/zip/Decaid.app/Contents"
cat > "$TMP/zip/Decaid.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleShortVersionString</key><string>2.1.0</string>
  <key>CFBundleVersion</key><string>102</string>
</dict></plist>
PLIST
ditto -c -k --keepParent "$TMP/zip/Decaid.app" "$TMP/decaid-macos-2.1.0.zip"

BUILD="$(zip_read_build "$TMP/decaid-macos-2.1.0.zip")"
[ "$BUILD" = "102" ] || fail "zip_read_build expected 102, got '$BUILD'"
echo "ok: zip_read_build = $BUILD"

# --- Item assertions ---
appcast_assert_item "$TMP/fixture.xml" 101 \
  "https://github.com/decentespresso/decaid/releases/download/v2.0.0/decaid-macos-2.0.0.zip" \
  "beta" && echo "ok: beta item assertions pass"

# --- Count assertions ---
read -r TOTAL DEFAULT_COUNT <<< "$(appcast_item_counts "$TMP/fixture.xml")"
[ "$TOTAL" = "2" ] || fail "appcast_item_counts total expected 2, got '$TOTAL'"
[ "$DEFAULT_COUNT" = "1" ] || fail "appcast_item_counts default expected 1, got '$DEFAULT_COUNT'"
echo "ok: appcast_item_counts = $TOTAL total, $DEFAULT_COUNT default"

assert_item_counts_not_decreased "$TOTAL $DEFAULT_COUNT" "$TMP/fixture.xml" \
  && echo "ok: equal counts accepted"
if assert_item_counts_not_decreased "3 2" "$TMP/fixture.xml" >/dev/null 2>&1; then
  fail "assert_item_counts_not_decreased accepted a shrunken feed"
fi

if appcast_assert_item "$TMP/fixture.xml" 101 \
  "https://github.com/decentespresso/decaid/releases/download/v2.0.0/decaid-macos-2.0.0.zip" \
  "stable" >/dev/null 2>&1; then
  fail "appcast_assert_item accepted a beta item as stable"
fi

if appcast_assert_item "$TMP/fixture.xml" 100 \
  "https://example.com/wrong.zip" "stable" >/dev/null 2>&1; then
  fail "appcast_assert_item accepted a wrong enclosure URL"
fi

if [ "$FAILURES" -ne 0 ]; then
  echo "$FAILURES assertion(s) failed"
  exit 1
fi
echo "All appcast helper tests passed"
