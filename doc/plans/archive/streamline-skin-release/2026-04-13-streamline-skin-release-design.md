# Streamline skin — switch from github_branch to github_release

**Date:** 2026-04-13
**Branch (bridge):** `feature/streamline-skin-release`
**Fork (upstreaming vehicle):** `tadelv/streamline_project`
**Completion:** PR on both repos (bridge + upstream PR to `allofmeng/streamline_project`)
**Reporter:** Nils B — Basecamp, 2026-04-11, build `3a7d5a7`

---

## Problem

Windows users cannot install the Streamline skin. From Nils B's log (`/tmp/bc_windows_log.txt`):

```
SEVERE WebUIStorage - Failed to install WebUI from URL: https://github.com/allofmeng/streamline_project/archive/refs/heads/main.zip
### PathNotFoundException: PathNotFoundException: Cannot create file,
  path = '...\temp_webui_extract\streamline_project-main\shots\2025-09-12T16:04:38.049213.json'
  (OS Error: Die Syntax für den Dateinamen, Verzeichnisnamen oder die Datenträgerbezeichnung ist falsch, errno = 123)
#2  WebUIStorage._installFromZip (webui_storage.dart:1081)
```

**Root cause.** `allofmeng/streamline_project` is a working repo, not a release repo. It ships non-skin junk (`shots/`, `.DS_Store`, AI-agent dirs, loose notes, TCL files, `visulizer_REAPLUGIN/`, loose CSV/JSON dumps). Crucially `shots/` contains files with ISO timestamp names like `2025-09-12T16:04:38.049213.json`. Windows `CreateFile` rejects `:` in filenames (`ERROR_INVALID_NAME` / errno 123). `WebUIStorage._installFromZip` extracts entries with raw `createSync()` and no per-entry try/catch, so the first `:` aborts the entire zip extraction. Streamline skin never lands on the user's machine.

**Same crash fires on two code paths in the same session:**

1. **Bundled asset install** at app start (`_copyBundledSkins` → `_installFromZip` on `assets/bundled_skins/streamline_project-main.zip`). The outer `try/catch` at `lib/src/webui_support/webui_storage.dart:938` logs the failure at `fine` level and silently continues — no visible symptom, just a missing skin.
2. **Remote re-download** during `downloadRemoteSkins` (`_installFromUrlAsRemoteBundled` → `_installFromZip` on the temp zip). Logs `SEVERE`, retries every init/restart — 7× in Nils's session, no backoff.

> **Important:** the silent swallow in path (1) is **not Windows-specific**. Any bundled skin zip whose first extraction error hits this block on any platform will kill every *remaining* bundled install in the same loop and leave no visible error — only a `fine`-level log line saying "No bundled skin zips found in assets: …". This has been ambient for a while; Nils's crash only surfaced it. It is called out here, but the fix is **out of scope for this PR** — tracked as a follow-up (see "Deferred").

---

## Goals

1. Windows users get a working Streamline skin on next build.
2. Other platforms unaffected.
3. Existing users' skin preference survives the id change.
4. The fix also hardens the skin supply chain so future releases are built artefacts, not raw working-repo snapshots.
5. The fork change is framed as an **upstreaming vehicle**, not a replacement of allofmeng's canonical repo.

## Non-goals

- Fixing the Win32 path-sanitisation bug in `_installFromZip` itself — separate PR (better to fail hard than silently half-install).
- Fixing the silent-swallow bug in `_copyBundledSkins` — separate PR (see "Deferred").
- Fixing the retry storm — deferred, low priority.
- Cleaning the upstream allofmeng repo — out of scope; whitelist zipping sidesteps the pollution at build time.

---

## Design

### Part 1 — streamline_project fork: build + release

**Repo:** `tadelv/streamline_project` (fork of `allofmeng/streamline_project`)
**Branch:** `feature/release-build`
**Final target:** PR into `allofmeng/streamline_project:main`

#### New files

- `.github/workflows/release.yml` — triggered on `v*` tags. No npm, no bundler. Steps:
  1. Checkout
  2. Validate: check that `skin-manifest.json` exists and has `id == "streamline.js"`
  3. Create release zip from a fixed whitelist (bash `zip -r`):
     - `index.html`
     - `skin-manifest.json`
     - `css/`
     - `modules/`
     - `profiles/`
     - `settings/`
     - `ui/`
     - Anything else added to the whitelist deliberately
  4. Publish as GitHub Release asset `streamline.js-<tag>.zip` using `softprops/action-gh-release@v1`

  Everything else in the repo — `shots/`, `.DS_Store`, AI agent dirs, loose notes, `skin.tcl`, `visulizer_REAPLUGIN/`, `figama_code/`, CSVs, log dumps — is **excluded by construction**, not by ignore rules. Whitelisting means future repo pollution cannot slip into releases.

