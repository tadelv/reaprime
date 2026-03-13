# App Store Readiness Design

## Goal

Prepare Streamline-Bridge for iOS App Store / TestFlight submission by removing features that violate App Store review guidelines, while preserving full functionality on other platforms.

## Scope

- iOS App Store distribution only (macOS stays direct distribution)
- Compile-time gating via `--dart-define=appStore=true`
- Build-time skin bundling (benefits all platforms)
- iOS-specific permission fixes

## Compile-time Flag

Introduce `kAppStore` constant:

```dart
const bool kAppStore = bool.fromEnvironment('appStore');
```

All App Store restrictions key off this flag. The flag is passed via `flutter_with_commit.sh` for App Store builds.

## Changes Under `kAppStore`

### Plugin System

| What | Change |
|------|--------|
| Plugin install UI ("+" button in `PluginsSettingsView`) | Hidden |
| `PluginLoaderService.addPlugin()` from filesystem | No-op / disabled |
| Bundled plugins (DYE2) | Continue to load normally |
| JS runtime | Active (only executes bundled, reviewed code) |

### Skin / WebUI System

| What | Change |
|------|--------|
| "Load custom folder..." in settings | Hidden |
| `downloadRemoteSkins()` at startup | Skipped |
| `updateAllSkins()` background updates | Skipped |
| REST endpoints: `POST .../install/url`, `install/github-release`, `install/github-branch` | Return 403 or unregistered |
| Bundled skins (from assets) | Only source of skins |

## Build-time Skin Bundling

### Overview

Skins are downloaded at build time and shipped as Flutter assets. This benefits all platforms (faster first launch) and is required for App Store builds.

### Config: `skin_sources.json`

Single source of truth for skin URLs, replacing the hardcoded `_remoteWebUISources` list in `WebUIStorage`:

```json
[
  {
    "type": "github_release",
    "repo": "tadelv/baseline.js",
    "asset": "baseline-skin.zip",
    "prerelease": true
  },
  {
    "type": "github_branch",
    "repo": "allofmeng/streamline_project",
    "branch": "main"
  }
]
```

### Build Script: `bundle_skins.sh`

1. Reads `skin_sources.json`
2. Downloads each skin (caches in `.skin_cache/` to avoid re-downloading every build)
3. Extracts to `assets/bundled_skins/<skin-id>/`
4. `pubspec.yaml` asset glob picks them up

Integrated into `flutter_with_commit.sh` — runs before `flutter build`/`flutter run`.

### Runtime: `WebUIStorage.initialize()`

1. Copies bundled skins from Flutter assets to `web-ui/` directory
2. **Non-App Store builds**: also runs `downloadRemoteSkins()` for background updates (existing behavior)
3. **App Store builds**: skips remote downloads entirely

### `_remoteWebUISources` Migration

- Dart code reads from `skin_sources.json` asset instead of hardcoded list
- Same data, single source of truth for build script and runtime

## Unconditional iOS Fixes

| What | Change | Why |
|------|--------|-----|
| `locationWhenInUse` permission request | Remove from iOS path in `permissions_view.dart` | Not needed for BLE on iOS; will cause rejection |

## What Stays As-Is

- Web servers on ports 8080 and 3000 (justified by `NSLocalNetworkUsageDescription`)
- `flutter_inappwebview` beta (needed for VoiceOver/TalkBack accessibility)
- Simulated Devices toggle (useful for review team)
- Bundled plugins (DYE2) — load and execute normally
- JavaScript runtime (only runs bundled code under `kAppStore`)
- Firebase Crashlytics (existing consent flow)
- BLE background mode (`bluetooth-central`)

## Key Files to Modify

| File | Change |
|------|--------|
| `lib/src/plugins/plugin_loader_service.dart` | Gate `addPlugin()` on `kAppStore` |
| `lib/src/settings/plugins_settings_view.dart` | Hide install button when `kAppStore` |
| `lib/src/webui_support/webui_storage.dart` | Read from `skin_sources.json`, skip remote downloads when `kAppStore`, expand bundled skin copying |
| `lib/src/settings/settings_view.dart` | Hide "Load custom folder..." when `kAppStore` |
| `lib/src/services/webserver/webui_handler.dart` | Gate install endpoints on `kAppStore` |
| `lib/src/permissions_feature/permissions_view.dart` | Remove `locationWhenInUse` on iOS |
| `flutter_with_commit.sh` | Integrate `bundle_skins.sh` |
| `pubspec.yaml` | Add `assets/bundled_skins/` glob |
| `skin_sources.json` (new) | Skin source config |
| `bundle_skins.sh` (new) | Build-time skin downloader |
