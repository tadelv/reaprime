# App Store Readiness Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Prepare the iOS build for App Store / TestFlight submission by gating non-compliant features behind a compile-time flag and bundling skins at build time.

**Architecture:** A `kAppStore` compile-time constant gates plugin installation, skin downloading, and REST install endpoints. A build script downloads skins into `assets/bundled_skins/` before Flutter builds. `WebUIStorage` reads skin sources from a shared JSON config.

**Tech Stack:** Flutter/Dart, shell scripting (bash), GitHub API for skin downloads

---

### Task 1: Add `kAppStore` build flag

**Files:**
- Modify: `lib/build_info.dart:1-12`

**Step 1: Write the test**

Create `test/build_info_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/build_info.dart';

void main() {
  test('kAppStore defaults to false', () {
    // When no --dart-define=APP_STORE=true is passed, kAppStore should be false
    expect(BuildInfo.appStore, isFalse);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/build_info_test.dart`
Expected: FAIL — `appStore` not defined on `BuildInfo`

**Step 3: Add `appStore` constant to `BuildInfo`**

In `lib/build_info.dart`, add after the existing constants:

```dart
/// Whether this is an App Store build (iOS).
/// Pass --dart-define=APP_STORE=true to enable.
static const bool appStore = bool.fromEnvironment('APP_STORE');
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/build_info_test.dart`
Expected: PASS

**Step 5: Run flutter analyze**

Run: `flutter analyze`
Expected: No new issues

**Step 6: Commit**

```bash
git add lib/build_info.dart test/build_info_test.dart
git commit -m "feat: add kAppStore compile-time flag to BuildInfo"
```

---

### Task 2: Remove iOS location permission request

**Files:**
- Modify: `lib/src/permissions_feature/permissions_view.dart:127-130`
- Test: `test/permissions_view_test.dart` (create)

**Step 1: Write the test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'dart:io' show Platform;

// This is a behavioral verification test.
// We verify the permission list no longer includes locationWhenInUse on iOS.
// Since we can't easily mock Platform.isIOS in unit tests,
// we'll verify the code change via static analysis.

