# Rename to Decent.app — Implementation Plan

**Issue:** [#68](https://github.com/tadelv/reaprime/issues/68)
**Scope:** User-visible branding only. Keep all internal identifiers.

## Naming reference (authoritative)

| Layer | Value |
|-------|-------|
| User-facing display name | **Decent.app** (or "Decent" where short form fits — e.g., launcher labels) |
| Dart package name | `reaprime` |
| Plugin file extension | `.reaplugin` |
| Bundle ID (iOS/macOS/Android) | `net.tadel.reaprime` |
| Database name | `streamline_bridge` |
| API schema names | `ReaSettings`, `WebUIReaMetadata` |
| GitHub repo | `tadelv/reaprime` |
| MethodChannel | `com.reaprime.updater/apk_installer` |
| Telemetry salt | `reaprime-telemetry-v1` |

**Context for future agents:** Vid is part of the Decent team. John (Decent Espresso) has explicitly OK'd this rename. Decent.app will become the default companion app for Decent machines this year. Bundle ID and package name stay `reaprime` because rebinding App Store / Firebase / Google Play / database is not worth the breakage.

## Out of scope

- App icon — current icon stays until a better one exists
- Splash screen art
- Plugin internal API names (`fetchReaSettings`, `convertReaToVisualizerFormat`, `updateReaSetting`) — kept for plugin compatibility; documented as legacy prefix in `doc/Plugins.md`
- Database name `streamline_bridge` (no migration)
- API schema names `ReaSettings`/`WebUIReaMetadata` (no API break)
- Telemetry salt (changing breaks hash continuity)
- All `tadelv/reaprime` GitHub URLs (repo not renamed)
- `doc/plans/archive/` (historical record)
- `test/webui_zip_support_test.dart:84` tmp-dir name `reaprime_zip_support_test_` (internal, no user impact)

## Target brand names per platform

| Platform | Display name | Notes |
|----------|-------------|-------|
| iOS home screen | **Decent** | Short, clean |
| Android launcher | **Decent** | Short, clean |
| macOS Finder | **Decent.app** | `PRODUCT_NAME = Decent` produces `Decent.app` |
| Windows | **Decent.exe** | Window title + VERSIONINFO |
| Linux | **decent** | Binary name, window title lowercase |
| Flutter web | **Decent** | manifest + title tag |

---

## Incision List

### 1. App Title (localization)

| File | Change |
|------|--------|
| `lib/src/localization/app_en.arb:2` | `"appTitle": "reaprime"` → `"appTitle": "Decent"` |
| `lib/src/localization/app_localizations_en.dart:12` | `'reaprime'` → `'Decent'` |
| `lib/src/localization/app_localizations.dart:100` | Doc comment `'reaprime'` → `'Decent'` |

### 2. iOS

| File | Change |
|------|--------|
| `ios/Runner/Info.plist:10` | `CFBundleDisplayName` → `Decent` |
| `ios/Runner/Info.plist:18` | `CFBundleName` → `Decent` |

### 3. macOS

| File | Change |
|------|--------|
| `macos/Runner/Configs/AppInfo.xcconfig:7` | `PRODUCT_NAME = Streamline-Bridge` → `PRODUCT_NAME = Decent` |
| `macos/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme` | 3× `BuildableName = "reaprime.app"` → `"Decent.app"` |
| `macos/Runner.xcodeproj/project.pbxproj` | 3× `TEST_HOST = "$(BUILT_PRODUCTS_DIR)/reaprime.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/reaprime"` → `Decent.app/.../Decent` |

> **Xcode caveat:** scheme + pbxproj edits can be regenerated when Xcode rewrites the project. After first build, re-verify these still hold.

### 4. Android

| File | Change |
|------|--------|
| `android/app/src/main/AndroidManifest.xml:39` | `android:label="Streamline-Bridge"` → `android:label="Decent"` |
| `android/app/src/main/AndroidManifest.xml` (comment block above `<application>`) | `Streamline Bridge - A gateway application for Decent Espresso machines` → `Decent - …` |

### 5. Windows

| File | Change |
|------|--------|
| `windows/runner/main.cpp:30` | `L"reaprime"` → `L"Decent"` |
| `windows/runner/Runner.rc:93` | `"FileDescription", "reaprime"` → `"Decent"` |
| `windows/runner/Runner.rc:95` | `"InternalName", "reaprime"` → `"Decent"` |
| `windows/runner/Runner.rc:97` | `"OriginalFilename", "reaprime.exe"` → `"Decent.exe"` |
| `windows/runner/Runner.rc:98` | `"ProductName", "reaprime"` → `"Decent"` |

### 6. Linux

| File | Change |
|------|--------|
| `linux/CMakeLists.txt:7` | `set(BINARY_NAME "reaprime")` → `set(BINARY_NAME "decent")` |
| `linux/runner/my_application.cc:43` | `"reaprime"` → `"Decent"` (header bar title) |
| `linux/runner/my_application.cc:47` | `"reaprime"` → `"Decent"` (window title) |

`linux/CMakeLists.txt` `APPLICATION_ID = net.tadel.reaprime` — keep.

### 7. Flutter web

| File | Change |
|------|--------|
| `web/manifest.json` | `"name": "Streamline-Bridge"` → `"Decent"`; description `Streamline Bridge - Gateway…` → `Decent - Gateway for Decent Espresso Machines` |
| `web/index.html` | `<meta name="apple-mobile-web-app-title" content="reaprime">` → `Decent`; `<title>reaprime</title>` → `Decent` |

### 8. pubspec

| File | Change |
|------|--------|
| `pubspec.yaml` (description) | `"Streamline Bridge - Gateway for Decent Espresso Machines"` → `"Decent - Gateway for Decent Espresso Machines"` |

`name: reaprime` — keep.

### 9. UI Strings

| File | Change |
|------|--------|
| `lib/src/onboarding_feature/steps/welcome_step.dart:42` | `'Welcome to Streamline Bridge'` → `'Welcome to Decent'` |
| `lib/src/settings/settings_view.dart:763` | `'Exit Streamline-Bridge'` → `'Exit Decent'` |
| `lib/src/settings/settings_view.dart:767` | `"Exit Streamline-Bridge"` → `"Exit Decent"` |
| `lib/src/home_feature/home_feature.dart` | Delete commented-out `// title: Text('ReaPrime'),` (dead) |
| `lib/main.dart` | `Logger.root.info("==== REA PRIME starting ====")` → `==== Decent starting ====` |

### 10. User-Agent Strings

| File | Change |
|------|--------|
| `lib/src/skin_feature/skin_view.dart:192` | `"Streamline-Bridge"` → `"Decent"` |
| `lib/src/webui_support/webui_storage.dart:378,537` | `'Streamline-Bridge-WebUI'` → `'Decent-WebUI'` (2×) |
| `bundle_skins.sh` | `User-Agent: Streamline-Bridge-Build` → `Decent-Build` (2×) |

### 11. Feedback / Gist payload

| File | Change |
|------|--------|
| `lib/src/services/feedback_service.dart` | `gistFiles['reaprime_logs.txt']` → `decent_logs.txt` |
| `lib/src/services/feedback_service.dart` | `gistFiles['reaprime_webview_logs.txt']` → `decent_webview_logs.txt` |
| `lib/src/services/feedback_service.dart` | `'ReaPrime feedback - …'` gist description → `'Decent feedback - …'` |

`repo = 'tadelv/reaprime'` arg — keep (repo not renamed).

### 12. Plugin Assets

| File | Change |
|------|--------|
| `assets/plugins/settings.reaplugin/manifest.json:5` | `"Streamline-Bridge"` → `"Decent"` in description |
| `assets/plugins/settings.reaplugin/plugin.js` (`<meta name="description">`) | `"REA Prime Settings Dashboard…"` → `"Decent Settings Dashboard…"` |
| `assets/plugins/settings.reaplugin/plugin.js:373,379` | `"Streamline-Bridge Settings"` → `"Decent Settings"` (2×) |
| `assets/plugins/dye2.reaplugin/manifest.json:3` | `"author": "Streamline"` → `"Decent Espresso"` |
| `assets/plugins/dye2.reaplugin/manifest.json:4` | `"name": "Streamline/DYE2"` → `"Decent/DYE2"` |
| `assets/defaultProfiles/manifest.json` | `"Default espresso profiles bundled with REA Prime"` → `"…with Decent"` |

JS function names (`fetchReaSettings`, `updateReaSetting`, `convertReaToVisualizerFormat`) — keep, document as legacy prefix in `doc/Plugins.md` (sec 16).

### 13. API Specs

| File | Change |
|------|--------|
| `assets/api/rest_v1.yml:3` | `title: Rea Prime Rest API` → `title: Decent API` |
| `assets/api/rest_v1.yml:457` | `…Rea logs` → `…Decent logs` |
| `assets/api/rest_v1.yml:507-508` | `connected to Rea` / `available through Rea` → `Decent` |
| `assets/api/rest_v1.yml:586-606` | `Rea settings` → `Decent settings` (human-readable text only; schema names stay `ReaSettings`) |
| `assets/api/websocket_v1.yml:3` | `title: Rea Prime AsyncAPI` → `title: Decent AsyncAPI` |
| `assets/api/websocket_v1.yml:6` | `Rea Prime WebSocket data streams` → `Decent WebSocket data streams` |
| `assets/api/websocket_v1.yml:71` | `Rea plugins` → `Decent plugins` |
| `assets/api/websocket_v1.yml:82` | `Rea logs` → `Decent logs` |
| `assets/api/websocket_v1.yml:222` | `Log message from Rea` → `Log message from Decent` |

### 14. Export Filenames

| File | Change |
|------|--------|
| `lib/src/services/webserver/data_export_handler.dart:74` | `streamline_bridge_export` → `decent_export` |
| `lib/src/settings/data_management_page.dart:285` | `streamline_bridge_export` → `decent_export` |
| `assets/api/rest_v1.yml:3286` | `streamline_bridge_export_{timestamp}` → `decent_export_{timestamp}` |

### 15. CI / GitHub Actions

| File | Change |
|------|--------|
| `.github/workflows/release.yml:73-76` | APK `reaprime-android-*` → `decent-android-*` |
| `.github/workflows/release.yml:166,213,218` | macOS `Streamline-Bridge.app` / `streamline-bridge-macos-*` → `Decent.app` / `decent-macos-*` |
| `.github/workflows/release.yml:266,271` | Linux `reaprime-linux-x64-*` → `decent-linux-x64-*` |
| `.github/workflows/release.yml:321,326` | Linux ARM64 `reaprime-linux-arm64-*` → `decent-linux-arm64-*` |
| `.github/workflows/release.yml:367,371` | Windows `reaprime-windows-x64-*` → `decent-windows-x64-*` |
| `.github/workflows/release.yml:583-630` | Release name/body: `ReaPrime` → `Decent`, all download links |
| `.github/workflows/develop-builds.yml:171,212,218` | macOS `streamline-bridge-macos-develop.zip` → `decent-macos-develop.zip` |

### 16. README & Docs

| File | Change |
|------|--------|
| `README.md` | All `Streamline Bridge` → `Decent` (including title, "Why Streamline Bridge?" → "Why Decent?", rewrite the history section to "REA → ReaPrime → Streamline Bridge → Decent" if keeping naming history at all) |
| `LICENSE.txt:1` | `Streamline Bridge - A gateway application for Decent Espresso machines` → `Decent - …` |
| `CLAUDE.md` (Project Overview) | Replace `Streamline-Bridge (formerly REA/ReaPrime/R1)` with `Decent.app (display name). Codebase, repo, package, and bundle ID all use legacy "reaprime"/"streamline-bridge" identifiers — see naming reference table.`; add the naming reference table from this plan near the top |
| `CLAUDE.md` (`adb shell run-as net.tadel.reaprime …`) | Keep — bundle ID unchanged |
| `CLAUDE.md` skill paths (`.agents/skills/streamline-bridge/...`, `.claude/skills/streamline-bridge/...`) | Update to `decent-app/` after sec 17 rename |
| `doc/Api.md:3` | `Streamline-Bridge` → `Decent` |
| `doc/RELEASE.md:3,7,43` | `ReaPrime` → `Decent` |
| `doc/RELEASE.md:31,37` | Keep `tadelv/reaprime` URLs (repo unchanged) |
| `doc/Skins.md` | All `Streamline-Bridge` → `Decent` throughout; keep `tadelv/reaprime` GitHub URL |
| `doc/Plugins.md` | `REA`/`Streamline-Bridge` → `Decent` where used as app name; add note: "Plugin JS APIs use `Rea`-prefixed names (`fetchReaSettings`, `updateReaSetting`, `convertReaToVisualizerFormat`) for backwards compatibility with existing plugins. Not renamed despite the app rename." |
| `doc/Profiles.md` | `"Default espresso profiles bundled with REA Prime"` (and any other `REA Prime` mentions) → `Decent` |
| `doc/agents/domain.md` | `.agents/skills/streamline-bridge/` → `.agents/skills/decent-app/` |
| `doc/agents/issue-tracker.md` | Keep `tadelv/reaprime` (repo URL) |
| `AGENTS.md` | All `Streamline Bridge` → `Decent`; update skill paths to `decent-app/` |
| `packages/dye2-plugin/README.md` | All `Streamline Bridge` → `Decent`; keep relative path `../../README.md` |
| `lib/src/services/webserver/data_sync_handler.dart` (dartdoc, 2×) | `Streamline Bridge instances` → `Decent instances` |
| `tools/ingest_profiles.py` | `Streamline-Bridge format` → `Decent format` (3×); `"Default espresso profiles bundled with REA Prime"` → `Decent`; CLI description string |

### 17. Skill directories (rename + content)

Rename directories, then update content. Order matters: rename first, then edit files at the new paths.

```bash
git mv .agents/skills/streamline-bridge .agents/skills/decent-app
git mv .claude/skills/streamline-bridge .claude/skills/decent-app
```

Then within the renamed dirs, replace `Streamline Bridge` / `Streamline-Bridge` → `Decent` in:

- `.agents/skills/decent-app/SKILL.md`
- `.agents/skills/decent-app/lifecycle.md` (incl. runtime dir `/tmp/streamline-bridge-$USER` → `/tmp/decent-$USER`)
- `.agents/skills/decent-app/simulated-devices.md`
- `.agents/skills/decent-app/websocket.md`
- `.agents/skills/decent-app/verification.md`
- `.agents/skills/decent-app/rest.md`
- `.agents/skills/decent-app/scenarios/*.md`
- `.claude/skills/decent-app/SKILL.md` (forwarder — update path it points to)
- `.claude/skills/tdd-workflow/SKILL.md` (`Streamline-Bridge` → `Decent`)

### 18. sb-dev.sh

| File | Change |
|------|--------|
| `scripts/sb-dev.sh` (header comment, usage block, `SB_RUNTIME_DIR` default) | `Streamline Bridge` → `Decent`; `/tmp/streamline-bridge-$USER` → `/tmp/decent-$USER`; skill path reference `.agents/skills/streamline-bridge/` → `.agents/skills/decent-app/` |

> **Dev-loop migration:** runtime dir change orphans any running session. Run `sb-dev stop` before pulling the rename commit. Stale `/tmp/streamline-bridge-$USER` is harmless leftover; rm manually.

### 19. Test files

| File | Change |
|------|--------|
| `test/onboarding/welcome_step_test.dart:35` | `'Welcome to Streamline Bridge'` → `'Welcome to Decent'` (matches sec 9) |
| `test/data_export/data_export_handler_test.dart:136` | `'attachment; filename="streamline_bridge_export_'` → `'…decent_export_'` (matches sec 14) |

---

## Test Plan

1. **Pre-merge grep gate:** run
   ```bash
   rg -i 'streamline.bridge|reaprime|rea.prime' \
     --glob '!doc/plans/archive/**' --glob '!**/*.lock' \
     --glob '!**/build/**' --glob '!**/.dart_tool/**' --glob '!**/Pods/**'
   ```
   Every remaining hit must match the "Out of scope" / naming-reference keep-list. No surprises.
2. `flutter analyze` — clean.
3. `flutter test` — full suite green, esp. `welcome_step_test`, `data_export_handler_test`.
4. CI builds for all platforms — verify artifact naming in release/develop-builds workflows.
5. `sb-dev stop && sb-dev start` post-rename — verify new runtime dir `/tmp/decent-$USER` works.
6. Manual launcher check: install on iOS + Android, confirm home-screen label reads "Decent".
7. macOS build: confirm Finder shows `Decent.app`.
8. Run flutter web build: confirm browser tab title is "Decent".

## Risks

- **Low risk.** No API breaks, no package renames, no bundle ID changes, no database migrations.
- Export filename change is cosmetic only, no compatibility concern.
- CI artifact rename: downstream consumers who hardcode artifact URLs will break. Acceptable — major version increment + release notes mapping old → new artifact names.
- Xcode may rewrite pbxproj/xcscheme on next project mutation — re-verify after first build.
- `sb-dev` runtime dir migration — orphans running session, requires `sb-dev stop` before pulling rename commit.
