#!/usr/bin/env bash
# Install the DYE2 plugin from its release repo into assets/plugins/dye2.reaplugin/.
#
# Usage:
#   fetch_dye2_plugin.sh
#
# Environment:
#   DYE2_REPO     Release repo (default allofmeng/dye2).
#   DYE2_VERSION  Release tag, e.g. v0.1.4 (default: latest release).
#   GH_TOKEN      GitHub token for `gh` (set to secrets.GITHUB_TOKEN in CI).
#
# The plugin used to be built from packages/dye2-plugin; it now ships as a
# release asset (dye2.reaplugin-<tag>.zip) containing the dye2.reaplugin/
# folder that pubspec.yaml declares as an asset directory.
set -euo pipefail

repo="${DYE2_REPO:-allofmeng/dye2}"
version="${DYE2_VERSION:-}"
plugins_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/assets/plugins"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

gh release download ${version:+"$version"} \
  --repo "$repo" --pattern 'dye2.reaplugin-*.zip' --dir "$tmp"

zip="$(ls "$tmp"/*.zip 2>/dev/null | head -n 1)"
if [ -z "$zip" ]; then
  echo "fetch_dye2_plugin: no dye2.reaplugin-*.zip asset in $repo ${version:-latest}" >&2
  exit 1
fi

mkdir -p "$plugins_dir"
rm -rf "$plugins_dir/dye2.reaplugin"
# ponytail: unzip on ubuntu/macos, bsdtar on windows runners (no unzip there).
if command -v unzip >/dev/null 2>&1; then
  unzip -q "$zip" -d "$plugins_dir"
else
  tar -xf "$zip" -C "$plugins_dir"
fi

for f in manifest.json plugin.js; do
  if [ ! -s "$plugins_dir/dye2.reaplugin/$f" ]; then
    echo "fetch_dye2_plugin: $(basename "$zip") is missing dye2.reaplugin/$f" >&2
    exit 1
  fi
done

echo "fetch_dye2_plugin: installed $(basename "$zip") -> $plugins_dir/dye2.reaplugin"
