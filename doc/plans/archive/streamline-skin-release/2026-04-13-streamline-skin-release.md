# Streamline Skin Release Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Ship working Streamline skin on Windows by cutting clean GitHub releases from a fork, consuming them via github_release in the bridge, and migrating persisted skin-id prefs.

**Architecture:** Two repos. Fork `tadelv/streamline_project` gets a GH Action that publishes both a `dist` branch (tracks main) and a tagged release zip from a bash-whitelisted staging dir. Bridge `tadelv/reaprime` swaps `skin_sources.json` from github_branch to github_release, updates 5 hardcoded refs, and adds one-shot pref migration `streamline_project-main` → `streamline.js`.

**Tech Stack:** Flutter/Dart (bridge), Bash + GitHub Actions (fork), `shared_preferences` for pref migration.

**Design doc:** `doc/plans/2026-04-13-streamline-skin-release-design.md`

---

## Layout

- **Part A** — fork work (outside reaprime repo)
- **Part B** — bridge work (inside reaprime repo, branch `feature/streamline-skin-release` already checked out)
- **Part C** — follow-up issue filing and PRs

Bridge and fork loosely coupled. Fork must tag v0.1.0 BEFORE bridge `bundle_skins.sh` can fetch real release. Part A finishes first.

---

# Part A — Fork: `tadelv/streamline_project`

Work happen outside reaprime tree. Clone fork somewhere like `~/development/repos/streamline_project_fork`.

## Task A1: Clone fork + make branch

**Files:** none in reaprime

**Step 1:** Clone fork

```bash
cd ~/development/repos
git clone git@github.com:tadelv/streamline_project.git streamline_project_fork
cd streamline_project_fork
```

**Step 2:** Verify remotes. Expect `origin = tadelv/streamline_project`. Add upstream.

```bash
git remote -v
git remote add upstream git@github.com:allofmeng/streamline_project.git
git fetch upstream
```

**Step 3:** Sync main with upstream so fork not stale

```bash
git checkout main
git pull upstream main
git push origin main
```

**Step 4:** Cut feature branch

```bash
git checkout -b feature/release-build
```

No commit yet.

---

## Task A2: Add `skin-manifest.json`

**Files:**
- Create: `skin-manifest.json` (fork repo root)

**Step 1:** Write file

```json
{
  "id": "streamline.js",
  "name": "Streamline.js",
  "description": "Modern, feature-complete WebUI skin for Streamline-Bridge",
  "version": "0.1.0"
}
```

**Step 2:** Check no existing `manifest.json` conflict at root

```bash
ls manifest.json 2>&1
```

If `manifest.json` exists and is a PWA manifest referenced from `index.html`, leave it alone — bridge prefer `skin-manifest.json` anyway (see `lib/src/webui_support/webui_storage.dart:999-1008` in bridge repo).

**Step 3:** Stage, no commit yet

```bash
git add skin-manifest.json
```

---

## Task A3: Add release workflow

**Files:**
- Create: `.github/workflows/release.yml`

**Step 1:** Make dir

```bash
mkdir -p .github/workflows
```

**Step 2:** Write workflow