- `skin-manifest.json` at repo root:
  ```json
  {
    "id": "streamline.js",
    "name": "Streamline.js",
    "description": "Modern, feature-complete WebUI skin for Streamline-Bridge",
    "version": "0.1.0"
  }
  ```
  Using `skin-manifest.json` (not `manifest.json`) because `index.html` may reference a PWA `manifest.json` with a different schema. `WebUIStorage._installFromDirectory` and `_scanInstalledSkins` both prefer `skin-manifest.json` over `manifest.json`.

- `RELEASE.md` (short) — document the release process: "tag `vX.Y.Z` on main → GH Action builds the whitelist zip → release published automatically".

#### Tag + release

- After the PR is merged to `tadelv/streamline_project:main` (for the interim), maintainer tags `v0.1.0`.
- GH Action builds and publishes `streamline.js-v0.1.0.zip`.
- Verified by downloading and inspecting the zip: must contain only whitelisted paths, must have `skin-manifest.json` at root, must have no `:` in any filename.

#### dist branch (tracks main)

**Yes — add it.** `extracto-patronum/.github/workflows/deploy.yml` already runs two jobs from one workflow: on `push main` it force-pushes a built `./dist` to a `dist` branch via `peaceiris/actions-gh-pages@v3`, on `push v*` it zips and releases. Same pattern here — free, consistent with sibling skins, and useful.

**What the dist branch gives us:**

- A sanitised, always-fresh working snapshot of the skin. All whitelist files, none of the junk (`shots/`, AI-agent dirs, loose notes, etc.).
- An install channel for bleeding-edge testing *without* cutting a release. A local dev can temporarily flip their `skin_sources.json` to `{type: github_branch, repo: allofmeng/streamline_project, branch: dist}` to pull the latest `main` without waiting for a tag.
- A clean target for documentation/screenshots that always reflects current main.
- Matches the mental model "releases for users, dist for devs". Users continue to consume via `github_release`; `skin_sources.json` production entry does **not** change to use the dist branch.

**Workflow shape (single `release.yml`, two jobs):**

