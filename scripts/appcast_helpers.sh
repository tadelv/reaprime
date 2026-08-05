#!/usr/bin/env bash
# Pure appcast helpers for the Sparkle publish job. Sourced by
# publish_appcast.sh and exercised by test_appcast_helpers.sh. All functions
# exit non-zero on failure so callers can fail fast.

# Largest sparkle:version (CFBundleVersion) among all appcast items.
# Empty string when the feed has no items.
appcast_max_build() {
  local appcast="$1"
  xmllint --xpath \
    '//*[local-name()="item"]/*[local-name()="version"]/text()' \
    "$appcast" 2>/dev/null | tr ' ' '\n' | sort -n | tail -1
}

# Refuse publishing an update Sparkle can never select (equal/lower build).
assert_build_increasing() {
  local new="$1" existing="$2"
  if [ -n "$existing" ] && [ "$new" -le "$existing" ]; then
    echo "FAIL: new CFBundleVersion $new is not greater than existing $existing"
    return 1
  fi
}

# Read CFBundleVersion out of a Decaid macOS release ZIP.
zip_read_build() {
  local zip="$1"
  unzip -p "$zip" "Decaid.app/Contents/Info.plist" \
    | plutil -extract CFBundleVersion raw -
}

# "total default-channel-count" pair for the feed.
appcast_item_counts() {
  local appcast="$1"
  local total default_count
  total=$(xmllint --xpath 'count(//*[local-name()="item"])' "$appcast" 2>/dev/null)
  default_count=$(xmllint --xpath \
    'count(//*[local-name()="item"][not(*[local-name()="channel"])])' "$appcast" 2>/dev/null)
  echo "$total $default_count"
}

# Reject a feed that shrank: a beta publication must never erase stable or
# historical items.
assert_item_counts_not_decreased() {
  local old_pair="$1" appcast="$2"
  local old_total old_default new_total new_default
  read -r old_total old_default <<< "$old_pair"
  read -r new_total new_default <<< "$(appcast_item_counts "$appcast")"
  [ "$new_total" -ge "$old_total" ] || {
    echo "FAIL: feed item count decreased ($old_total -> $new_total)"; return 1; }
  [ "$new_default" -ge "$old_default" ] || {
    echo "FAIL: default-channel item count decreased ($old_default -> $new_default)"; return 1; }
}

# Assert the item for $build carries the expected enclosure URL, an EdDSA
# signature, and the expected channel ("" for the default/stable channel).
appcast_assert_item() {
  local appcast="$1" build="$2" expected_url="$3" expected_channel="$4"

  local url sig
  url=$(xmllint --xpath \
    "string(//*[local-name()=\"item\"][*[local-name()=\"version\"]=\"$build\"]/*[local-name()=\"enclosure\"]/@url)" \
    "$appcast" 2>/dev/null)
  [ "$url" = "$expected_url" ] || {
    echo "FAIL: item $build url '$url' != '$expected_url'"; return 1; }

  sig=$(xmllint --xpath \
    "string(//*[local-name()=\"item\"][*[local-name()=\"version\"]=\"$build\"]/*[local-name()=\"enclosure\"]/@*[local-name()=\"edSignature\"])" \
    "$appcast" 2>/dev/null)
  [ -n "$sig" ] || {
    echo "FAIL: item $build has no edSignature"; return 1; }

  local channel_count
  channel_count=$(xmllint --xpath \
    "count(//*[local-name()=\"item\"][*[local-name()=\"version\"]=\"$build\"]/*[local-name()=\"channel\"])" \
    "$appcast" 2>/dev/null)
  if [ -z "$expected_channel" ]; then
    [ "$channel_count" = "0" ] || {
      echo "FAIL: stable item $build must not carry a sparkle:channel"; return 1; }
  else
    [ "$channel_count" = "1" ] || {
      echo "FAIL: item $build must carry exactly one sparkle:channel"; return 1; }
    local actual
    actual=$(xmllint --xpath \
      "string(//*[local-name()=\"item\"][*[local-name()=\"version\"]=\"$build\"]/*[local-name()=\"channel\"])" \
      "$appcast" 2>/dev/null)
    [ "$actual" = "$expected_channel" ] || {
      echo "FAIL: item $build channel '$actual' != '$expected_channel'"; return 1; }
  fi
}