```yaml
name: Build and Release Skin

on:
  push:
    branches: [main]
    tags: ['v*']

permissions:
  contents: write

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Stage whitelist into ./dist
        run: |
          set -euo pipefail
          mkdir -p dist
          # Whitelist — ONLY these paths become part of the skin.
          # Everything else in the repo (shots/, .DS_Store, AI agent dirs,
          # loose notes, TCL files, visulizer_REAPLUGIN/, figama_code/, etc.)
          # is excluded by construction, not by ignore rules.
          for path in index.html skin-manifest.json css modules profiles settings ui; do
            if [ -e "$path" ]; then
              cp -r "$path" dist/
            else
              echo "::warning::whitelist entry missing: $path"
            fi
          done

      - name: Validate skin-manifest.json
        run: |
          set -euo pipefail
          test -f dist/skin-manifest.json
          jq -e '.id == "streamline.js"' dist/skin-manifest.json > /dev/null
          jq -e '.version' dist/skin-manifest.json > /dev/null

      - name: Reject filenames with Win32 reserved chars
        run: |
          set -euo pipefail
          bad=$(find dist -type f | grep -E '[<>:"|?*]' || true)
          if [ -n "$bad" ]; then
            echo "::error::found filenames with Win32 reserved chars:"
            echo "$bad"
            exit 1
          fi

      # On every push to main: publish ./dist to the dist branch (orphan, force)
      - name: Deploy to dist branch
        if: github.ref == 'refs/heads/main'
        uses: peaceiris/actions-gh-pages@v3
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: ./dist
          publish_branch: dist
          force_orphan: true

      # On tag push: zip ./dist and publish a GitHub Release
      - name: Create release archive
        if: startsWith(github.ref, 'refs/tags/v')
        run: |
          cd dist
          zip -r ../streamline.js-${{ github.ref_name }}.zip .

      - name: Create GitHub Release
        if: startsWith(github.ref, 'refs/tags/v')
        uses: softprops/action-gh-release@v1
        with:
          files: streamline.js-${{ github.ref_name }}.zip
          generate_release_notes: true
```

**Step 3:** Stage

```bash
git add .github/workflows/release.yml
```

---

## Task A4: Add `RELEASE.md`

**Files:**
- Create: `RELEASE.md` (fork repo root)

**Step 1:** Write

```markdown
# Release Process

This repo uses a GitHub Action (`.github/workflows/release.yml`) that builds a sanitised snapshot of the skin from a whitelist of paths. Two triggers:

## `dist` branch — tracks `main`

Every push to `main` force-pushes a clean copy of the whitelist to the `dist` branch. This is the bleeding-edge dev channel. Downstream tools that want to follow main without waiting for a release can point at:

```
github_branch: <owner>/streamline_project@dist
```

## Tagged releases

Push a tag matching `v*` to cut a release:

```bash
git tag v0.1.0
git push origin v0.1.0
```

The action zips the staged whitelist as `streamline.js-v0.1.0.zip` and publishes a GitHub Release with auto-generated notes. Downstream tools consume this via:

```
github_release: <owner>/streamline_project
```

## Whitelist

Only these paths ship in the skin:

- `index.html`
- `skin-manifest.json`
- `css/`
- `modules/`
- `profiles/`
- `settings/`
- `ui/`

Anything else in the repo is excluded by construction. To add a new top-level path, edit the `Stage whitelist into ./dist` step in `.github/workflows/release.yml`.
```

**Step 2:** Stage

```bash
git add RELEASE.md
```

---

## Task A5: Commit fork changes

**Step 1:** Verify staged state

```bash
git status
git diff --cached --stat
```

Expected: 3 files (`skin-manifest.json`, `.github/workflows/release.yml`, `RELEASE.md`).

**Step 2:** Commit