```yaml
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
          mkdir -p dist
          # Bash-level whitelist — mirror the release zip contents exactly
          cp -r index.html skin-manifest.json css modules profiles settings ui dist/

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

**Key property:** the `dist` staging step is the single source of truth for "what counts as the skin". Both outputs (dist branch + release zip) are derived from the same staged tree, so they can never diverge. The whitelist lives in one place.

**Note on upstreaming:** adding the `dist` branch to `allofmeng/streamline_project` (once they merge the PR) will also put a force-pushed `dist` branch on their repo. Worth mentioning in the PR body so the maintainer is not surprised.

#### Upstreaming

- Open PR `tadelv:feature/release-build` → `allofmeng:main`.
- PR body explains: "adds a release workflow so downstream consumers (Streamline-Bridge) can point at tagged release zips instead of raw branch snapshots. Fixes #nils-windows-issue. No runtime code touched."
- Once merged, ask allofmeng to tag `v0.1.0` on their repo. Then the bridge flips one line (see Part 2, follow-up).

### Part 2 — streamline-bridge: consume the release

**Repo:** `tadelv/reaprime`
**Branch:** `feature/streamline-skin-release` (already checked out)

#### File changes

1. **`skin_sources.json`** — replace the `github_branch` entry:
   ```diff
   -  {
   -    "type": "github_branch",
   -    "repo": "allofmeng/streamline_project",
   -    "branch": "main"
   -  },
   +  {
   +    "type": "github_release",
   +    "repo": "tadelv/streamline_project"
   +  },
   ```
   *Interim.* The entry flips to `allofmeng/streamline_project` in a follow-up PR once upstream merges + tags. Single-line change.

2. **`bundle_skins.sh`** — add stale-zip cleanup. Currently the script only *writes* to `assets/bundled_skins/` and never removes. After the repo switch, `streamline_project-main.zip` would linger. Add near line 22:
   ```bash
   mkdir -p "$CACHE_DIR" "$OUTPUT_DIR"
   # Clear stale zips so removed/renamed skin_sources entries don't linger
   rm -f "$OUTPUT_DIR"/*.zip "$OUTPUT_DIR"/manifest.json
   ```
   Minor hardening, correct regardless of this PR.

3. **`lib/src/webui_support/webui_storage.dart`** — replace hardcoded id references:
   - Line 230: `if (preferredSkinId != 'streamline_project-main')` → `'streamline.js'`
   - Line 235: `_installedSkins['streamline_project-main']` → `_installedSkins['streamline.js']`

4. **`lib/src/settings/settings_service.dart`** — replace default + add pref migration:
   - Line 206: `return ... ?? 'streamline_project-main';` → `'streamline.js';`
   - Add migration in `SettingsService.initialize()` (or wherever first-run / prefs load happens):
     ```dart
     // One-shot migration: old default skin id → new
     final stored = await prefs.getString(SettingsKeys.defaultSkinId.name);
     if (stored == 'streamline_project-main') {
       await prefs.setString(SettingsKeys.defaultSkinId.name, 'streamline.js');
       _log.info('Migrated defaultSkinId: streamline_project-main → streamline.js');
     }
     ```
     Idempotent, runs on every init but only rewrites once. No cleanup needed.

5. **`test/helpers/mock_settings_service.dart`** — update test default line 20:
   - `String _defaultSkinId = 'streamline_project-main';` → `'streamline.js';`

#### What stays untouched (deliberately)

- `README.md:6,295` + `doc/Skins.md:23` — **keep pointing at `allofmeng/streamline_project`**. The fork is an upstreaming vehicle. Once allofmeng merges the build step, these links remain canonical without change.
- `_installFromZip` extraction loop — hardened in a separate PR.
- `_copyBundledSkins` swallow — separate follow-up (see "Deferred").
- Retry-storm behavior — deferred.

---

## Data flow (runtime, post-change)

1. Build time: `bundle_skins.sh` clears `assets/bundled_skins/*.zip`, reads `skin_sources.json`, hits `api.github.com/repos/tadelv/streamline_project/releases/latest`, downloads `streamline.js-v0.1.0.zip`, writes it to `assets/bundled_skins/streamline_project.zip` (filename from `$REPO_NAME`), regenerates `assets/bundled_skins/manifest.json`.
2. App install: zip shipped inside the Flutter bundle.
3. First run: `_copyBundledSkins` reads `assets/bundled_skins/manifest.json`, loads `streamline_project.zip`, calls `_installFromZip`.
4. `_installFromZip` extracts to `temp_webui_extract/`, calls `_installFromDirectory` which reads the top-level `skin-manifest.json`, gets `id: "streamline.js"`, installs to `web-ui/streamline.js`.
5. `_scanInstalledSkins` finds the dir, reads `skin-manifest.json` again, registers `_installedSkins['streamline.js']`.
6. `SettingsService.defaultSkinId()` returns migrated or new-default `"streamline.js"`. `WebUIStorage.preferredSkin` finds it. Skin loads.

On Windows: no filenames contain `:`, extraction never trips `ERROR_INVALID_NAME`.

---

## Risks

- **Upstream merge timing.** If allofmeng doesn't merge quickly, bridge is temporarily pointed at `tadelv/streamline_project`. Acceptable per Q7 answer: priority is unblocking users now. Follow-up bridge PR to flip the repo reference once upstream lands.
- **Release zip structure mismatch.** If the whitelist zip wraps files in an extra directory (e.g. `streamline.js-v0.1.0/index.html`), `_installFromZip` tries to handle the single-root-folder case (`webui_storage.dart:1091-1099`). With `skin-manifest.json` at root and a flat zip, the single-root path picks the right content dir. Verify by manual test-install on macOS before publishing.
- **Skin id with a dot.** `streamline.js` as a dir name: valid on all target platforms (macOS, Linux, Windows, iOS, Android — no trailing dot, no reserved chars). Settings keys are strings, JSON fine. No escaping needed.
- **Migration collision.** If a user has manually installed a custom skin named `streamline.js` AND has `streamline_project-main` as their default, the migration would point them at their custom skin instead of the new bundled one. Vanishingly unlikely (dot in user-chosen id), and the user would notice immediately. Not worth defending against.
- **Stale bundled zip cleanup as side effect.** `rm -f "$OUTPUT_DIR"/*.zip` runs on every build, including local dev. Cache dir (`$CACHE_DIR`) is untouched so downloads don't thrash. Verified safe.

---

## Testing

- **Unit:** update existing skin/settings tests to use `streamline.js` as the expected default. Add a migration test: seed prefs with `streamline_project-main`, call init, assert stored value is `streamline.js`.
- **Integration:** `flutter test` full suite — no regressions.
- **Manual (macOS):**
  1. Run `bundle_skins.sh`, confirm `assets/bundled_skins/streamline_project.zip` appears and `streamline_project-main.zip` does not.
  2. Inspect zip contents: whitelist only, `skin-manifest.json` at root, no `:` in any path.
  3. `flutter run` with `--dart-define=simulate=1`, verify Streamline skin shows up in the skin picker as "Streamline.js" and loads.
- **MCP smoke test:** after the bridge starts, `plugins_list` + confirm skin list via web server includes `streamline.js`.
- **Windows (if available):** reproduce Nils's flow on a real Windows box — install fresh, confirm no `SEVERE WebUIStorage - Failed` lines in log, confirm skin dir exists at `%USERPROFILE%\Documents\web-ui\streamline.js`.
- **Regression for migration:** install previous build (with old id), set preferred skin to `streamline_project-main`, upgrade to new build, confirm skin still shows as selected.

---

## Deferred — tracked as follow-ups

### 1. `_installFromZip` Win32 path sanitisation

File: `lib/src/webui_support/webui_storage.dart:1075-1086`. Wrap each per-entry `createSync`/`writeAsBytesSync` in a try/catch (log + skip, not abort), and sanitise reserved Win32 chars `<>:"|?*` in destination filenames before write. Not in this PR — per Q6b, "skins might have hardcoded paths, better to break hard than half work." But must be fixed before third-party skin installs are trusted on Windows.

### 2. `_copyBundledSkins` silent-swallow — **platform-agnostic, non-trivial**

File: `lib/src/webui_support/webui_storage.dart:912-940`. The bundled-zips loop is wrapped in one outer `try/catch` that catches **any** failure at `fine` level and breaks out of the loop. Consequences:

- **Any single bad bundled zip kills every subsequent bundled zip install in the same run.** Order-dependent: skins later in the loop get silently dropped.
- **Errors are logged at `fine` level.** Default release logging is typically `info` or `warning`, so the failure is invisible in user logs. A user reporting "my skin disappeared" gives us nothing to grep for.
- **This is not a Windows-specific issue.** Any platform-agnostic failure — corrupt asset, renamed zip, JSON parse error in `manifest.json`, OOM during extraction — produces the same silent amnesia.
- **Per-entry error handling missing.** Each skin should be tried independently with its own try/catch, errors logged at `warning` or `severe`.

Fix sketch:
```dart
for (final skinId in skinIds) {
  try {
    // per-skin install...
  } catch (e, st) {
    _log.warning('Failed to install bundled skin "$skinId"', e, st);
    // continue — don't kill remaining skins
  }
}
```
and move the outer `try/catch` to only cover the `manifest.json` load, logging that specific failure at `warning` if the manifest itself is missing or malformed.

**Priority:** high. Has been silently dropping skins on any extraction failure for an unknown amount of time. File a GitHub issue and schedule alongside the `_installFromZip` hardening PR (they touch the same area and share testing surface).

### 3. Retry storm

Deferred. `downloadRemoteSkins` retries the same failing URL on every onboarding/restart with no backoff or cache of prior failures. Low priority — only noisy in logs, not user-facing.

---

## Task ordering

1. **Fork:** branch + skin-manifest.json + release workflow + tag `v0.1.0` + verify release asset. Open PR to allofmeng in parallel (it's blocked on them anyway).
2. **Bridge:** edit 5 files on the already-checked-out `feature/streamline-skin-release` branch. Run `bundle_skins.sh`, confirm zip looks right. Run `flutter test`. Run `flutter analyze`. `flutter run --dart-define=simulate=1` sanity check.
3. **File follow-up GitHub issues** for Deferred items 1 and 2 before opening the bridge PR, so they exist as distinct tracked work.
4. **Open bridge PR.** Do NOT merge until asked.
5. **When allofmeng merges + tags:** follow-up 1-line bridge PR flipping `tadelv` → `allofmeng` in `skin_sources.json`.

---

## Open questions

None. Ready to implement.