void main() {
  test('iOS permission path should not request locationWhenInUse', () {
    // Read the source file and verify locationWhenInUse is not requested on iOS
    final sourceFile = File('lib/src/permissions_feature/permissions_view.dart');
    final content = sourceFile.readAsStringSync();

    // The iOS block should only request bluetooth, not locationWhenInUse
    // Find the iOS block
    final iosBlockMatch = RegExp(
      r'Platform\.isIOS\).*?\{(.*?)\}',
      dotAll: true,
    ).firstMatch(content);

    expect(iosBlockMatch, isNotNull, reason: 'iOS permission block should exist');
    final iosBlock = iosBlockMatch!.group(1)!;
    expect(iosBlock, isNot(contains('locationWhenInUse')),
        reason: 'iOS should not request locationWhenInUse — not needed for BLE');
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/permissions_view_test.dart`
Expected: FAIL — iOS block still contains `locationWhenInUse`

**Step 3: Remove locationWhenInUse from iOS path**

In `lib/src/permissions_feature/permissions_view.dart`, change lines 127-130 from:

```dart
} else if (Platform.isIOS) {
  await Permission.bluetooth.request();
  await Permission.locationWhenInUse.request();
}
```

To:

```dart
} else if (Platform.isIOS) {
  await Permission.bluetooth.request();
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/permissions_view_test.dart`
Expected: PASS

**Step 5: Run flutter analyze**

Run: `flutter analyze`
Expected: No new issues. Check for unused import of `Permission.locationWhenInUse` if it was the only usage.

**Step 6: Commit**

```bash
git add lib/src/permissions_feature/permissions_view.dart test/permissions_view_test.dart
git commit -m "fix(ios): remove unnecessary locationWhenInUse permission request"
```

---

### Task 3: Create `skin_sources.json` config and build script

**Files:**
- Create: `skin_sources.json`
- Create: `bundle_skins.sh`
- Modify: `pubspec.yaml:116-124` (add bundled_skins asset glob)
- Modify: `.gitignore` (add `.skin_cache/` and `assets/bundled_skins/`)

**Step 1: Create `skin_sources.json`**

Extract from `webui_storage.dart:148-174` into project root:

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

**Step 2: Create `bundle_skins.sh`**

```bash
#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/skin_sources.json"
CACHE_DIR="$SCRIPT_DIR/.skin_cache"
OUTPUT_DIR="$SCRIPT_DIR/assets/bundled_skins"

if [ ! -f "$CONFIG" ]; then
  echo "Error: skin_sources.json not found"
  exit 1
fi

# Require jq
if ! command -v jq &> /dev/null; then
  echo "Error: jq is required. Install with: brew install jq"
  exit 1
fi

mkdir -p "$CACHE_DIR" "$OUTPUT_DIR"

COUNT=$(jq length "$CONFIG")

for ((i=0; i<COUNT; i++)); do
  TYPE=$(jq -r ".[$i].type" "$CONFIG")
  REPO=$(jq -r ".[$i].repo" "$CONFIG")

  echo "--- Processing source $((i+1))/$COUNT: $TYPE $REPO ---"

  case "$TYPE" in
    github_release)
      ASSET=$(jq -r ".[$i].asset // empty" "$CONFIG")
      PRERELEASE=$(jq -r ".[$i].prerelease // false" "$CONFIG")

      # Fetch release info
      if [ "$PRERELEASE" = "true" ]; then
        RELEASE_JSON=$(curl -sfL "https://api.github.com/repos/$REPO/releases" \
          -H "Accept: application/vnd.github.v3+json" \
          -H "User-Agent: Streamline-Bridge-Build")
        RELEASE_JSON=$(echo "$RELEASE_JSON" | jq '.[0]')
      else
        RELEASE_JSON=$(curl -sfL "https://api.github.com/repos/$REPO/releases/latest" \
          -H "Accept: application/vnd.github.v3+json" \
          -H "User-Agent: Streamline-Bridge-Build")
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

      CACHE_KEY=$(echo "$REPO-$TAG" | tr '/' '-')
      CACHE_FILE="$CACHE_DIR/$CACHE_KEY.zip"

      if [ -f "$CACHE_FILE" ]; then
        echo "Using cached: $CACHE_FILE"
      else
        echo "Downloading: $DOWNLOAD_URL"
        curl -sfL -o "$CACHE_FILE" "$DOWNLOAD_URL"
      fi
      ;;

    github_branch)
      BRANCH=$(jq -r ".[$i].branch // \"main\"" "$CONFIG")
      URL="https://github.com/$REPO/archive/refs/heads/$BRANCH.zip"

      CACHE_KEY=$(echo "$REPO-$BRANCH" | tr '/' '-')
      # Branch archives always re-download (content may change)
      CACHE_FILE="$CACHE_DIR/$CACHE_KEY.zip"

      echo "Downloading: $URL"
      curl -sfL -o "$CACHE_FILE" "$URL"
      ;;

    *)
      echo "Warning: Unknown source type '$TYPE', skipping"
      continue
      ;;
  esac

  # Extract to output directory
  TEMP_DIR=$(mktemp -d)
  unzip -qo "$CACHE_FILE" -d "$TEMP_DIR"

  # Find the extracted directory (GitHub archives have a single root dir)
  EXTRACTED_DIR=$(find "$TEMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -1)

  if [ -z "$EXTRACTED_DIR" ]; then
    echo "Warning: No directory found in zip for $REPO, skipping"
    rm -rf "$TEMP_DIR"
    continue
  fi

  # Determine skin ID from the extracted directory name
  SKIN_ID=$(basename "$EXTRACTED_DIR")

  # Copy to output
  rm -rf "$OUTPUT_DIR/$SKIN_ID"
  cp -r "$EXTRACTED_DIR" "$OUTPUT_DIR/$SKIN_ID"

  echo "Installed skin: $SKIN_ID -> $OUTPUT_DIR/$SKIN_ID"

  rm -rf "$TEMP_DIR"
done

echo "--- Done: $(ls -1 "$OUTPUT_DIR" | wc -l | tr -d ' ') skins bundled ---"
```

**Step 3: Add to `.gitignore`**

Append:
```
.skin_cache/
assets/bundled_skins/
```

**Step 4: Add asset glob to `pubspec.yaml`**

After existing assets (line ~124), add a comment. Note: Flutter asset bundling requires listing each subdirectory explicitly or using a generator. Since skins are dynamic, we'll need to list them. The build script will also generate a manifest file that lists bundled skin directories.

Actually, Flutter doesn't support recursive asset globs for arbitrary subdirectories. We need a different approach: the build script should also generate a `pubspec_overrides.yaml` or we register each skin directory. Simpler approach: the build script generates a file `assets/bundled_skins/manifest.json` listing the skin directories, and we add `assets/bundled_skins/` as an asset path. At runtime, we read the manifest and copy files.

**Revised approach:** Bundle skins as zip files in assets (no extraction needed at build time):

Update `bundle_skins.sh` to just copy the cached zips:
```bash
# Instead of extracting, copy zip to output:
cp "$CACHE_FILE" "$OUTPUT_DIR/$SKIN_ID.zip"
```

And create a manifest:
```bash
# At the end, generate manifest
echo "[" > "$OUTPUT_DIR/manifest.json"
FIRST=true
for ZIP in "$OUTPUT_DIR"/*.zip; do
  SKIN_NAME=$(basename "$ZIP" .zip)
  if [ "$FIRST" = true ]; then FIRST=false; else echo "," >> "$OUTPUT_DIR/manifest.json"; fi
  echo "  \"$SKIN_NAME\"" >> "$OUTPUT_DIR/manifest.json"
done
echo "]" >> "$OUTPUT_DIR/manifest.json"
```

Add to `pubspec.yaml` assets section:
```yaml
    - assets/bundled_skins/
```

This way Flutter bundles all files in that directory (manifest.json + zip files).

**Step 5: Test the build script manually**

Run: `chmod +x bundle_skins.sh && ./bundle_skins.sh`
Expected: Downloads skins, creates `assets/bundled_skins/manifest.json` and `.zip` files

**Step 6: Run flutter analyze**

Run: `flutter analyze`
Expected: No new issues

**Step 7: Commit**

```bash
git add skin_sources.json bundle_skins.sh .gitignore pubspec.yaml
git commit -m "feat: add build-time skin bundling script and config"
```

---

### Task 4: Update `WebUIStorage` to load bundled skin zips from assets

**Files:**
- Modify: `lib/src/webui_support/webui_storage.dart:140-217, 886-910`
- Test: `test/webui_storage_test.dart` (create)

**Step 1: Write test for bundled skin loading**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/webui_support/webui_storage.dart';

// Test that WebUIStorage can read the bundled skins manifest
// and that initialize() installs bundled skins when kAppStore is true.
// This requires mocking rootBundle — use the existing test patterns.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('WebUIStorage reads skin_sources.json from assets', () async {
    // Verify the config file can be parsed
    final configString = await rootBundle.loadString('skin_sources.json');
    final sources = jsonDecode(configString) as List;
    expect(sources, isNotEmpty);
    expect(sources.first['type'], isNotNull);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/webui_storage_test.dart`
Expected: FAIL — skin_sources.json not in assets yet, or method not implemented

**Step 3: Implement changes to `WebUIStorage`**

In `webui_storage.dart`:

a) Replace `_remoteWebUISources` (lines 146-174) — load from asset at runtime:

```dart
/// Remote skin sources — loaded from skin_sources.json asset at runtime.
/// At build time, bundle_skins.sh reads the same file to pre-download skins.
static List<Map<String, dynamic>>? _remoteWebUISourcesCache;

Future<List<Map<String, dynamic>>> _getRemoteWebUISources() async {
  if (_remoteWebUISourcesCache != null) return _remoteWebUISourcesCache!;
  try {
    final configString = await rootBundle.loadString('assets/skin_sources.json');
    _remoteWebUISourcesCache = (jsonDecode(configString) as List).cast<Map<String, dynamic>>();
  } catch (e) {
    _log.warning('Failed to load skin_sources.json', e);
    _remoteWebUISourcesCache = [];
  }
  return _remoteWebUISourcesCache!;
}
```

b) Update `_copyBundledSkins()` (lines 886-910) to also handle zip-based bundled skins:

```dart
Future<void> _copyBundledSkins() async {
  // Existing asset path copying...

  // Also install bundled skin zips from assets/bundled_skins/
  try {
    final manifestString = await rootBundle.loadString('assets/bundled_skins/manifest.json');
    final skinIds = (jsonDecode(manifestString) as List).cast<String>();

    for (final skinId in skinIds) {
      final destDir = Directory('${_webUIDir.path}/$skinId');
      if (destDir.existsSync() && destDir.listSync().isNotEmpty) {
        _log.fine('Bundled skin already exists: $skinId');
        continue;
      }

      // Load zip from assets and extract
      final zipData = await rootBundle.load('assets/bundled_skins/$skinId.zip');
      final tempFile = File('${_webUIDir.path}/$skinId.zip');
      await tempFile.writeAsBytes(zipData.buffer.asUint8List());

      try {
        await _installFromZip(tempFile.path);
        _log.info('Installed bundled skin from asset: $skinId');
      } finally {
        if (tempFile.existsSync()) await tempFile.delete();
      }
    }
  } catch (e) {
    _log.fine('No bundled skin zips found in assets: $e');
  }
}
```

c) Update `initialize()` (lines 184-217) — skip remote downloads when `kAppStore`:

```dart
// Download and install remote bundled skins (includes version checking)
if (!BuildInfo.appStore) {
  await downloadRemoteSkins();
}
```

d) Update `downloadRemoteSkins()` to use async source loading:

```dart
Future<void> downloadRemoteSkins() async {
  final sources = await _getRemoteWebUISources();
  for (final sourceConfig in sources) {
    // ... rest of existing logic unchanged
  }
}
```

**Step 4: Add `skin_sources.json` to pubspec.yaml assets**

```yaml
    - assets/bundled_skins/
    - assets/skin_sources.json
```

Note: Also copy `skin_sources.json` to `assets/skin_sources.json` (or symlink) so it's accessible via `rootBundle`. The root `skin_sources.json` is the source of truth for the build script; the one in `assets/` is for runtime. The build script should copy it.

**Step 5: Run test to verify it passes**

Run: `flutter test test/webui_storage_test.dart`
Expected: PASS

**Step 6: Run flutter analyze**

Run: `flutter analyze`

**Step 7: Commit**

```bash
git add lib/src/webui_support/webui_storage.dart test/webui_storage_test.dart pubspec.yaml
git commit -m "feat: load bundled skins from assets, skip remote downloads on App Store builds"
```

---

### Task 5: Gate plugin installation UI on `kAppStore`

**Files:**
- Modify: `lib/src/settings/plugins_settings_view.dart:62-71, 362-402`
- Test: widget test

**Step 1: Write failing widget test**

```dart
// Test that the install button is hidden when BuildInfo.appStore is true.
// Since BuildInfo.appStore is a compile-time const, we can't toggle it in tests.
// Instead, extract the condition into a parameter and test that.

import 'package:flutter_test/flutter_test.dart';

void main() {
  // Test the source code directly — verify the install button is gated
  test('plugin install button is conditional on appStore flag', () {
    final source = File('lib/src/settings/plugins_settings_view.dart').readAsStringSync();
    expect(source, contains('BuildInfo.appStore'));
    expect(source, contains('appStore'));
  });
}
```

Actually, a better approach: add a `showInstallButton` parameter (defaulting to `!BuildInfo.appStore`) to `PluginsSettingsView` and test both states.

**Step 1 (revised): Write widget test**

```dart
void main() {
  testWidgets('hides install button when appStore mode', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PluginsSettingsView(
          pluginLoaderService: mockPluginLoaderService,
          pluginManager: mockPluginManager,
          allowInstall: false,  // Simulates App Store mode
        ),
      ),
    );

    // Install button should not be present
    expect(find.byIcon(LucideIcons.plus), findsNothing);
  });

  testWidgets('shows install button when not appStore mode', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PluginsSettingsView(
          pluginLoaderService: mockPluginLoaderService,
          pluginManager: mockPluginManager,
          allowInstall: true,  // Default non-App Store mode
        ),
      ),
    );

    expect(find.byIcon(LucideIcons.plus), findsOneWidget);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/plugins_settings_view_test.dart`
Expected: FAIL — `allowInstall` parameter doesn't exist

**Step 3: Add `allowInstall` parameter**

In `plugins_settings_view.dart`:
- Add `final bool allowInstall;` field to widget, default `!BuildInfo.appStore`
- Wrap the install `IconButton` (line 67-71) in: `if (widget.allowInstall)`

**Step 4: Run test to verify it passes**

Run: `flutter test test/plugins_settings_view_test.dart`

**Step 5: Commit**

```bash
git add lib/src/settings/plugins_settings_view.dart test/plugins_settings_view_test.dart
git commit -m "feat: hide plugin install button on App Store builds"
```

---

### Task 6: Gate skin installation UI on `kAppStore`

**Files:**
- Modify: `lib/src/settings/settings_view.dart:612-664` (skin selector dropdown)
- Test: widget test

**Step 1: Write failing test**

Test that the "Load custom folder..." dropdown item is absent when in App Store mode. Similar to Task 5 — add a parameter or check `BuildInfo.appStore` in the build method.

**Step 2: Implement**

In `_buildSkinSelector()` (settings_view.dart:612-664), wrap the "Load custom folder..." `DropdownMenuItem` (around line 652-660) in:

```dart
if (!BuildInfo.appStore)
  const DropdownMenuItem(
    value: _customSkinId,
    child: Row(
      children: [
        Icon(Icons.folder_open, size: 16),
        SizedBox(width: 8),
        Text('Load custom folder...'),
      ],
    ),
  ),
```

**Step 3: Run test, then flutter analyze**

**Step 4: Commit**

```bash
git add lib/src/settings/settings_view.dart test/settings_view_skin_test.dart
git commit -m "feat: hide custom skin folder option on App Store builds"
```

---

### Task 7: Gate skin REST install endpoints on `kAppStore`

**Files:**
- Modify: `lib/src/services/webserver/webui_handler.dart:22-29`
- Test: unit test for handler

**Step 1: Write failing test**

```dart
void main() {
  test('install endpoints return 403 when appStore is true', () async {
    // Create handler in app-store mode
    final handler = WebUIHandler(mockStorage, appStoreMode: true);

    final request = Request('POST', Uri.parse('http://localhost/api/v1/webui/skins/install/url'),
      body: jsonEncode({'url': 'https://example.com/skin.zip'}));

    final response = await handler.handleInstallFromUrl(request);
    expect(response.statusCode, equals(403));
  });
}
```

**Step 2: Implement**

Add an `appStoreMode` parameter to `WebUIHandler` (defaulting to `BuildInfo.appStore`). In each install handler, return 403 early:

```dart
if (_appStoreMode) {
  return Response.forbidden(
    jsonEncode({'error': 'Skin installation is not available on this platform'}),
  );
}
```

Alternatively, don't register the routes at all when `BuildInfo.appStore` is true.

**Step 3: Run tests, analyze**

**Step 4: Commit**

```bash
git add lib/src/services/webserver/webui_handler.dart test/webui_handler_test.dart
git commit -m "feat: disable skin install REST endpoints on App Store builds"
```

---

### Task 8: Gate `PluginLoaderService.addPlugin()` on `kAppStore`

**Files:**
- Modify: `lib/src/plugins/plugin_loader_service.dart:69-112`
- Test: unit test

**Step 1: Write failing test**

```dart
test('addPlugin throws when appStore mode is enabled', () async {
  final service = PluginLoaderService(appStoreMode: true, ...);

  expect(
    () => service.addPlugin('/some/path'),
    throwsA(isA<UnsupportedError>()),
  );
});
```

**Step 2: Implement**

Add `appStoreMode` parameter (default `BuildInfo.appStore`). At the top of `addPlugin()`:

```dart
if (_appStoreMode) {
  throw UnsupportedError('Plugin installation is not available on this platform');
}
```

**Step 3: Run tests, analyze**

**Step 4: Commit**

```bash
git add lib/src/plugins/plugin_loader_service.dart test/plugin_loader_service_test.dart
git commit -m "feat: block plugin installation on App Store builds"
```

---

### Task 9: Integrate `bundle_skins.sh` into `flutter_with_commit.sh`

**Files:**
- Modify: `flutter_with_commit.sh`

**Step 1: Add skin bundling call**

Before the `flutter build` / `flutter run` invocation, add:

```bash
# --- Bundle skins (downloads to assets/bundled_skins/) ---
if [ -f "$SCRIPT_DIR/bundle_skins.sh" ]; then
  echo "Bundling skins..."
  bash "$SCRIPT_DIR/bundle_skins.sh"
fi
```

For App Store builds, the flag is passed as an extra arg:
```bash
./flutter_with_commit.sh build ios --dart-define=APP_STORE=true
```

**Step 2: Test manually**

Run: `./flutter_with_commit.sh run --dart-define=simulate=1`
Expected: Skins are bundled, app starts with bundled skins available

**Step 3: Commit**

```bash
git add flutter_with_commit.sh
git commit -m "feat: integrate skin bundling into build script"
```

---

### Task 10: Update `WebUIStorage.updateAllSkins()` to respect `kAppStore`

**Files:**
- Modify: `lib/src/webui_support/webui_storage.dart:470-518`

**Step 1: Write test**

```dart
test('updateAllSkins is no-op when appStore mode', () async {
  final storage = WebUIStorage(mockSettings, appStoreMode: true);
  // Should complete without making any HTTP requests
  await storage.updateAllSkins();
  verifyNever(mockHttp.get(any));
});
```

**Step 2: Implement**

At the top of `updateAllSkins()`:

```dart
if (_appStoreMode) {
  _log.fine('Skin updates disabled in App Store mode');
  return;
}
```

**Step 3: Run tests, analyze**

**Step 4: Commit**

```bash
git add lib/src/webui_support/webui_storage.dart test/webui_storage_test.dart
git commit -m "feat: disable skin updates in App Store mode"
```

---

### Task 11: Final integration test and cleanup

**Step 1: Run full test suite**

Run: `flutter test`
Expected: All tests pass

**Step 2: Run flutter analyze**

Run: `flutter analyze`
Expected: No issues

**Step 3: Manual verification with simulated devices**

Run: `flutter run --dart-define=simulate=1 --dart-define=APP_STORE=true`

Verify:
- [ ] No "+" button in Plugins settings
- [ ] No "Load custom folder..." in skin dropdown
- [ ] Bundled skins load from assets
- [ ] Bundled plugins (DYE2) still work
- [ ] Settings > Simulated Devices toggle still visible
- [ ] No location permission prompt on iOS

**Step 4: Manual verification without App Store flag**

Run: `flutter run --dart-define=simulate=1`

Verify:
- [ ] "+" button present in Plugins settings
- [ ] "Load custom folder..." present in skin dropdown
- [ ] Remote skin downloads still work
- [ ] All existing functionality preserved

**Step 5: Commit any final fixes, then create PR**

```bash
git commit -m "chore: final integration verification for App Store readiness"
```