```bash
git commit -m "$(cat <<'EOF'
feat: add release workflow and skin manifest

Adds a GitHub Action that publishes both a tracked `dist` branch
(clean whitelist snapshot of main) and tagged release zips. Build
pulls from a fixed whitelist — no bundler, no npm — so non-skin
junk (shots/, .DS_Store, AI agent dirs, etc.) is excluded by
construction, not by ignore rules.

Also adds `skin-manifest.json` with id `streamline.js` so
downstream consumers (Streamline-Bridge) can key installs
deterministically instead of falling back to the zip-root dir name.

Fixes the Windows install crash on Streamline-Bridge: the working
repo ships `shots/*.json` files with `:` in the filename (ISO
timestamps), which Windows `CreateFile` rejects with errno 123.
Release zip never contains those files.
EOF
)"
```

**Step 3:** Push

```bash
git push -u origin feature/release-build
```

---

## Task A6: Self-PR to tadelv main, verify dist branch

Self-PR is fine — the "PR per repo" rule applies here. We want CI to run the workflow once on main before tagging, so dist branch exists.

**Step 1:** Open PR

```bash
gh pr create \
  --repo tadelv/streamline_project \
  --base main \
  --head feature/release-build \
  --title "Add release workflow and skin manifest" \
  --body "$(cat <<'EOF'
## Summary
- Adds `.github/workflows/release.yml` that publishes both a `dist` branch (tracks main) and tagged release zips from a whitelisted staging dir.
- Adds `skin-manifest.json` declaring id `streamline.js`.
- Adds `RELEASE.md` documenting the process.

## Why
Streamline-Bridge currently consumes this repo via `github_branch` at main. That ships the entire working tree including `shots/*.json` files with `:` in the filename, which Windows rejects — Windows users cannot install the skin. This PR changes nothing in runtime code; it only adds a clean distribution mechanism.

## Test plan
- [ ] merge → watch Actions → `dist` branch created with whitelist contents
- [ ] tag `v0.1.0` → release zip published
- [ ] download zip, confirm no `:` in any filename, `skin-manifest.json` at root
EOF
)"
```

**Step 2:** Merge the PR (use squash so main history stays clean)

```bash
gh pr merge --repo tadelv/streamline_project --squash --delete-branch
```

**Step 3:** Wait for Actions to finish. Watch run.

```bash
gh run watch --repo tadelv/streamline_project
```

Expected: workflow fires on the merge commit, "Deploy to dist branch" step succeeds.

**Step 4:** Verify `dist` branch exists with whitelist contents

```bash
gh api repos/tadelv/streamline_project/branches/dist --jq .name
gh api 'repos/tadelv/streamline_project/git/trees/dist?recursive=1' --jq '.tree[] | select(.type=="blob") | .path' | head -30
```

Expected: `index.html`, `skin-manifest.json`, and files under `css/`, `modules/`, `profiles/`, `settings/`, `ui/`. No `shots/`, no `.DS_Store`, no `.claude/`, no `.gemini/`.

---

## Task A7: Tag v0.1.0, verify release

**Step 1:** Pull latest main locally

```bash
cd ~/development/repos/streamline_project_fork
git checkout main
git pull origin main
```

**Step 2:** Tag + push

```bash
git tag v0.1.0
git push origin v0.1.0
```

**Step 3:** Wait for Actions

```bash
gh run watch --repo tadelv/streamline_project
```

**Step 4:** Verify release

```bash
gh release view v0.1.0 --repo tadelv/streamline_project
```

Expected: release exists, asset `streamline.js-v0.1.0.zip` listed.

**Step 5:** Download + inspect zip

```bash
gh release download v0.1.0 --repo tadelv/streamline_project --pattern 'streamline.js-*.zip' -D /tmp/streamline-check
cd /tmp/streamline-check
unzip -l streamline.js-v0.1.0.zip | head -40
```

Confirm:
- `skin-manifest.json` present at top level
- `index.html` present
- no file path contains `:`
- no `shots/`, no `.DS_Store`, no AI agent dirs

Also check filenames for `:` paranoidly:

```bash
unzip -l streamline.js-v0.1.0.zip | grep ':' || echo "clean"
```

Expected: `clean`.

---

## Task A8: Open upstream PR to allofmeng

Separate PR from the self-PR. Head = `tadelv:main`, base = `allofmeng:main`.

**Step 1:** Open PR

```bash
gh pr create \
  --repo allofmeng/streamline_project \
  --base main \
  --head tadelv:main \
  --title "Add release workflow and skin manifest" \
  --body "$(cat <<'EOF'
## Summary

Adds a GitHub Action that publishes both a `dist` branch (tracks main) and tagged release zips, plus a `skin-manifest.json` at root. No runtime code touched.

## Why

Streamline-Bridge (the downstream consumer) currently pulls this repo as a `github_branch` zip of `main`. That ships the entire working tree — including `shots/*.json` files with `:` in the filename (ISO timestamps) — and Windows `CreateFile` rejects `:` with errno 123. **Windows users of Streamline-Bridge cannot currently install Streamline.js.** This PR gives Bridge a clean distribution channel without needing to clean the repo itself.

## What it adds

- `.github/workflows/release.yml` — single workflow, two triggers:
  - push to `main` → force-push a whitelisted staging tree to a new `dist` branch (bleeding-edge dev channel)
  - push tag `v*` → zip the same staging tree and publish a GitHub Release
- `skin-manifest.json` — declares skin `id`, `name`, `description`, `version`. Bridge prefers this over PWA `manifest.json`.
- `RELEASE.md` — documents how to cut a release.

## Whitelist

Only these paths ship in the skin:

- `index.html`, `skin-manifest.json`
- `css/`, `modules/`, `profiles/`, `settings/`, `ui/`

Everything else in the repo (`shots/`, `.DS_Store`, AI agent dirs, loose docs, `skin.tcl`, `visulizer_REAPLUGIN/`, etc.) is excluded **by construction**, so future repo pollution cannot slip into releases.

## Heads up

Merging this adds a force-pushed `dist` branch to the repo on every push to `main`. The branch is orphan with `force_orphan: true` in `peaceiris/actions-gh-pages@v3`, so no history accumulates.

## Verification

Already verified on `tadelv/streamline_project` (the fork this PR is coming from):
- `dist` branch populates correctly with whitelist contents
- `v0.1.0` tag produced a clean `streamline.js-v0.1.0.zip` with no filename issues

Once merged here, Streamline-Bridge will flip its `skin_sources.json` entry from `{type: github_branch, repo: allofmeng/streamline_project, branch: main}` to `{type: github_release, repo: allofmeng/streamline_project}`.
EOF
)"
```

**Step 2:** Record PR URL. Do NOT wait for merge. Bridge work proceeds pointing at `tadelv/streamline_project` in the interim.

---

# Part B — Bridge: `tadelv/reaprime`

Branch `feature/streamline-skin-release` already checked out.

## Task B1: Update `skin_sources.json`

**Files:**
- Modify: `skin_sources.json:8-12`

**Step 1:** Read current state

```bash
cat skin_sources.json
```

**Step 2:** Edit — replace the `github_branch` entry with `github_release: tadelv/streamline_project`:

```diff
   {
     "type": "github_release",
     "repo": "tadelv/baseline.js",
     "asset": "baseline-skin.zip",
     "prerelease": true
   },
   {
-    "type": "github_branch",
-    "repo": "allofmeng/streamline_project",
-    "branch": "main"
+    "type": "github_release",
+    "repo": "tadelv/streamline_project"
   },
   {
     "type": "github_release",
     "repo": "tadelv/extracto-patronum"
   },
```

**Step 3:** Verify still parses

```bash
jq . skin_sources.json > /dev/null && echo ok
```

No commit yet — batch bridge commits.

---

## Task B2: Harden `bundle_skins.sh` stale cleanup

**Files:**
- Modify: `bundle_skins.sh:22`

**Step 1:** Insert cleanup right after `mkdir -p "$CACHE_DIR" "$OUTPUT_DIR"`

```diff
 mkdir -p "$CACHE_DIR" "$OUTPUT_DIR"
+
+# Clear stale zips so removed/renamed skin_sources entries don't linger.
+# Cache dir is preserved to avoid re-downloading unchanged sources.
+rm -f "$OUTPUT_DIR"/*.zip "$OUTPUT_DIR"/manifest.json
 
 COUNT=$(jq length "$CONFIG")
```

**Step 2:** Syntax check

```bash
bash -n bundle_skins.sh && echo ok
```

---

## Task B3: Run bundle script, verify new zip

**Step 1:** Delete old bundled zip explicitly so we see the cleanup work

```bash
ls assets/bundled_skins/
```

Expected: old `streamline_project-main.zip` still listed.

**Step 2:** Run

```bash
./bundle_skins.sh
```

Expected: `github_release tadelv/streamline_project` line, successful download, "Bundled skin: streamline_project" line.

**Step 3:** Verify output

```bash
ls assets/bundled_skins/
```

Expected:
- `baseline.js.zip`
- `streamline_project.zip` (new, from release)
- `extracto-patronum.zip`
- `passione.zip`
- `manifest.json`
- **NO** `streamline_project-main.zip`

**Step 4:** Inspect new zip

```bash
unzip -l assets/bundled_skins/streamline_project.zip | head -40
unzip -p assets/bundled_skins/streamline_project.zip skin-manifest.json 2>&1 | jq .
unzip -l assets/bundled_skins/streamline_project.zip | grep ':' || echo "no colons"
```

Expected: `skin-manifest.json` present with `id: "streamline.js"`. No `:` anywhere.

**Step 5:** Check `manifest.json` regenerated

```bash
cat assets/bundled_skins/manifest.json
```

Expected: contains `"streamline_project"`, NOT `"streamline_project-main"`.

---

## Task B4: Update hardcoded skin id refs in `webui_storage.dart`

**Files:**
- Modify: `lib/src/webui_support/webui_storage.dart:230,235`

**Step 1:** Edit both lines

```diff
-    if (preferredSkinId != 'streamline_project-main') {
+    if (preferredSkinId != 'streamline.js') {
       _log.warning('Preferred skin "$preferredSkinId" not found, falling back to default');
     }

     // Try to find streamline-project as default
-    final streamlineSkin = _installedSkins['streamline_project-main'];
+    final streamlineSkin = _installedSkins['streamline.js'];
     if (streamlineSkin != null) {
```

**Step 2:** Verify no other stale refs

```bash
grep -rn "streamline_project-main" lib/ test/ skin_sources.json 2>&1
```

Expected at this point: only `test/helpers/mock_settings_service.dart:20` (next task) and `lib/src/settings/settings_service.dart:206` (task B5) remaining.

---

## Task B5: Update default + add migration in `settings_service.dart`

**Files:**
- Modify: `lib/src/settings/settings_service.dart:203-207`

**Step 1:** Replace the `defaultSkinId()` implementation with one-shot migration + new default

```diff
   @override
   Future<String> defaultSkinId() async {
-    return await prefs.getString(SettingsKeys.defaultSkinId.name) ??
-        'streamline_project-main';
+    final stored = await prefs.getString(SettingsKeys.defaultSkinId.name);
+    // One-shot migration: old bundled-skin id (github_branch naming) → new release id.
+    // The old id was derived from the GitHub branch zip's root folder; the new id comes
+    // from skin-manifest.json inside the release zip.
+    if (stored == 'streamline_project-main') {
+      await prefs.setString(
+        SettingsKeys.defaultSkinId.name,
+        'streamline.js',
+      );
+      return 'streamline.js';
+    }
+    return stored ?? 'streamline.js';
   }
```

Why inline (not a separate `migrate()` method): `SharedPreferencesSettingsService` has no `initialize()` method, no main.dart bootstrap hook, and lazy-loads via `SharedPreferencesAsync`. Inline in `defaultSkinId()` is idempotent, runs only on getter calls, and needs no new API surface. Exactly one persisted rewrite per user. YAGNI.

**Step 2:** Sanity check the diff

```bash
git diff lib/src/settings/settings_service.dart
```

---

## Task B6: Update `mock_settings_service.dart` test default

**Files:**
- Modify: `test/helpers/mock_settings_service.dart:20`

**Step 1:** Edit

```diff
-  String _defaultSkinId = 'streamline_project-main';
+  String _defaultSkinId = 'streamline.js';
```

**Step 2:** Confirm no stale refs remain anywhere

```bash
grep -rn "streamline_project-main" lib/ test/ skin_sources.json 2>&1
```

Expected: no matches.

---

## Task B7: Run `flutter analyze`

**Step 1:**

```bash
flutter analyze
```

Expected: no new issues introduced by the edits. Existing warnings unchanged.

If `analyze` reports anything on the touched files, fix before moving on. If pre-existing unrelated warnings appear, leave them.

---

## Task B8: Run `flutter test`

**Step 1:**

```bash
flutter test
```

Expected: all green. The `mock_settings_service.dart` default change is consumed by any onboarding/skin widget tests — they expect a skin in `_installedSkins` matching `_defaultSkinId`. The `MockSettingsService` is in-memory only; no migration code path runs through it.

If a test fails with something like "preferred skin 'streamline.js' not found", that test is probably seeding a fake skin list that still uses the old id. Search and update:

```bash
grep -rn "streamline_project-main" test/
```

Fix any hits found, re-run.

---

## Task B9: Manual smoke test — simulated mode

**Step 1:** Run app in simulate mode

```bash
flutter run --dart-define=simulate=1 -d macos
```

(Or `-d linux` / whatever local desktop target is handy. Real hardware not needed.)

**Step 2:** In the running app, confirm:
- Onboarding completes without errors
- Skin picker lists "Streamline.js"
- Picking it loads without crash
- Log contains `INFO WebUIStorage - Installed WebUI skin: streamline.js at ...`
- Log does NOT contain `SEVERE WebUIStorage - Failed to install WebUI from URL`
- Log does NOT contain `PathNotFoundException`

**Step 3:** Check the on-disk skin layout

```bash
find ~/Library/Containers/*/Data/Documents/web-ui -maxdepth 2 -type d 2>/dev/null | grep streamline
```

Or for non-sandboxed desktop:

```bash
find ~/Documents/web-ui -maxdepth 2 -type d 2>/dev/null | grep streamline
```

Expected: directory `streamline.js` exists with `skin-manifest.json` + whitelist contents inside.

**Step 4:** Kill app

---

## Task B10: MCP smoke test (optional but low-cost)

If MCP server configured, run a quick end-to-end check via `app_start` + `plugins_list` to confirm the web server comes up clean with the new skin bundled. Skip if not set up — `flutter test` + manual run covers the critical path.

---

## Task B11: Commit bridge changes

**Step 1:** Review

```bash
git status
git diff --stat
```

Expected files changed:
- `skin_sources.json`
- `bundle_skins.sh`
- `lib/src/webui_support/webui_storage.dart`
- `lib/src/settings/settings_service.dart`
- `test/helpers/mock_settings_service.dart`
- `assets/bundled_skins/streamline_project.zip` (new binary)
- `assets/bundled_skins/manifest.json` (regenerated)
- `assets/bundled_skins/streamline_project-main.zip` (deleted)

**Step 2:** Confirm no stray edits

```bash
git diff
```

**Step 3:** Commit

```bash
git add \
  skin_sources.json \
  bundle_skins.sh \
  lib/src/webui_support/webui_storage.dart \
  lib/src/settings/settings_service.dart \
  test/helpers/mock_settings_service.dart \
  assets/bundled_skins/

