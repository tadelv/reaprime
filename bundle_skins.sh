#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/skin_sources.json"
CACHE_DIR="$SCRIPT_DIR/.skin_cache"
OUTPUT_DIR="$SCRIPT_DIR/assets/bundled_skins"

if [ ! -f "$CONFIG" ]; then
  echo "Warning: skin_sources.json not found, skipping skin bundling"
  exit 0
fi

if ! command -v jq &> /dev/null; then
  echo "Warning: jq not found, skipping skin bundling (install with: brew install jq)"
  exit 0
fi

mkdir -p "$CACHE_DIR" "$OUTPUT_DIR"

COUNT=$(jq length "$CONFIG")

for ((i=0; i<COUNT; i++)); do
  TYPE=$(jq -r ".[$i].type" "$CONFIG")
  REPO=$(jq -r ".[$i].repo" "$CONFIG")
  REPO_NAME=$(echo "$REPO" | cut -d'/' -f2)

  echo "--- Processing source $((i+1))/$COUNT: $TYPE $REPO ---"

  case "$TYPE" in
    github_release)
      ASSET=$(jq -r ".[$i].asset // empty" "$CONFIG")
      PRERELEASE=$(jq -r ".[$i].prerelease // false" "$CONFIG")

      if [ "$PRERELEASE" = "true" ]; then
        RELEASE_JSON=$(curl -sfL "https://api.github.com/repos/$REPO/releases" \
          -H "Accept: application/vnd.github.v3+json" \
          -H "User-Agent: Streamline-Bridge-Build" 2>/dev/null) || { echo "Warning: Failed to fetch releases for $REPO"; continue; }
        RELEASE_JSON=$(echo "$RELEASE_JSON" | jq '.[0]')
      else
        RELEASE_JSON=$(curl -sfL "https://api.github.com/repos/$REPO/releases/latest" \
          -H "Accept: application/vnd.github.v3+json" \
          -H "User-Agent: Streamline-Bridge-Build" 2>/dev/null) || { echo "Warning: Failed to fetch latest release for $REPO"; continue; }
      fi

      TAG=$(echo "$RELEASE_JSON" | jq -r '.tag_name')

      if [ -n "$ASSET" ]; then
        DOWNLOAD_URL=$(echo "$RELEASE_JSON" | jq -r ".assets[] | select(.name == \"$ASSET\") | .browser_download_url")
      else
        DOWNLOAD_URL=$(echo "$RELEASE_JSON" | jq -r '.assets[] | select(.name | endswith(".zip")) | .browser_download_url' | head -1)
      fi

      if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ]; then
        echo "Warning: No download URL found for $REPO, skipping"
        continue
      fi

      CACHE_KEY=$(echo "$REPO_NAME-$TAG" | tr '/' '-')
      CACHE_FILE="$CACHE_DIR/$CACHE_KEY.zip"
      SKIN_ID="$REPO_NAME"

      if [ -f "$CACHE_FILE" ]; then
        echo "Using cached: $CACHE_FILE"
      else
        echo "Downloading: $DOWNLOAD_URL"
        curl -sfL -o "$CACHE_FILE" "$DOWNLOAD_URL" || { echo "Warning: Download failed for $REPO"; continue; }
      fi

      cp "$CACHE_FILE" "$OUTPUT_DIR/$SKIN_ID.zip"
      echo "Bundled skin: $SKIN_ID"
      ;;

    github_branch)
      BRANCH=$(jq -r ".[$i].branch // \"main\"" "$CONFIG")
      URL="https://github.com/$REPO/archive/refs/heads/$BRANCH.zip"
      SKIN_ID="${REPO_NAME}-${BRANCH}"
      CACHE_FILE="$CACHE_DIR/${SKIN_ID}.zip"

      echo "Downloading: $URL"
      curl -sfL -o "$CACHE_FILE" "$URL" || { echo "Warning: Download failed for $REPO/$BRANCH"; continue; }

      cp "$CACHE_FILE" "$OUTPUT_DIR/$SKIN_ID.zip"
      echo "Bundled skin: $SKIN_ID"
      ;;

    *)
      echo "Warning: Unknown source type '$TYPE', skipping"
      continue
      ;;
  esac
done

# Generate manifest
echo "[" > "$OUTPUT_DIR/manifest.json"
FIRST=true
for ZIP in "$OUTPUT_DIR"/*.zip; do
  [ -f "$ZIP" ] || continue
  SKIN_NAME=$(basename "$ZIP" .zip)
  if [ "$FIRST" = true ]; then FIRST=false; else echo "," >> "$OUTPUT_DIR/manifest.json"; fi
  printf '  "%s"' "$SKIN_NAME" >> "$OUTPUT_DIR/manifest.json"
done
echo "" >> "$OUTPUT_DIR/manifest.json"
echo "]" >> "$OUTPUT_DIR/manifest.json"

echo "--- Done: $(ls -1 "$OUTPUT_DIR"/*.zip 2>/dev/null | wc -l | tr -d ' ') skins bundled ---"
