#!/usr/bin/env bash
# Symlink gitignored Flutter assets from the main checkout into lane worktrees.
# Required because pubspec.yaml references assets/plugins/dye2.reaplugin/ and
# assets/bundled_skins/, which are .gitignore'd and absent from git worktrees.
set -euo pipefail

ROOT="${SPINE_PROJECT_ROOT:-}"
WT="${SPINE_WORKTREE:-$(pwd)}"

if [[ -z "$ROOT" ]]; then
  echo '{"ok":false,"error":"SPINE_PROJECT_ROOT not set"}'
  exit 1
fi

link_dir() {
  local rel="$1"
  local src="${ROOT}/${rel}"
  local dst="${WT}/${rel}"
  if [[ -e "$src" ]]; then
    mkdir -p "$(dirname "$dst")"
    if [[ -e "$dst" && ! -L "$dst" ]]; then
      rm -rf "$dst"
    fi
    if [[ ! -e "$dst" ]]; then
      ln -s "$src" "$dst"
    fi
  fi
}

link_dir "assets/plugins/dye2.reaplugin"
link_dir "assets/bundled_skins"

echo '{"ok":true}'