git commit -m "$(cat <<'EOF'
fix: consume streamline.js as a release, not a branch zip

The allofmeng/streamline_project repo is a working tree, not a
distribution. Its main branch ships shot snapshot files with ISO
timestamp names like 2025-09-12T16:04:38.049213.json — and Windows
CreateFile rejects `:` in filenames with errno 123, so every
Windows user's skin install crashes mid-extraction and they end
up with no Streamline skin at all.

Switch skin_sources.json from github_branch allofmeng/streamline_project
to github_release tadelv/streamline_project (temporary — will flip
to allofmeng/streamline_project once their PR merges and they tag).
The release zip is cut from a whitelisted staging dir by a GitHub
Action on the fork, so non-skin junk is excluded by construction.

New skin id is streamline.js (read from skin-manifest.json in the
release zip) instead of the old github_branch dir-name fallback
streamline_project-main. Added one-shot pref migration in
SharedPreferencesSettingsService.defaultSkinId() so existing users'
preferred-skin setting follows them to the new id.

Also: bundle_skins.sh now clears stale zips before rebuilding, so
removed/renamed entries in skin_sources.json don't leave orphaned
bundles under assets/bundled_skins/.

Reported by Nils B (Basecamp, 2026-04-11) on Windows build 3a7d5a7.
Design: doc/plans/2026-04-13-streamline-skin-release-design.md

Does NOT fix the underlying _installFromZip Windows path handling
or the _copyBundledSkins silent-swallow bug — both tracked as
separate follow-up PRs.
EOF
)"
```

---

# Part C — Follow-ups

## Task C1: File GitHub issue for `_installFromZip` Win32 path handling

**Step 1:**

```bash
gh issue create \
  --repo tadelv/reaprime \
  --title "WebUIStorage._installFromZip crashes on Windows-reserved filename chars" \
  --label bug \
  --body "$(cat <<'EOF'
## Problem

\`WebUIStorage._installFromZip\` at \`lib/src/webui_support/webui_storage.dart:1075-1086\` extracts zip entries with raw \`File.createSync\` and no per-entry try/catch. On Windows, any entry with a filename containing \`<>:\"|?*\` aborts the entire install — \`CreateFile\` returns errno 123 (\`ERROR_INVALID_NAME\`).

Hit in the wild when a user tried to install a skin whose zip contained ISO-timestamp JSON files (\`2025-09-12T16:04:38.049213.json\`). See Basecamp report (Nils B, 2026-04-11) and the release-based fix landed in #TBD.

## Fix

1. Wrap each per-entry \`createSync\` + \`writeAsBytesSync\` in a try/catch: log + skip, not abort.
2. Sanitise Win32 reserved chars in destination filename before write: replace \`<>:\"|?*\` with \`_\`.
3. On the sanitised path also strip trailing dots/spaces (another Win32 landmine).

## Why separate PR

Per the design for the release-based fix: \"skins might have hardcoded paths, better to break hard than half work.\" Silent sanitisation could mask a mismatched manifest reference. Ship as its own change with its own test + release note.

## Test plan

- Synthetic zip with a file named \`bad:name.txt\` → install should succeed on Windows with that file silently skipped (and a \`warning\` log line).
- Existing well-formed skins unaffected on macOS/Linux.
EOF
)"
```

## Task C2: File GitHub issue for `_copyBundledSkins` silent-swallow

**Step 1:**

```bash
gh issue create \
  --repo tadelv/reaprime \
  --title "WebUIStorage._copyBundledSkins silently drops every later skin on any extraction failure" \
  --label bug \
  --body "$(cat <<'EOF'
## Problem (not Windows-specific)

\`WebUIStorage._copyBundledSkins\` at \`lib/src/webui_support/webui_storage.dart:912-940\` iterates the bundled skin zips in \`assets/bundled_skins/manifest.json\`, calling \`_installFromZip\` on each. The **entire loop** is wrapped in one outer \`try/catch\` that:

1. Catches any exception from any skin in the loop
2. **Breaks out** of the loop — every remaining bundled skin is silently skipped
3. Logs at \`fine\` level, which is below the default log filter — the failure is **invisible** in user logs

This means any single bad bundled zip — corrupted asset, missing file, JSON parse error, Windows path crash, OOM, whatever — kills every skin after it in the iteration order. Users report \"my skin disappeared\" and there's nothing to grep for.

This was surfaced during the Streamline.js Windows release fix (see #TBD) but the bug itself is platform-agnostic.

## Fix sketch

\`\`\`dart
for (final skinId in skinIds) {
  try {
    final destDir = Directory('\${_webUIDir.path}/\$skinId');
    if (destDir.existsSync() && destDir.listSync().isNotEmpty) {
      _log.fine('Bundled skin already exists: \$skinId');
      continue;
    }
    final zipData = await rootBundle.load('assets/bundled_skins/\$skinId.zip');
    final tempFile = File('\${_webUIDir.path}/\$skinId.zip');
    await tempFile.writeAsBytes(zipData.buffer.asUint8List());
    try {
      await _installFromZip(tempFile.path);
      _log.info('Installed bundled skin from asset: \$skinId');
    } finally {
      if (tempFile.existsSync()) await tempFile.delete();
    }
  } catch (e, st) {
    _log.warning('Failed to install bundled skin \"\$skinId\"', e, st);
    // keep going — do NOT abort the whole loop
  }
}
\`\`\`

The outer \`try/catch\` should only cover the \`manifest.json\` load, so a missing/malformed bundled manifest logs \`warning\` instead of the current \`fine\`.

## Priority

High. Has been dropping skins silently for an unknown duration. Schedule alongside the \`_installFromZip\` hardening PR — they touch the same area and share testing surface.
EOF
)"
```

## Task C3: Open bridge PR

**Step 1:** Push

```bash
git push -u origin feature/streamline-skin-release
```

**Step 2:** Open PR

```bash
gh pr create \
  --repo tadelv/reaprime \
  --base main \
  --head feature/streamline-skin-release \
  --title "fix: consume streamline.js skin as a release, not a branch zip" \
  --body "$(cat <<'EOF'
## Summary

- Switch \`skin_sources.json\` from \`github_branch allofmeng/streamline_project\` → \`github_release tadelv/streamline_project\` (temporary, will flip to \`allofmeng\` once their upstream PR merges and they tag)
- New skin id \`streamline.js\` everywhere, migrated from old \`streamline_project-main\`
- \`bundle_skins.sh\` now clears stale zips before rebuilding

## Why

Windows users cannot currently install the Streamline skin. The github_branch zip contains shot snapshot files like \`2025-09-12T16:04:38.049213.json\`, and Windows \`CreateFile\` rejects \`:\` in filenames with errno 123. Fix routes around the problem by shipping a clean release cut from a whitelisted staging dir in the fork.

Reported by Nils B (Basecamp, 2026-04-11) on build \`3a7d5a7\`.

## Files

- \`skin_sources.json\` — entry type swap
- \`bundle_skins.sh\` — stale-zip cleanup
- \`lib/src/webui_support/webui_storage.dart\` — 2 hardcoded id refs updated
- \`lib/src/settings/settings_service.dart\` — new default + one-shot pref migration
- \`test/helpers/mock_settings_service.dart\` — test default updated
- \`assets/bundled_skins/\` — regenerated, old zip removed, new zip added

## Out of scope (tracked separately)

- \`_installFromZip\` Windows path sanitisation (issue #TBD)
- \`_copyBundledSkins\` silent-swallow bug — not Windows-specific (issue #TBD)
- Retry storm in \`downloadRemoteSkins\`

## Test plan

- [x] \`flutter analyze\` clean
- [x] \`flutter test\` green
- [x] \`bundle_skins.sh\` produces clean \`streamline_project.zip\` with \`skin-manifest.json\` (\`id: streamline.js\`) and no \`:\` in filenames
- [x] Manual: \`flutter run --dart-define=simulate=1\`, skin picker shows \"Streamline.js\", loads without crash
- [ ] Manual (Windows): reproduce Nils's flow on a real Windows box if available
- [ ] Follow-up PR flips \`tadelv\` → \`allofmeng\` in \`skin_sources.json\` once upstream merges + tags

## Design doc

\`doc/plans/2026-04-13-streamline-skin-release-design.md\`
EOF
)"
```

**Step 3:** Record PR URL.

**Step 4:** Do NOT merge. Wait for user to say ship it.

---

# Execution ordering recap

Fork must tag v0.1.0 before bridge `bundle_skins.sh` can fetch a real release. Strict order:

1. A1 → A7 (fork: branch, files, self-PR, merge, tag, verify release)
2. A8 (open upstream PR — async, don't block on it)
3. B1 → B3 (bridge: swap sources, run bundle, verify new zip)
4. B4 → B6 (bridge: code edits)
5. B7 → B8 (bridge: analyze + test)
6. B9 (bridge: manual smoke test)
7. B10 (optional MCP smoke)
8. B11 (bridge: commit)
9. C1 → C2 (file follow-up issues so the PR body can link them)
10. C3 (bridge PR)

When allofmeng merges upstream PR and tags: separate tiny bridge PR flips `tadelv/streamline_project` → `allofmeng/streamline_project` in `skin_sources.json`. Not in this plan.
